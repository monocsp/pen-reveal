// tool/bench.dart — 굽기 경로의 **단계별 실측**.
//
//   "느리다/빠르다"를 감으로 말하지 않으려고 만든다. 정본 10종을 여러 해상도로 굽고
//   단계마다 시간을 잰다. 각 단계를 어디로 옮길 수 있는지(순수 Dart / isolate / FFI)
//   판단하려면 **어디에 시간이 쏠려 있는지**부터 알아야 한다.
//
//   실행:  cd example && flutter test tool/bench.dart
@Tags(['corpus'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _outDir = 'tool/out';
const _warmup = 2;
const _runs = 7;

/// 중앙값 — 평균은 첫 실행의 JIT 비용에 끌려간다.
double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _max(List<double> xs) => xs.reduce((a, b) => a > b ? a : b);

Future<double> _time(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

double _timeSync(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '굽기 경로 단계별 실측',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }
      Directory(_outDir).createSync(recursive: true);
      final out = StringBuffer();

      void say(String s) {
        out.writeln(s);
        // ignore: avoid_print
        print(s);
      }

      say('# 굽기 경로 실측 — Flutter ${_flutterHint()}');
      say('');
      say('지도 ${keys.length}종 · 워밍업 $_warmup · 측정 $_runs회 · 값은 **중앙값 ms**');
      say('');

      for (final longSide in <int>[210, 420, 840]) {
        final phase = <String, List<double>>{
          '디코드 ×2': [],
          'rgbaAt ×2': [],
          'detect(동기)': [],
          'detect(compute)': [],
          '  ├ bake(세선화·DFS·전파)': [],
          '  ├ X 분할': [],
          '  └ 글씨 분할': [],
          'schedule': [],
          'compile': [],
          'RGBA→ui.Image': [],
          'prepare 전체': [],
        };
        final pxCount = <int>[];

        for (final key in keys) {
          // ── 디코드 ─────────────────────────────────────────────
          late ({ui.Image base, ui.Image composed}) pair;
          final decodeMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            if (r > 0) {
              pair.base.dispose();
              pair.composed.dispose();
            }
            final t = await _time(() async => pair = await loadCorpusMap(key));
            if (r >= _warmup) decodeMs.add(t);
          }
          phase['디코드 ×2']!.add(_median(decodeMs));

          final size = fitImageLongSide(pair.composed, longSide);
          final w = size.width;
          final h = size.height;
          pxCount.add(w * h);

          // ── rgbaAt ────────────────────────────────────────────
          late Uint8List baseRgba;
          late Uint8List composedRgba;
          final rgbaMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = await _time(() async {
              composedRgba = await rgbaAt(pair.composed, w, h);
              baseRgba = await rgbaAt(pair.base, w, h);
            });
            if (r >= _warmup) rgbaMs.add(t);
          }
          phase['rgbaAt ×2']!.add(_median(rgbaMs));

          final input = RevealDetectInput(
            baseRgba: baseRgba,
            composedRgba: composedRgba,
            width: w,
            height: h,
          );

          // ── detect: 같은 isolate 에서 직접 (순수 CPU) ────────────
          late RevealPlan plan;
          final syncMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = _timeSync(() => plan = detectReveal(input));
            if (r >= _warmup) syncMs.add(t);
          }
          phase['detect(동기)']!.add(_median(syncMs));

          // ── detect: compute 로 (isolate 왕복 + 직렬화 포함) ──────
          final computeMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = await _time(() async => compute(detectReveal, input));
            if (r >= _warmup) computeMs.add(t);
          }
          phase['detect(compute)']!.add(_median(computeMs));

          // ── detect 안쪽 쪼개기 ─────────────────────────────────
          final road = Uint8List(w * h);
          final accent = <int>[];
          const cfg = RevealDetectConfig();
          for (var i = 0; i < w * h; i++) {
            final j = i * 4;
            final d = (composedRgba[j] - baseRgba[j]).abs() +
                (composedRgba[j + 1] - baseRgba[j + 1]).abs() +
                (composedRgba[j + 2] - baseRgba[j + 2]).abs();
            if (d <= cfg.differenceThreshold ||
                composedRgba[j + 3] < cfg.composedAlphaThreshold) {
              continue;
            }
            if (composedRgba[j] - composedRgba[j + 1] >
                cfg.accentRedDeltaThreshold) {
              accent.add(i);
            } else {
              road[i] = 255;
            }
          }
          final bakeMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t =
                _timeSync(() => bakeOneStrokeOrder(StrokeMask(road, w, h)));
            if (r >= _warmup) bakeMs.add(t);
          }
          phase['  ├ bake(세선화·DFS·전파)']!.add(_median(bakeMs));

          // X·글씨는 계획에서 실제로 잡힌 것을 다시 돌린다.
          final xPixels = <int>[];
          final notePixels = <int>[];
          for (var i = 0; i < w * h; i++) {
            final id = plan.segmentId[i];
            if (id == kRevealHiddenSegment) continue;
            switch (plan.segments[id].kind) {
              case RevealSegmentKind.crossBackslash:
              case RevealSegmentKind.crossSlash:
                xPixels.add(i);
              case RevealSegmentKind.annotation:
                notePixels.add(i);
              case RevealSegmentKind.primaryStroke:
                break;
            }
          }
          if (xPixels.isNotEmpty) {
            final xs = Int32List.fromList(xPixels);
            final ms = <double>[];
            for (var r = 0; r < _warmup + _runs; r++) {
              final t =
                  _timeSync(() => splitCrossStrokes(pixels: xs, width: w));
              if (r >= _warmup) ms.add(t);
            }
            phase['  ├ X 분할']!.add(_median(ms));
          }
          if (notePixels.isNotEmpty) {
            final ns = Int32List.fromList(notePixels);
            final ms = <double>[];
            for (var r = 0; r < _warmup + _runs; r++) {
              final t = _timeSync(
                () => segmentAnnotation(pixels: ns, width: w, height: h),
              );
              if (r >= _warmup) ms.add(t);
            }
            phase['  └ 글씨 분할']!.add(_median(ms));
          }

          // ── schedule · compile · 텍스처 ────────────────────────
          const timing = HandwritingRevealTiming();
          const compiler = RevealTextureCompiler();
          late RevealSchedule schedule;
          final schedMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = _timeSync(() => schedule = timing.schedule(plan));
            if (r >= _warmup) schedMs.add(t);
          }
          phase['schedule']!.add(_median(schedMs));

          late Uint8List order;
          final compileMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = _timeSync(() => order = compiler.compile(plan, schedule));
            if (r >= _warmup) compileMs.add(t);
          }
          phase['compile']!.add(_median(compileMs));

          final texMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = await _time(() async {
              final img = await textureFromRgba(
                revealOrderToRgba(order),
                plan.width,
                plan.height,
              );
              img.dispose();
            });
            if (r >= _warmup) texMs.add(t);
          }
          phase['RGBA→ui.Image']!.add(_median(texMs));

          // ── prepare 전체 ───────────────────────────────────────
          final preparer = RevealPreparer(longSide: longSide);
          final wholeMs = <double>[];
          for (var r = 0; r < _warmup + _runs; r++) {
            final t = await _time(() async {
              final p = await preparer.prepare(
                base: pair.base,
                composed: pair.composed,
              );
              p.dispose();
            });
            if (r >= _warmup) wholeMs.add(t);
          }
          phase['prepare 전체']!.add(_median(wholeMs));

          pair.base.dispose();
          pair.composed.dispose();
        }

        final avgPx = pxCount.reduce((a, b) => a + b) ~/ pxCount.length;
        say('## longSide = $longSide  (평균 $avgPx px)');
        say('');
        say('| 단계 | 중앙값 ms | 최악 ms | 전체 대비 |');
        say('|---|---:|---:|---:|');
        final whole = _median(phase['prepare 전체']!);
        for (final e in phase.entries) {
          if (e.value.isEmpty) continue;
          final m = _median(e.value);
          final mx = _max(e.value);
          final pct = e.key == 'prepare 전체'
              ? '—'
              : '${(m / whole * 100).toStringAsFixed(1)}%';
          say('| ${e.key} | ${m.toStringAsFixed(2)} | ${mx.toStringAsFixed(2)} | $pct |');
        }
        say('');
      }

      File('$_outDir/bench.md').writeAsStringSync(out.toString());
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

String _flutterHint() =>
    '3.41.1 · ${_isDebug() ? 'DEBUG(JIT)' : 'RELEASE(AOT)'}';

bool _isDebug() {
  var debug = false;
  assert(
    () {
      debug = true;
      return true;
    }(),
    'assert 로 디버그 모드를 가른다',
  );
  return debug;
}
