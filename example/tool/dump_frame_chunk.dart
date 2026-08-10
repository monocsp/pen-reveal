// **한 프레임에 얼마나 큰 덩어리가 한꺼번에 켜지나** — 눈이 보는 것에 가장 가까운 지표.
//
//   앞선 계측 둘 다 빗나갔다. 반투명 픽셀 **총수**는 붓끝 두께를 재고, 반투명 집합의
//   **덩어리 개수**는 (재 보니) 거의 언제나 1 이다. 그런데 사장님이 본 것은
//   "선이 지나가는 게 아니라 면이 자라난다" 였다.
//
//   면이 자라나 보이는 조건은 따로 있다 — **한 프레임에 새로 불투명해지는 픽셀이 넓게
//   뭉쳐 있을 때**다. 붓이라면 그 덩어리가 붓 굵기만큼 가늘고 길어야 한다.
//
//   순서값이 0~254 뿐인데 길은 픽셀이 수천이라, 같은 값을 가진 **고원**이 생긴다.
//   임계가 그 값을 지나는 순간 고원 전체가 통째로 켜진다 — 그게 "자라나는" 정체라는 가설.
//   고원은 텍스처의 성질이라 **k 와 무관하다**(그래서 손잡이가 안 듣는다).
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;
const _keys = ['map_deep_05', 'map_deep_04', 'map_basic_01'];

/// 60fps 로 재생할 때 한 프레임이 차지하는 진행도.
const _fps = 60;

List<int> _components(Uint8List take, int w, int h) {
  final seen = Uint8List(w * h);
  final out = <int>[];
  for (var s = 0; s < w * h; s++) {
    if (take[s] == 0 || seen[s] == 1) continue;
    var n = 0;
    final st = <int>[s];
    seen[s] = 1;
    while (st.isNotEmpty) {
      final q = st.removeLast();
      n++;
      final x = q % w;
      final y = q ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (take[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            st.add(j);
          }
        }
      }
    }
    out.add(n);
  }
  out.sort((a, b) => b.compareTo(a));
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '한 프레임에 켜지는 덩어리 크기',
    () async {
      final have = await availableCorpusKeys();
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();

      for (final key in _keys) {
        if (!have.contains(key)) continue;
        final pair = await loadCorpusMap(key);
        final size = fitImageLongSide(pair.composed, _side);
        final base = await rgbaAt(pair.base, size.width, size.height);
        final composed = await rgbaAt(pair.composed, size.width, size.height);
        final plan = detectReveal(
          RevealDetectInput(
            baseRgba: base,
            composedRgba: composed,
            width: size.width,
            height: size.height,
          ),
        );
        final schedule = timing.schedule(plan);
        final order = compiler.compile(plan, schedule);
        final w = size.width;
        final h = size.height;
        final roadIds = <int>{
          for (final s in plan.segments)
            if (s.kind == RevealSegmentKind.primaryStroke) s.id,
        };
        final isRoad = Uint8List(w * h);
        var roadPx = 0;
        for (var i = 0; i < w * h; i++) {
          if (roadIds.contains(plan.segmentId[i])) {
            isRoad[i] = 1;
            roadPx++;
          }
        }
        // 길이 쓰는 순서값 구간 — 여기가 좁을수록 고원이 커진다.
        var lo = 255;
        var hi = 0;
        final used = <int>{};
        for (var i = 0; i < w * h; i++) {
          if (isRoad[i] == 0) continue;
          final v = order[i];
          used.add(v);
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }

        final total = schedule.total.inMilliseconds;
        final frames = (total * _fps / 1000).round();
        final step = 1.0 / frames;

        var worst = 0;
        var worstAt = 0.0;
        var chunkySum = 0;
        var chunkyFrames = 0;
        Uint8List opaqueAt(double p) {
          final o = Uint8List(w * h);
          for (var i = 0; i < w * h; i++) {
            if (isRoad[i] == 0) continue;
            if (24.0 * (p * 255 - order[i]) >= 255) o[i] = 1;
          }
          return o;
        }

        var prev = opaqueAt(0);
        for (var f = 1; f <= frames; f++) {
          final p = f * step;
          final now = opaqueAt(p);
          final fresh = Uint8List(w * h);
          var n = 0;
          for (var i = 0; i < w * h; i++) {
            if (now[i] == 1 && prev[i] == 0) {
              fresh[i] = 1;
              n++;
            }
          }
          prev = now;
          if (n == 0) continue;
          final comps = _components(fresh, w, h);
          if (comps.first > worst) {
            worst = comps.first;
            worstAt = p;
          }
          chunkySum += comps.first;
          chunkyFrames++;
        }

        // ignore: avoid_print
        print('\n══ $key ══');
        // ignore: avoid_print
        print('  길 $roadPx px · 순서값 $lo~$hi (${used.length}종) · '
            '재생 ${total}ms = $frames프레임');
        // ignore: avoid_print
        print('  길 픽셀 ÷ 순서값 종수 = ${(roadPx / used.length).toStringAsFixed(1)} px/단계');
        // ignore: avoid_print
        print('  한 프레임 최대 덩어리 ${worst}px (진행도 ${worstAt.toStringAsFixed(3)})'
            ' · 평균 ${(chunkySum / chunkyFrames).toStringAsFixed(1)}px');
        pair.base.dispose();
        pair.composed.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
