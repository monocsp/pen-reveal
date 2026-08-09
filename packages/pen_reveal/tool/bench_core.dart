// tool/bench_core.dart — **순수 Dart 코어만** 재는 벤치.
//
//   Flutter 를 안 쓰므로 `dart run`(JIT) 과 `dart compile exe`(AOT) 로 각각 돌릴 수 있다.
//   프로덕션은 AOT 라, `flutter test` 로 잰 DEBUG 숫자를 그대로 믿으면 안 된다.
//
//   실행:
//     dart run tool/bench_core.dart <rgba-dir>              # JIT
//     dart compile exe tool/bench_core.dart -o /tmp/bc      # AOT
//     /tmp/bc <rgba-dir>
//
//   입력은 `example/tool/dump_rgba.dart` 가 뱉은 `<key>_<longSide>.bin`:
//     [uint32 be width][uint32 be height][base RGBA][composed RGBA]
import 'dart:io';
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';

const _warmup = 3;
const _runs = 9;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _timeSync(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'rgba' : args.first);
  if (!dir.existsSync()) {
    stderr.writeln('RGBA 덤프 디렉터리가 없다: ${dir.path}');
    exit(2);
  }
  final mode = _isJit() ? 'JIT (dart run)' : 'AOT (compile exe)';
  stdout
    ..writeln('# 순수 코어 벤치 — $mode')
    ..writeln()
    ..writeln('워밍업 $_warmup · 측정 $_runs 회 · 중앙값 ms')
    ..writeln();

  for (final longSide in <int>[210, 420, 840]) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_$longSide.bin'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) continue;

    final detect = <double>[];
    final bake = <double>[];
    final compileT = <double>[];
    var px = 0;

    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final head = ByteData.sublistView(bytes, 0, 8);
      final w = head.getUint32(0);
      final h = head.getUint32(4);
      final n = w * h * 4;
      final base = Uint8List.sublistView(bytes, 8, 8 + n);
      final composed = Uint8List.sublistView(bytes, 8 + n, 8 + 2 * n);
      px = w * h;

      final input = RevealDetectInput(
        baseRgba: base,
        composedRgba: composed,
        width: w,
        height: h,
      );

      // 전체 탐지
      final ds = <double>[];
      for (var r = 0; r < _warmup + _runs; r++) {
        final t = _timeSync(() => detectReveal(input));
        if (r >= _warmup) ds.add(t);
      }
      detect.add(_median(ds));

      // 그중 bake 만 — diff 를 손으로 돌려 길 마스크를 만든다.
      const cfg = RevealDetectConfig();
      final road = Uint8List(w * h);
      for (var i = 0; i < w * h; i++) {
        final j = i * 4;
        final d = (composed[j] - base[j]).abs() +
            (composed[j + 1] - base[j + 1]).abs() +
            (composed[j + 2] - base[j + 2]).abs();
        if (d <= cfg.differenceThreshold ||
            composed[j + 3] < cfg.composedAlphaThreshold) {
          continue;
        }
        if (composed[j] - composed[j + 1] > cfg.accentRedDeltaThreshold) {
          continue;
        }
        road[i] = 255;
      }
      final bs = <double>[];
      for (var r = 0; r < _warmup + _runs; r++) {
        final t = _timeSync(() => bakeOneStrokeOrder(StrokeMask(road, w, h)));
        if (r >= _warmup) bs.add(t);
      }
      bake.add(_median(bs));

      // 순수 diff 만 — 픽셀 루프의 바닥값.
      final cs = <double>[];
      for (var r = 0; r < _warmup + _runs; r++) {
        final t = _timeSync(() {
          var acc = 0;
          for (var i = 0; i < w * h; i++) {
            final j = i * 4;
            final d = (composed[j] - base[j]).abs() +
                (composed[j + 1] - base[j + 1]).abs() +
                (composed[j + 2] - base[j + 2]).abs();
            if (d > 18) acc++;
          }
          if (acc < 0) stdout.write('');
        });
        if (r >= _warmup) cs.add(t);
      }
      compileT.add(_median(cs));
    }

    stdout
      ..writeln('## longSide $longSide  ($px px · ${files.length}종)')
      ..writeln()
      ..writeln('| 단계 | 중앙값 ms |')
      ..writeln('|---|---:|')
      ..writeln('| detectReveal 전체 | ${_median(detect).toStringAsFixed(2)} |')
      ..writeln('| ├ bake | ${_median(bake).toStringAsFixed(2)} |')
      ..writeln('| └ diff 루프만 | ${_median(compileT).toStringAsFixed(2)} |')
      ..writeln();
  }
}

/// ⚠️ `assert` 로는 못 가른다 — `dart run` 은 기본으로 assert 를 끈다.
///   AOT(`dart compile exe`)는 product 모드로 빌드되므로 이 상수가 참이다.
bool _isJit() => !const bool.fromEnvironment('dart.vm.product');
