// codex 가 제안한 2×2 결정 실험 — 넓은 반투명 면적의 원인이
//   **경사 폭(k)** 인가, **양자화(8비트)** 인가, **공간 기하** 인가를 가른다.
//
//   생산 텍스처는 안 건드린다. 계획과 일정에서 알파를 CPU 로 직접 계산해 넷을 견준다:
//
//       ① 8비트 순서값 · k=24      = 지금 화면
//       ② 8비트 순서값 · 이진 임계  = 경사를 없앤 것(k=∞)
//       ③ 고해상 시각 · k=24       = 양자화를 없앤 것
//       ④ 고해상 시각 · 이진 임계   = 둘 다 없앤 것
//
//   읽는 법:
//     · ②가 면적을 없애면  → 경사 폭이 주범. k 를 올리면 된다.
//     · ②도 여전히 넓으면  → 양자화나 기하. ③으로 갈라 본다.
//     · ③이 ①과 같으면    → 정밀도는 무죄. 남는 것은 기하다.
//
//   ⚠️ **먼저 물어야 할 것: 계획의 `within` 이 진짜 16비트인가.** 굽기가 이미 0~254 로
//   반올림한 값을 16비트 통에 담고만 있다면 채널을 늘려도 아무것도 안 는다.
@Tags(['corpus'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;
const _keys = ['map_deep_04', 'map_special_01', 'map_basic_01'];
const _progresses = [0.15, 0.27, 0.42];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '반투명 면적의 원인 가르기 — 경사 폭 / 양자화 / 기하',
    () async {
      final have = await availableCorpusKeys();
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final k = compiler.sharpness.k;

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
        final n = size.width * size.height;

        final roadIds = <int>{
          for (final s in plan.segments)
            if (s.kind == RevealSegmentKind.primaryStroke) s.id,
        };

        // 계획이 실제로 몇 단계를 들고 있나 — 통이 16비트여도 값이 255 종이면 8비트다.
        final distinctWithin = <int>{};
        final distinctOrder = <int>{};
        for (var i = 0; i < n; i++) {
          if (!roadIds.contains(plan.segmentId[i])) continue;
          distinctWithin.add(plan.within[i]);
          distinctOrder.add(order[i]);
        }

        // 세그먼트별 창(고해상 시각을 다시 만들려면 필요하다).
        final win = <int, SegmentWindow>{
          for (final w in schedule.windows) w.segmentId: w,
        };

        // ignore: avoid_print
        print('\n══ $key @$_side ══  길 픽셀 '
            '${[
          for (var i = 0; i < n; i++)
            if (roadIds.contains(plan.segmentId[i])) i,
        ].length}');
        // ignore: avoid_print
        print('  within 서로 다른 값 ${distinctWithin.length}종 '
            '(통은 0~65535) · order ${distinctOrder.length}종 (통은 0~254)');

        // ignore: avoid_print
        print('  진행도  ①8비트·k24  ②8비트·이진  ③고해상·k24  ④고해상·이진');
        for (final p in _progresses) {
          var a1 = 0;
          var a2 = 0;
          var a3 = 0;
          var a4 = 0;
          for (var i = 0; i < n; i++) {
            final id = plan.segmentId[i];
            if (!roadIds.contains(id)) continue;

            // ① 지금 화면 — 8비트 순서값에 경사.
            final v1 = (k * (p * 255 - order[i])).clamp(0.0, 255.0);
            if (v1 > 0 && v1 < 255) a1++;

            // ② 같은 8비트인데 경사만 없앤다.
            //    이진이면 반투명이 원리상 0 이라, 대신 **한 프레임에 같이 켜지는 최대
            //    덩어리**를 봐야 뜻이 있다. 여기서는 경계에 걸친 픽셀 수로 대신한다.
            if (order[i] == (p * 255).round()) a2++;

            // ③ 양자화를 없앤 고해상 시각 — 컴파일러와 같은 식이되 반올림을 안 한다.
            final w = win[id];
            if (w == null) continue;
            final within = plan.within[i] / kRevealWithinScale;
            final tHi = w.start + (w.end - w.start) * w.ease.timeOf(within);
            final v3 = (k * (p - tHi) * 255).clamp(0.0, 255.0);
            if (v3 > 0 && v3 < 255) a3++;

            // ④ 고해상 + 이진.
            if ((tHi - p).abs() < 0.5 / 255) a4++;
          }
          // ignore: avoid_print
          print('   ${p.toStringAsFixed(2)}  ${a1.toString().padLeft(10)}'
              '  ${a2.toString().padLeft(10)}'
              '  ${a3.toString().padLeft(10)}'
              '  ${a4.toString().padLeft(10)}');
        }
        pair.base.dispose();
        pair.composed.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
