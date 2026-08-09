// tool/dump_stages.dart — 정본 지도 한 장을 굽고 **중간 산출물을 전부 PNG 로 뱉는다.**
//
//   설명용 그림을 손으로 그리면 실제와 어긋난다. 엔진이 실제로 만든 것을 그대로 꺼낸다.
//
//   실행:  cd example && flutter test tool/dump_stages.dart
//   결과:  tool/out/*.png  (gitignore 대상 — 정본 픽셀에서 나온 것이다)
@Tags(['corpus'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _key = 'map_basic_01';
const _outDir = 'tool/out';

/// 설명 그림에 넣을 진행도들 — 단계 경계를 끼워 넣는다.
const _named = <String, double?>{
  '00': 0,
  '10': 0.10,
  '20': 0.20,
  'roadEnd': null, // stages.primaryEnd
  'crossMid': null, // 두 X 획 사이
  'crossEnd': null, // stages.crossEnd
  '80': 0.80,
  '100': 1,
};

Future<void> _save(ui.Image image, String name) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

Future<ui.Image> _fromRgba(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('정본 한 장의 중간 산출물을 전부 뱉는다', () async {
    final keys = await availableCorpusKeys();
    if (!keys.contains(_key)) {
      markTestSkipped('정본 지도가 번들에 없다 — example/assets/maps/ 를 채워라');
      return;
    }
    Directory(_outDir).createSync(recursive: true);

    final pair = await loadCorpusMap(_key);
    final base = pair.base;
    final composed = pair.composed;

    // ── ① 입력 두 장 ──────────────────────────────────────────────
    await _save(base, '01_base');
    await _save(composed, '02_composed');

    // ── ② 굽기 해상도로 RGBA 를 떠서 detector 가 보는 것과 같게 만든다 ──
    final size = fitImageLongSide(composed, kBakeLongSide);
    final w = size.width;
    final h = size.height;
    final baseRgba = await rgbaAt(base, w, h);
    final composedRgba = await rgbaAt(composed, w, h);

    // ── ③ diff 세 갈래를 색으로 ────────────────────────────────────
    //   버린 곳=어둡게, 길=흰색, 빨강=주황. detector 와 같은 임계를 쓴다.
    // 정본 문구는 전부 '발견한곳' 4음절이다 — 힌트를 줘서 음절·자모 순서를 본다.
    const cfg = RevealDetectConfig(
      annotation: AnnotationSegmenterConfig(expectedSyllableCount: 4),
    );
    final diff = Uint8List(w * h * 4);
    var roadPx = 0;
    var accentPx = 0;
    for (var i = 0; i < w * h; i++) {
      final j = i * 4;
      final d = (composedRgba[j] - baseRgba[j]).abs() +
          (composedRgba[j + 1] - baseRgba[j + 1]).abs() +
          (composedRgba[j + 2] - baseRgba[j + 2]).abs();
      final kept = d > cfg.differenceThreshold &&
          composedRgba[j + 3] >= cfg.composedAlphaThreshold;
      if (!kept) {
        diff[j] = 26;
        diff[j + 1] = 22;
        diff[j + 2] = 19;
      } else if (composedRgba[j] - composedRgba[j + 1] >
          cfg.accentRedDeltaThreshold) {
        diff[j] = 240;
        diff[j + 1] = 90;
        diff[j + 2] = 80;
        accentPx++;
      } else {
        diff[j] = 255;
        diff[j + 1] = 253;
        diff[j + 2] = 248;
        roadPx++;
      }
      diff[j + 3] = 255;
    }
    await _save(await _fromRgba(diff, w, h), '03_diff');

    // ── ④ 계획 — 세그먼트 종류로 칠한다 ─────────────────────────────
    final plan = detectReveal(
      RevealDetectInput(
        baseRgba: baseRgba,
        composedRgba: composedRgba,
        width: w,
        height: h,
        config: cfg,
      ),
    );
    const kindColor = <RevealSegmentKind, List<int>>{
      RevealSegmentKind.primaryStroke: [90, 160, 235], // 길 — 파랑
      RevealSegmentKind.crossBackslash: [245, 150, 60], // X \ — 주황
      RevealSegmentKind.crossSlash: [225, 80, 70], // X / — 빨강
      RevealSegmentKind.annotation: [95, 185, 130], // 글씨 — 초록
    };
    final seg = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final j = i * 4;
      final id = plan.segmentId[i];
      if (id == kRevealHiddenSegment) {
        seg[j] = 26;
        seg[j + 1] = 22;
        seg[j + 2] = 19;
      } else {
        final c = kindColor[plan.segments[id].kind]!;
        // 덩어리 안 진행도를 밝기로 — 왼→오 wipe 가 눈에 보이게.
        final t = 0.45 + 0.55 * (plan.within[i] / kRevealWithinScale);
        seg[j] = (c[0] * t).round();
        seg[j + 1] = (c[1] * t).round();
        seg[j + 2] = (c[2] * t).round();
      }
      seg[j + 3] = 255;
    }
    await _save(await _fromRgba(seg, w, h), '04_segments');

    // ── ⑤ 순서 텍스처 — 회색 대신 열지도로 ──────────────────────────
    const timing = HandwritingRevealTiming();
    final schedule = timing.schedule(plan);
    const compiler = RevealTextureCompiler();
    final order = compiler.compile(plan, schedule);
    final heat = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final j = i * 4;
      final v = order[i];
      if (v >= kRevealHiddenSegment) {
        heat[j] = 26;
        heat[j + 1] = 22;
        heat[j + 2] = 19;
      } else {
        final t = v / compiler.maxOrderValue;
        // 짙은 남색 → 청록 → 노랑. 먼저 드러날수록 어둡다.
        heat[j] = (40 + 215 * t).round().clamp(0, 255);
        heat[j + 1] = (60 + 180 * t).round().clamp(0, 255);
        heat[j + 2] = (120 - 60 * t).round().clamp(0, 255);
      }
      heat[j + 3] = 255;
    }
    await _save(await _fromRgba(heat, w, h), '05_order');

    // ── ⑥ 실제 재생 프레임 ─────────────────────────────────────────
    final prepared = await const RevealPreparer(detectConfig: cfg)
        .prepare(base: base, composed: composed);
    final s = prepared.stages;
    final marks = <String, double>{
      for (final e in _named.entries)
        e.key: switch (e.key) {
          'roadEnd' => s.primaryEnd,
          'crossMid' => s.primaryEnd + (s.crossEnd - s.primaryEnd) * 0.45,
          'crossEnd' => s.crossEnd,
          _ => e.value!,
        },
    };
    final side = Size(composed.width.toDouble(), composed.height.toDouble());
    for (final e in marks.entries) {
      final recorder = ui.PictureRecorder();
      SequentialRevealPainter(
        base: base,
        composed: composed,
        prepared: prepared,
        progress: e.value,
      ).paint(ui.Canvas(recorder), side);
      final pic = recorder.endRecording();
      final img = await pic.toImage(composed.width, composed.height);
      await _save(img, '06_frame_${e.key}');
      pic.dispose();
      img.dispose();
    }

    // ── ⑦ 숫자 요약 ────────────────────────────────────────────────
    final counts = <RevealSegmentKind, int>{};
    for (final segment in plan.segments) {
      counts[segment.kind] = (counts[segment.kind] ?? 0) + 1;
    }
    final report = StringBuffer()
      ..writeln('key            $_key')
      ..writeln('원본           ${composed.width}×${composed.height}')
      ..writeln('굽기 해상도    $w×$h  (${w * h} px)')
      ..writeln(
        '길 픽셀        $roadPx  (${(roadPx / (w * h) * 100).toStringAsFixed(2)}%)',
      )
      ..writeln(
        '빨강 픽셀      $accentPx  (${(accentPx / (w * h) * 100).toStringAsFixed(2)}%)',
      )
      ..writeln('세그먼트       ${plan.segments.length}개  $counts')
      ..writeln('재생 시간      ${prepared.revealDuration.inMilliseconds} ms')
      ..writeln(
        '가파르기 k     ${prepared.sharpness.k}  (상한 ${prepared.sharpness.maxOrderValue})',
      )
      ..writeln(
        '선단 폭        ${prepared.sharpness.leadingEdgeCodes.toStringAsFixed(1)} 코드',
      )
      ..writeln('단계 경계      길 ${s.primaryEnd.toStringAsFixed(4)} · '
          'X ${s.crossEnd.toStringAsFixed(4)} · 끝 ${s.annotationEnd.toStringAsFixed(4)}')
      ..writeln(
          '구간 ms        길 ${(prepared.revealDuration.inMilliseconds * s.primaryEnd).round()} · '
          'X ${(prepared.revealDuration.inMilliseconds * (s.crossEnd - s.primaryEnd)).round()} · '
          '글씨 ${(prepared.revealDuration.inMilliseconds * (1 - s.crossEnd)).round()}')
      ..writeln()
      ..writeln('세그먼트 상세 (재생 순서):');
    for (var i = 0; i < plan.segments.length; i++) {
      final g = plan.segments[i];
      final win = schedule.windows[i];
      report.writeln(
          '  ${g.id.toString().padLeft(2)} ${g.kind.name.padRight(15)} '
          'px=${g.pixelCount.toString().padLeft(6)} '
          'measure=${g.measure.toStringAsFixed(1).padLeft(7)} '
          'rel=${g.relativeLength?.toStringAsFixed(3) ?? '   —'} '
          'win=[${win.start.toStringAsFixed(3)}, ${win.end.toStringAsFixed(3)}]');
    }
    File('$_outDir/report.txt').writeAsStringSync(report.toString());
    // ignore: avoid_print
    print(report);

    prepared.dispose();
    base.dispose();
    composed.dispose();
  });
}
