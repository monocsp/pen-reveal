@Tags(['corpus'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'RGBA 덤프',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('자산 없음');
        return;
      }
      Directory('tool/out/rgba').createSync(recursive: true);
      for (final longSide in [210, 420, 840]) {
        for (final key in keys) {
          final p = await loadCorpusMap(key);
          final s = fitImageLongSide(p.composed, longSide);
          final b = await rgbaAt(p.base, s.width, s.height);
          final c = await rgbaAt(p.composed, s.width, s.height);
          final head = ByteData(8)
            ..setUint32(0, s.width)
            ..setUint32(4, s.height);
          final out = BytesBuilder()
            ..add(head.buffer.asUint8List())
            ..add(b)
            ..add(c);
          File('tool/out/rgba/${key}_$longSide.bin')
              .writeAsBytesSync(out.toBytes());
          p.base.dispose();
          p.composed.dispose();
        }
      }
      // ignore: avoid_print
      print('덤프 완료: ${Directory('tool/out/rgba').listSync().length}개');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
