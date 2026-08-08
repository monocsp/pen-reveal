// 굽기 **다리**(ui.Image → RGBA → isolate → 계획 → 일정 → 텍스처)를 잠근다.
//
//   순수 코어 시험(`pen_reveal` 의 detector·timing 테스트)이 못 보는 것들이 여기 있다:
//     · 리샘플·바이트 뜨기가 실제로 도는가(엔진 경계)
//     · 입력과 **계획**이 isolate 를 오가는가(`compute` 직렬화 — 필드 하나만 늘려도 깨질 수 있다)
//     · 만든 텍스처가 그릴 수 있는 크기·내용인가
//     · **재생 시간이 굽기 해상도에 안 흔들리는가** — 흔들리면 품질만 올렸는데 연출이 느려진다
//     · **구운 임계 가파르기가 그리는 쪽까지 그대로 실려 가는가**
//   여기 그림은 전부 인공이다. 실제 지도로 실측값을 못 박는 쪽은 `test/corpus/` 가 맡는다.
@Tags(['regression'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 흰 바닥에 [stroke] 를 검게 칠한 그림.
Future<ui.Image> _painted(int w, int h, {bool Function(int x, int y)? stroke}) {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final dark = stroke?.call(x, y) ?? false;
      bytes[i] = bytes[i + 1] = bytes[i + 2] = dark ? 0 : 255;
      bytes[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

bool _bar(int x, int y) => x >= 46 && x <= 54 && y >= 20 && y <= 140;

/// 420×420 안을 한 번 꺾어 도는 길.
///
///   ⚠️ 길이를 **일부러 가운데로** 잡았다(경로 ≈ 440 → 밴드 한복판). 밴드 양끝(500·2000)에
///   붙는 길이로 재면 자를 아무리 틀리게 잡아도 값이 같아 해상도 시험이 통과해 버린다.
bool _serpentine(int x, int y) {
  const thickness = 7;
  for (var row = 0; row < 2; row++) {
    final top = 40 + row * 80;
    if (y >= top && y < top + thickness && x >= 40 && x <= 220) return true;
  }
  if (x >= 220 - thickness + 1 && x <= 219 && y >= 40 && y <= 120) return true;
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('두 장을 넣으면 그릴 수 있는 텍스처와 재생 시간이 나온다', () async {
    final base = await _painted(100, 160);
    final composed = await _painted(100, 160, stroke: _bar);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    const preparer = RevealPreparer(longSide: 160);
    final prepared = await preparer.prepare(base: base, composed: composed);
    addTearDown(prepared.dispose);

    // 세로로 긴 그림이라 긴 변(세로)이 굽기 해상도가 된다.
    expect(prepared.reveal.height, 160);
    expect(prepared.reveal.width, 100);
    expect(prepared.revealDuration, greaterThan(Duration.zero));

    // 텍스처 안에 '획'(255 미만)이 실제로 들어 있다.
    final data = await prepared.reveal.toByteData();
    final px = data!.buffer.asUint8List();
    var strokePixels = 0;
    for (var i = 0; i < px.length; i += 4) {
      if (px[i] < 255) strokePixels++;
    }
    expect(strokePixels, greaterThan(100), reason: '획이 통째로 사라졌다');
  });

  test('굽기 해상도를 바꿔도 재생 시간은 안 흔들린다', () async {
    final base = await _painted(420, 420);
    final composed = await _painted(420, 420, stroke: _serpentine);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    final measured = <int, int>{};
    for (final longSide in const [210, 420, 840]) {
      final preparer = RevealPreparer(longSide: longSide);
      final prepared = await preparer.prepare(base: base, composed: composed);
      addTearDown(prepared.dispose);
      measured[longSide] = prepared.revealDuration.inMilliseconds;
    }

    // ⚠️ **밴드 양끝에서 100ms 이상 떨어진 값으로 재야 의미가 있다.** 포화 구간(500·2000)에
    //   붙어 있으면 자를 아무리 틀리게 잡아도 값이 같아 시험이 통과한다.
    const floor = 500;
    const ceiling = 2000;
    for (final entry in measured.entries) {
      expect(
        entry.value,
        greaterThan(floor + 100),
        reason: '@${entry.key}: 밴드 바닥에 붙어 있어 해상도 시험이 무의미하다',
      );
      expect(entry.value, lessThan(ceiling - 100), reason: '@${entry.key}: 천장');
    }
    // 환산을 안 하면 해상도 배수(210↔840 은 4배)만큼 자가 벌어져 시간이 갈린다.
    final values = measured.values.toList()..sort();
    expect(
      values.last - values.first,
      lessThanOrEqualTo(((ceiling - floor) * 0.05).round()),
      reason: '해상도만 바꿨는데 길 그리는 시간이 밴드의 5% 넘게 움직였다: $measured',
    );
  });

  test('바닥과 최종본이 같으면 재생 시간 0 — 그려도 아무 일도 안 일어난다', () async {
    final base = await _painted(80, 80);
    final composed = await _painted(80, 80);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    const preparer = RevealPreparer(longSide: 80);
    final prepared = await preparer.prepare(base: base, composed: composed);
    addTearDown(prepared.dispose);
    expect(prepared.revealDuration, Duration.zero);
  });

  // 아래 둘은 **추출하면서 일부러 고친 버그**를 잠근다.
  //
  //   원본은 같은 24 를 굽는 쪽(`painterSharpness`)과 그리는 쪽(`_edgeSharpness`)에 따로
  //   뒀고, 둘을 묶는 테스트가 없었다. 한쪽만 바꾸면 아무 테스트도 안 빨개진 채
  //   **연출이 끝나도 마지막 획이 반투명하게 남았다** — 실기에서 눈으로 봐야 아는 종류다.
  //   지금은 굽기 결과가 자기가 구워진 `RevealSharpness` 를 들고 페인터까지 간다.
  //   (`RevealSharpness` 자체의 수학은 `pen_reveal` 의 `sharpness_binding_test` 가 잠근다.
  //   여기서 보는 것은 **그 값이 굽기 다리를 건너오는가** 하나다.)

  test('기본으로 구우면 결과가 표준 k 를 들고 나온다', () async {
    final base = await _painted(100, 160);
    final composed = await _painted(100, 160, stroke: _bar);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    const preparer = RevealPreparer();
    final prepared = await preparer.prepare(base: base, composed: composed);
    addTearDown(prepared.dispose);

    expect(
      prepared.sharpness.k,
      RevealSharpness.standard.k,
      reason: '페인터가 기본과 다른 k 로 그리면 마지막 획이 반투명하게 남는다',
    );
  });

  test('컴파일러의 k 를 바꾸면 결과와 텍스처가 함께 따라온다', () async {
    // 기본값만 보면 양쪽이 24 를 각자 하드코딩해도 통과한다. 기본이 아닌 k 로 구워야
    //   "결과가 **구운 그 값**을 실어 보낸다" 가 증명된다.
    final base = await _painted(100, 160);
    final composed = await _painted(100, 160, stroke: _bar);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    const sharpness = RevealSharpness(128);
    const preparer = RevealPreparer(
      longSide: 160,
      compiler: RevealTextureCompiler(sharpness: sharpness),
    );
    final prepared = await preparer.prepare(base: base, composed: composed);
    addTearDown(prepared.dispose);

    expect(prepared.sharpness.k, 128, reason: '구운 k 가 결과에 안 실렸다');

    // 순서값 상한도 같은 k 를 따라간다 — 넘어가면 그 픽셀은 progress=1 에서도
    //   불투명해지지 못한다(= 마지막 획이 반투명하게 남는 그 증상).
    final data = await prepared.reveal.toByteData();
    final px = data!.buffer.asUint8List();
    var maxOrder = 0;
    for (var i = 0; i < px.length; i += 4) {
      // 영영 안 드러나는 픽셀은 순서값이 아니라 표식이다.
      if (px[i] == kRevealHiddenSegment) continue;
      if (px[i] > maxOrder) maxOrder = px[i];
    }
    expect(maxOrder, greaterThan(0), reason: '획이 없어 상한 시험이 무의미하다');
    expect(
      maxOrder,
      lessThanOrEqualTo(sharpness.maxOrderValue),
      reason: '굽기가 페인터가 못 지우는 구간까지 순서값을 썼다',
    );
  });
}
