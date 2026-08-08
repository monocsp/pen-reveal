// src/plan/cross_stroke_detector.dart — 빨간 X 를 `\` 획과 `/` 획으로 가른다.
//
//   방법은 **방향 스윕**이다. 각도 θ 를 1°씩 훑으면서 픽셀을 θ 의 법선에 투영하고, 값이
//   가장 좁은 띠에 뭉치는 두 θ 를 고른다. 획 하나는 그 방향으로 길고 법선 방향으로 얇아서,
//   제 방향으로 봤을 때만 투영이 뭉친다.
//
//   ⚠️ **PCA·좌표 k-means 를 쓰면 안 된다.** X 는 등방성이라 주축이 불안정하고, 좌표
//   클러스터링은 대각선이 아니라 좌우/상하를 가른다(codex 기각).
//
//   ⚠️ **비트맵 템플릿도 안 쓴다.** 지도 10종의 X 는 픽셀 수가 ±0.16% 로 같아 한 글리프
//   처럼 보이지만 실제로는 방향이 다르다 — 8종이 38°/137°, map_deep_04 가 32°/115°,
//   map_deep_05 가 19°/116°. 회전이 섞이면 bbox 정렬로는 못 맞추고, 회전을 알아내려면
//   결국 이 스윕을 해야 한다. 축을 알고 나면 "축까지의 거리" 가 템플릿 매칭보다 직접적인
//   분류 기준이라 템플릿이 더 줄 게 없다. 굽기 도구가 내놓는 것은 비트맵이 아니라
//   [CrossCalibration] 상수와 회귀 픽스처다(`tool/bake_cross_calibration.py`).
//
//   ⚠️ 알고리즘은 그 python 스크립트와 **한 글자도 어긋나면 안 된다**. 한쪽만 고치면
//   `test/corpus/cross_stroke_detector_test.dart` 의 실지도 픽스처가 RED 로 잡는다.
//
//   순수 Dart 다 — `package:flutter` 를 안 쓴다(isolate 로 통째로 넘길 수 있어야 한다).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pen_reveal/src/plan/generated/cross_calibration.g.dart';

/// 획 하나가 놓인 직선 — 방향과, 그 방향의 법선에서 차지하는 띠.
class StrokeAxis {
  const StrokeAxis({
    required this.angleDegrees,
    required this.normalOffset,
    required this.halfWidth,
    required this.score,
  });

  /// 0~179. 화면 좌표(y 가 아래로 증가)라 0~90 은 오른쪽 아래(`\`),
  ///   90~180 은 왼쪽 아래(`/`) 를 향한다.
  final int angleDegrees;

  /// 무게중심 기준 법선 좌표에서 띠의 중심.
  final double normalOffset;

  /// 띠의 폭(= 획 굵기 추정). 픽셀을 어느 획에 줄지 잴 때 나누는 자다.
  final double halfWidth;

  /// 그 띠에 들어온 픽셀 수 — 클수록 "정말 이 방향으로 획이 있다".
  final int score;

  double get dx => math.cos(angleDegrees * math.pi / 180);

  /// 각도가 0~179 라 언제나 ≥ 0 — 축을 따라가면 **화면 아래로 간다**.
  double get dy => math.sin(angleDegrees * math.pi / 180);
}

/// 두 획으로 가른 결과. 배열은 모두 입력 픽셀 목록과 **같은 순서·같은 길이**다.
class CrossStrokeSplit {
  const CrossStrokeSplit({
    required this.backslash,
    required this.slash,
    required this.onBackslash,
    required this.within,
    required this.backslashCount,
    required this.backslashLength,
    required this.slashLength,
  });

  /// 먼저 그어지는 획(사용자 지정: `\` 먼저).
  final StrokeAxis backslash;
  final StrokeAxis slash;

  /// 1 이면 `\` 획, 0 이면 `/` 획.
  ///
  ///   ⚠️ **겹치는 픽셀도 한쪽에만 준다.** 최종 산출물이 픽셀당 시각 하나인 8비트
  ///   텍스처라 한 픽셀이 두 시각을 가질 수 없다. 교차부를 먼저 그어지는 `\` 에 주면
  ///   `/` 를 그을 때 그 자리는 이미 그려져 있는데, 진짜 펜도 그렇게 지나간다.
  final Uint8List onBackslash;

  /// 그 픽셀이 **자기 획 안에서** 갖는 진행도 0~1. 언제나 위 → 아래로 커진다.
  final Float32List within;

  final int backslashCount;

  /// 축 방향으로 잰 획 길이(픽셀). 타이밍 정책이 쓰는 구조적 자다.
  final double backslashLength;
  final double slashLength;

  int get slashCount => onBackslash.length - backslashCount;
}

/// X 픽셀 목록을 두 획으로 가른다. X 로 안 보이면 `null`.
///
///   [pixels] 는 행 우선 평면 인덱스(`y * width + x`)다. 반환하는 배열의 i 번째는
///   `pixels[i]` 에 대응한다.
CrossStrokeSplit? splitCrossStrokes({
  required Int32List pixels,
  required int width,
}) {
  final n = pixels.length;
  if (n < 8 || width <= 0) return null;

  final xs = Float64List(n);
  final ys = Float64List(n);
  var sumX = 0.0;
  var sumY = 0.0;
  var minX = double.infinity;
  var maxX = -double.infinity;
  var minY = double.infinity;
  var maxY = -double.infinity;
  for (var i = 0; i < n; i++) {
    final x = (pixels[i] % width).toDouble();
    final y = (pixels[i] ~/ width).toDouble();
    xs[i] = x;
    ys[i] = y;
    sumX += x;
    sumY += y;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  final cx = sumX / n;
  final cy = sumY / n;
  for (var i = 0; i < n; i++) {
    xs[i] -= cx;
    ys[i] -= cy;
  }

  // 획 굵기 추정 — 면적 ÷ 대각 길이. 두 막대로 된 X 의 폭에 비례한다.
  final span = math.sqrt(
    (maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY),
  );
  if (span <= 0) return null;
  final band = math.max(
    3,
    (n / (CrossCalibration.bandWidthDivisor * span)).round(),
  );

  // bbox 대비 띠 폭이 실측 범위를 벗어나면 두 막대 X 가 아니다.
  final boxSpan = math.max(maxX - minX + 1, maxY - minY + 1);
  final bandRatio = band / boxSpan;
  if (bandRatio < CrossCalibration.minBandWidthRatio ||
      bandRatio > CrossCalibration.maxBandWidthRatio) {
    return null;
  }

  final axes = _sweep(xs, ys, band);
  final first = axes.first;
  StrokeAxis? second;
  for (final axis in axes) {
    if (_angularSeparation(axis.angleDegrees, first.angleDegrees) >=
        CrossCalibration.minAxisSeparationDegrees) {
      second = axis;
      break;
    }
  }
  if (second == null) return null;
  if (first.score / n < CrossCalibration.minAxisScoreRatio) return null;

  // 0~90 은 오른쪽 아래로 = `\`, 90~180 은 왼쪽 아래로 = `/`.
  final StrokeAxis backslash;
  final StrokeAxis slash;
  if (first.angleDegrees > 0 && first.angleDegrees < 90) {
    backslash = first;
    slash = second;
  } else if (second.angleDegrees > 0 && second.angleDegrees < 90) {
    backslash = second;
    slash = first;
  } else {
    // 둘 다 수직·수평에 걸리면(0° 또는 90°) 각도가 작은 쪽을 `\` 로 — 결정론만 지킨다.
    final firstIsSmaller = first.angleDegrees <= second.angleDegrees;
    backslash = firstIsSmaller ? first : second;
    slash = firstIsSmaller ? second : first;
  }

  final onBackslash = Uint8List(n);
  var backslashCount = 0;
  for (var i = 0; i < n; i++) {
    final toBackslash = _normalDistance(backslash, xs[i], ys[i]);
    final toSlash = _normalDistance(slash, xs[i], ys[i]);
    if (toBackslash <= toSlash) {
      onBackslash[i] = 1;
      backslashCount++;
    }
  }
  if (backslashCount == 0 || backslashCount == n) return null;

  final within = Float32List(n);
  final backslashLength = _fillWithin(
    within,
    xs,
    ys,
    onBackslash,
    1,
    backslash,
  );
  final slashLength = _fillWithin(within, xs, ys, onBackslash, 0, slash);

  return CrossStrokeSplit(
    backslash: backslash,
    slash: slash,
    onBackslash: onBackslash,
    within: within,
    backslashCount: backslashCount,
    backslashLength: backslashLength,
    slashLength: slashLength,
  );
}

/// 각도마다 "가장 뭉치는 띠"를 찾아 점수 높은 순으로.
///
///   ⚠️ 윈도우는 **명시적 슬라이딩 합**이다 — python 쪽에서 `np.convolve(..., 'same')`
///   을 쓰면 짝수 폭에서 중심이 어긋나 두 구현이 갈린다.
List<StrokeAxis> _sweep(Float64List xs, Float64List ys, int band) {
  final n = xs.length;
  final out = <StrokeAxis>[];
  final projection = Float64List(n);
  for (var deg = 0; deg < CrossCalibration.angleSteps; deg++) {
    final theta = deg * math.pi / 180;
    final sin = math.sin(theta);
    final cos = math.cos(theta);
    var lo = double.infinity;
    var hi = -double.infinity;
    for (var i = 0; i < n; i++) {
      final p = -xs[i] * sin + ys[i] * cos;
      projection[i] = p;
      if (p < lo) lo = p;
      if (p > hi) hi = p;
    }
    final base = lo.floorToDouble();
    final bins = hi.floor() - base.toInt() + 1;
    final histogram = Int32List(bins);
    for (var i = 0; i < n; i++) {
      var index = (projection[i] - base).floor();
      if (index < 0) index = 0;
      if (index >= bins) index = bins - 1;
      histogram[index]++;
    }
    if (bins <= band) {
      out.add(
        StrokeAxis(
          angleDegrees: deg,
          normalOffset: base + bins / 2,
          halfWidth: band.toDouble(),
          score: n,
        ),
      );
      continue;
    }
    var running = 0;
    for (var i = 0; i < band; i++) {
      running += histogram[i];
    }
    var best = running;
    var bestAt = 0;
    for (var i = 1; i <= bins - band; i++) {
      running += histogram[i + band - 1] - histogram[i - 1];
      if (running > best) {
        best = running;
        bestAt = i;
      }
    }
    out.add(
      StrokeAxis(
        angleDegrees: deg,
        normalOffset: base + bestAt + band / 2,
        halfWidth: band.toDouble(),
        score: best,
      ),
    );
  }
  // 점수 내림차순, 같으면 각도 오름차순 — python 의 `key=(-score, deg)` 와 같다.
  out.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.angleDegrees.compareTo(b.angleDegrees);
  });
  return out;
}

int _angularSeparation(int a, int b) {
  final d = (a - b).abs() % 180;
  return math.min(d, 180 - d);
}

/// 축의 띠 중심에서 얼마나 떨어졌나 — 띠 폭으로 나눠 두 축을 같은 자로 비교한다.
double _normalDistance(StrokeAxis axis, double x, double y) {
  final theta = axis.angleDegrees * math.pi / 180;
  final projection = -x * math.sin(theta) + y * math.cos(theta);
  return (projection - axis.normalOffset).abs() / axis.halfWidth;
}

/// 한 획의 픽셀에 진행도를 채우고 획 길이를 돌려준다.
///
///   축 방향 투영을 쓴다 — 화면 y 를 그냥 쓰면 획이 기울었을 때 양끝이 어긋난다.
///   각도가 0~179 라 [StrokeAxis.dy] 가 언제나 ≥0 이므로 투영이 커질수록 아래다.
double _fillWithin(
  Float32List within,
  Float64List xs,
  Float64List ys,
  Uint8List onBackslash,
  int want,
  StrokeAxis axis,
) {
  final dx = axis.dx;
  final dy = axis.dy;
  var lo = double.infinity;
  var hi = -double.infinity;
  for (var i = 0; i < xs.length; i++) {
    if (onBackslash[i] != want) continue;
    final along = xs[i] * dx + ys[i] * dy;
    if (along < lo) lo = along;
    if (along > hi) hi = along;
  }
  final extent = hi - lo;
  for (var i = 0; i < xs.length; i++) {
    if (onBackslash[i] != want) continue;
    within[i] = extent <= 0 ? 0 : ((xs[i] * dx + ys[i] * dy) - lo) / extent;
  }
  return extent <= 0 ? 0 : extent;
}
