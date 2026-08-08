// X 를 두 획으로 가르는 탐지를 잠근다 — 합성 마스크 갈래.
//
//   각도·굵기·잡음을 내가 정해 놓고 X 를 그린 다음 "그 각도가 나오나" 를 묻는다.
//   정답을 알고 들어가는 그림이라 탐지가 어디서부터 어긋나는지가 바로 보이고, 자산이
//   한 장도 필요 없어서 공개 CI 에서 늘 돈다.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

/// 두 획으로 된 X 를 그린다. [rotation] 라디안만큼 통째로 돌린다.
CrossMask drawCross({
  int size = 120,
  double thickness = 14,
  double rotation = 0,
  double armAngle = math.pi / 4,
  double noise = 0,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final pixels = <int>[];
  final centre = size / 2;
  // 화면 좌표(y 아래로 증가)에서 `\` 는 +armAngle, `/` 는 −armAngle 이다.
  final axes = <List<double>>[
    [math.cos(armAngle + rotation), math.sin(armAngle + rotation)],
    [math.cos(-armAngle + rotation), math.sin(-armAngle + rotation)],
  ];
  final reach = size * 0.36;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final rx = x - centre;
      final ry = y - centre;
      for (final axis in axes) {
        final along = rx * axis[0] + ry * axis[1];
        final across = -rx * axis[1] + ry * axis[0];
        final half =
            thickness / 2 + (noise > 0 ? random.nextDouble() * noise : 0);
        if (along.abs() <= reach && across.abs() <= half) {
          pixels.add(y * size + x);
          break;
        }
      }
    }
  }
  return CrossMask(Int32List.fromList(pixels), size);
}

class CrossMask {
  const CrossMask(this.pixels, this.width);
  final Int32List pixels;
  final int width;
}

/// 각도가 [expected] 에서 [tolerance] 안인가(0~180 순환).
Matcher nearAngle(int expected, {int tolerance = 3}) => predicate<int>(
      (actual) {
        final d = (actual - expected).abs() % 180;
        return math.min(d, 180 - d) <= tolerance;
      },
      '$expected° ±$tolerance°',
    );

void main() {
  group('합성 X', () {
    test(r'`\` 획과 `/` 획을 각도로 가른다', () {
      final mask = drawCross();
      final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width)!;

      // `\` = 오른쪽 아래(0~90°), `/` = 왼쪽 아래(90~180°).
      expect(split.backslash.angleDegrees, nearAngle(45));
      expect(split.slash.angleDegrees, nearAngle(135));
      expect(split.backslash.angleDegrees, greaterThan(0));
      expect(split.backslash.angleDegrees, lessThan(90));
      expect(split.slash.angleDegrees, greaterThan(90));
      expect(split.slash.angleDegrees, lessThan(180));
    });

    test('모든 픽셀이 정확히 한 획에 들어간다 — 교차부도 한쪽만', () {
      final mask = drawCross();
      final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width)!;

      expect(split.onBackslash.length, mask.pixels.length);
      expect(
        split.backslashCount + split.slashCount,
        mask.pixels.length,
        reason: '두 획의 합이 X 전체와 같아야 한다 — 8비트 텍스처는 픽셀당 시각이 하나뿐이다',
      );
      expect(split.backslashCount, greaterThan(0));
      expect(split.slashCount, greaterThan(0));
    });

    test('각 획 안의 진행도는 위 → 아래로 커진다', () {
      final mask = drawCross();
      final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width)!;

      for (final want in const [1, 0]) {
        var topY = 1 << 30;
        var bottomY = -1;
        var atTop = 2.0;
        var atBottom = -1.0;
        for (var i = 0; i < mask.pixels.length; i++) {
          if (split.onBackslash[i] != want) continue;
          final y = mask.pixels[i] ~/ mask.width;
          if (y < topY) {
            topY = y;
            atTop = split.within[i];
          }
          if (y > bottomY) {
            bottomY = y;
            atBottom = split.within[i];
          }
        }
        expect(atTop, lessThan(0.2), reason: '맨 위 픽셀은 획의 시작이어야 한다');
        expect(atBottom, greaterThan(0.8), reason: '맨 아래 픽셀은 획의 끝이어야 한다');
      }
      expect(
        split.within.every((v) => v >= 0 && v <= 1),
        isTrue,
        reason: '진행도는 0~1 로 정규화된다',
      );
    });

    test('회전시켜도 두 획을 가른다 — 회전 각도만큼 축이 따라 돈다', () {
      for (final degrees in const [-30, -15, 10, 25]) {
        final rotation = degrees * math.pi / 180;
        final mask = drawCross(rotation: rotation);
        final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width);

        expect(split, isNotNull, reason: '$degrees° 회전에서 분해 실패');
        expect(split!.backslash.angleDegrees, nearAngle(45 + degrees));
        expect(split.slash.angleDegrees, nearAngle(135 + degrees));
        expect(split.backslashCount + split.slashCount, mask.pixels.length);
      }
    });

    test('굵기가 달라도 가른다', () {
      for (final thickness in const <double>[8, 14, 22]) {
        final mask = drawCross(thickness: thickness);
        final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width);

        expect(split, isNotNull, reason: '굵기 $thickness 에서 분해 실패');
        expect(split!.backslash.angleDegrees, nearAngle(45, tolerance: 5));
        expect(split.slash.angleDegrees, nearAngle(135, tolerance: 5));
      }
    });

    test('가장자리가 너덜해도(잡음) 가른다', () {
      final mask = drawCross(noise: 4);
      final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width);

      expect(split, isNotNull);
      expect(split!.backslash.angleDegrees, nearAngle(45, tolerance: 5));
      expect(split.slash.angleDegrees, nearAngle(135, tolerance: 5));
      expect(split.backslashCount + split.slashCount, mask.pixels.length);
    });

    test('사잇각이 좁아도(82°, map_deep_04 급) 가른다', () {
      final mask = drawCross(armAngle: 41 * math.pi / 180);
      final split = splitCrossStrokes(pixels: mask.pixels, width: mask.width);

      expect(split, isNotNull);
      expect(
        (split!.slash.angleDegrees - split.backslash.angleDegrees).abs(),
        greaterThanOrEqualTo(25),
      );
      expect(split.backslashCount + split.slashCount, mask.pixels.length);
    });

    test('X 가 아니면 null — 획 하나짜리 막대는 두 축이 없다', () {
      final pixels = <int>[];
      for (var y = 20; y < 100; y++) {
        for (var x = y - 6; x <= y + 6; x++) {
          pixels.add(y * 120 + x);
        }
      }
      expect(
        splitCrossStrokes(pixels: Int32List.fromList(pixels), width: 120),
        isNull,
      );
    });

    test('픽셀이 거의 없으면 null', () {
      expect(
        splitCrossStrokes(
          pixels: Int32List.fromList(const [0, 1, 2]),
          width: 10,
        ),
        isNull,
      );
    });
  });
}

// 실지도 픽스처 갈래는 test/corpus/cross_stroke_corpus_test.dart 로 갈라 나갔다.
