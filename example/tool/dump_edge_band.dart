// 일회성 계측 — **선단이 왜 "서서히 채워지는" 것처럼 보이나.**
//
//   화면에서 보이는 것: 길의 꺾이는 자리 근처에서 반투명한 회색 띠가 넓게 깔리고,
//   진행도가 오르면서 그 띠가 차오른다. 곧은 구간에서는 선단이 좁고 또렷하다.
//
//   후보 둘:
//     ① `_smoothField` 의 3×3 평균 5패스가 시간장을 뭉갠다. 알파는
//        `k·(진행도·255 − 순서값)` 이라 **순서값이 10.6(=255/24) 만큼 변하는 구간**이
//        반투명 띠다. 평활로 기울기가 완만해질수록 그 띠가 픽셀로는 넓어진다.
//     ② 꺾이는 자리는 두 팔이 공간적으로 붙어 있는데 시각은 멀다. 3×3 평균은 마스크
//        안이면 시간 차를 안 보고 섞으므로, 거기서 기울기가 가장 많이 죽는다.
//
//   재는 것: 길 픽셀마다 8-이웃과의 순서값 차 중 최대(=국소 기울기). 기울기가 작을수록
//   반투명 띠가 넓다. 평활 5패스와 0패스를 견줘 원인을 가른다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;
const _key = 'map_deep_04';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '선단 반투명 띠의 폭이 어디서 넓어지나',
    () async {
      final keys = await availableCorpusKeys();
      if (!keys.contains(_key)) {
        markTestSkipped('$_key 없음');
        return;
      }
      final pair = await loadCorpusMap(_key);
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
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final order = compiler.compile(plan, timing.schedule(plan));
      final k = compiler.sharpness.k;
      final w = size.width;
      final h = size.height;

      // 길 세그먼트 픽셀만.
      final roadIds = <int>{
        for (final s in plan.segments)
          if (s.kind == RevealSegmentKind.primaryStroke) s.id,
      };

      // 국소 기울기 = 8-이웃과의 순서값 차 중 최대.
      final grad = <int>[];
      final gradAt = Int32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (!roadIds.contains(plan.segmentId[i])) continue;
          var g = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              final j = ny * w + nx;
              if (!roadIds.contains(plan.segmentId[j])) continue;
              final d = (order[i] - order[j]).abs();
              if (d > g) g = d;
            }
          }
          grad.add(g);
          gradAt[i] = g;
        }
      }
      grad.sort();
      String pct(int p) => grad[(grad.length * p / 100).floor().clamp(0, grad.length - 1)].toString();

      // ignore: avoid_print
      print('\n[$_key @$_side] 길 픽셀 ${grad.length}개 · 가파르기 k=$k');
      // ignore: avoid_print
      print('선단 폭(반투명이 되는 순서값 구간) = 255/k = ${(255 / k).toStringAsFixed(1)}');
      // ignore: avoid_print
      print('국소 기울기 분위 — 10%:${pct(10)}  50%:${pct(50)}  90%:${pct(90)}  최대:${grad.last}');
      // ignore: avoid_print
      print('기울기 0 인 길 픽셀: ${grad.where((g) => g == 0).length}개'
          ' (${(grad.where((g) => g == 0).length * 100 / grad.length).toStringAsFixed(1)}%)');

      // 진행도별 반투명 픽셀 수 — 실제로 화면에 회색으로 뜨는 것.
      // ignore: avoid_print
      print('\n진행도  반투명(1~254)  불투명  반투명/불투명');
      for (final p in [0.15, 0.30, 0.42, 0.55]) {
        var partial = 0;
        var opaque = 0;
        for (var i = 0; i < w * h; i++) {
          if (!roadIds.contains(plan.segmentId[i])) continue;
          final a = (k * (p * 255 - order[i])).round().clamp(0, 255);
          if (a >= 255) {
            opaque++;
          } else if (a > 0) {
            partial++;
          }
        }
        // ignore: avoid_print
        print('  ${p.toStringAsFixed(2)}  ${partial.toString().padLeft(11)}'
            '  ${opaque.toString().padLeft(6)}'
            '  ${opaque == 0 ? "-" : (partial / opaque).toStringAsFixed(2).padLeft(6)}');
      }

      // 가파르기를 흔들면 띠가 좁아지나 — 같은 텍스처에 알파만 다시 계산한다.
      // ignore: avoid_print
      print('\n가파르기 k  선단폭(순서값)  진행도 0.15 의 반투명 픽셀');
      for (final kk in [12.0, 24.0, 48.0, 96.0]) {
        var partial = 0;
        for (var i = 0; i < w * h; i++) {
          if (!roadIds.contains(plan.segmentId[i])) continue;
          final a = (kk * (0.15 * 255 - order[i])).round().clamp(0, 255);
          if (a > 0 && a < 255) partial++;
        }
        // ignore: avoid_print
        print('     ${kk.toStringAsFixed(0).padLeft(3)}'
            '  ${(255 / kk).toStringAsFixed(1).padLeft(12)}'
            '  ${partial.toString().padLeft(24)}');
      }

      // 기울기가 가장 완만한 자리 — 여기가 화면에서 가장 넓게 번진다.
      final flat = <int>[];
      for (var i = 0; i < w * h; i++) {
        if (roadIds.contains(plan.segmentId[i]) && gradAt[i] == 0) flat.add(i);
      }
      if (flat.isNotEmpty) {
        var minX = w, maxX = 0, minY = h, maxY = 0;
        for (final i in flat) {
          final x = i % w;
          final y = i ~/ w;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        // ignore: avoid_print
        print('\n기울기 0 픽셀이 몰린 상자: x $minX~$maxX · y $minY~$maxY'
            ' (캔버스 ${w}x$h)');
      }
      pair.base.dispose();
      pair.composed.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
