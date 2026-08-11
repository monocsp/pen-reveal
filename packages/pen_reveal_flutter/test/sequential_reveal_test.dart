// 그리기(합성 규칙)만 따로 잠근다 — 굽기·시간과 별개다.
//
//   4×1 짜리 손으로 만든 세 장(바닥 파랑 / 최종 빨강 / 순서 0·100·200·255)을 실제로 그려
//   **임계 아래만 최종본이 나오는지**를 픽셀로 확인한다. 여기서 잡고 싶은 함정 둘:
//     · 색행렬 translation 열은 0~255 공간이다 — `×255` 를 빠뜨리면 마스크가 통째로 사라진다
//     · 255(바닥)는 progress 1 에서도 안 드러나야 한다
//
//   추출하면서 하나 더 붙었다(맨 아래 그룹): 페인터가 **자기 가파르기 상수를 갖지 않고**
//   `PreparedReveal` 이 들고 온 k 를 쓴다는 것. 상수가 되살아나면 거기가 빨개진다.
@Tags(['regression'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 가로 [pixels] 개 ×1 짜리 그림. RGBA 그대로 채운다.
Future<ui.Image> _strip(List<List<int>> pixels) {
  final bytes = Uint8List.fromList([for (final p in pixels) ...p]);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    pixels.length,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

const _blue = [0, 0, 255, 255];
const _red = [255, 0, 0, 255];
List<int> _gray(int v) => [v, v, v, 255];

/// 그려서 픽셀을 읽는다.
///
///   [sharpness] 는 이 순서 텍스처를 **구울 때 쓴** 가파르기다. 페인터는 텍스처를 날것으로
///   안 받고 [PreparedReveal] 한 벌로 받으므로, 여기서 손으로 싸서 넘긴다(구운 게 아니라
///   손으로 만든 것이라 텍스처 수명은 부르는 쪽이 본다 — `dispose` 는 안 부른다).
Future<List<List<int>>> _paint({
  required ui.Image base,
  required ui.Image composed,
  required ui.Image reveal,
  required double progress,
  RevealSharpness sharpness = RevealSharpness.standard,
}) async {
  final width = reveal.width;
  final recorder = ui.PictureRecorder();
  SequentialRevealPainter(
    base: base,
    composed: composed,
    prepared: PreparedReveal(
      reveal: reveal,
      revealDuration: Duration.zero,
      sharpness: sharpness,
      stages: RevealStageMarks.single,
      segmentCount: 1,
      profile: RevealPrepareProfile.unmeasured,
    ),
    progress: progress,
  ).paint(ui.Canvas(recorder), Size(width.toDouble(), 1));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 1);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  return [
    for (var x = 0; x < width; x++)
      [bytes[x * 4], bytes[x * 4 + 1], bytes[x * 4 + 2], bytes[x * 4 + 3]],
  ];
}

void main() {
  late ui.Image base;
  late ui.Image composed;
  late ui.Image reveal;
  late PreparedReveal prepared;

  setUp(() async {
    base = await _strip(List.filled(4, _blue));
    composed = await _strip(List.filled(4, _red));
    // 0=맨 처음 · 100·200=중간 · 255=영영 안 드러남.
    reveal = await _strip([_gray(0), _gray(100), _gray(200), _gray(255)]);
    prepared = PreparedReveal(
      reveal: reveal,
      revealDuration: Duration.zero,
      sharpness: RevealSharpness.standard,
      stages: RevealStageMarks.single,
      segmentCount: 1,
      profile: RevealPrepareProfile.unmeasured,
    );
  });

  tearDown(() {
    base.dispose();
    composed.dispose();
    // 텍스처는 여기서 놓는다 — `prepared` 는 손으로 싼 것이라 `dispose` 를 또 부르면
    //   같은 이미지를 두 번 놓는다.
    reveal.dispose();
  });

  group('임계 — 순서값이 progress 아래인 곳만 최종본', () {
    test('progress 0 — 바닥만 보인다', () async {
      final px = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 0,
      );
      expect(px.every((p) => p[2] > 200), isTrue, reason: '전부 바닥(파랑)');
    });

    test('progress 0.5 — 0·100 만 드러나고 200·255 는 아직', () async {
      final px = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 0.5, // 임계 127.5
      );
      expect(px[0][0], greaterThan(200), reason: '순서 0 은 드러났다(빨강)');
      expect(px[1][0], greaterThan(200), reason: '순서 100 도 드러났다');
      expect(px[2][2], greaterThan(200), reason: '순서 200 은 아직 바닥');
      expect(px[3][2], greaterThan(200), reason: '순서 255 도 아직 바닥');
    });

    test('progress 1 — 255 만 끝까지 안 드러난다', () async {
      final px = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 1,
      );
      expect(px[0][0], greaterThan(200));
      expect(px[1][0], greaterThan(200));
      expect(px[2][0], greaterThan(200), reason: '순서 200 은 끝에 드러난다');
      expect(px[3][2], greaterThan(200), reason: '255 는 영영 바닥으로 남는다');
    });

    test('범위를 벗어난 progress 는 잘라 쓴다 — 마스크가 뒤집히지 않는다', () async {
      final over = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 4,
      );
      final full = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 1,
      );
      expect(over, full);
      final under = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: -3,
      );
      final none = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 0,
      );
      expect(under, none);
    });
  });

  // ⚠️ **기대값의 24 를 손으로 적는다** — 굽는 쪽에서 k 를 읽어다 쓰지 않는다.
  //   그게 이 그룹의 요점이다: 임계가 얼마나 칼같은가는 **표현 계약**이라 기본값을 48 로
  //   바꾸면 여기가 빨개져야 한다. 받는 쪽을 `RevealSharpness.standard` 로 적는 것은
  //   상관없다 — 계약을 붙잡고 있는 것은 아래 `24`·`-24` 리터럴이지 생성자 인자가 아니다.
  //
  //   행렬을 내는 쪽은 이제 페인터가 아니라 `RevealSharpness` 다(페인터의 정적 메서드는
  //   없어졌다). 겨누는 대상만 옮겼을 뿐 단언은 원본 그대로다.
  group('색행렬 — 0~255 공간 (×255 빠뜨림 함정)', () {
    test('translation 열은 progress×255 에 가파르기를 곱한 값', () {
      final at0 = RevealSharpness.standard.thresholdMatrix(0);
      final atHalf = RevealSharpness.standard.thresholdMatrix(0.5);
      final at1 = RevealSharpness.standard.thresholdMatrix(1);
      expect(at0[19], 0);
      expect(atHalf[19], closeTo(24 * 0.5 * 255, 1e-9));
      expect(at1[19], closeTo(24 * 255, 1e-9));
      // 0~1 공간으로 잘못 쓰면 임계가 255배 작아져 마스크가 통째로 사라진다.
      expect(atHalf[19], greaterThan(1));
    });

    test('알파는 순서값에 반비례한다(계단 임계)', () {
      final m = RevealSharpness.standard.thresholdMatrix(0.5);
      expect(m[15], -24, reason: 'reveal 이 클수록 알파가 준다');
      expect(m.sublist(16, 19), [0, 0, 0], reason: 'G·B·A 는 안 본다');
      expect(m.length, 20);
    });

    test('progress 는 행렬 단계에서 이미 잘린다', () {
      expect(
        RevealSharpness.standard.thresholdMatrix(9),
        RevealSharpness.standard.thresholdMatrix(1),
      );
      expect(
        RevealSharpness.standard.thresholdMatrix(-9),
        RevealSharpness.standard.thresholdMatrix(0),
      );
    });
  });

  group('다시 그리기', () {
    test('progress 가 바뀌면 다시 그린다', () {
      final a = SequentialRevealPainter(
        base: base,
        composed: composed,
        prepared: prepared,
        progress: 0.2,
      );
      final b = SequentialRevealPainter(
        base: base,
        composed: composed,
        prepared: prepared,
        progress: 0.3,
      );
      expect(b.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(a), isFalse);
    });

    test('구운 결과가 바뀌면 다시 그린다', () async {
      // 원본에서 `reveal` 그림을 갈아 끼우던 자리다 — 이제 텍스처는 `PreparedReveal`
      //   안에 있으니 한 벌째 갈아 끼운다.
      final other = await _strip(List.filled(4, _gray(10)));
      addTearDown(other.dispose);
      final a = SequentialRevealPainter(
        base: base,
        composed: composed,
        prepared: prepared,
        progress: 0.2,
      );
      final b = SequentialRevealPainter(
        base: base,
        composed: composed,
        prepared: PreparedReveal(
          reveal: other,
          revealDuration: Duration.zero,
          sharpness: RevealSharpness.standard,
          stages: RevealStageMarks.single,
          segmentCount: 1,
          profile: RevealPrepareProfile.unmeasured,
        ),
        progress: 0.2,
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  group('위젯 — 준비된 세 장과 진행도만 받는다', () {
    testWidgets('CustomPaint 로 넘어간다(크기·페인터)', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SequentialReveal(
              base: base,
              composed: composed,
              prepared: prepared,
              progress: 0.4,
              size: const Size(40, 10),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(SequentialReveal),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paint.size, const Size(40, 10));
      final painter = paint.painter! as SequentialRevealPainter;
      expect(painter.progress, 0.4);
      // 원본은 `painter.reveal` 이 그대로 넘어가는지를 봤다 — 이제 텍스처는 한 벌
      //   안에 있으므로 그 한 벌이 통째로 넘어가는지를 본다.
      expect(painter.prepared, same(prepared));
      expect(painter.prepared.reveal, same(reveal));
      expect(
        tester.getSize(find.byType(SequentialReveal)),
        const Size(40, 10),
      );
    });
  });

  // 페인터가 **자기 가파르기 상수를 안 갖는다**는 것을 픽셀로 잠근다.
  //
  //   왜 있나: 추출 전 원본은 같은 24 를 굽는 쪽(`painterSharpness`)과 그리는
  //   쪽(`_edgeSharpness`)에 따로 뒀고, 둘을 묶는 테스트가 없었다 — 한쪽만 바꾸면
  //   **연출이 끝나도 마지막 획이 반투명하게 남는다.** 아무 테스트도 안 빨개지고 실기에서
  //   눈으로 봐야 아는 종류의 버그다.
  //
  //   이제 k 는 굽기 결과(`PreparedReveal.sharpness`)가 들고 오니, 같은 순서 텍스처를 다른
  //   k 로 싸면 **그림이 달라져야** 한다. 페인터가 자기 상수를 되살리면 두 결과가 같아져
  //   여기가 빨개진다 — 그게 목적이다.
  group('가파르기 — 페인터는 prepared 가 들고 온 k 를 쓴다', () {
    test('같은 텍스처라도 k 가 다르면 픽셀이 다르다', () async {
      // 기본값이 곧 표현 계약의 k(=24)다 — 그래서 안 넘긴다.
      final sharp = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 0.5,
      );
      final soft = await _paint(
        base: base,
        composed: composed,
        reveal: reveal,
        progress: 0.5,
        sharpness: const RevealSharpness(2),
      );
      expect(soft, isNot(sharp), reason: '페인터가 자기 상수를 쓰면 둘이 같아진다');
      // 임계는 둘 다 127.5 다. 다른 건 선단 폭뿐이다 — k=24 는 10.6 코드라 순서 100 이
      //   이미 완전히 드러났고, k=2 는 127.5 코드라 같은 자리가 중간 알파(2×27.5=55)로
      //   번져 바닥 파랑이 비친다.
      expect(sharp[1][0], greaterThan(200), reason: 'k=24 — 순서 100 은 완전히 빨강');
      expect(soft[1][0], lessThan(200), reason: 'k=2 — 선단이 번져 중간 알파다');
      expect(soft[1][2], greaterThan(100), reason: 'k=2 — 바닥이 비쳐 남는다');
    });
  });
}
