// tool/dump_issues.dart — 사용자가 지적한 세 가지를 **확대해서 실측**한다.
//
//   ① 길의 빗살 아티팩트 — 순서값이 국소적으로 튀는가?
//   ② X 교차부 — `\` 에 통째로 가는가, 사분면으로 갈리는가?
//   ③ 글씨 연결요소 — 자모 단위로 갈리는가, 붙어 있는가?
//
//   실행:  cd example && flutter test tool/dump_issues.dart
@Tags(['corpus'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _key = 'map_basic_01';
const _outDir = 'tool/out';

Future<void> _save(Uint8List rgba, int w, int h, String name) async {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  final image = await c.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

/// [scale] 배로 최근접 확대 — 픽셀 하나하나가 보여야 진단이 된다.
Uint8List _zoom(Uint8List src, int sw, int sh, Rect crop, int scale) {
  final cw = crop.width.toInt();
  final ch = crop.height.toInt();
  final out = Uint8List(cw * scale * ch * scale * 4);
  for (var y = 0; y < ch * scale; y++) {
    for (var x = 0; x < cw * scale; x++) {
      final sx = crop.left.toInt() + x ~/ scale;
      final sy = crop.top.toInt() + y ~/ scale;
      final di = (y * cw * scale + x) * 4;
      if (sx < 0 || sy < 0 || sx >= sw || sy >= sh) continue;
      final si = (sy * sw + sx) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = 255;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '세 가지 지적을 확대 실측',
    () async {
      final keys = await availableCorpusKeys();
      if (!keys.contains(_key)) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }
      Directory(_outDir).createSync(recursive: true);
      final log = StringBuffer();
      void say(String s) {
        log.writeln(s);
        // ignore: avoid_print
        print(s);
      }

      final pair = await loadCorpusMap(_key);
      final size = fitImageLongSide(pair.composed, kBakeLongSide);
      final w = size.width;
      final h = size.height;
      final baseRgba = await rgbaAt(pair.base, w, h);
      final composedRgba = await rgbaAt(pair.composed, w, h);

      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: baseRgba,
          composedRgba: composedRgba,
          width: w,
          height: h,
        ),
      );
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final schedule = timing.schedule(plan);
      final order = compiler.compile(plan, schedule);

      // ══ ① 길 — 순서값이 이웃과 얼마나 튀는가 ══════════════════════
      say('## ① 길 빗살');
      var roadMin = 255;
      var roadMax = 0;
      var roadN = 0;
      var jumpTotal = 0;
      var jumpMax = 0;
      final jumpHist = <int, int>{};
      for (var i = 0; i < w * h; i++) {
        final id = plan.segmentId[i];
        if (id == kRevealHiddenSegment) continue;
        if (plan.segments[id].kind != RevealSegmentKind.primaryStroke) continue;
        final v = order[i];
        if (v == 255) continue;
        roadN++;
        if (v < roadMin) roadMin = v;
        if (v > roadMax) roadMax = v;
        // 4-이웃과의 최대 차이
        final x = i % w;
        final y = i ~/ w;
        var localMax = 0;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (plan.segmentId[ni] != id) continue;
          final d = (order[ni] - order[i]).abs();
          if (d > localMax) localMax = d;
        }
        jumpTotal += localMax;
        if (localMax > jumpMax) jumpMax = localMax;
        final bucket = localMax == 0
            ? 0
            : (localMax <= 2
                ? 2
                : (localMax <= 5 ? 5 : (localMax <= 10 ? 10 : 99)));
        jumpHist[bucket] = (jumpHist[bucket] ?? 0) + 1;
      }
      say('길 픽셀 $roadN · 순서값 $roadMin~$roadMax (폭 ${roadMax - roadMin})');
      say('이웃 간 순서값 차이 — 평균 ${(jumpTotal / roadN).toStringAsFixed(2)} · 최대 $jumpMax');
      say('  차이 0: ${jumpHist[0] ?? 0} · ≤2: ${jumpHist[2] ?? 0} · ≤5: ${jumpHist[5] ?? 0} '
          '· ≤10: ${jumpHist[10] ?? 0} · >10: ${jumpHist[99] ?? 0}');
      say('선단 폭 = 255/k = ${(255 / compiler.sharpness.k).toStringAsFixed(1)} 코드');
      say('');

      // ── 진짜 지표: 진행도별 **고립된 구멍** ────────────────────────
      //   이웃 간 차이는 갈래 경계에서도 크게 나오는데 그건 눈에 안 띈다. 눈에 띄는 건
      //   "주변은 다 드러났는데 혼자 안 드러난" 픽셀이다. 그걸 직접 센다.
      say('진행도별 고립 구멍 (길 픽셀 중, 8-이웃의 ≥6개가 이미 드러났는데 자기는 아직):');
      var holeWorst = 0;
      for (final p in <double>[0.05, 0.1, 0.15, 0.197, 0.25, 0.29]) {
        final gate = p * 255;
        var holes = 0;
        var revealed = 0;
        for (var i = 0; i < w * h; i++) {
          final id = plan.segmentId[i];
          if (id == kRevealHiddenSegment) continue;
          if (plan.segments[id].kind != RevealSegmentKind.primaryStroke) {
            continue;
          }
          final open =
              compiler.sharpness.alphaAt(order: order[i], progress: p) > 200;
          if (open) {
            revealed++;
            continue;
          }
          final x = i % w;
          final y = i ~/ w;
          var openNeighbors = 0;
          var roadNeighbors = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = x + dx;
              final ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              final ni = ny * w + nx;
              final nid = plan.segmentId[ni];
              if (nid == kRevealHiddenSegment) continue;
              if (plan.segments[nid].kind != RevealSegmentKind.primaryStroke) {
                continue;
              }
              roadNeighbors++;
              if (compiler.sharpness.alphaAt(order: order[ni], progress: p) >
                  200) {
                openNeighbors++;
              }
            }
          }
          if (roadNeighbors >= 6 && openNeighbors >= 6) holes++;
        }
        if (holes > holeWorst) holeWorst = holes;
        say('  p=${p.toStringAsFixed(3)}  드러남 ${revealed.toString().padLeft(4)}  '
            '구멍 ${holes.toString().padLeft(3)}  (gate=${gate.toStringAsFixed(0)})');
      }
      say('최악 구멍 수: $holeWorst');
      say('');

      // 길 순서값을 확대해 그린다 — 사용자가 캡처한 그 구간
      final roadHeat = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final j = i * 4;
        final id = plan.segmentId[i];
        final isRoad = id != kRevealHiddenSegment &&
            plan.segments[id].kind == RevealSegmentKind.primaryStroke;
        if (!isRoad) {
          roadHeat[j] = 26;
          roadHeat[j + 1] = 22;
          roadHeat[j + 2] = 19;
        } else {
          final t = (order[i] - roadMin) / math.max(1, roadMax - roadMin);
          roadHeat[j] = (30 + 225 * t).round().clamp(0, 255);
          roadHeat[j + 1] = (80 + 150 * t).round().clamp(0, 255);
          roadHeat[j + 2] = (200 - 140 * t).round().clamp(0, 255);
        }
        roadHeat[j + 3] = 255;
      }
      await _save(
        _zoom(roadHeat, w, h, const Rect.fromLTWH(120, 90, 80, 80), 6),
        80 * 6,
        80 * 6,
        '21_road_zoom',
      );

      // ② X — 두 획이 픽셀을 어떻게 나눠 갖는가 ══════════════════════
      say('## ② X 교차부');
      final xBack = <int>[];
      final xFwd = <int>[];
      for (var i = 0; i < w * h; i++) {
        final id = plan.segmentId[i];
        if (id == kRevealHiddenSegment) continue;
        switch (plan.segments[id].kind) {
          case RevealSegmentKind.crossBackslash:
            xBack.add(i);
          case RevealSegmentKind.crossSlash:
            xFwd.add(i);
          case RevealSegmentKind.primaryStroke:
          case RevealSegmentKind.annotation:
            break;
        }
      }
      say('`\\` ${xBack.length} px · `/` ${xFwd.length} px');
      if (xBack.isNotEmpty) {
        final allX = [...xBack, ...xFwd];
        var lo = w;
        var hi = 0;
        var top = h;
        var bot = 0;
        for (final i in allX) {
          lo = math.min(lo, i % w);
          hi = math.max(hi, i % w);
          top = math.min(top, i ~/ w);
          bot = math.max(bot, i ~/ w);
        }
        say('X bbox ($lo,$top)-($hi,$bot)  ${hi - lo + 1}×${bot - top + 1}');

        // 교차 중심 근처 5×5 에서 누가 가져갔는지
        final cx = (lo + hi) ~/ 2;
        final cy = (top + bot) ~/ 2;
        say('중심 ($cx,$cy) 근처 9×9 배정 (B=\\ · F=/ · .=없음):');
        for (var y = cy - 4; y <= cy + 4; y++) {
          final row = StringBuffer('  ');
          for (var x = cx - 4; x <= cx + 4; x++) {
            final i = y * w + x;
            final id = plan.segmentId[i];
            if (id == kRevealHiddenSegment) {
              row.write('.');
            } else {
              row.write(
                switch (plan.segments[id].kind) {
                  RevealSegmentKind.crossBackslash => 'B',
                  RevealSegmentKind.crossSlash => 'F',
                  _ => '?',
                },
              );
            }
          }
          say(row.toString());
        }

        // 확대 그림 — `\` 주황 / `/` 청록
        final xPx = Uint8List(w * h * 4);
        for (var i = 0; i < w * h; i++) {
          final j = i * 4;
          xPx[j] = 26;
          xPx[j + 1] = 22;
          xPx[j + 2] = 19;
          xPx[j + 3] = 255;
        }
        for (final i in xBack) {
          final j = i * 4;
          xPx[j] = 250;
          xPx[j + 1] = 170;
          xPx[j + 2] = 60;
        }
        for (final i in xFwd) {
          final j = i * 4;
          xPx[j] = 90;
          xPx[j + 1] = 200;
          xPx[j + 2] = 255;
        }
        await _save(
          _zoom(
            xPx,
            w,
            h,
            Rect.fromLTWH(lo - 6, top - 6, hi - lo + 13, bot - top + 13),
            7,
          ),
          (hi - lo + 13) * 7,
          (bot - top + 13) * 7,
          '22_x_zoom',
        );
      }
      say('');

      // ══ ③ 글씨 — 원시 연결요소는 몇 개인가 ════════════════════════
      say('## ③ 글씨 연결요소');
      final notePixels = <int>[];
      for (var i = 0; i < w * h; i++) {
        final id = plan.segmentId[i];
        if (id == kRevealHiddenSegment) continue;
        if (plan.segments[id].kind == RevealSegmentKind.annotation) {
          notePixels.add(i);
        }
      }
      // 기본 설정(orphan 흡수 O)
      final chunksDefault = segmentAnnotation(
        pixels: Int32List.fromList(notePixels),
        width: w,
        height: h,
      );
      say('현재 설정: ${chunksDefault.length}덩어리');
      // orphan 흡수를 사실상 끄고 최소 크기를 낮춘 것 — 원시 연결요소에 가깝다
      final chunksRaw = segmentAnnotation(
        pixels: Int32List.fromList(notePixels),
        width: w,
        height: h,
        config: const AnnotationSegmenterConfig(
          minChunkPixels: 1,
          orphanAttachRatio: 0,
        ),
      );
      say('orphan 흡수 없이: ${chunksRaw.length}덩어리');
      for (var i = 0; i < chunksRaw.length; i++) {
        final c = chunksRaw[i];
        say('  ${i.toString().padLeft(2)} line=${c.line} '
            'bbox=(${c.left},${c.top})-(${c.right},${c.bottom}) '
            '${(c.right - c.left + 1).toString().padLeft(3)}×${(c.bottom - c.top + 1).toString().padLeft(3)} '
            'px=${c.pixels.length}');
      }

      final notePx = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final j = i * 4;
        notePx[j] = 26;
        notePx[j + 1] = 22;
        notePx[j + 2] = 19;
        notePx[j + 3] = 255;
      }
      const palette = <List<int>>[
        [244, 162, 60],
        [236, 110, 70],
        [225, 84, 130],
        [186, 84, 200],
        [120, 110, 225],
        [70, 165, 235],
        [70, 205, 190],
        [110, 210, 110],
        [190, 210, 70],
        [235, 180, 70],
        [200, 120, 90],
        [160, 150, 150],
      ];
      for (var ci = 0; ci < chunksRaw.length; ci++) {
        final c = palette[ci % palette.length];
        for (final i in chunksRaw[ci].pixels) {
          final j = i * 4;
          notePx[j] = c[0];
          notePx[j + 1] = c[1];
          notePx[j + 2] = c[2];
        }
      }
      var nl = w;
      var nr = 0;
      var nt = h;
      var nb = 0;
      for (final i in notePixels) {
        nl = math.min(nl, i % w);
        nr = math.max(nr, i % w);
        nt = math.min(nt, i ~/ w);
        nb = math.max(nb, i ~/ w);
      }
      await _save(
        _zoom(
          notePx,
          w,
          h,
          Rect.fromLTWH(nl - 4, nt - 4, nr - nl + 9, nb - nt + 9),
          5,
        ),
        (nr - nl + 9) * 5,
        (nb - nt + 9) * 5,
        '23_note_zoom',
      );

      File('$_outDir/issues.txt').writeAsStringSync(log.toString());
      pair.base.dispose();
      pair.composed.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
