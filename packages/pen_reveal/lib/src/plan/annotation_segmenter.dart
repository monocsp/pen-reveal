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
    this.strokes = const <Int32List>[],
  });

  /// 행 우선 평면 인덱스.
  final Int32List pixels;

  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 몇 번째 줄인가(0 이 맨 위). 줄이 하나면 전부 0.
  final int line;

  /// 덩어리 **안**을 다시 나눈 조각들 — 쓰는 순서대로. 비어 있으면 나누지 않은 것이다.
  ///
  ///   음절 힌트([AnnotationSegmenterConfig.expectedSyllableCount])를 주면 이 덩어리가
  ///   음절 하나가 되고, 여기에 그 음절의 자모가 **위→아래, 같은 높이는 좌→우** 순으로
  ///   들어간다. 표현 계층은 이 순서를 덩어리 **안의 진행도**로 인코딩하면 되므로
  ///   세그먼트를 자모 수만큼 늘리지 않아도 된다(늘리면 덩어리마다 쉼이 붙어 연출이
  ///   최소 386ms 길어진다 — 실측).
  ///
  ///   ⚠️ 자모가 붙어 있으면 못 가른다. 래스터에는 글자 경계도 획순도 없다 — 여기서 내는
  ///   것은 **연결요소를 읽는 순서로 정렬한 것**이지 진짜 자모 분해가 아니다.
  final List<Int32List> strokes;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

/// 덩어리 나누기 기준. 전부 **굽기 해상도 픽셀 단위**라 해상도를 바꾸면 같이 재야 한다.
class AnnotationSegmenterConfig {
  const AnnotationSegmenterConfig({
    this.minChunkPixels = 24,
    this.orphanAttachRatio = 0.8,
    this.lineOverlapRatio = 0.34,
    this.expectedSyllableCount,
    this.jamoBandOverlapRatio = 0.5,
  });

  /// 줄 하나에 글자가 **몇 자**인지 아는 경우에만 준다. `null` 이면 연결요소 그대로다.
  ///
  ///   왜 힌트가 필요한가: 손글씨는 이웃 음절이 실제로 **붙는다**(실측: "발견한곳" 에서
  ///   "견"과 "한"이 8-이웃으로 이어진 한 덩어리다). 연결성만으로는 절대 못 가른다.
  ///   반대로 "곳"은 ㄱ·ㅗ·ㅅ 이 세 덩어리로 떨어져 나온다 — 붙는 쪽과 떨어지는 쪽이
  ///   섞여 있어서 개수를 모르면 어느 쪽으로도 판단할 수 없다.
  ///
  ///   ⚠️ 글씨가 아닐 수도 있다는 계약은 그대로다(map_deep_05 는 육각형 얼굴 그림).
  ///   그래서 **기본은 `null`** 이고, 아는 호출부만 준다.
  final int? expectedSyllableCount;

  /// 음절 안에서 두 조각이 "같은 높이"인가 — 세로로 겹친 길이 ÷ 둘 중 낮은 높이.
  ///
  ///   ⚠️ 중심 y 차이로 보면 안 된다. ㅂ 과 ㅏ 는 둘 다 세로로 길어 중심이 비슷하지만,
  ///   ㅗ 처럼 납작한 자모는 중심이 크게 달라진다. 겹침 비율로 봐야 "ㅂ·ㅏ 는 같은 줄,
  ///   ㄹ 은 아랫줄" 이 제대로 나온다.
  final double jamoBandOverlapRatio;

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

  // 값 동등성 — 없으면 호출부가 "설정이 바뀌었나" 를 못 물어서 **매 build 마다 다시
  //   굽거나**, 그걸 피하려고 `ValueKey` 로 우회해야 한다(계측대가 그러고 있었다).
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnnotationSegmenterConfig &&
          other.minChunkPixels == minChunkPixels &&
          other.orphanAttachRatio == orphanAttachRatio &&
          other.lineOverlapRatio == lineOverlapRatio &&
          other.expectedSyllableCount == expectedSyllableCount);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(
        minChunkPixels,
        orphanAttachRatio,
        lineOverlapRatio,
        expectedSyllableCount,
      );
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
    final syllables = config.expectedSyllableCount;
    // ⚠️ 예전엔 `row.length > 1` 도 요구했다. 그러면 **줄이 통째로 한 연결요소일 때**
    //   — 즉 자모가 다 붙어 갈라야 할 이유가 가장 큰 경우 — 힌트를 줘도 안 갈렸다.
    //   조각 개수가 아니라 "몇 음절로 갈라 달라고 했나" 로만 판단한다.
    if (syllables != null && syllables > 1) {
      out.addAll(_asSyllables(row, line, syllables, width, height, config));
      continue;
    }
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

/// 줄 하나를 음절 [count] 개로 가르고, 음절 안을 쓰는 순서로 정렬한다.
///
///   경계는 **균등 분할을 출발점으로 잡고 잉크가 가장 얇은 열로 스냅**한다. 균등만 쓰면
///   획 한복판을 자르고, 골짜기만 찾으면 음절 안의 세로 자모 사이(ㅂ 과 ㅏ)가 더 깊어
///   엉뚱한 데를 자른다. 둘을 합쳐야 실제 글자 사이로 간다.
List<AnnotationChunk> _asSyllables(
  List<_Component> row,
  int line,
  int count,
  int width,
  int height,
  AnnotationSegmenterConfig config,
) {
  var left = 1 << 30;
  var right = -1;
  for (final c in row) {
    if (c.left < left) left = c.left;
    if (c.right > right) right = c.right;
  }
  final span = right - left + 1;
  if (span < count) return _plainChunks(row, line);

  // 열별 잉크 양 — 경계를 얇은 데로 밀 때 쓴다.
  final ink = Int32List(span);
  for (final c in row) {
    for (final index in c.pixels) {
      final x = index % width - left;
      if (x >= 0 && x < span) ink[x]++;
    }
  }

  final cell = span / count;
  final cuts = <int>[];
  final slack = math.max(1, (cell * 0.25).round());
  for (var i = 1; i < count; i++) {
    final want = (cell * i).round();
    var best = want;
    var bestInk = 1 << 30;
    for (var x = want - slack; x <= want + slack; x++) {
      if (x <= 0 || x >= span) continue;
      if (ink[x] < bestInk) {
        bestInk = ink[x];
        best = x;
      }
    }
    cuts.add(best + left);
  }

  // ⚠️ **픽셀 단위로 자른다.** 연결요소를 칸에 배정하는 방식으로는 "견"과 "한"처럼
  //   실제로 이어진 덩어리를 절대 못 가른다(실측: 51px 짜리 한 덩어리로 남았다).
  //   경계가 잉크가 얇은 열로 스냅돼 있으므로 획을 가로지르는 손해는 최소다.
  final cellPixels = List<List<int>>.generate(count, (_) => <int>[]);
  for (final c in row) {
    for (final index in c.pixels) {
      final x = index % width;
      var slot = 0;
      while (slot < cuts.length && x >= cuts[slot]) {
        slot++;
      }
      cellPixels[slot].add(index);
    }
  }

  final out = <AnnotationChunk>[];
  for (final cellIndices in cellPixels) {
    if (cellIndices.isEmpty) continue;
    // 칸 안에서 다시 연결요소를 잡으면 그게 곧 자모 후보다.
    final group = _connectedComponents(
      Int32List.fromList(cellIndices),
      width,
      height,
    );
    if (group.isEmpty) continue;
    final ordered = _orderJamo(group, config);
    var l = 1 << 30;
    var t = 1 << 30;
    var r = -1;
    var b = -1;
    var total = 0;
    for (final c in ordered) {
      if (c.left < l) l = c.left;
      if (c.top < t) t = c.top;
      if (c.right > r) r = c.right;
      if (c.bottom > b) b = c.bottom;
      total += c.pixels.length;
    }
    // 픽셀은 **쓰는 순서대로** 이어 붙인다 — 표현 계층이 같은 순서의 진행도를 만든다.
    final flat = Int32List(total);
    final strokes = <Int32List>[];
    var at = 0;
    for (final c in ordered) {
      final one = c.toInt32List();
      strokes.add(one);
      for (final index in one) {
        flat[at++] = index;
      }
    }
    out.add(
      AnnotationChunk(
        pixels: flat,
        left: l,
        top: t,
        right: r,
        bottom: b,
        line: line,
        strokes: strokes,
      ),
    );
  }
  return out.isEmpty ? _plainChunks(row, line) : out;
}

List<AnnotationChunk> _plainChunks(List<_Component> row, int line) => [
      for (final c in row)
        AnnotationChunk(
          pixels: c.toInt32List(),
          left: c.left,
          top: c.top,
          right: c.right,
          bottom: c.bottom,
          line: line,
        ),
    ];

/// 음절 안의 조각들을 **위→아래, 같은 높이는 좌→우** 로.
///
///   "같은 높이"는 세로 겹침 비율로 본다 — ㅂ 과 ㅏ 는 크게 겹쳐 한 띠, 받침 ㄹ 은
///   겹침이 작아 다음 띠로 내려간다.
List<_Component> _orderJamo(
  List<_Component> group,
  AnnotationSegmenterConfig config,
) {
  final rest = [...group]..sort((a, b) => a.top.compareTo(b.top));
  final out = <_Component>[];
  while (rest.isNotEmpty) {
    final head = rest.removeAt(0);
    final band = <_Component>[head];
    rest.removeWhere((c) {
      final overlap =
          math.min(head.bottom, c.bottom) - math.max(head.top, c.top) + 1;
      final shorter = math.min(
        head.bottom - head.top + 1,
        c.bottom - c.top + 1,
      );
      final same =
          shorter > 0 && overlap / shorter >= config.jamoBandOverlapRatio;
      if (same) band.add(c);
      return same;
    });
    band.sort((a, b) => a.left.compareTo(b.left));
    out.addAll(band);
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
