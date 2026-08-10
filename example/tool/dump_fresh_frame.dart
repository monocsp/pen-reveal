// 문제의 프레임에서 **무엇이 새로 켜지나** 를 그림으로 뽑는다.
//
//   숫자로 세 가설(붓 반경·평활·디더)을 다 지웠다. 남은 것은 "한 프레임에 켜지는 면적이
//   원래 그만큼이어야 한다" 는 가능성이다 — 길 9,905px 을 115프레임에 드러내려면
//   프레임당 86px 은 켜져야 한다. 그렇다면 문제는 **양이 아니라 모양**이다.
//   붓이면 획을 가로지르는 얇은 띠고, 면이 자라면 뭉친 덩어리다.
//
//   그래서 본다. 회색조 PNG 로 떨군다 — 흰 = 이번 프레임에 새로 켜짐, 중간 회색 = 이미
//   켜진 길, 검정 = 아직.
@Tags(['corpus'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;

/// 회색조 바이트를 PNG 로.
void _writePng(String path, Uint8List gray, int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw
      ..addByte(0)
      ..add(gray.sublist(y * w, (y + 1) * w));
  }
  final idat = ZLibEncoder().convert(raw.toBytes());
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);

  void chunk(String type, List<int> data) {
    final b = ByteData(4)..setUint32(0, data.length);
    out.add(b.buffer.asUint8List());
    final body = <int>[...ascii.encode(type), ...data];
    out.add(body);
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    final c = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    out.add(c.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  File(path).writeAsBytesSync(out.toBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '문제 프레임의 새로 켜진 픽셀을 그림으로',
    () async {
      final have = await availableCorpusKeys();
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      Directory('tool/out').createSync(recursive: true);

      for (final spec in [
        ('map_deep_05', 0.593),
        ('map_deep_05', 0.300),
        ('map_deep_04', 0.043),
        ('map_basic_01', 0.059),
      ]) {
        final key = spec.$1;
        final at = spec.$2;
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
        final w = size.width;
        final h = size.height;
        final roadIds = <int>{
          for (final s in plan.segments)
            if (s.kind == RevealSegmentKind.primaryStroke) s.id,
        };
        final frames = (schedule.total.inMilliseconds * 60 / 1000).round();
        final step = 1.0 / frames;

        Uint8List opaque(double p) {
          final o = Uint8List(w * h);
          for (var i = 0; i < w * h; i++) {
            if (!roadIds.contains(plan.segmentId[i])) continue;
            if (24.0 * (p * 255 - order[i]) >= 255) o[i] = 1;
          }
          return o;
        }

        final before = opaque(at - step);
        final after = opaque(at);
        final gray = Uint8List(w * h);
        var fresh = 0;
        for (var i = 0; i < w * h; i++) {
          if (!roadIds.contains(plan.segmentId[i])) continue;
          if (after[i] == 1 && before[i] == 0) {
            gray[i] = 255; // 이번 프레임에 새로
            fresh++;
          } else if (after[i] == 1) {
            gray[i] = 90; // 이미 켜진 길
          } else {
            gray[i] = 35; // 아직
          }
        }
        // 새로 켜진 픽셀이 실제로 어디 있나 — 상자와 표본 좌표.
        var minX = w;
        var maxX = -1;
        var minY = h;
        var maxY = -1;
        final sample = <String>[];
        for (var i = 0; i < w * h; i++) {
          if (gray[i] != 255) continue;
          final x = i % w;
          final y = i ~/ w;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          if (sample.length < 6) sample.add('($x,$y)');
        }
        // ignore: avoid_print
        print('  새로 켜진 상자 x $minX~$maxX · y $minY~$maxY · 표본 $sample');
        _writePng('tool/out/fresh_$key.png', gray, w, h);
        // ignore: avoid_print
        print('tool/out/fresh_$key.png — 진행도 $at 에서 새로 $fresh px '
            '(${w}x$h, 프레임 $frames)');
        pair.base.dispose();
        pair.composed.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
