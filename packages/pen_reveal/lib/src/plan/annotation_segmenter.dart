// src/plan/annotation_segmenter.dart — X 를 뺀 붉은 픽셀(손글씨·그림)을
//   **읽는 순서**대로 덩어리로 가른다.
//
//   ⚠️ **한글의 진짜 획순은 래스터에서 복원할 수 없다.** 교차점에 시간 정보가 없어서
//   어느 자모를 먼저 썼는지 알 길이 없다. 글자 안을 한 붓 DFS 로 훑으면 자모가 역순으로
//   써져 한글 읽는 사람에게 오히려 어색해진다(codex 경고). 그래서 여기서 내는 것은
//   **덩어리 단위 읽기 순서**뿐이고, 덩어리 안은 왼→오 wipe 로 때운다.
//
//   ⚠️ 덩어리를 `character` 라 부르지 않는 이유: 연결요소가 음절과 1:1 이 아니다.
//   한글 손글씨는 이웃 음절과 붙는다(실측: "발견한곳" 이 굽기 해상도 420px 에서 두
//   덩어리, 원본 879px 에서 열 덩어리). 아예 글씨가 아닌 경우도 있다 — map_deep_05 는
//   문구 대신 육각형 얼굴 그림이다. **정직하게 "덩어리"라고 부른다.**
//
//   ⚠️ 작은 조각을 먼저 버리면 안 된다. 느낌표의 점, 반짝임, 서명의 짧은 획이 다 작다.
//   가까운 덩어리에 **먼저 붙여 보고**, 못 붙은 것은 제 덩어리로 세운다 —
//   **버리지는 않는다**(진행도 1 에서 최종본과 100% 같아야 한다. 2026-08-07 회귀).
//
//   순수 Dart 다 — `package:flutter` 를 안 쓴다.
import 'dart:math' as math;
import 'dart:typed_data';

/// 읽기 순서로 정렬된 덩어리 하나.
class AnnotationChunk {
  const AnnotationChunk({
    required this.pixels,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.line,
  });

  /// 행 우선 평면 인덱스.
  final Int32List pixels;

  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 몇 번째 줄인가(0 이 맨 위). 줄이 하나면 전부 0.
  final int line;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

/// 덩어리 나누기 기준. 전부 **굽기 해상도 픽셀 단위**라 해상도를 바꾸면 같이 재야 한다.
class AnnotationSegmenterConfig {
  const AnnotationSegmenterConfig({
    this.minChunkPixels = 24,
    this.orphanAttachRatio = 0.8,
    this.lineOverlapRatio = 0.34,
  });

  /// 이보다 작은 연결요소는 **바로 버리는 게 아니라** 붙일 곳을 찾는다.
  ///
  ///   기본값은 굽기 해상도 420px 실측 기준 — 그 해상도에서 가장 작은 진짜 조각
  ///   (map_deep_05 의 반짝임 획)이 54px, 확실한 잡티는 한 자릿수다.
  final int minChunkPixels;

  /// 작은 조각을 붙일 최대 거리 = 그 줄 덩어리 높이 중앙값 × 이 비율.
  final double orphanAttachRatio;

  /// 두 덩어리가 같은 줄인가 — 세로로 겹친 길이 ÷ 둘 중 낮은 높이.
  ///
  ///   ⚠️ 중심 y 로 묶으면 **한글에서 반드시 틀린다**. 받침(종성)이 따로 떨어진
  ///   연결요소라 중심이 낮게 잡혀, 한 줄짜리 문구가 "윗줄 + 아랫줄" 로 갈린다
  ///   (실측: "발견한곳" 이 두 줄로 잘못 잡혔다). 겹침으로 봐야 받침이 제 글자와 붙는다.
  final double lineOverlapRatio;
}

/// [pixels] 를 읽기 순서(위 줄 먼저, 줄 안에서는 왼→오) 덩어리로 가른다.
List<AnnotationChunk> segmentAnnotation({
  required Int32List pixels,
  required int width,
  required int height,
  AnnotationSegmenterConfig config = const AnnotationSegmenterConfig(),
}) {
  if (pixels.isEmpty) return const <AnnotationChunk>[];

  final components = _connectedComponents(pixels, width, height);
  if (components.isEmpty) return const <AnnotationChunk>[];

  final solid = <_Component>[];
  final orphans = <_Component>[];
  for (final component in components) {
    (component.pixels.length >= config.minChunkPixels ? solid : orphans).add(
      component,
    );
  }
  // 큰 덩어리가 하나도 없으면(전부 자잘한 그림) 있는 대로 쓴다.
  if (solid.isEmpty) {
    solid.addAll(orphans);
    orphans.clear();
  }

  // 붙을 데를 못 찾은 조각도 제 덩어리로 남는다 — 픽셀 하나도 안 버린다.
  solid.addAll(_attachOrphans(solid, orphans, config));

  final lines = _groupIntoLines(solid, config);
  final out = <AnnotationChunk>[];
  for (var line = 0; line < lines.length; line++) {
    final row = lines[line]..sort((a, b) => a.left.compareTo(b.left));
    for (final component in row) {
      out.add(
        AnnotationChunk(
          pixels: component.toInt32List(),
          left: component.left,
          top: component.top,
          right: component.right,
          bottom: component.bottom,
          line: line,
        ),
      );
    }
  }
  return out;
}

/// 8-이웃 연결요소. 입력에 있는 픽셀만 이어 본다.
List<_Component> _connectedComponents(Int32List pixels, int width, int height) {
  final member = Uint8List(width * height);
  for (final index in pixels) {
    member[index] = 1;
  }
  final seen = Uint8List(width * height);
  final out = <_Component>[];
  final queue = Int32List(pixels.length);
  for (final start in pixels) {
    if (seen[start] == 1) continue;
    seen[start] = 1;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    final component = _Component();
    while (head < tail) {
      final index = queue[head++];
      final x = index % width;
      final y = index ~/ width;
      component.add(index, x, y);
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final neighbour = ny * width + nx;
          if (member[neighbour] == 1 && seen[neighbour] == 0) {
            seen[neighbour] = 1;
            queue[tail++] = neighbour;
          }
        }
      }
    }
    out.add(component);
  }
  return out;
}

/// 작은 조각을 가장 가까운 덩어리에 붙인다. **못 붙은 것을 돌려준다** —
///   호출부가 제 덩어리로 세운다(버리면 그 픽셀이 영영 안 드러난다).
List<_Component> _attachOrphans(
  List<_Component> solid,
  List<_Component> orphans,
  AnnotationSegmenterConfig config,
) {
  if (orphans.isEmpty) return const <_Component>[];
  final heights = [for (final c in solid) c.bottom - c.top + 1]..sort();
  final medianHeight = heights[heights.length ~/ 2];
  final reach = medianHeight * config.orphanAttachRatio;
  final unattached = <_Component>[];
  for (final orphan in orphans) {
    _Component? best;
    var bestGap = double.infinity;
    for (final host in solid) {
      final gap = _boxGap(orphan, host);
      if (gap < bestGap) {
        bestGap = gap;
        best = host;
      }
    }
    if (best != null && bestGap <= reach) {
      best.absorb(orphan);
    } else {
      unattached.add(orphan);
    }
  }
  return unattached;
}

/// 두 bbox 사이의 빈틈(겹치면 0).
double _boxGap(_Component a, _Component b) {
  final dx = math.max(0, math.max(a.left - b.right, b.left - a.right));
  final dy = math.max(0, math.max(a.top - b.bottom, b.top - a.bottom));
  return math.sqrt((dx * dx + dy * dy).toDouble());
}

/// 세로 겹침으로 줄을 묶고, 줄을 위에서 아래로 정렬한다.
List<List<_Component>> _groupIntoLines(
  List<_Component> components,
  AnnotationSegmenterConfig config,
) {
  final remaining = [...components]..sort((a, b) => a.top.compareTo(b.top));
  final lines = <List<_Component>>[];
  for (final component in remaining) {
    List<_Component>? target;
    for (final line in lines) {
      for (final member in line) {
        final overlap = math.min(component.bottom, member.bottom) -
            math.max(component.top, member.top) +
            1;
        final shorter = math.min(
          component.bottom - component.top + 1,
          member.bottom - member.top + 1,
        );
        if (shorter > 0 && overlap / shorter >= config.lineOverlapRatio) {
          target = line;
          break;
        }
      }
      if (target != null) break;
    }
    if (target == null) {
      lines.add(<_Component>[component]);
    } else {
      target.add(component);
    }
  }
  lines.sort((a, b) {
    final aTop = a.map((c) => c.top).reduce(math.min);
    final bTop = b.map((c) => c.top).reduce(math.min);
    return aTop.compareTo(bTop);
  });
  return lines;
}

/// 모으는 동안만 쓰는 가변 덩어리.
class _Component {
  final List<int> pixels = <int>[];
  int left = 1 << 30;
  int top = 1 << 30;
  int right = -1;
  int bottom = -1;

  void add(int index, int x, int y) {
    pixels.add(index);
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }

  void absorb(_Component other) {
    pixels.addAll(other.pixels);
    left = math.min(left, other.left);
    top = math.min(top, other.top);
    right = math.max(right, other.right);
    bottom = math.max(bottom, other.bottom);
  }

  Int32List toInt32List() => Int32List.fromList(pixels);
}
