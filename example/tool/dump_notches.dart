// 길 위의 **결함 세 종**을 정본 전체에서 센다.
//
//   ① 고립 구멍   — 둘레가 다 열렸는데 혼자 안 열린 픽셀. 점으로 보인다.
//   ② 선단 계단   — 이웃 순서값 차가 선단 폭(255/k)을 넘는 자리. 계단으로 보인다.
//   ③ **만灣(notch)** — 이미 지나간 자리에 남은 **덩어리진** 미개방 영역. 사장님이 본
//      "하얀색이 파여 있는" 것. ①은 1px 이라 안 잡히고, 여기서 잡는다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'notches',
    () async {
      final keys = await availableCorpusKeys();
      const sharp = RevealSharpness.standard;
      stdout.writeln(
        '지도            길픽셀   만 최대   만 총합  만 개수   진행도    구멍  계단',
      );
      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        final s = fitImageLongSide(pair.composed, 420);
        final w = s.width;
        final h = s.height;
        final plan = detectReveal(
          RevealDetectInput(
            baseRgba: await rgbaAt(pair.base, w, h),
            composedRgba: await rgbaAt(pair.composed, w, h),
            width: w,
            height: h,
          ),
        );
        final order = const RevealTextureCompiler()
            .compile(plan, const HandwritingRevealTiming().schedule(plan));
        // 길 세그먼트만
        final road = List<bool>.generate(w * h, (i) {
          final id = plan.segmentId[i];
          return id < plan.segments.length &&
              plan.segments[id].kind == RevealSegmentKind.primaryStroke;
        });
        var roadPx = 0;
        for (final r in road) {
          if (r) roadPx++;
        }

        var worstBlob = 0;
        var worstSum = 0;
        var worstCount = 0;
        var worstP = 0.0;
        var holes = 0;
        for (var pi = 5; pi <= 95; pi++) {
          final p = pi / 100;
          // 열린 곳
          final open = List<bool>.generate(
            w * h,
            (i) => road[i] && sharp.alphaAt(order: order[i], progress: p) > 200,
          );
          // 선단 뒤쪽 = 이미 지나간 자리. "닫힘인데 8-이웃 중 열린 게 많다" 로 본다.
          final closedBehind = List<bool>.filled(w * h, false);
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
              if (tot >= 8 && lit >= tot * 0.6) closedBehind[i] = true;
            }
          }
          // 덩어리로 묶는다
          final seen = List<bool>.filled(w * h, false);
          var blob = 0;
          var sum = 0;
          var count = 0;
          var hole = 0;
          for (var i = 0; i < w * h; i++) {
            if (!closedBehind[i] || seen[i]) continue;
            var n = 0;
            final st = <int>[i];
            seen[i] = true;
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
                  if (closedBehind[j] && !seen[j]) {
                    seen[j] = true;
                    st.add(j);
                  }
                }
              }
            }
            if (n == 1) {
              hole++;
            } else {
              count++;
              sum += n;
              if (n > blob) blob = n;
            }
          }
          if (blob > worstBlob) {
            worstBlob = blob;
            worstSum = sum;
            worstCount = count;
            worstP = p;
          }
          if (hole > holes) holes = hole;
        }
        // 선단 계단
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
              if ((order[j] - order[i]).abs() > 255 / 24) jumps++;
            }
          }
        }
        stdout.writeln('${key.padRight(15)}${roadPx.toString().padLeft(6)}'
            '${worstBlob.toString().padLeft(9)}${worstSum.toString().padLeft(9)}'
            '${worstCount.toString().padLeft(8)}'
            '${worstP.toStringAsFixed(2).padLeft(9)}'
            '${holes.toString().padLeft(7)}${jumps.toString().padLeft(6)}');
        pair.base.dispose();
        pair.composed.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
