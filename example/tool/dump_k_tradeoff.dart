// k 를 올리면 무엇을 얻고 무엇을 잃나 — 정본 10종으로 잰다.
//
//   얻는 것: 반투명 띠가 좁아진다(면적 ∝ 1/k). 꺾이는 자리가 "차오르는" 느낌이 준다.
//   잃는 것: **선단 계단 지표가 정의상 나빠진다.** 그 지표는 "이웃 순서값 차 > 255/k"
//   인 자리를 세는데, k 를 올리면 255/k 가 작아져 문턱이 내려간다. 같은 텍스처인데도
//   더 많이 걸린다는 뜻이라, `road_smoothness_corpus_test.dart` 의 지도별 예산과
//   직접 부딪친다.
//
//   두 값을 같이 봐야 고를 수 있다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;
const _ks = [24.0, 32.0, 40.0, 48.0, 64.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'k 별 — 반투명 면적과 선단 계단',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('자산 없음');
        return;
      }
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();

      final bandTotal = <double, int>{for (final k in _ks) k: 0};
      final stepTotal = <double, int>{for (final k in _ks) k: 0};
      final stepWorst = <double, int>{for (final k in _ks) k: 0};

      // ignore: avoid_print
      print('\n지도            k=24        k=32        k=40        k=48        k=64');
      // ignore: avoid_print
      print('                면적/계단   면적/계단   면적/계단   면적/계단   면적/계단');

      for (final key in keys) {
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
        final order = compiler.compile(plan, timing.schedule(plan));
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

        final row = StringBuffer(key.padRight(15));
        for (final k in _ks) {
          // 반투명 면적 — 진행도 0.15·0.27·0.42 평균.
          var band = 0;
          for (final p in [0.15, 0.27, 0.42]) {
            for (var i = 0; i < w * h; i++) {
              if (isRoad[i] == 0) continue;
              final a = (k * (p * 255 - order[i])).clamp(0.0, 255.0);
              if (a > 0 && a < 255) band++;
            }
          }
          band = (band / 3).round();

          // 선단 계단 — 이웃 순서값 차가 선단 폭(255/k)을 넘는 자리.
          final front = 255 / k;
          var steps = 0;
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              final i = y * w + x;
              if (isRoad[i] == 0) continue;
              var over = false;
              for (var dy = -1; dy <= 1 && !over; dy++) {
                for (var dx = -1; dx <= 1; dx++) {
                  final nx = x + dx;
                  final ny = y + dy;
                  if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                  final j = ny * w + nx;
                  if (isRoad[j] == 0) continue;
                  if ((order[i] - order[j]).abs() > front) {
                    over = true;
                    break;
                  }
                }
              }
              if (over) steps++;
            }
          }
          bandTotal[k] = bandTotal[k]! + band;
          stepTotal[k] = stepTotal[k]! + steps;
          if (steps > stepWorst[k]!) stepWorst[k] = steps;
          row.write('${band.toString().padLeft(6)}/${steps.toString().padLeft(4)}  ');
        }
        // ignore: avoid_print
        print('$row');
        pair.base.dispose();
        pair.composed.dispose();
      }

      // ignore: avoid_print
      print('\n       k   반투명 면적 합   선단 계단 합   최악 지도   면적 대비 24');
      for (final k in _ks) {
        // ignore: avoid_print
        print('  ${k.toStringAsFixed(0).padLeft(6)}'
            '  ${bandTotal[k]!.toString().padLeft(13)}'
            '  ${stepTotal[k]!.toString().padLeft(12)}'
            '  ${stepWorst[k]!.toString().padLeft(9)}'
            '  ${(bandTotal[k]! / bandTotal[24]!).toStringAsFixed(2).padLeft(11)}');
      }
      // ignore: avoid_print
      print('\n순서값 상한 maxOrderValue = 255 - ceil(255/k):');
      for (final k in _ks) {
        // ignore: avoid_print
        print('  k=${k.toStringAsFixed(0).padLeft(3)} -> ${255 - (255 / k).ceil()}');
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
