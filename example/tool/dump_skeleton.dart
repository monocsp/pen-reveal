@Tags(['corpus'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal/plan.dart' show DebugSkeleton, debugSkeletonSink;
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 얇게 깎은 선을 자리·갈래수 목록으로 뱉는다 — 굵은 그림 위에 겹쳐 볼 수 있게.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('얇은 선', () async {
    final have = await availableCorpusKeys();
    for (final key in ['map_special_01']) {
      if (!have.contains(key)) continue;
      final pair = await loadCorpusMap(key);
      final size = fitImageLongSide(pair.composed, 420);
      final b = await rgbaAt(pair.base, size.width, size.height);
      final c = await rgbaAt(pair.composed, size.width, size.height);
      DebugSkeleton? got;
      debugSkeletonSink = (s) {
        // 길 세그먼트가 가장 크다 — 자리 수가 가장 많은 것을 고른다.
        if (got == null || s.pixels.length > got!.pixels.length) got = s;
      };
      detectReveal(
        RevealDetectInput(
          baseRgba: b,
          composedRgba: c,
          width: size.width,
          height: size.height,
        ),
      );
      debugSkeletonSink = null;
      final s = got!;
      final buf = StringBuffer('${s.width} ${s.height} ${s.left} ${s.top}\n');
      for (var i = 0; i < s.pixels.length; i++) {
        final p = s.pixels[i];
        buf.writeln('${p % s.width} ${p ~/ s.width} ${s.degrees[i]}');
      }
      final f = File('tool/out/skel_$key.txt');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(buf.toString());
      // ignore: avoid_print
      print('    $key 자리 ${s.pixels.length} · 창 ${s.width}x${s.height} '
          '@(${s.left},${s.top})');
      pair.base.dispose();
      pair.composed.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
