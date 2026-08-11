// 정본 지도에서 **길이 매끄럽게 파이는지**를 잠근다.
//
//   ⚠️ **합성 도형만 보면 이 부류를 통째로 놓친다.** 실제로 놓쳤다.
//   `packages/pen_reveal/test/plan/spread_smoothness_test.dart` 는 머리핀·뱀꼴·굵은 직선으로
//   같은 지표를 재고 통과하고 있었는데, 그동안 정본 deep 계열에서는 선단 계단이 지도당
//   192~477개씩 나 있었다. 합성 획은 자기 위를 다시 지나가지 않아서 그렇다. 정본 길은
//   고리를 그리며 앞서 그은 데를 밟는다 — 문제는 전부 거기서 났다.
//
//   재는 것 셋(전부 길 세그먼트만):
//     · **선단 계단** — 이웃 순서값 차가 선단 폭(255/k)을 넘는 자리. "물어뜯긴" 자국.
//     · **만(灣)** — 이미 지나간 자리(5×5 이웃의 60% 이상이 열림)에 남은 2px 이상 덩어리.
//     · **구멍** — 같은 조건의 1px.
//
//   상한은 실측값이다. 굽기는 결정적이라 값이 안 흔들리므로, 좋아지는 것은 통과하고
//   나빠지는 것만 걸린다. 올려야 한다면 연출이 바뀐 것이니 왜 바뀌었는지를 커밋에 적는다.
//
//   자산이 없으면 스스로 skip 한다.
@Tags(['corpus'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// `key` → (선단 계단 상한, 만 최대 상한, 구멍 상한).
///
///   ⚠️ **`_brushSweep` 이전에는 이랬다** — 이 표가 무엇을 지키는지 보라는 뜻이다:
///     basic 6·0·3 / deep_01 28 / deep_02 380 / deep_03 242 / deep_04 192 /
///     deep_05 477 / deep_06 380 / special_01 343.
const _budget = <String, (int, int, int)>{
  'map_basic_01': (0, 0, 2),
  'map_basic_02': (0, 0, 2),
  'map_basic_03': (0, 0, 1),
  'map_deep_01': (0, 0, 1),
  'map_deep_02': (0, 4, 2),
  'map_deep_03': (0, 5, 2),
  // deep_04·special_01 에 남은 것은 고리가 앞선 획에 되붙는 **Y 접합** 한 자리씩이다
  //   (deep_04 는 x 109~125·y 176~182, special_01 은 x 200~217·y 211~223).
  //   두 팔이 겹치지 않고 스치기만 해서 붓 반경으로는 안 덮인다 — 접합이 맞는 자리다.
  'map_deep_04': (11, 2, 1),
  'map_deep_05': (0, 5, 2),
  'map_deep_06': (0, 4, 2),
  'map_special_01': (51, 4, 3),
};

const _side = 420;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '정본 길이 선단 계단·만·구멍 상한을 안 넘는다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다 — example/assets/maps 를 채운다');
        return;
      }

      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      const sharp = RevealSharpness.standard;
      const leadingEdge = 255 / 24;
      final over = <String>[];
      final seen = <String>{};

      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        final size = fitImageLongSide(pair.composed, _side);
        final w = size.width;
        final h = size.height;
        final plan = detectReveal(
          RevealDetectInput(
            baseRgba: await rgbaAt(pair.base, w, h),
            composedRgba: await rgbaAt(pair.composed, w, h),
            width: w,
            height: h,
          ),
        );
        final order = compiler.compile(plan, timing.schedule(plan));
        pair.base.dispose();
        pair.composed.dispose();

        final road = List<bool>.generate(w * h, (i) {
          final id = plan.segmentId[i];
          return id < plan.segments.length &&
              plan.segments[id].kind == RevealSegmentKind.primaryStroke;
        });

        var jumps = 0;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final i = y * w + x;
            if (!road[i]) continue;
            for (final d in const [(1, 0), (0, 1)]) {
              final nx = x + d.$1;
              final ny = y + d.$2;
              if (nx >= w || ny >= h) continue;
              final j = ny * w + nx;
              if (!road[j]) continue;
              if ((order[j] - order[i]).abs() > leadingEdge) jumps++;
            }
          }
        }

        var worstBay = 0;
        var worstHoles = 0;
        // 진행도를 5%씩 훑는다 — 100 스텝이면 정본 10종에 몇 분씩 든다.
        for (var pi = 1; pi <= 19; pi++) {
          final p = pi / 20;
          final open = List<bool>.generate(
            w * h,
            (i) => road[i] && sharp.alphaAt(order: order[i], progress: p) > 200,
          );
          final behind = List<bool>.filled(w * h, false);
          for (var y = 1; y < h - 1; y++) {
            for (var x = 1; x < w - 1; x++) {
              final i = y * w + x;
              if (!road[i] || open[i]) continue;
              var lit = 0;
              var tot = 0;
              for (var dy = -2; dy <= 2; dy++) {
                for (var dx = -2; dx <= 2; dx++) {
                  final nx = x + dx;
                  final ny = y + dy;
                  if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                  final j = ny * w + nx;
                  if (!road[j]) continue;
                  tot++;
                  if (open[j]) lit++;
                }
              }
              if (tot >= 8 && lit >= tot * 0.6) behind[i] = true;
            }
          }
          final seenPx = List<bool>.filled(w * h, false);
          var holes = 0;
          for (var i = 0; i < w * h; i++) {
            if (!behind[i] || seenPx[i]) continue;
            var n = 0;
            final st = <int>[i];
            seenPx[i] = true;
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
                  if (behind[j] && !seenPx[j]) {
                    seenPx[j] = true;
                    st.add(j);
                  }
                }
              }
            }
            if (n == 1) {
              holes++;
            } else if (n > worstBay) {
              worstBay = n;
            }
          }
          if (holes > worstHoles) worstHoles = holes;
        }

        seen.add(key);
        final budget = _budget[key];
        if (budget == null) {
          over.add('$key — 상한이 없다 (계단 $jumps · 만 $worstBay · 구멍 $worstHoles)');
          continue;
        }
        final (maxJumps, maxBay, maxHoles) = budget;
        if (jumps > maxJumps) over.add('$key 계단 $jumps > $maxJumps');
        if (worstBay > maxBay) over.add('$key 만 $worstBay > $maxBay');
        if (worstHoles > maxHoles) over.add('$key 구멍 $worstHoles > $maxHoles');
      }

      expect(
        over,
        isEmpty,
        reason: '\n길이 거칠어졌다 — 굽기의 어떤 변경이 원인인지 찾아라.\n'
            '${over.join('\n')}\n',
      );
      expect(seen, _budget.keys.toSet(), reason: '잠긴 지도와 실제로 돈 지도가 다르다');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
