// src/plan/detector.dart — 그림 두 장(바닥/최종)의 차이를 읽어
//   **무엇을 어떤 순서로 드러낼지**([RevealPlan])를 만든다. 코어의 단일 진입점이다.
//
//   순서는 사용자 지정이다:
//     ① 길이 한 붓으로 파고들고
//     ② 빨간 X 를 `\` → `/` 두 획으로 긋고
//     ③ 곧바로 붉은 문구가 덩어리 단위로 왼→오 써진다
//
//   ⚠️ **여기엔 시간이 없다.** 몇 밀리초에 그릴지, 사이를 얼마나 띄울지, 어떤 curve 를
//   쓸지는 한 톨도 모른다 — 표현 계층(`src/timing/timing_policy.dart`)이 정한다.
//   이 파일이 아는 것은 "무엇이 무엇보다 먼저" 와 "그 안에서 몇 % 지점" 뿐이다.
//
//   ⚠️ **드러낼 픽셀은 하나도 안 버린다.** 진행도 1 에서 최종본과 100% 같아져야 한다
//   (2026-08-07 회귀 — `test/plan/coverage_test.dart` 와 `test/corpus/coverage_corpus_test.dart`).
//   길은 뼈대 덩어리를 전부 훑고, 문구는
//   붙을 데 없는 조각도 제 덩어리로 세우고, 세그먼트 자리가 모자라면 묶어서라도 넣는다.
//
//   순수 Dart 다 — `package:flutter` 를 안 쓴다. 21만 픽셀 루프와 세선화를 통째로
//   `compute` 한 번에 태울 수 있어야 하기 때문이다.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pen_reveal/src/plan/annotation_segmenter.dart';
import 'package:pen_reveal/src/plan/cross_stroke_detector.dart';
import 'package:pen_reveal/src/plan/length_profile.dart';
import 'package:pen_reveal/src/plan/one_stroke_bake.dart';
import 'package:pen_reveal/src/plan/reveal_plan.dart';

/// 픽셀을 길/붉은표시/바닥으로 가르는 기준과, 붉은 덩어리에서 X 를 고르는 관문.
class RevealDetectConfig {
  const RevealDetectConfig({
    this.differenceThreshold = 18,
    this.composedAlphaThreshold = 200,
    this.accentRedDeltaThreshold = 35,
    this.xMinBlobAreaRatio = 6.9e-5,
    this.xMaxRoadDistanceRatio = 0.05,
    this.xMinRoadDistanceDominance = 1.6,
    this.xMinAreaRatio = 0.0050,
    this.xMaxAreaRatio = 0.0105,
    this.strayInkMaxPixels = 12,
    this.annotation = const AnnotationSegmenterConfig(),
  });

  /// |ΔR|+|ΔG|+|ΔB| 가 이 값 이하면 "안 변한 곳"(=바닥). 압축 잡음을 흘려보낸다.
  final int differenceThreshold;

  /// 최종본이 이보다 투명하면 무시한다(반투명 가장자리가 획으로 잡히는 것 방지).
  final int composedAlphaThreshold;

  /// R−G 가 이보다 크면 붉은 표시(X·문구)로 본다.
  final int accentRedDeltaThreshold;

  /// X 후보로 볼 최소 덩어리 크기 — **캔버스 면적 대비 비율**이다.
  ///
  ///   ⚠️ 절대 픽셀로 두면 굽기 해상도를 바꾸는 순간 조용히 무력화된다
  ///   (`RevealPreparer.longSide` 는 실제로 바뀐다). 아래 관문 넷이 전부
  ///   비율인 이유도 같다 — 해상도 240~1065 에서 면적비·거리비는 ±6% 안으로 불변인데
  ///   절대 픽셀 기준(`CrossCalibration.minComponentPixels` 등)은 무너진다.
  final double xMinBlobAreaRatio;

  /// X 는 **길 위에** 찍힌다 — 중심에서 길까지의 거리 ÷ 캔버스 폭이 이 값 이하여야 한다.
  ///
  ///   실측(지도 10종 × 해상도 6): X 0.0270~0.0334, 가장 가까운 non-X 0.0711~0.1916.
  final double xMaxRoadDistanceRatio;

  /// 2등이 1등보다 이 배수만큼은 멀어야 한다(실측 최악 2.05배).
  final double xMinRoadDistanceDominance;

  /// X 덩어리가 캔버스에서 차지하는 면적비의 실측 범위(관측 0.00692~0.00774).
  final double xMinAreaRatio;
  final double xMaxAreaRatio;

  /// 붉은 잉크에 **닿아 있는** 길 덩어리가 이보다 작으면 길이 아니라 그 잉크의 테두리로 본다.
  ///
  ///   ⚠️ 이게 없으면 화면에 붉은 점이 뜬다. 빨간 글씨의 안티에일리어싱 테두리는 바닥과
  ///   충분히 다르면서(diff > [differenceThreshold]) 아직 붉지는 않아(R−G ≤
  ///   [accentRedDeltaThreshold]) **길로 분류된다.** 뼈대에서 끊긴 섬이라 굽기가 길 단계의
  ///   **맨 끝** 시각을 주고, 그래서 글씨 차례가 오기도 전에 글씨 윤곽을 따라 점이 켜진다 —
  ///   정본 map_basic_01(420)에서 덩어리 101개·122px 이 그렇게 떴다.
  ///
  ///   크기 상한이 진짜 길을 지킨다. 길은 X 와 실제로 맞닿지만 한 덩어리(2,383px)라
  ///   이 관문에 걸리지 않는다. 0 으로 두면 규칙이 꺼진다.
  final int strayInkMaxPixels;

  final AnnotationSegmenterConfig annotation;
}

/// 탐지 입력 — isolate 를 넘길 수 있는 최소 형태(둘 다 같은 크기의 RGBA).
class RevealDetectInput {
  const RevealDetectInput({
    required this.baseRgba,
    required this.composedRgba,
    required this.width,
    required this.height,
    this.config = const RevealDetectConfig(),
  });

  /// 바닥(드러낼 것이 없는 상태)의 RGBA.
  final Uint8List baseRgba;

  /// 최종(다 드러난 상태)의 RGBA. **[baseRgba] 와 같은 크기·같은 구도**여야 한다 —
  ///   어긋나면 화면 전체가 '변한 곳'으로 잡혀 엉뚱한 획이 나온다.
  final Uint8List composedRgba;

  final int width;
  final int height;
  final RevealDetectConfig config;
}

/// 두 장을 읽어 드러낼 순서를 짠다. `compute` 진입점(인자 하나·순수 Dart).
RevealPlan detectReveal(RevealDetectInput input) {
  final w = input.width;
  final h = input.height;
  if (w <= 0 || h <= 0) {
    throw ArgumentError.value(w * h, 'width*height', '크기는 양수여야 한다');
  }
  final expected = w * h * 4;
  if (input.baseRgba.length != expected ||
      input.composedRgba.length != expected) {
    throw ArgumentError(
      'RGBA 길이가 크기와 안 맞는다 — expected $expected, '
      'base ${input.baseRgba.length}, composed ${input.composedRgba.length}',
    );
  }

  final cfg = input.config;
  final base = input.baseRgba;
  final composed = input.composedRgba;
  final road = Uint8List(w * h);
  final accent = <int>[];
  for (var i = 0; i < road.length; i++) {
    final j = i * 4;
    final diff = (composed[j] - base[j]).abs() +
        (composed[j + 1] - base[j + 1]).abs() +
        (composed[j + 2] - base[j + 2]).abs();
    if (diff <= cfg.differenceThreshold ||
        composed[j + 3] < cfg.composedAlphaThreshold) {
      continue;
    }
    if (composed[j] - composed[j + 1] > cfg.accentRedDeltaThreshold) {
      accent.add(i);
    } else {
      road[i] = 255;
    }
  }

  _absorbStrayInk(road, accent, w, h, cfg.strayInkMaxPixels);

  final segmentId = Uint8List(w * h)..fillRange(0, w * h, kRevealHiddenSegment);
  final within = Uint16List(w * h);
  final segments = <RevealSegment>[];

  accent.sort();
  final baked = bakeOneStrokeOrder(StrokeMask(road, w, h));
  _addRoad(baked, w, math.max(w, h), segmentId, within, segments);
  final leftovers = _addXStrokes(
    Int32List.fromList(accent),
    w,
    h,
    baked.bytes,
    cfg,
    segmentId,
    within,
    segments,
  );
  _addAnnotation(leftovers, w, h, cfg.annotation, segmentId, within, segments);

  return RevealPlan(
    width: w,
    height: h,
    segmentId: segmentId,
    within: within,
    segments: segments,
  );
}

/// 붉은 잉크에 닿은 **작은** 길 덩어리를 그 잉크 쪽으로 넘긴다.
///
///   빨간 글씨의 안티에일리어싱 테두리가 R−G 관문을 못 넘겨 길로 분류되는 것을 되돌린다.
///   자세한 근거는 [RevealDetectConfig.strayInkMaxPixels] 에 적었다.
///
///   ⚠️ **덩어리 단위로 판정한다.** 픽셀 단위로 "붉은 것에 닿았으면 넘긴다"로 하면 길이 X 와
///   실제로 맞닿는 자리에서 길 끝이 조금씩 깎여 나간다. 덩어리로 보면 진짜 길은 한 덩어리라
///   크기 상한에 걸려 통째로 남는다.
///
///   [road] 를 제자리에서 지우고 [accent] 에 밀어 넣는다.
void _absorbStrayInk(
  Uint8List road,
  List<int> accent,
  int w,
  int h,
  int maxPixels,
) {
  if (maxPixels <= 0 || accent.isEmpty) return;

  final isAccent = Uint8List(w * h);
  for (final i in accent) {
    isAccent[i] = 1;
  }

  final seen = Uint8List(w * h);
  final stack = <int>[];
  final blob = <int>[];
  for (var start = 0; start < road.length; start++) {
    if (road[start] == 0 || seen[start] == 1) continue;
    stack
      ..clear()
      ..add(start);
    blob.clear();
    seen[start] = 1;
    var touches = false;
    // 상한을 넘는 순간 멈추지 **않는다** — 덩어리를 끝까지 훑어야 다음 덩어리로 샐 일이 없다.
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      blob.add(p);
      final x = p % w;
      final y = p ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (isAccent[j] == 1) touches = true;
          if (road[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
    }
    if (!touches || blob.length > maxPixels) continue;
    for (final p in blob) {
      road[p] = 0;
      accent.add(p);
    }
  }
}

/// 길 — 세선화 한 붓 순서를 그대로 세그먼트 하나의 진행도로 옮긴다.
///
///   [longSide] 는 이 캔버스의 긴 변 — 잰 길이를 기준 해상도로 환산해 0~1 로 접는 데 쓴다.
void _addRoad(
  OneStrokeResult baked,
  int w,
  int longSide,
  Uint8List segmentId,
  Uint16List within,
  List<RevealSegment> segments,
) {
  final id = segments.length;
  var count = 0;
  var left = 1 << 30;
  var top = 1 << 30;
  var right = -1;
  var bottom = -1;
  for (var i = 0; i < baked.bytes.length; i++) {
    // `bakeOneStrokeOrder` 은 길 안을 0~254, 길 밖을 255 로 준다.
    final order = baked.bytes[i];
    if (order == 255) continue;
    segmentId[i] = id;
    within[i] = (order * kRevealWithinScale / 254).round();
    count++;
    final x = i % w;
    final y = i ~/ w;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  if (count == 0) return;
  segments.add(
    RevealSegment(
      id: id,
      kind: RevealSegmentKind.primaryStroke,
      pixelCount: count,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      // 한 붓 경로의 누적 길이 — 긴 길을 짧은 길과 같은 시간에 그으면 펜이 너무 빨라 보인다.
      measure: baked.length,
      // ⚠️ 밖으로 나가는 것은 **픽셀이 아니라 0~1** 이다. 표현 계층은 이 값만 보고
      //   자기 밴드(최소~최대)로 환산한다 — 코퍼스 기준·압축 곡선은 코어가 소유한다.
      relativeLength: normalizeStrokeLengthAt(baked.length, longSide: longSide),
    ),
  );
}

/// 붉은 픽셀에서 X 를 골라 두 획으로 가른다. 반환값은 **X 를 뺀 나머지**다.
///
///   ⚠️ **"최대 연결요소 = X" 는 쓰지 않는다.** 면적 우세비가 최악 1.21 배(map_deep_05 의
///   육각형 얼굴 그림)라 여유가 거의 없고, X 가 반쪽만 남으면 10종 중 6종이 문구를 X 로
///   골랐다. `splitCrossStrokes` 는 형태 검사이지 정체 검사가 아니라 non-X 덩어리도 8/10 이
///   통과한다. 가장 센 신호는 **위치**다 — X 는 길 위에 찍힌다(중심→길 거리비가 가장 가까운
///   non-X 보다 2.38~6.52 배 가깝고, 해상도를 240~1065 로 바꿔도 ±6% 안).
///
///   ⚠️ 관문에 걸리면 후보를 **문구 목록에 되돌린다.** 세그먼트로 곧장 박으면 id 가 제일
///   작아 읽기 순서를 무시하고 맨 처음 떠 버린다.
Int32List _addXStrokes(
  Int32List accent,
  int w,
  int h,
  Uint8List roadOrder,
  RevealDetectConfig cfg,
  Uint8List segmentId,
  Uint16List within,
  List<RevealSegment> segments,
) {
  if (accent.isEmpty) return accent;
  final chosen = _chooseX(accent, w, h, roadOrder, cfg);
  if (chosen == null) return accent;

  final x = chosen.pixels;
  final split = chosen.split;
  for (final wantBackslash in const [true, false]) {
    final want = wantBackslash ? 1 : 0;
    final count = wantBackslash ? split.backslashCount : split.slashCount;
    final pixels = Int32List(count);
    final progress = Float32List(count);
    var at = 0;
    for (var i = 0; i < x.length; i++) {
      if (split.onBackslash[i] != want) continue;
      pixels[at] = x[i];
      progress[at] = split.within[i];
      at++;
    }
    _addSegment(
      pixels: pixels,
      kind: wantBackslash
          ? RevealSegmentKind.crossBackslash
          : RevealSegmentKind.crossSlash,
      w: w,
      progress: progress,
      measure: wantBackslash ? split.backslashLength : split.slashLength,
      segmentId: segmentId,
      within: within,
      segments: segments,
    );
  }
  return _without(accent, x);
}

/// 고른 X 한 덩어리와 그 분해 결과.
class _ChosenX {
  const _ChosenX(this.pixels, this.split);
  final Int32List pixels;
  final CrossStrokeSplit split;
}

/// 관문 넷을 다 통과한 덩어리 하나 — 없으면 `null`.
_ChosenX? _chooseX(
  Int32List accent,
  int w,
  int h,
  Uint8List roadOrder,
  RevealDetectConfig cfg,
) {
  // 길 픽셀은 `_addRoad` 가 이미 구운 것을 그대로 읽는다(추가 비용 0).
  final drawn = <int>[];
  for (var i = 0; i < roadOrder.length; i++) {
    if (roadOrder[i] != 255) drawn.add(i);
  }
  // 길이 없으면 위치 신호도 없다 — 면적·형태만으로 고르면 문구를 X 로 오인한다.
  if (drawn.isEmpty) return null;
  // ⚠️ **길 채널 전부가 아니라 그중 제일 큰 덩어리**를 자로 쓴다. 붉은 문구 둘레의
  //   안티에일리어싱 부스러기도 "붉지 않은 변화"라 길 채널에 섞이는데, 그걸 길로 치면
  //   문구가 저 자신에게서 0px 떨어진 것이 되어 위치 신호가 통째로 무너진다
  //   (실측: 지도 10종 전부가 X 를 못 찾았다). 진짜 길은 2위보다 11~48배 크다.
  final road = _components(Int32List.fromList(drawn), w, h).first;

  final area = w * h;
  final blobs = _components(accent, w, h);
  final candidates = [
    for (final blob in blobs)
      if (blob.length / area >= cfg.xMinBlobAreaRatio) blob,
  ];
  if (candidates.isEmpty) return null;

  var bestAt = -1;
  var best = double.infinity;
  var second = double.infinity;
  for (var i = 0; i < candidates.length; i++) {
    final distance = _centroidToRoad(candidates[i], w, road);
    if (distance < best) {
      second = best;
      best = distance;
      bestAt = i;
    } else if (distance < second) {
      second = distance;
    }
  }
  if (bestAt < 0) return null;

  // ① 절대 — X 는 길 위에 있다.
  if (best / w > cfg.xMaxRoadDistanceRatio) return null;
  // ② 상대 — 2등이 확실히 더 멀어야 한다(둘이 비슷하면 어느 쪽인지 모르는 것이다).
  if (best > 0 && second / best < cfg.xMinRoadDistanceDominance) return null;
  // ③ 크기 — 문구 한 덩어리나 그림과는 면적비가 다르다.
  final ratio = candidates[bestAt].length / area;
  if (ratio < cfg.xMinAreaRatio || ratio > cfg.xMaxAreaRatio) return null;
  // ④ 형태 — 두 막대로 갈리는가.
  final split = splitCrossStrokes(pixels: candidates[bestAt], width: w);
  if (split == null) return null;
  return _ChosenX(candidates[bestAt], split);
}

/// 덩어리 무게중심에서 가장 가까운 길 픽셀까지의 거리.
///
///   ⚠️ **픽셀-최소가 아니라 중심 거리다.** 문구 한 글자가 길을 스치기만 해도 픽셀-최소는
///   0 이 되지만, 중심은 여전히 멀다.
double _centroidToRoad(Int32List blob, int w, Int32List road) {
  var sumX = 0.0;
  var sumY = 0.0;
  for (final index in blob) {
    sumX += index % w;
    sumY += index ~/ w;
  }
  final cx = sumX / blob.length;
  final cy = sumY / blob.length;
  var best = double.infinity;
  for (final index in road) {
    final dx = index % w - cx;
    final dy = index ~/ w - cy;
    final d = dx * dx + dy * dy;
    if (d < best) best = d;
  }
  return best.isFinite ? math.sqrt(best) : best;
}

/// 남은 붉은 픽셀 — 손글씨·그림을 읽기 순서 덩어리로.
///
///   자리가 모자라면 **버리지 않고 묶는다** — 마지막 한 자리에 남은 덩어리를 다 넣는다.
void _addAnnotation(
  Int32List leftovers,
  int w,
  int h,
  AnnotationSegmenterConfig config,
  Uint8List segmentId,
  Uint16List within,
  List<RevealSegment> segments,
) {
  final chunks = segmentAnnotation(
    pixels: leftovers,
    width: w,
    height: h,
    config: config,
  );
  for (var i = 0; i < chunks.length; i++) {
    final room = kRevealMaxSegmentId + 1 - segments.length;
    if (room <= 0) return;
    if (room == 1 && i < chunks.length - 1) {
      final merged = <int>[];
      for (final chunk in chunks.skip(i)) {
        merged.addAll(chunk.pixels);
      }
      _addSegment(
        pixels: Int32List.fromList(merged),
        kind: RevealSegmentKind.annotation,
        w: w,
        progress: null,
        segmentId: segmentId,
        within: within,
        segments: segments,
      );
      return;
    }
    _addSegment(
      pixels: chunks[i].pixels,
      kind: RevealSegmentKind.annotation,
      w: w,
      // 음절로 갈렸으면 자모 순서를 쓰고, 아니면 `_addSegment` 가 행 우선으로 매긴다.
      //   어느 쪽이든 덩어리 **안**은 위→아래다.
      progress: _jamoProgress(chunks[i], w),
      segmentId: segmentId,
      within: within,
      segments: segments,
    );
  }
}

/// 자모 순서를 덩어리 **안의 진행도**로 편다 — 조각 하나가 한 구간을 차지하고,
///   그 구간 안에서는 왼→오로 쓸린다.
///
///   세그먼트를 자모 수만큼 늘리지 않는 이유: 타이밍 정책이 덩어리마다 쉼(30ms)과 최소
///   시간(70ms)을 붙여서, 6덩어리를 12개로 늘리면 글씨 구간이 최소 386ms 길어진다.
///   순서만 필요한 것이므로 진행도에 담으면 리듬을 안 건드리고 끝난다.
///
///   [AnnotationChunk.strokes] 가 비었으면 `null` — 호출부가 기존 왼→오로 간다.
Float32List? _jamoProgress(AnnotationChunk chunk, int w) {
  final strokes = chunk.strokes;
  if (strokes.isEmpty) return null;
  final out = Float32List(chunk.pixels.length);
  var at = 0;
  for (var rank = 0; rank < strokes.length; rank++) {
    final one = strokes[rank];
    // 조각 **안**도 위→아래, 같은 줄은 좌→우 로 쓴다.
    //
    //   ⚠️ 여기서 x 만 보면 안 된다. 자모가 붙어 한 조각으로 남은 음절("발" 의 ㅂㅏㄹ 은
    //   래스터에서 한 덩어리다)이 통째로 **좌→오 wipe** 가 되어 버린다(실측: 첫 음절의
    //   corr(within, x) 가 1.00 이었다). 행 우선으로 매기면 자모를 못 갈라도 규칙이
    //   무너지지 않는다.
    var left = 1 << 30;
    var right = -1;
    var top = 1 << 30;
    var bottom = -1;
    for (final index in one) {
      final x = index % w;
      final y = index ~/ w;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
    final cols = right - left + 1;
    final cells = (bottom - top + 1) * cols;
    for (final index in one) {
      final row = index ~/ w - top;
      final col = index % w - left;
      final local = cells <= 1 ? 1.0 : (row * cols + col) / (cells - 1);
      out[at++] = (rank + local) / strokes.length;
    }
  }
  return out;
}

/// 세그먼트 하나를 평면 배열에 찍고 목록에 더한다.
///
///   [progress] 가 `null` 이면 진행도를 **행 우선**(위→아래, 같은 줄은 좌→우)으로 매긴다.
///
///   ⚠️ **예전엔 여기가 bbox 안의 x 위치, 즉 좌→우 wipe 였다.** 그래서 규칙이 반쪽만
///   지켜졌다 — 음절 힌트를 준 호출부만 [_jamoProgress] 로 행 우선을 받고, 힌트가 없으면
///   (기본값이다) 덩어리가 통째로 옆으로 쓸렸다. 실측으로 갈렸다:
///
///       힌트 있음   corr(진행도, y) 0.85~1.00 · corr(진행도, x) 0.01~0.40   ← 위→아래
///       힌트 없음   corr(진행도, x) **1.00**  · corr(진행도, y) ~0          ← 좌→우
///
///   규칙은 하나여야 한다. 폴백도 행 우선으로 두면 힌트 유무와 상관없이
///   "덩어리는 좌→우, 덩어리 **안**은 위→아래" 가 지켜진다.
void _addSegment({
  required Int32List pixels,
  required RevealSegmentKind kind,
  required int w,
  required Float32List? progress,
  required Uint8List segmentId,
  required Uint16List within,
  required List<RevealSegment> segments,
  double? measure,
}) {
  if (pixels.isEmpty || segments.length > kRevealMaxSegmentId) return;
  final id = segments.length;
  var left = 1 << 30;
  var top = 1 << 30;
  var right = -1;
  var bottom = -1;
  for (final index in pixels) {
    final x = index % w;
    final y = index ~/ w;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  // 행 우선 폴백에 쓸 격자. 한 칸짜리면 나눌 게 없다.
  final cols = right - left + 1;
  final cells = (bottom - top + 1) * cols;
  for (var i = 0; i < pixels.length; i++) {
    final index = pixels[i];
    segmentId[index] = id;
    final double t;
    if (progress != null) {
      t = progress[i];
    } else if (cells <= 1) {
      // 픽셀이 한 칸뿐이면 통째로 한 번에 뜬다.
      t = 1;
    } else {
      final row = index ~/ w - top;
      final col = index % w - left;
      t = (row * cols + col) / (cells - 1);
    }
    within[index] = (t.clamp(0.0, 1.0) * kRevealWithinScale).round();
  }
  segments.add(
    RevealSegment(
      id: id,
      kind: kind,
      pixelCount: pixels.length,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      // 자를 하나로 맞춘다 — 셋 다 "펜이 지나는 거리"(굽기 해상도 픽셀)다.
      measure: measure ?? (right - left + 1).toDouble(),
    ),
  );
}

/// [pixels] 에서 [remove] 를 뺀 나머지.
Int32List _without(Int32List pixels, Int32List remove) {
  final drop = <int>{...remove};
  final out = Int32List(pixels.length - drop.length);
  var at = 0;
  for (final index in pixels) {
    if (!drop.contains(index)) out[at++] = index;
  }
  return out;
}

/// 8-이웃 연결요소 전부(큰 것부터).
List<Int32List> _components(Int32List pixels, int w, int h) {
  final length = w * h;
  final member = Uint8List(length);
  for (final index in pixels) {
    member[index] = 1;
  }
  final seen = Uint8List(length);
  final queue = Int32List(pixels.length);
  final out = <Int32List>[];
  for (final start in pixels) {
    if (seen[start] == 1) continue;
    seen[start] = 1;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    while (head < tail) {
      final index = queue[head++];
      final x = index % w;
      final y = index ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final neighbour = ny * w + nx;
          if (member[neighbour] == 1 && seen[neighbour] == 0) {
            seen[neighbour] = 1;
            queue[tail++] = neighbour;
          }
        }
      }
    }
    out.add(Int32List(tail)..setRange(0, tail, queue));
  }
  out.sort((a, b) => b.length.compareTo(a.length));
  return out;
}
