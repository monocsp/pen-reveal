// src/reveal_preparer.dart — 그림 두 장을 [SequentialReveal] 이 그릴 수 있는
//   **순서 텍스처 한 장**으로 굽는다.
//
//   여기는 Flutter 와 순수 코어 사이의 다리다:
//     ① `ui.Image` 두 장을 같은 크기로 리샘플해 RGBA 를 뜨고(엔진 경계 — `image_bytes.dart`)
//     ② 무엇을 어떤 순서로 드러낼지는 통째로 `compute`(별도 isolate)에 넘기고 — `detectReveal`
//     ③ 돌아온 **계획**에 타이밍 정책(`RevealTimingPolicy`)을 씌워 일정을 짜고
//     ④ 계획+일정을 `RevealTextureCompiler` 로 한 장에 구워 텍스처(`ui.Image`)로 만든다.
//
//   왜 ②를 통째로 넘기나: 세선화만 넘기고 diff·재매핑을 UI 스레드에 두면 21만 픽셀 루프가
//   프레임에 얹힌다. 순수하게 뗄 수 있는 CPU 일은 전부 한 번에 보내는 편이 경계도 선명하다.
//
//   ⚠️ **③④를 코어의 구조 층에 넣지 마라.** 계획은 *공간과 순서*만 말하고, 그걸 몇 밀리초에
//   그릴지는 화면이 정한다(같은 지도를 스플래시에선 느리게 그리고 싶을 수 있다). 그 분리는
//   `pen_reveal` 의 `test/purity_test.dart` 가 소스 수준에서 잠근다.
//
//   ⚠️ **비용은 굽는 그림당 한 번**을 전제로 한다(세선화가 이미지를 여러 번 훑는다).
//   호출부가 결과를 들고 있어야지, 프레임마다 부르면 안 된다.
//
//   소유권: 넘긴 base/composed 는 **건드리지 않는다**(호출부 소유). 만들어 낸 텍스처만
//   결과가 소유하므로, 다 쓰면 [PreparedReveal.dispose] 를 불러야 한다.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:pen_reveal_flutter/src/image_bytes.dart';

/// 구워 낸 순서 텍스처 한 벌 — 그리는 쪽이 필요로 하는 것이 전부 여기 있다.
class PreparedReveal {
  const PreparedReveal({
    required this.reveal,
    required this.revealDuration,
    required this.sharpness,
    required this.stages,
    required this.profile,
    required this.segmentCount,
  });

  /// 픽셀값 = 드러나는 시점(0~[RevealSharpness.maxOrderValue]).
  ///   `SequentialRevealPainter` 가 임계 마스크로 쓴다.
  final ui.Image reveal;

  /// 이 텍스처를 처음부터 끝까지 재생하는 데 걸리는 시간.
  ///
  ///   ⚠️ **가감속은 이미 텍스처에 구워져 있다.** 컨트롤러는 이 길이로 **선형** 재생해야
  ///   한다 — curve 를 또 걸면 가감속이 두 번 먹는다.
  final Duration revealDuration;

  /// 이 텍스처를 **구울 때 쓴** 임계 가파르기. 페인터는 여기서 받아 쓴다.
  ///
  ///   ⚠️ **그리는 쪽이 자기 상수를 갖지 않게 하려고 결과에 실어 보낸다.** 추출 전 원본은
  ///   같은 24 를 굽는 쪽(`painterSharpness`)과 그리는 쪽(`_edgeSharpness`)에 따로 뒀고
  ///   둘을 묶는 테스트가 없었다 — 한쪽만 바꾸면 **연출이 끝나도 마지막 획이 반투명하게
  ///   남는다.** 굽기 결과가 자기 k 를 들고 다니면 그 어긋남이 문법적으로 불가능해진다.
  final RevealSharpness sharpness;

  /// 연출을 셋으로 접은 경계(길 끝 / X 끝 / 전체 끝) — 0~1 진행도.
  ///
  ///   ⚠️ **텍스처에서 역추정할 수 없는 정보라 여기 실어 보낸다.** 굽고 나면 남는 것은
  ///   픽셀당 시각뿐이라, "저 회색값이 길의 끝인지 X 의 시작인지"를 밖에서 알 방법이 없다.
  ///   일정은 굽는 순간에만 존재하므로 그때 접어 두지 않으면 사라진다.
  final RevealStageMarks stages;

  /// 이 굽기가 어디에 시간을 썼나. 화면에 띄우거나 로그로 남겨 회귀를 잡는 데 쓴다.
  final RevealPrepareProfile profile;

  /// 이 굽기가 찾아낸 세그먼트 수(길 + X 두 획 + 문구 덩어리들).
  ///
  ///   ⚠️ **탐지가 아무것도 못 찾았는지 밖에서 알 수 있는 유일한 값이다.** 0 이면 텍스처가
  ///   통째로 "영영 안 드러남"(255)이라 진행도를 1 까지 올려도 화면은 [ui.Image] `base`
  ///   그대로다 — 연출이 실패한 게 아니라 **아예 시작도 안 한 것처럼** 보인다.
  ///   두 장이 사실상 같거나, 더한 그림이 반투명하거나(알파 200 미만), 바닥과 너무 비슷하면
  ///   (채널 차 18 이하) 그렇게 된다.
  ///
  ///   ```dart
  ///   if (prepared.isEmpty) {
  ///     // 연출을 포기하고 완성본을 그냥 보여 준다.
  ///     return Image(image: composedProvider);
  ///   }
  ///   ```
  final int segmentCount;

  /// 드러낼 것이 하나도 없다 — 재생해도 화면이 안 바뀐다.
  ///
  ///   호출부는 이때 **완성본을 그냥 띄우는 대비책**을 두는 것이 좋다. 그러지 않으면
  ///   사용자는 빈 화면을 오래 본다.
  bool get isEmpty => segmentCount == 0 || revealDuration == Duration.zero;

  /// 실어 온 [ui.Image] 를 놓아준다.
  ///
  ///   ⚠️ **소유는 하나뿐이다.** 이 객체를 두 위젯이 나눠 쓰면 먼저 버리는 쪽이 텍스처를
  ///   지워, 나머지 쪽은 그릴 때 "Cannot access a disposed image" 로 죽는다 — 원인에서
  ///   한참 떨어진 자리에서 터진다. 다시 구웠으면 **옛 것을 반드시 버린다**(안 버리면 샌다).
  ///
  ///   ⚠️ 두 번 부르면 안 된다. [ui.Image.dispose] 가 그렇다.
  ///
  ///   ⚠️ `prepare()` 에 넘긴 `base`·`composed` 는 **여기서 안 버린다.** 그건 호출부 것이다.
  void dispose() => reveal.dispose();
}

/// 두 장의 가로세로비가 이만큼까지는 다를 수 있다 — 리샘플 반올림 여유다.
const double _aspectTolerance = 0.01;

/// 두 장 → 순서 텍스처. 값 객체라 `const` 로 두고 재사용한다.
class RevealPreparer {
  const RevealPreparer({
    this.longSide = kBakeLongSide,
    this.detectConfig = const RevealDetectConfig(),
    this.timing = const HandwritingRevealTiming(),
    this.compiler = const RevealTextureCompiler(),
  }) : assert(longSide > 0, '굽는 해상도는 양수여야 한다');

  /// 굽는 해상도(긴 변). 낮추면 싸지지만 가는 획이 뭉개진다. 자(measure)는 기준 해상도로
  ///   환산해 정책에 넘기므로 이 값을 바꿔도 그리는 시간은 안 흔들린다.
  final int longSide;

  final RevealDetectConfig detectConfig;

  /// 계획 → 일정. 화면마다 다른 리듬을 주고 싶으면 갈아 끼운다.
  final RevealTimingPolicy timing;

  /// 계획+일정 → 시간축 한 장. **임계 가파르기를 들고 있는 쪽이기도 하다** —
  ///   그 값이 그대로 [PreparedReveal.sharpness] 로 나가 페인터까지 간다.
  final RevealTextureCompiler compiler;

  /// [base] 위에 [composed] 를 순차로 드러낼 텍스처를 굽는다.
  ///
  ///   두 장은 **같은 구도·같은 비율**이어야 한다 — 어긋나면 화면 전체가 '변한 곳'으로
  ///   잡혀 엉뚱한 획이 나온다. 실패하면 예외를 던진다(로딩/실패 표면은 조립 계층 몫).
  Future<PreparedReveal> prepare({
    required ui.Image base,
    required ui.Image composed,
  }) async {
    final clock = Stopwatch()..start();

    // 굽기 해상도로 줄여 뜬다 — 원본 크기로 돌리면 몇 배 든다.
    // ⚠️ **두 장은 같은 그림의 같은 틀이어야 한다.** 굽기 크기를 `composed` 에서만 뽑고
    //   `base` 를 거기에 맞춰 리샘플하므로, 가로세로비가 다르면 `base` 가 늘어난 채로
    //   빼진다 — **화면 거의 전체가 "변한 곳"** 이 되어 그럴듯하지만 완전히 틀린 순서가
    //   나온다. 조용히 이상해지느니 여기서 막는다.
    final baseRatio = base.width / base.height;
    final composedRatio = composed.width / composed.height;
    if ((baseRatio - composedRatio).abs() > _aspectTolerance) {
      throw ArgumentError(
        '바닥과 최종본의 가로세로비가 다르다 — '
        'base ${base.width}x${base.height}, '
        'composed ${composed.width}x${composed.height}. '
        '두 장은 같은 그림에서 획만 더한 것이어야 한다.',
      );
    }

    final size = fitImageLongSide(composed, longSide);
    final composedRgba = await rgbaAt(composed, size.width, size.height);
    final baseRgba = await rgbaAt(base, size.width, size.height);
    final resampled = clock.elapsedMicroseconds;

    final detected = await compute(
      detectReveal,
      RevealDetectInput(
        baseRgba: baseRgba,
        composedRgba: composedRgba,
        width: size.width,
        height: size.height,
        config: detectConfig,
      ),
    );
    final detectedAt = clock.elapsedMicroseconds;

    // 자를 기준 해상도로 환산한다 — 안 하면 품질만 올렸는데 연출이 느려진다.
    //   기본값이면 곱셈 자체를 건너뛴다(부동소수 오차 없이 그대로).
    final plan = longSide == kBakeLongSide
        ? detected
        : detected.scaleMeasures(kBakeLongSide / longSide);
    final schedule = timing.schedule(plan);
    final order = compiler.compile(plan, schedule);
    final compiledAt = clock.elapsedMicroseconds;

    final texture = await textureFromRgba(
      revealOrderToRgba(order),
      plan.width,
      plan.height,
    );
    clock.stop();

    return PreparedReveal(
      reveal: texture,
      revealDuration: schedule.total,
      // ⚠️ 상수를 다시 적지 않는다 — **구운 그 값**을 그대로 실어 보낸다.
      sharpness: compiler.sharpness,
      stages: RevealStageMarks.of(plan, schedule),
      segmentCount: plan.segments.length,
      profile: RevealPrepareProfile(
        resample: Duration(microseconds: resampled),
        detect: Duration(microseconds: detectedAt - resampled),
        compile: Duration(microseconds: compiledAt - detectedAt),
        upload: Duration(microseconds: clock.elapsedMicroseconds - compiledAt),
      ),
    );
  }
}

/// 한 번의 굽기가 어디에 시간을 썼나 — **재 본 값**이지 추정이 아니다.
///
///   ⚠️ 이 넷을 더한 것이 `prepare()` 의 전부이고, **그림을 디코딩하는 시간은 안 들어 있다.**
///   `prepare()` 는 이미 디코딩된 `ui.Image` 두 장을 받는다. "지도를 주면 몇 ms 뒤에
///   시작하나" 를 답하려면 자산 로드와 PNG 디코딩을 호출부에서 따로 재서 더해야 한다.
///   전에 벤치가 이 경계를 흐려서 구간 합이 총합을 넘는 표를 냈다 — 같은 실수를 막으려고
///   경계를 값으로 박아 둔다.
class RevealPrepareProfile {
  const RevealPrepareProfile({
    required this.resample,
    required this.detect,
    required this.compile,
    required this.upload,
  });

  /// 안 재고 만든 결과 — 손으로 텍스처를 만들어 그려 볼 때(페인터 시험 등) 쓴다.
  ///
  ///   ⚠️ 기본값으로 두지 **않는다.** 기본값이면 "안 잰 것"과 "0 이 나온 것"이 구분되지
  ///   않고, 굽기 경로가 프로파일을 안 채워도 아무도 모른다. 이름으로 밝히게 한다.
  static const RevealPrepareProfile unmeasured = RevealPrepareProfile(
    resample: Duration.zero,
    detect: Duration.zero,
    compile: Duration.zero,
    upload: Duration.zero,
  );

  /// 두 장을 굽기 해상도로 줄여 RGBA 로 뜨는 데 든 시간(GPU 왕복 2회).
  final Duration resample;

  /// `detectReveal` — 분류·세선화·한 붓 순회·붓 자국 칠하기·평활. **다른 isolate 에서** 돈다.
  final Duration detect;

  /// 일정 계산과 8비트 텍스처 컴파일. 본 스레드다.
  final Duration compile;

  /// 텍스처를 `ui.Image` 로 올리는 데 든 시간.
  final Duration upload;

  Duration get total => resample + detect + compile + upload;

  @override
  String toString() => '리샘플 ${_ms(resample)} · 탐지 ${_ms(detect)} · '
      '컴파일 ${_ms(compile)} · 업로드 ${_ms(upload)} = ${_ms(total)}';

  static String _ms(Duration d) =>
      '${(d.inMicroseconds / 1000).toStringAsFixed(1)}ms';
}
