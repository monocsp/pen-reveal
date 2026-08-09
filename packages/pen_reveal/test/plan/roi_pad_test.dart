// ROI 여백이 실제로 필요하다는 것을 **정본 없이** 잠근다.
//
//   `bakeOneStrokeOrder` 는 잉크 bbox + `_roiPad` 만 잘라 커널을 태운다. 순수 최적화라
//   출력이 캔버스 전체로 돌린 것과 같아야 한다.
//
//   ⚠️ **정본 코퍼스로는 이 계약을 못 지킨다.** 정본 10종의 bbox 는 캔버스 경계에 하나도
//   안 닿아서(가장 가까운 것도 210 에서 좌 23px 여유) `_roiPad` 를 0 으로 낮춰도 30/30 이
//   통과한다. 깨지는 것은 bbox 가 경계 쪽으로 몰린 그림이고, 그 자리를 여기서 만든다 —
//   합성이라 공개 CI 에서 자산 없이 늘 돈다.
//
//   ⚠️ **위치를 옮겨 비교하면 안 된다.** 캔버스 경계는 ROI 여백과 무관하게 팽창을 막으므로
//   같은 그림이라도 안쪽에 있을 때와 경계에 붙었을 때의 답이 원래 다르다(그게 정상이다).
//   그래서 여기서는 **알려진 좋은 출력을 값으로 못 박는다** — 여백을 줄이면 이 값이 바뀐다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

Uint8List _canvas(int w, int h, List<(int, int)> ink) {
  final a = Uint8List(w * h);
  for (final (x, y) in ink) {
    a[y * w + x] = 255;
  }
  return a;
}

List<int> _at(Uint8List bytes, int w, List<(int, int)> ink) =>
    [for (final (x, y) in ink) bytes[y * w + x]];

void main() {
  group('ROI 여백', () {
    // 감사에서 나온 최소 반례 — 잉크 넉 점. 여백이 0 이면 `(6,3)` 의 순서값이
    //   254(맨 끝)에서 0(맨 처음)으로 **뒤집힌다** — 최대치 오차다.
    const counterexample = <(int, int)>[(3, 3), (6, 3), (3, 5), (5, 5)];

    test('최소 반례의 순서가 캔버스 전체로 돌린 것과 같다', () {
      final r = bakeOneStrokeOrder(
        StrokeMask(_canvas(20, 20, counterexample), 20, 20),
      );
      expect(
        _at(r.bytes, 20, counterexample),
        [0, 254, 0, 0],
        reason: '여백을 줄였는가? (6,3) 은 뼈대에 못 닿은 섬이라 맨 끝(254)이어야 한다',
      );
    });

    test('마스크 픽셀은 하나도 안 드러난 채로 안 남는다 — 커버리지 계약', () {
      for (final shape in <List<(int, int)>>[
        counterexample,
        // 캔버스 네 변에 닿는 테두리.
        [
          for (var x = 0; x < 24; x++) ...[(x, 0), (x, 23)],
          for (var y = 0; y < 24; y++) ...[(0, y), (23, y)],
        ],
        // 좌상 모서리 한 점.
        [(0, 0)],
        // 맨 윗줄에 붙은 가로 1px 선.
        [for (var x = 2; x < 20; x++) (x, 0)],
      ]) {
        final r = bakeOneStrokeOrder(
          StrokeMask(_canvas(24, 24, shape), 24, 24),
        );
        final mask = _canvas(24, 24, shape);
        for (var i = 0; i < mask.length; i++) {
          if (mask[i] == 0) continue;
          expect(
            r.bytes[i],
            lessThan(255),
            reason: '잉크 픽셀이 영영 안 드러난다 (i=$i)',
          );
        }
      }
    });

    test('잉크가 캔버스를 꽉 채워도(ROI = 전체) 터지지 않는다', () {
      const w = 24;
      const h = 24;
      final full = Uint8List(w * h)..fillRange(0, w * h, 255);
      final r = bakeOneStrokeOrder(StrokeMask(full, w, h));
      expect(r.bytes.where((v) => v == 255), isEmpty);
    });

    test('빈 마스크는 전면 255 · 길이 0', () {
      final r = bakeOneStrokeOrder(StrokeMask(Uint8List(400), 20, 20));
      expect(r.bytes.every((v) => v == 255), isTrue);
      expect(r.length, 0);
    });
  });
}
