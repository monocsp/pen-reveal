// 되찾은 순서가 **한 붓처럼 나아가는가** — 합성 도형으로 잠근다.
//
//   ⚠️ **이 파일이 왜 필요한가.** 순회 순서를 고쳤다고 보고했다가 되돌린 적이 있다.
//   회색조 그림을 눈으로 보고 판정했고, 좌표로 재 보니 길이 끝나는 자리가 엉뚱한 데로
//   옮겨져 있었다. 다시 손대기 전에 **기계가 읽는 합격 기준**을 세운다.
//
//   자산이 필요 없다 — 도형을 코드로 그려 `bakeOneStrokeOrder` 에 바로 넣는다.
//   그래서 CI 가 매번 돈다.
//
//   재는 것 둘:
//
//   ① **펜 끝 속도 균일성.** 순서값은 누적 경로 길이다. 같은 폭의 구간에는 같은 길이가
//      들어가므로, 구간마다 펜 끝(무게중심)이 **비슷한 거리씩** 움직여야 한다. 갈림길에서
//      먼 가지로 순간이동하면 한 걸음만 크게 튄다 — 최대/중앙값 비로 잡는다.
//
//   ② **전선이 하나인가.** ①만으로는 부족하다. "위에서부터 거리장을 뿌리는" 가짜 구현은
//      속도가 정의상 균일해 **①에서 만점**을 받는다. 그건 붓이 아니라 물결이다.
//      한 구간에 켜지는 픽셀이 몇 덩어리로 갈리는지, 갈렸다면 얼마나 떨어져 있는지 본다.
@Tags(['regression'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

const _w = 160;
const _h = 160;

/// 점들을 이어 굵기 [r] 로 칠한다.
Uint8List _stroke(List<(int, int)> pts, int r) {
  final m = Uint8List(_w * _h);
  for (var i = 0; i < pts.length - 1; i++) {
    final (x0, y0) = pts[i];
    final (x1, y1) = pts[i + 1];
    for (var t = 0; t <= 400; t++) {
      final x = (x0 + (x1 - x0) * t / 400).round();
      final y = (y0 + (y1 - y0) * t / 400).round();
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > r * r) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= _w || ny >= _h) continue;
          m[ny * _w + nx] = 255;
        }
      }
    }
  }
  return m;
}

/// 구간별 펜 끝 무게중심.
List<(double, double)?> _tips(Uint8List order, int bins) {
  final sx = List<double>.filled(bins, 0);
  final sy = List<double>.filled(bins, 0);
  final n = List<int>.filled(bins, 0);
  for (var i = 0; i < order.length; i++) {
    final v = order[i];
    if (v >= 255) continue;
    final b = (v * (bins - 1) / 254).round().clamp(0, bins - 1);
    sx[b] += (i % _w).toDouble();
    sy[b] += (i ~/ _w).toDouble();
    n[b]++;
  }
  return [
    for (var b = 0; b < bins; b++)
      if (n[b] == 0) null else (sx[b] / n[b], sy[b] / n[b]),
  ];
}

/// ① 한 걸음의 최대 / 중앙값. 순간이동이 있으면 커진다.
double _speedRatio(Uint8List order, int bins) {
  final tips = _tips(order, bins);
  final steps = <double>[];
  (double, double)? prev;
  for (final t in tips) {
    if (t == null) continue;
    if (prev != null) {
      final dx = t.$1 - prev.$1;
      final dy = t.$2 - prev.$2;
      steps.add(math.sqrt(dx * dx + dy * dy));
    }
    prev = t;
  }
  if (steps.length < 4) return 0;
  final sorted = [...steps]..sort();
  final median = sorted[sorted.length ~/ 2];
  if (median <= 0) return 0;
  return sorted.last / median;
}

/// ② 한 구간에 켜지는 픽셀이 몇 덩어리로 갈리나 · 가장 멀리 떨어진 두 덩어리의 거리.
(int, double) _fronts(Uint8List order, int bins) {
  var worstCount = 0;
  var worstGap = 0.0;
  for (var b = 0; b < bins; b++) {
    final take = <int>[];
    for (var i = 0; i < order.length; i++) {
      final v = order[i];
      if (v >= 255) continue;
      if ((v * (bins - 1) / 254).round().clamp(0, bins - 1) == b) take.add(i);
    }
    if (take.length < 4) continue;
    // 8-이웃 덩어리 나누기.
    final member = <int>{...take};
    final seen = <int>{};
    final groups = <List<int>>[];
    for (final s in take) {
      if (seen.contains(s)) continue;
      final g = <int>[];
      final st = <int>[s];
      seen.add(s);
      while (st.isNotEmpty) {
        final q = st.removeLast();
        g.add(q);
        final x = q % _w;
        final y = q ~/ _w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= _w || ny >= _h) continue;
            final j = ny * _w + nx;
            if (member.contains(j) && seen.add(j)) st.add(j);
          }
        }
      }
      if (g.length >= 4) groups.add(g);
    }
    if (groups.length > worstCount) worstCount = groups.length;
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        var best = double.infinity;
        for (final a in groups[i]) {
          for (final c in groups[j]) {
            final dx = (a % _w - c % _w).toDouble();
            final dy = (a ~/ _w - c ~/ _w).toDouble();
            final d = math.sqrt(dx * dx + dy * dy);
            if (d < best) best = d;
          }
        }
        if (best.isFinite && best > worstGap) worstGap = best;
      }
    }
  }
  return (worstCount, worstGap);
}

/// 도형 → (마스크, 속도비 상한, 전선 수 상한, 전선 거리 상한).
///
///   ⚠️ 상한은 **실측값**이다. 곧은 획·완만한 곡선·헤어핀은 지금도 깨끗하고, T자와
///   올가미는 지금 코드에서 **일부러 빨갛게 둔다** — 그 둘이 사장님이 지적한 결함
///   (갈림길에서 위로 되꺾기 · 먼 자리가 먼저 켜지기)의 최소 재현이다.
///   수정의 정의는 **T자·올가미를 초록으로 만들면서 나머지를 안 깨는 것**이다.
final _shapes = <String, (Uint8List, double, int, double)>{
  '곧은 획': (_stroke(const [(30, 20), (30, 140)], 6), 3, 1, 0),
  '완만한 곡선': (
    _stroke(const [(25, 20), (60, 55), (95, 90), (130, 135)], 6),
    3,
    1,
    0,
  ),
  '헤어핀': (
    _stroke(const [(40, 20), (40, 90), (95, 90), (95, 20)], 6),
    4,
    2,
    12,
  ),
};

/// 올가미 — 고리를 그린 뒤 시작점으로 돌아온다(고리가 자기 자신에 닿는다).
const _lassoPoints = <(int, int)>[
  (80, 20),
  (80, 55),
  (45, 75),
  (45, 110),
  (80, 130),
  (115, 110),
  (115, 75),
  (80, 55),
];

/// 결함을 재현하는 도형들 — **지금 코드에서 빨갛다.** 이게 수정의 과녁이다.
final _adversarial = <String, Uint8List>{
  // T자 — 위에서 내려오다 좌우로 갈린다. 갈림길에서 한쪽을 끝까지 그린 뒤 되돌아와
  //   반대쪽을 그리면, 되돌아오는 순간 펜 끝이 반대편으로 순간이동한다.
  'T자': () {
    final a = _stroke(const [(80, 20), (80, 80)], 6);
    final b = _stroke(const [(25, 80), (135, 80)], 6);
    for (var i = 0; i < a.length; i++) {
      if (b[i] != 0) a[i] = 255;
    }
    return a;
  }(),
  // 올가미 — 고리를 그린 뒤 꼬리로 빠진다. 고리가 자기 자신에 닿는다.
  '올가미': _stroke(_lassoPoints, 6),
};

void main() {
  group('한 붓처럼 나아간다 — 합성', () {
    _shapes.forEach((name, spec) {
      final (mask, speedMax, frontMax, gapMax) = spec;
      test(name, () {
        final baked = bakeOneStrokeOrder(StrokeMask(mask, _w, _h));
        expect(baked.length, greaterThan(0), reason: '순서를 못 매겼다');
        final bins = (baked.length / 5).round().clamp(16, 160);

        final ratio = _speedRatio(baked.bytes, bins);
        expect(
          ratio,
          lessThanOrEqualTo(speedMax),
          reason: '$name — 펜 끝이 한 걸음에 중앙값의 '
              '${ratio.toStringAsFixed(1)}배를 뛰었다. 먼 자리로 순간이동했다는 뜻이다',
        );

        final (count, gap) = _fronts(baked.bytes, bins);
        expect(
          count,
          lessThanOrEqualTo(frontMax),
          reason: '$name — 한 구간이 $count 덩어리로 갈렸다. 붓끝 하나가 아니다',
        );
        expect(
          gap,
          lessThanOrEqualTo(gapMax),
          reason: '$name — 갈린 덩어리가 ${gap.toStringAsFixed(0)}px 떨어져 있다. '
              '떨어진 자리가 같이 켜진다',
        );
      });
    });
  });

  // ⚠️ **여기는 지금 빨갛다. 일부러다.**
  //
  //   T자와 올가미는 사장님이 지적한 결함의 최소 재현이다 — 갈림길에서 위로 되꺾고,
  //   펜이 저쪽에 있는데 이쪽이 먼저 켜진다. 순회를 고치면 여기가 초록이 되어야 한다.
  //   **초록이 되기 전에는 "고쳤다" 고 말하지 않는다.**
  group(
    '아직 못 고친 것 — 수정의 과녁',
    () {
      _adversarial.forEach((name, mask) {
        test('$name — 펜 끝이 순간이동하지 않는다', () {
          final baked = bakeOneStrokeOrder(StrokeMask(mask, _w, _h));
          expect(baked.length, greaterThan(0));
          final bins = (baked.length / 5).round().clamp(16, 160);
          final ratio = _speedRatio(baked.bytes, bins);
          final (count, gap) = _fronts(baked.bytes, bins);
          expect(
            ratio,
            lessThanOrEqualTo(4),
            reason: '$name — 한 걸음에 중앙값의 ${ratio.toStringAsFixed(1)}배를 뛰었다 '
                '(전선 $count 덩어리 · 최대 ${gap.toStringAsFixed(0)}px 떨어짐)',
          );
        });
      });
    },
    skip: '순회를 고치기 전까지 빨갛다 — 고치면 이 skip 을 지운다',
  );
}
