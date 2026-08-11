@Tags(['corpus'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal/plan.dart' show debugRouteSink;
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 길을 순서에 따라 색으로 칠한 지도를 뱉는다 — 파랑(먼저) → 빨강(나중).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('경로 지도', () async {
    final have = await availableCorpusKeys();
    for (final key in ['map_special_01', 'map_deep_04', 'map_deep_05']) {
      if (!have.contains(key)) continue;
      final pair = await loadCorpusMap(key);
      final size = fitImageLongSide(pair.composed, 420);
      final b = await rgbaAt(pair.base, size.width, size.height);
      final c = await rgbaAt(pair.composed, size.width, size.height);
      debugRouteSink = (m) {
        // ignore: avoid_print
        print('    $key  $m');
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
      final h = size.height;
      final ids = <int>{
        for (final s in plan.segments)
          if (s.kind == RevealSegmentKind.primaryStroke) s.id,
      };
      final px = Uint8List(w * h * 3);
      for (var i = 0; i < w * h; i++) {
        px[i * 3] = 250;
        px[i * 3 + 1] = 248;
        px[i * 3 + 2] = 244;
      }
      // ⚠️ within 값 자체가 아니라 **순위**로 칠한다 — 값이 한쪽에 몰려 있으면
      //   그대로 칠했을 때 전부 같은 색이 되어 아무것도 안 보인다.
      final road = <int>[
        for (var i = 0; i < w * h; i++)
          if (ids.contains(plan.segmentId[i]) && plan.within[i] > 0) i,
      ]..sort((x, y) => plan.within[x].compareTo(plan.within[y]));
      for (var r = 0; r < road.length; r++) {
        final i = road[r];
        final t = r / (road.length - 1);
        px[i * 3] = (t < 0.5 ? t * 2 * 255 : 255).round().clamp(0, 255);
        px[i * 3 + 1] =
            ((t < 0.5 ? t * 2 : 2 - t * 2) * 200).round().clamp(0, 255);
        px[i * 3 + 2] = (t < 0.5 ? 255 - t * 2 * 255 : 0).round().clamp(0, 255);
      }
      final f = File('tool/out/route_$key.ppm');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(<int>[
        ...'P6\n$w $h\n255\n'.codeUnits,
        ...px,
      ]);
      pair.base.dispose();
      pair.composed.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
