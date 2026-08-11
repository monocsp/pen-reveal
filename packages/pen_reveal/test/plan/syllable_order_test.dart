// 음절 힌트와 자모 순서. **힌트가 없을 때 동작이 안 바뀌는 것**이 이 파일의 절반이다 —
//   annotation 은 글씨가 아닐 수도 있다는 계약(그림)이 있어서, 기본 경로를 건드리면 안 된다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

const _w = 60;
const _h = 40;

/// 채워진 사각형 하나를 픽셀 목록으로.
List<int> _box(int left, int top, int right, int bottom) => [
      for (var y = top; y <= bottom; y++)
        for (var x = left; x <= right; x++) y * _w + x,
    ];

/// 글자 두 개가 **획으로 이어진** 한 줄. 실제 손글씨에서 관찰된 구조를 그대로 옮겼다:
///   · 이웃 음절이 붙어 하나의 연결요소가 된다("견"과 "한")
///   · 받침은 떨어져 별도 연결요소가 된다("발"의 ㄹ)
///   · 옆 글자가 글자 전체 높이를 덮어서 받침이 **같은 줄**로 묶인다
///
///        x4      x17  x18───x31   x32      x46
///   y4   ㅂ  ㅏ          ═다리═     ███████
///   y16  ─┘  ─┘                     █ 둘째 █
///   y20  ㄹㄹㄹㄹ                    █ 글자 █
///   y30  ─────┘                     ███████
Int32List _twoJoinedGlyphs() => Int32List.fromList([
      ..._box(4, 4, 9, 16), // 첫 글자 초성 (ㅂ)
      ..._box(13, 4, 17, 16), // 첫 글자 중성 (ㅏ)
      ..._box(4, 20, 17, 30), // 첫 글자 종성 (ㄹ) — 떨어져 있다
      ..._box(18, 8, 31, 10), // ← 두 글자를 잇는 획
      ..._box(32, 4, 46, 30), // 둘째 글자 — 전체 높이를 덮는다
    ]);

void main() {
  group('음절 힌트가 없으면', () {
    test('연결요소 그대로 — 붙은 두 글자는 한 덩어리다', () {
      final chunks = segmentAnnotation(
        pixels: _twoJoinedGlyphs(),
        width: _w,
        height: _h,
      );
      // 초성 / (중성+다리+둘째글자) / 종성 — 셋이다. 붙은 두 글자는 못 가른다.
      expect(chunks.length, 3);
      expect(
        chunks.every((c) => c.strokes.isEmpty),
        isTrue,
        reason: '힌트가 없으면 자모 순서를 만들지 않는다',
      );
    });
  });

  group('음절 힌트를 주면', () {
    late List<AnnotationChunk> chunks;

    setUp(() {
      chunks = segmentAnnotation(
        pixels: _twoJoinedGlyphs(),
        width: _w,
        height: _h,
        config: const AnnotationSegmenterConfig(expectedSyllableCount: 2),
      );
    });

    test('붙어 있어도 글자 수만큼 갈린다', () {
      expect(chunks.length, 2);
    });

    test('픽셀을 하나도 안 잃는다 — 진행도 1 계약', () {
      final all = <int>{};
      for (final c in chunks) {
        all.addAll(c.pixels);
      }
      expect(all.length, _twoJoinedGlyphs().length);
    });

    test('음절은 왼쪽부터', () {
      expect(chunks[0].left, lessThan(chunks[1].left));
    });

    test('자모가 위→아래, 같은 높이는 좌→우 로 정렬된다', () {
      final first = chunks.first;
      expect(
        first.strokes.length,
        greaterThanOrEqualTo(2),
        reason: '첫 글자는 위(초성·중성)와 종성으로 갈려야 한다',
      );

      // 각 조각의 bbox 를 다시 재서 순서를 확인한다.
      List<int> boxOf(Int32List one) {
        var l = 1 << 30;
        var t = 1 << 30;
        var b = -1;
        for (final i in one) {
          final x = i % _w;
          final y = i ~/ _w;
          if (x < l) l = x;
          if (y < t) t = y;
          if (y > b) b = y;
        }
        return [l, t, b];
      }

      final boxes = first.strokes.map(boxOf).toList();
      // 마지막 조각(받침)이 제일 아래에 있어야 한다.
      final lastTop = boxes.last[1];
      for (final box in boxes.take(boxes.length - 1)) {
        expect(box[1], lessThan(lastTop), reason: '받침이 마지막이어야 한다');
      }
      // 같은 띠 안에서는 왼쪽부터.
      final topBand = boxes.where((b) => b[1] < lastTop).toList();
      for (var i = 1; i < topBand.length; i++) {
        expect(topBand[i][0], greaterThan(topBand[i - 1][0]));
      }
    });

    test('덩어리를 늘리지 않는다 — 순서는 within 에 담는다', () {
      // 자모가 3개여도 세그먼트는 음절 수(2)를 넘지 않는다.
      expect(chunks.length, 2);
      expect(
        chunks.first.strokes.length,
        greaterThan(1),
        reason: '자모는 strokes 안에만 있고 별도 덩어리가 되지 않는다',
      );
    });
  });

  group('힌트가 무의미하면 조용히 기존 동작으로', () {
    // ⚠️ **예전엔 "덩어리가 하나뿐이면 안 가른다" 를 잠그고 있었다.** 그건 구현의
    //   `row.length > 1` 조건을 그대로 옮겨 적은 것인데, 하필 **갈라야 할 이유가 가장 큰
    //   경우**를 막고 있었다 — 줄이 통째로 한 연결요소면 연결요소만으로는 음절이 절대
    //   안 나뉜다. 실제로 정본 map_deep_06 에서 "견한" 이 한 덩어리(폭 50px, 다른
    //   덩어리의 두 배)로 남아 **두 음절이 동시에 떴다.**
    //
    //   힌트를 준 쪽은 "이 줄을 n 음절로 갈라 달라" 고 말한 것이다. 조각이 몇 개인지는
    //   그 요청과 무관하다.
    test('덩어리가 하나뿐이어도 힌트대로 가른다', () {
      final chunks = segmentAnnotation(
        pixels: Int32List.fromList(_box(4, 4, 9, 18)),
        width: _w,
        height: _h,
        config: const AnnotationSegmenterConfig(expectedSyllableCount: 4),
      );
      expect(chunks.length, 4, reason: '한 덩어리라고 힌트를 무시하면 안 된다');
      // 갈린 조각은 왼쪽부터 차례로 놓인다.
      for (var i = 1; i < chunks.length; i++) {
        expect(
          chunks[i].left,
          greaterThanOrEqualTo(chunks[i - 1].left),
          reason: '음절이 좌→우 순서가 아니다',
        );
      }
    });

    test('힌트가 1 이면 안 가른다', () {
      final chunks = segmentAnnotation(
        pixels: _twoJoinedGlyphs(),
        width: _w,
        height: _h,
        config: const AnnotationSegmenterConfig(expectedSyllableCount: 1),
      );
      expect(chunks.every((c) => c.strokes.isEmpty), isTrue);
    });
  });
}
