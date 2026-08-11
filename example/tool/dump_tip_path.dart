@Tags(['corpus'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal/plan.dart' show debugRouteSink;
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('펜 끝 자취', () async {
    final have = await availableCorpusKeys();
    for (final key in ['map_special_01']) {
      if (!have.contains(key)) continue;
      final pair = await loadCorpusMap(key);
      final size = fitImageLongSide(pair.composed, 420);
      final b = await rgbaAt(pair.base, size.width, size.height);
      final c = await rgbaAt(pair.composed, size.width, size.height);
      debugRouteSink = (m) {
        // ignore: avoid_print
        print('    $m');
      };
      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: b,
          composedRgba: c,
          width: size.width,
          height: size.height,
        ),
      );
      debugRouteSink = null;
      final w = size.width;
      final ids = <int>{
        for (final s in plan.segments)
          if (s.kind == RevealSegmentKind.primaryStroke) s.id,
      };
      // 길 픽셀을 within 순으로 세우고 80 칸으로 나눠 무게중심을 찍는다.
      final road = <int>[
        for (var i = 0; i < plan.segmentId.length; i++)
          if (ids.contains(plan.segmentId[i]) && plan.within[i] > 0) i,
      ]..sort((x, y) => plan.within[x].compareTo(plan.within[y]));
      const bins = 60;
      final buf = StringBuffer('\n$key 길 픽셀 ${road.length}\n');
      (double, double)? prev;
      for (var k = 0; k < bins; k++) {
        final lo = road.length * k ~/ bins;
        final hi = road.length * (k + 1) ~/ bins;
        if (hi <= lo) continue;
        var sx = 0.0;
        var sy = 0.0;
        for (var j = lo; j < hi; j++) {
          sx += road[j] % w;
          sy += road[j] ~/ w;
        }
        final n = hi - lo;
        final x = sx / n;
        final y = sy / n;
        var mark = '';
        if (prev != null) {
          final dx = x - prev.$1;
          final dy = y - prev.$2;
          final d = math.sqrt(dx * dx + dy * dy);
          mark = ' 걸음 ${d.toStringAsFixed(1)}'
              '${dy < -3 ? "  ↑↑ 위로" : ""}'
              '${d > 25 ? "  ** 순간이동" : ""}';
        }
        buf.writeln(
          '${k.toString().padLeft(2)}  '
          '(${x.toStringAsFixed(0).padLeft(3)},${y.toStringAsFixed(0).padLeft(3)})$mark',
        );
        prev = (x, y);
      }
      // ignore: avoid_print
      print(buf);
      pair.base.dispose();
      pair.composed.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
