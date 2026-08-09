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

  void dispose() => reveal.dispose();
}

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
    // 굽기 해상도로 줄여 뜬다 — 원본 크기로 돌리면 몇 배 든다.
    final size = fitImageLongSide(composed, longSide);
    final composedRgba = await rgbaAt(composed, size.width, size.height);
    final baseRgba = await rgbaAt(base, size.width, size.height);

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
    // 자를 기준 해상도로 환산한다 — 안 하면 품질만 올렸는데 연출이 느려진다.
    //   기본값이면 곱셈 자체를 건너뛴다(부동소수 오차 없이 그대로).
    final plan = longSide == kBakeLongSide
        ? detected
        : detected.scaleMeasures(kBakeLongSide / longSide);
    final schedule = timing.schedule(plan);
    final order = compiler.compile(plan, schedule);
    return PreparedReveal(
      reveal: await textureFromRgba(
        revealOrderToRgba(order),
        plan.width,
        plan.height,
      ),
      revealDuration: schedule.total,
      // ⚠️ 상수를 다시 적지 않는다 — **구운 그 값**을 그대로 실어 보낸다.
      sharpness: compiler.sharpness,
      stages: RevealStageMarks.of(plan, schedule),
    );
  }
}
