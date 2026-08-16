// 길을 **얇은 선 하나로 단순화한 결과**를 그림으로 뽑는다.
//
//   두 장(바닥·최종)의 차이에서 길을 고르고, 형태 정리 → 세선화 → 가시 제거까지 끝난
//   선을 그 길 위에 겹쳐 그린다. 순서·시간은 여기서 안 본다 — **모양만** 본다.
//
//   색:
//     · 옅은 회색 = 길(굵은 그대로)
//     · 파랑      = 지나가는 자리(갈래 2)
//     · 초록      = 끝점(갈래 1)
//     · 빨강      = 갈림길(갈래 3 이상)  ← 단순화가 잘 됐는지는 거의 이걸로 읽힌다
//
//   `tool/out/skel_<key>.png` 로 떨군다(그 디렉터리는 ignore 다).
//
//   돌리는 법: cd example && flutter test tool/dump_skeleton.dart
@Tags(['corpus'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 굽는 해상도. 세선화가 도는 해상도라 이 값이 곧 단순화의 해상도다.
const _side = 420;

/// 화면에서 보기 좋게 키우는 배수(최근접 — 픽셀을 뭉개지 않는다).
const _zoom = 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '길을 얇은 선으로 단순화한 결과를 그림으로 뽑는다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다 — example/assets/maps 를 채운다');
        return;
      }
      final outDir = Directory('tool/out')..createSync(recursive: true);

      stdout.writeln(
        '지도             길 px   얇은 선   압축비   끝점  갈림길  지나감',
      );

      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        final size = fitImageLongSide(pair.composed, _side);
        final w = size.width;
        final h = size.height;
        final base = await rgbaAt(pair.base, w, h);
        final composed = await rgbaAt(pair.composed, w, h);
        pair.base.dispose();
        pair.composed.dispose();

        // 얇은 선을 받아 둔다. 세그먼트마다 한 번씩 오므로 **가장 큰 것**이 길이다.
        DebugSkeleton? road;
        debugSkeletonSink = (s) {
          if (road == null || s.pixels.length > road!.pixels.length) road = s;
        };
        final plan = detectReveal(
          RevealDetectInput(
            baseRgba: base,
            composedRgba: composed,
            width: w,
            height: h,
          ),
        );
        // ⚠️ 전역이라 반드시 되돌린다 — 안 그러면 다음 지도가 이걸 물고 간다.
        debugSkeletonSink = null;

        final skel = road;
        if (skel == null) {
          stdout.writeln('$key — 얇은 선이 안 나왔다');
          continue;
        }

        // 길 픽셀은 계획에서 읽는다(세선화 입력과 같은 마스크다).
        final roadPx = <int>[];
        for (var i = 0; i < w * h; i++) {
          final id = plan.segmentId[i];
          if (id < plan.segments.length &&
              plan.segments[id].kind == RevealSegmentKind.primaryStroke) {
            roadPx.add(i);
          }
        }

        var ends = 0;
        var forks = 0;
        var through = 0;
        for (final d in skel.degrees) {
          if (d <= 1) {
            ends++;
          } else if (d == 2) {
            through++;
          } else {
            forks++;
          }
        }

        final png = await _render(w, h, roadPx, skel);
        File('${outDir.path}/skel_$key.png').writeAsBytesSync(png);

        stdout.writeln(
          '${key.padRight(16)}'
          '${roadPx.length.toString().padLeft(6)}'
          '${skel.pixels.length.toString().padLeft(9)}'
          '${(roadPx.length / skel.pixels.length).toStringAsFixed(1).padLeft(8)}배'
          '${ends.toString().padLeft(6)}'
          '${forks.toString().padLeft(7)}'
          '${through.toString().padLeft(8)}',
        );
      }
      stdout.writeln('\n그림: example/tool/out/skel_*.png');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// 길 위에 얇은 선을 겹쳐 PNG 바이트로 만든다.
Future<Uint8List> _render(
  int w,
  int h,
  List<int> roadPx,
  DebugSkeleton skel,
) async {
  final zw = w * _zoom;
  final zh = h * _zoom;
  final px = Uint8List(zw * zh * 4);
  // 바탕은 흰색.
  for (var i = 0; i < zw * zh; i++) {
    px[i * 4] = 255;
    px[i * 4 + 1] = 255;
    px[i * 4 + 2] = 255;
    px[i * 4 + 3] = 255;
  }

  void put(int x, int y, int r, int g, int b) {
    for (var dy = 0; dy < _zoom; dy++) {
      for (var dx = 0; dx < _zoom; dx++) {
        final zx = x * _zoom + dx;
        final zy = y * _zoom + dy;
        if (zx < 0 || zy < 0 || zx >= zw || zy >= zh) continue;
        final j = (zy * zw + zx) * 4;
        px[j] = r;
        px[j + 1] = g;
        px[j + 2] = b;
      }
    }
  }

  for (final i in roadPx) {
    put(i % w, i ~/ w, 222, 222, 226);
  }
  for (var n = 0; n < skel.pixels.length; n++) {
    final p = skel.pixels[n];
    // 창(ROI) 좌표 → 원본 좌표.
    final x = p % skel.width + skel.left;
    final y = p ~/ skel.width + skel.top;
    final d = skel.degrees[n];
    if (d <= 1) {
      put(x, y, 22, 163, 74); // 끝점
    } else if (d == 2) {
      put(x, y, 37, 99, 235); // 지나가는 자리
    } else {
      put(x, y, 220, 38, 38); // 갈림길
    }
  }

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, zw, zh, ui.PixelFormat.rgba8888, done.complete);
  final img = await done.future;
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}
