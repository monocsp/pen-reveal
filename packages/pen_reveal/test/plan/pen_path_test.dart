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
/// **실선만 놓고** 잰다 — 걷는 순서에서 새 잉크가 끊긴 자리.
///
///   ⚠️ **`_speedRatio` 로는 이걸 못 잰다.** 그건 최대/중앙값이라, 다른 데가 매끄러워져
///   중앙값이 작아지면 **좋아졌는데 값이 올라간다.** 실제로 끝점 짝짓기를 고쳤을 때
///   전선이 3덩어리 → 2, 최장 끊김 68 → 23px 로 나아졌는데 비율은 7.6 → 12.2 로 올랐다.
///   그래서 여기서는 **절대 거리**를 본다.
///
///   되돌려 주는 것: (붓끝 최대 걸음 px, 잉크 끊김 수, 최장 끊김 px, 되짚기 배수).
///
///   ⚠️ **붓끝 걸음과 잉크 끊김은 다른 것이다.**
///     · 붓끝 걸음 — 걷기의 이웃한 두 자리 사이 거리. 8-이웃이라 **언제나 √2 이하여야
///       한다.** 이걸 넘으면 경로가 걷기가 아니라 조각을 이어 붙인 것이다(히어홀저가
///       막혀서 그렇게 된다). 붓이 공중을 난다.
///     · 잉크 끊김 — **새로** 켜지는 두 자리 사이 거리. 되짚는 동안엔 새 잉크가 없으므로,
///       되짚기가 필요한 그림에서는 반드시 생긴다. 없앨 수 없고 **줄일 수만** 있다.
(double, int, double, double) _lineBreaks(Uint8List mask) {
  DebugSkeleton? got;
  debugSkeletonSink = (s) {
    if (got == null || s.pixels.length > got!.pixels.length) got = s;
  };
  bakeOneStrokeOrder(StrokeMask(mask, _w, _h));
  // ⚠️ 전역이라 반드시 되돌린다.
  debugSkeletonSink = null;

  final s = got;
  if (s == null || s.route.isEmpty) return (999, 999, 999, 999);
  final sw = s.width;

  // 붓끝 — 걷기의 이웃한 두 자리.
  var penJump = 0.0;
  for (var i = 1; i < s.route.length; i++) {
    final a = s.route[i - 1];
    final b = s.route[i];
    final dx = (b % sw - a % sw).toDouble();
    final dy = (b ~/ sw - a ~/ sw).toDouble();
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > penJump) penJump = d;
  }

  final fresh = <int>[];
  final seen = <int>{};
  for (final v in s.route) {
    if (seen.add(v)) fresh.add(v);
  }
  var count = 0;
  var longest = 0.0;
  for (var i = 1; i < fresh.length; i++) {
    final a = fresh[i - 1];
    final b = fresh[i];
    final dx = (b % sw - a % sw).toDouble();
    final dy = (b ~/ sw - a ~/ sw).toDouble();
    final d = math.sqrt(dx * dx + dy * dy);
    // 8-이웃이면 최대 √2 다. 그보다 멀면 붓끝이 튄 것이다.
    if (d > 1.5) {
      count++;
      if (d > longest) longest = d;
    }
  }
  return (penJump, count, longest, s.route.length / s.pixels.length);
}

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

/// 올가미 — 고리를 그린 뒤 꼬리로 빠진다. **고리가 자기 자신에 닿는다.**
///
///   ⚠️ **정본 지도의 결함은 전부 이 모양이다.** 사장님 지도에 T 자 갈림길(길 셋이
///   한 점에서 만나는 것)은 없다 — 한 획이 자기 자신과 나란히 붙었다 갈라질 뿐이다.
///   얇게 깎으면 그 붙은 구간이 한 줄이 되어 양끝이 갈래 3 처럼 보인다.
///   실측 다리 길이 special_01 24 · deep_04 45 가 "두 가닥이 그만큼 붙어 있었다" 는 증거다.
///
///   `_pairOddVertices` 가 그 구간을 두 번 지나게 만들면서 초록이 됐다.
final _lasso = _stroke(_lassoPoints, 6);

/// T 자 — 길 셋이 한 점에서 만난다. **지금 코드에서 빨갛다.**
///
///   ⚠️ **정본 지도에는 이 모양이 없다.** 그래서 이건 코퍼스의 결함 재현이 아니라
///   패키지를 남의 그림에 쓸 때를 대비한 **남은 과녁**이다. 되짚기를 넣어 12.0 → 7.6 배로
///   내려왔지만 기준 4 는 아직 못 넘는다 — 되짚어 돌아오는 순간 펜 끝이 반대편으로 뛴다.
final _tee = () {
  final a = _stroke(const [(80, 20), (80, 80)], 6);
  final b = _stroke(const [(25, 80), (135, 80)], 6);
  for (var i = 0; i < a.length; i++) {
    if (b[i] != 0) a[i] = 255;
  }
  return a;
}();

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

  // 올가미 — **정본 지도 결함의 최소 재현.** 되짚기를 넣기 전에는 빨갰다.
  //
  //   ⚠️ 이 시험이 다시 빨개지면 되짚기가 깨진 것이다. 정본 열 장이 전부 이 모양이므로,
  //   여기가 무너지면 코퍼스도 같이 무너진다.
  test('올가미 — 자기 자신에 닿는 고리를 한 붓으로 지난다', () {
    final baked = bakeOneStrokeOrder(StrokeMask(_lasso, _w, _h));
    expect(baked.length, greaterThan(0));
    final bins = (baked.length / 5).round().clamp(16, 160);
    final ratio = _speedRatio(baked.bytes, bins);
    final (count, gap) = _fronts(baked.bytes, bins);
    expect(
      ratio,
      lessThanOrEqualTo(4),
      reason: '올가미 — 한 걸음에 중앙값의 ${ratio.toStringAsFixed(1)}배를 뛰었다 '
          '(전선 $count 덩어리 · 최대 ${gap.toStringAsFixed(0)}px 떨어짐)',
    );
  });

  // 길 셋이 한 점에서 만나는 진짜 T 자.
  //
  //   ⚠️ **이 시험이 `_pairOddVertices` 가 끝점을 세는지를 지키는 자리다.** 예전엔 홀수
  //   정점을 셀 때 차수 1(끝점)을 뺐다. 끝점이 정확히 둘이면 그래도 맞는다 — 그 둘이
  //   경로의 시작·끝이 되니까. 그런데 T 자는 끝점이 **셋**이라 홀수 정점이 남고, 오일러
  //   경로가 아예 없어 히어홀저가 조각을 이어 붙였다. 전선이 3덩어리로 갈리고 한 걸음에
  //   중앙값의 7.6배를 뛰었다.
  //
  //   정본 열 장에는 이 모양이 없다 — 끝점이 전부 둘이다. 그래서 이 결함은 정본으로는
  //   못 잡고 여기서만 잡힌다.
  test(
    'T자 — 경로가 진짜 걷기다 · 잉크 끊김은 하나뿐이다',
    () {
      final (penJump, breaks, longest, retrace) = _lineBreaks(_tee);

      // ① **경로가 진짜 걷기여야 한다.** 이게 이 시험의 본론이다. 끝점을 홀수 정점으로
      //    안 세면 오일러 경로가 없어 히어홀저가 조각을 이어 붙이고, 붓끝이 55px 을
      //    날아간다(되짚기 1.00배 = 한 번도 안 되돌아왔다는 증거).
      expect(
        penJump,
        lessThanOrEqualTo(1.5),
        reason: 'T자 — 붓끝이 한 걸음에 ${penJump.toStringAsFixed(0)}px 을 날았다. '
            '경로가 걷기가 아니라 조각을 이어 붙인 것이다',
      );

      // ② 되짚기는 **있어야 한다.** 끝점 셋이면 한 가지를 두 번 지나는 수밖에 없다.
      expect(retrace, greaterThan(1.0), reason: 'T자 — 되짚기가 없다. 그럴 수 없는 모양이다');
      expect(
        retrace,
        lessThanOrEqualTo(1.5),
        reason: 'T자 — 선을 ${retrace.toStringAsFixed(2)}배 걸었다. 너무 많이 되짚는다',
      );

      // ③ 잉크 끊김 하나는 구조적이다 — 되짚는 동안 새 잉크가 없다. 그 길이는 되짚는
      //    가지의 길이(가장 짧은 가지 ≈ 55)라 더 줄일 수 없다.
      expect(breaks, lessThanOrEqualTo(1), reason: 'T자 — 잉크가 $breaks 번 끊겼다');
      expect(
        longest,
        lessThanOrEqualTo(56),
        reason: 'T자 — 최장 끊김 ${longest.toStringAsFixed(0)}px',
      );
    },
  );
}
