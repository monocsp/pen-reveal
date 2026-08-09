// tool/dump_discrimination.dart — **세 갈래를 어떻게 가르는지**를 그림으로 뽑는다.
//
//   dump_stages.dart 가 "파이프라인 전체"라면, 이쪽은 판정 세 개만 확대한다:
//     ① 길의 순서 — 어디서 시작해 어디로 가는가
//     ② X 고르기 — 붉은 덩어리 여럿 중 왜 저것만 X 인가
//     ③ X 를 두 획으로 · 나머지를 읽는 순서로
//
//   실행:  cd example && flutter test tool/dump_discrimination.dart
@Tags(['corpus'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _key = 'map_basic_01';
const _outDir = 'tool/out';
const _bg = [26, 22, 19];

Future<void> _save(Uint8List rgba, int w, int h, String name) async {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  final image = await c.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

Uint8List _canvas(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final j = i * 4;
    px[j] = _bg[0];
    px[j + 1] = _bg[1];
    px[j + 2] = _bg[2];
    px[j + 3] = 255;
  }
  return px;
}

void _put(Uint8List px, int i, List<int> c) {
  final j = i * 4;
  px[j] = c[0];
  px[j + 1] = c[1];
  px[j + 2] = c[2];
}

void _ring(Uint8List px, int w, int h, int cx, int cy, int rad, List<int> c) {
  for (var a = 0; a < 360; a += 2) {
    final t = a * math.pi / 180;
    for (var d = 0; d < 2; d++) {
      final x = (cx + (rad + d) * math.cos(t)).round();
      final y = (cy + (rad + d) * math.sin(t)).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      _put(px, y * w + x, c);
    }
  }
}

void _line(
  Uint8List px,
  int w,
  int h,
  int x0,
  int y0,
  int x1,
  int y1,
  List<int> c,
) {
  final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
  if (steps == 0) return;
  for (var s = 0; s <= steps; s++) {
    if ((s ~/ 3).isOdd) continue; // 점선
    final x = (x0 + (x1 - x0) * s / steps).round();
    final y = (y0 + (y1 - y0) * s / steps).round();
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    _put(px, y * w + x, c);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('세 갈래 판정을 그림으로', () async {
    final keys = await availableCorpusKeys();
    if (!keys.contains(_key)) {
      markTestSkipped('정본 지도가 번들에 없다');
      return;
    }
    Directory(_outDir).createSync(recursive: true);

    final pair = await loadCorpusMap(_key);
    final size = fitImageLongSide(pair.composed, kBakeLongSide);
    final w = size.width;
    final h = size.height;
    final baseRgba = await rgbaAt(pair.base, w, h);
    final composedRgba = await rgbaAt(pair.composed, w, h);
    // 정본 문구는 전부 '발견한곳' 4음절이다 — 힌트를 줘서 음절·자모 순서를 본다.
    const cfg = RevealDetectConfig(
      annotation: AnnotationSegmenterConfig(expectedSyllableCount: 4),
    );

    // ── diff 로 길·빨강 채널을 손으로 만든다(detector 와 같은 판정) ──
    final road = Uint8List(w * h);
    final accentIdx = <int>[];
    for (var i = 0; i < w * h; i++) {
      final j = i * 4;
      final d = (composedRgba[j] - baseRgba[j]).abs() +
          (composedRgba[j + 1] - baseRgba[j + 1]).abs() +
          (composedRgba[j + 2] - baseRgba[j + 2]).abs();
      if (d <= cfg.differenceThreshold ||
          composedRgba[j + 3] < cfg.composedAlphaThreshold) {
        continue;
      }
      if (composedRgba[j] - composedRgba[j + 1] > cfg.accentRedDeltaThreshold) {
        accentIdx.add(i);
      } else {
        road[i] = 255;
      }
    }

    // ══ ① 길 — 뼈대와 순회 순서 ═══════════════════════════════════
    final baked = bakeOneStrokeOrder(
      StrokeMask(road, w, h),
    );
    final orderPx = _canvas(w, h);
    // 길 전체를 아주 어둡게 깔고
    for (var i = 0; i < w * h; i++) {
      if (road[i] != 0) _put(orderPx, i, [58, 50, 42]);
    }
    // 순서값을 색으로 — 먼저=파랑, 나중=노랑
    var startIdx = -1;
    var startVal = 999;
    for (var i = 0; i < w * h; i++) {
      final v = baked.bytes[i];
      if (v == 255) continue;
      final t = v / 254;
      _put(orderPx, i, [
        (60 + 195 * t).round(),
        (110 + 130 * t).round(),
        (210 - 130 * t).round(),
      ]);
      if (v < startVal) {
        startVal = v;
        startIdx = i;
      }
    }
    // 시작점에 고리
    if (startIdx >= 0) {
      _ring(orderPx, w, h, startIdx % w, startIdx ~/ w, 9, [255, 255, 255]);
      _ring(orderPx, w, h, startIdx % w, startIdx ~/ w, 13, [80, 200, 255]);
    }
    await _save(orderPx, w, h, '11_road_order');

    // ══ ② X 고르기 — 붉은 덩어리들과 길까지의 거리 ═══════════════
    final plan = detectReveal(
      RevealDetectInput(
        baseRgba: baseRgba,
        composedRgba: composedRgba,
        width: w,
        height: h,
        config: cfg,
      ),
    );
    // 길의 최대 연결요소(= X 판정의 자)
    final drawn = <int>[
      for (var i = 0; i < w * h; i++)
        if (baked.bytes[i] != 255) i,
    ];

    final pick = _canvas(w, h);
    for (final i in drawn) {
      _put(pick, i, [70, 62, 54]);
    }
    // 빨강 덩어리를 계획의 세그먼트로 되짚어 색칠 — X 인 것과 아닌 것.
    final xIds = <int>{};
    for (final s in plan.segments) {
      if (s.kind == RevealSegmentKind.crossBackslash ||
          s.kind == RevealSegmentKind.crossSlash) {
        xIds.add(s.id);
      }
    }
    var xSumX = 0;
    var xSumY = 0;
    var xN = 0;
    final noteCentroids = <int, (int, int, int)>{};
    for (var i = 0; i < w * h; i++) {
      final id = plan.segmentId[i];
      if (id == kRevealHiddenSegment) continue;
      final kind = plan.segments[id].kind;
      if (kind == RevealSegmentKind.primaryStroke) continue;
      if (xIds.contains(id)) {
        _put(pick, i, [235, 90, 80]);
        xSumX += i % w;
        xSumY += i ~/ w;
        xN++;
      } else if (kind == RevealSegmentKind.annotation) {
        _put(pick, i, [110, 105, 100]);
        final cur = noteCentroids[id] ?? (0, 0, 0);
        noteCentroids[id] = (cur.$1 + i % w, cur.$2 + i ~/ w, cur.$3 + 1);
      }
    }
    // X 무게중심 → 가장 가까운 길 픽셀 점선
    if (xN > 0) {
      final cx = xSumX ~/ xN;
      final cy = xSumY ~/ xN;
      var bx = 0;
      var by = 0;
      var bd = 1e18;
      for (final i in drawn) {
        final dx = (i % w) - cx;
        final dy = (i ~/ w) - cy;
        final d = (dx * dx + dy * dy).toDouble();
        if (d < bd) {
          bd = d;
          bx = i % w;
          by = i ~/ w;
        }
      }
      _line(pick, w, h, cx, cy, bx, by, [120, 230, 160]);
      _ring(pick, w, h, cx, cy, 6, [255, 255, 255]);
    }
    // 글씨 덩어리 무게중심 → 길 점선(멀다는 것을 보여 준다)
    for (final e in noteCentroids.entries) {
      final cx = e.value.$1 ~/ e.value.$3;
      final cy = e.value.$2 ~/ e.value.$3;
      var bx = 0;
      var by = 0;
      var bd = 1e18;
      for (final i in drawn) {
        final dx = (i % w) - cx;
        final dy = (i ~/ w) - cy;
        final d = (dx * dx + dy * dy).toDouble();
        if (d < bd) {
          bd = d;
          bx = i % w;
          by = i ~/ w;
        }
      }
      _line(pick, w, h, cx, cy, bx, by, [200, 170, 90]);
      _ring(pick, w, h, cx, cy, 4, [210, 190, 130]);
    }
    await _save(pick, w, h, '12_x_pick');

    // ══ ③ X 두 획 · 글씨 읽는 순서 ═══════════════════════════════
    final split = _canvas(w, h);
    for (final i in drawn) {
      _put(split, i, [52, 46, 40]);
    }
    const order6 = <List<int>>[
      [244, 162, 60],
      [236, 120, 70],
      [225, 84, 96],
      [186, 84, 168],
      [110, 110, 210],
      [80, 172, 200],
    ];
    var noteRank = 0;
    final rankOf = <int, int>{};
    for (final s in plan.segments) {
      if (s.kind == RevealSegmentKind.annotation) rankOf[s.id] = noteRank++;
    }
    for (var i = 0; i < w * h; i++) {
      final id = plan.segmentId[i];
      if (id == kRevealHiddenSegment) continue;
      final s = plan.segments[id];
      switch (s.kind) {
        case RevealSegmentKind.primaryStroke:
          break;
        case RevealSegmentKind.crossBackslash:
          _put(split, i, [250, 170, 60]);
        case RevealSegmentKind.crossSlash:
          _put(split, i, [90, 200, 255]);
        case RevealSegmentKind.annotation:
          _put(split, i, order6[rankOf[id]! % order6.length]);
      }
    }
    await _save(split, w, h, '13_split_order');

    // ── 숫자 ────────────────────────────────────────────────────
    final report = StringBuffer()
      ..writeln('길 뼈대 길이(measure)  ${baked.length.toStringAsFixed(1)} px')
      ..writeln('길 시작점              (${startIdx % w}, ${startIdx ~/ w})  '
          '— 최상단에서 시작한다')
      ..writeln('길 순서값 범위         0 ~ 254')
      ..writeln();
    for (final s in plan.segments) {
      if (s.kind != RevealSegmentKind.annotation) continue;
      report.writeln(
          '글씨 덩어리 id=${s.id}  bbox=(${s.left},${s.top})-(${s.right},${s.bottom})  '
          '폭=${s.width} 높이=${s.height} px=${s.pixelCount}');
    }
    File('$_outDir/report2.txt').writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);

    pair.base.dispose();
    pair.composed.dispose();
  });
}
