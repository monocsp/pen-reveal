// 반투명 픽셀이 **어디에** 있나 — 개수가 아니라 모양을 본다.
//
//   앞선 계측은 반투명 픽셀 **총수**만 셌다. 그건 "붓끝이 얼마나 번지나" 는 답해도
//   "선이 안 지나가는 자리가 왜 자라나" 는 못 답한다. 사장님이 본 것은 후자다.
//
//   붓끝 하나라면 반투명 집합은 **연결된 한 덩어리**다. 떨어진 자리가 같이 켜지면
//   **덩어리가 여럿**이 된다 — 그게 "선이 진행되는 곳이 아닌데 자라난다" 의 정체다.
//
//   같이 재는 것:
//     · 반투명 덩어리 개수와 크기
//     · 가장 큰 **같은 순서값** 덩어리(고원) — 한 값이 넓은 면을 덮으면 통째로 밝아진다
//     · 고원 자리의 붓 반경 R(= 길 가장자리까지 거리). 굵은 자리일수록 고원이 크다는 가설
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;
const _keys = ['map_deep_05', 'map_deep_04', 'map_basic_01'];
const _progresses = [0.10, 0.18, 0.26, 0.34];

/// 조건을 만족하는 픽셀들의 8-이웃 덩어리 크기(내림차순).
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
    '반투명 집합이 한 덩어리인가 여럿인가',
    () async {
      final have = await availableCorpusKeys();
      const timing = HandwritingRevealTiming();

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
        final w = size.width;
        final h = size.height;
        final roadIds = <int>{
          for (final s in plan.segments)
            if (s.kind == RevealSegmentKind.primaryStroke) s.id,
        };
        final isRoad = Uint8List(w * h);
        for (var i = 0; i < w * h; i++) {
          if (roadIds.contains(plan.segmentId[i])) isRoad[i] = 1;
        }

        // ignore: avoid_print
        print('\n══ $key ══');
        for (final kk in [24.0, 64.0]) {
          final compiler = RevealTextureCompiler(
            sharpness: RevealSharpness(kk),
          );
          final order = compiler.compile(plan, timing.schedule(plan));

          // 같은 순서값 고원 — k 와 무관하게 텍스처의 성질이다.
          if (kk == 24.0) {
            final plateaus = <int>[];
            final seen = Uint8List(w * h);
            for (var s = 0; s < w * h; s++) {
              if (isRoad[s] == 0 || seen[s] == 1) continue;
              final v = order[s];
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
                    if (isRoad[j] != 0 && seen[j] == 0 && order[j] == v) {
                      seen[j] = 1;
                      st.add(j);
                    }
                  }
                }
              }
              plateaus.add(n);
            }
            plateaus.sort((a, b) => b.compareTo(a));
            // ignore: avoid_print
            print('  같은 순서값 고원 — 개수 ${plateaus.length} · '
                '가장 큰 다섯 ${plateaus.take(5).toList()}');
          }

          // ignore: avoid_print
          print('  k=${kk.toStringAsFixed(0)}');
          for (final p in _progresses) {
            final partial = Uint8List(w * h);
            var n = 0;
            for (var i = 0; i < w * h; i++) {
              if (isRoad[i] == 0) continue;
              final a = (kk * (p * 255 - order[i])).clamp(0.0, 255.0);
              if (a > 0 && a < 255) {
                partial[i] = 1;
                n++;
              }
            }
            final comps = _components(partial, w, h);
            // ignore: avoid_print
            print('    진행도 ${p.toStringAsFixed(2)} — 반투명 $n px · '
                '덩어리 ${comps.length}개 · 큰 것 ${comps.take(4).toList()}');
          }
        }
        pair.base.dispose();
        pair.composed.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
