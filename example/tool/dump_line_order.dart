// **실선만 놓고 그리는 순서를 본다.**
//
//   굽기의 나머지(폭으로 퍼뜨리기·평활·8비트 양자화)를 전부 빼고 얇은 선 하나만 남긴다.
//   순서가 이상해 보이는 것이 규칙 탓인지 그 뒤 단계 탓인지를 가르려면 여기부터 봐야 한다.
//
//   그림 `tool/out/line_<key>.png`:
//     · 선 색     = 그려지는 순서(짙은 남색 → 밝은 노랑). 눈으로 따라가면 붓의 경로다.
//     · 빨간 동그라미 = **붓끝이 튄 자리.** 새로 잉크가 켜지는 두 자리가 8-이웃이 아닌 곳.
//     · 초록 = 시작점 · 파랑 = 끝점
//
//   숫자:
//     · **되짚기** — 걸은 걸음 수 ÷ 선 픽셀 수. 1.00 이면 한 붓에 겹침 없이 끝났다는 뜻이다.
//     · **끊김** — 붓끝이 튄 횟수와 그 거리. 되짚기가 있으면 반드시 생긴다(되짚는 동안엔
//       새 잉크가 없으니 그 구간이 통째로 빈다).
//     · **총 꺾임** — 걸음마다의 방향 변화 합. 작을수록 곧게 간다(R1 이 겨냥하는 값).
//
//   돌리는 법: cd example && flutter test tool/dump_line_order.dart
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

const _side = 420;
const _zoom = 2;

/// 붓끝이 튄 것으로 볼 거리 — 8-이웃이면 최대 √2 다.
const _teleport = 1.5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '실선만 놓고 그리는 순서를 본다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }
      Directory('tool/out').createSync(recursive: true);

      stdout.writeln(
        '지도              선 px   걸음   되짚기   끊김  최장끊김   총 꺾임/걸음',
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

        DebugSkeleton? road;
        debugSkeletonSink = (s) {
          if (road == null || s.pixels.length > road!.pixels.length) road = s;
        };
        detectReveal(
          RevealDetectInput(
            baseRgba: base,
            composedRgba: composed,
            width: w,
            height: h,
          ),
        );
        debugSkeletonSink = null;

        final skel = road;
        if (skel == null || skel.route.isEmpty) {
          stdout.writeln('$key — 순서가 안 나왔다');
          continue;
        }

        final m = _measure(skel);
        await _paint(key, w, h, skel, m);

        stdout.writeln(
          '${key.padRight(16)}'
          '${skel.pixels.length.toString().padLeft(6)}'
          '${skel.route.length.toString().padLeft(7)}'
          '${(skel.route.length / skel.pixels.length).toStringAsFixed(2).padLeft(8)}배'
          '${m.breaks.length.toString().padLeft(6)}'
          '${m.longestBreak.toStringAsFixed(0).padLeft(9)}px'
          '${(m.turning / skel.route.length).toStringAsFixed(3).padLeft(12)}',
        );
      }
      stdout.writeln('\n그림: example/tool/out/line_*.png');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// 선 위의 순서 품질.
class _Order {
  const _Order({
    required this.firstAt,
    required this.breaks,
    required this.longestBreak,
    required this.turning,
  });

  /// 자리 → **처음 밟힌 걸음 번호**. 이게 화면에 켜지는 순서다.
  final Map<int, int> firstAt;

  /// 붓끝이 튄 자리들 — (튀기 직전 자리, 튄 뒤 자리, 거리).
  final List<(int, int, double)> breaks;
  final double longestBreak;

  /// 걸음마다의 방향 변화(라디안) 합.
  final double turning;
}

_Order _measure(DebugSkeleton s) {
  final w = s.width;
  final firstAt = <int, int>{};
  for (var i = 0; i < s.route.length; i++) {
    firstAt.putIfAbsent(s.route[i], () => i);
  }

  // 새로 켜지는 순서대로 늘어놓고, 이웃하지 않은 자리로 건너뛴 곳을 찾는다.
  final fresh = <int>[];
  final seen = <int>{};
  for (final v in s.route) {
    if (seen.add(v)) fresh.add(v);
  }
  final breaks = <(int, int, double)>[];
  var longest = 0.0;
  for (var i = 1; i < fresh.length; i++) {
    final a = fresh[i - 1];
    final b = fresh[i];
    final dx = (b % w - a % w).toDouble();
    final dy = (b ~/ w - a ~/ w).toDouble();
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > _teleport) {
      breaks.add((a, b, d));
      if (d > longest) longest = d;
    }
  }

  // 걸은 경로의 총 꺾임.
  var turning = 0.0;
  for (var i = 2; i < s.route.length; i++) {
    final a = s.route[i - 2];
    final b = s.route[i - 1];
    final c = s.route[i];
    final ax = (b % w - a % w).toDouble();
    final ay = (b ~/ w - a ~/ w).toDouble();
    final bx = (c % w - b % w).toDouble();
    final by = (c ~/ w - b ~/ w).toDouble();
    final la = math.sqrt(ax * ax + ay * ay);
    final lb = math.sqrt(bx * bx + by * by);
    if (la <= 0 || lb <= 0) continue;
    final cos = ((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0);
    turning += math.acos(cos);
  }

  return _Order(
    firstAt: firstAt,
    breaks: breaks,
    longestBreak: longest,
    turning: turning,
  );
}

/// 순서를 색으로 칠한 그림 한 장.
Future<void> _paint(
  String key,
  int w,
  int h,
  DebugSkeleton s,
  _Order m,
) async {
  final zw = w * _zoom;
  final zh = h * _zoom;
  final px = Uint8List(zw * zh * 4);
  for (var i = 0; i < zw * zh; i++) {
    px[i * 4] = 250;
    px[i * 4 + 1] = 250;
    px[i * 4 + 2] = 252;
    px[i * 4 + 3] = 255;
  }
  void put(int x, int y, int r, int g, int b, {int size = _zoom}) {
    for (var dy = 0; dy < size; dy++) {
      for (var dx = 0; dx < size; dx++) {
        final zx = x * _zoom + dx - (size - _zoom) ~/ 2;
        final zy = y * _zoom + dy - (size - _zoom) ~/ 2;
        if (zx < 0 || zy < 0 || zx >= zw || zy >= zh) continue;
        final j = (zy * zw + zx) * 4;
        px[j] = r;
        px[j + 1] = g;
        px[j + 2] = b;
      }
    }
  }

  // 순서 → 색. 짙은 남색(처음) → 밝은 노랑(끝).
  final steps = s.route.length <= 1 ? 1 : s.route.length - 1;
  (int, int, int) ramp(double t) {
    final u = t.clamp(0.0, 1.0);
    return (
      (30 + 225 * u).round(),
      (25 + 200 * math.pow(u, 0.7).toDouble()).round(),
      (110 - 90 * u).round(),
    );
  }

  m.firstAt.forEach((p, at) {
    final x = p % s.width + s.left;
    final y = p ~/ s.width + s.top;
    final (r, g, b) = ramp(at / steps);
    put(x, y, r, g, b);
  });

  // 붓끝이 튄 자리 — 양쪽에 빨간 점.
  for (final (a, b, _) in m.breaks) {
    for (final p in [a, b]) {
      put(p % s.width + s.left, p ~/ s.width + s.top, 220, 20, 40, size: 6);
    }
  }
  // 시작·끝.
  if (s.route.isNotEmpty) {
    final f = s.route.first;
    final l = s.route.last;
    put(f % s.width + s.left, f ~/ s.width + s.top, 20, 170, 70, size: 8);
    put(l % s.width + s.left, l ~/ s.width + s.top, 30, 90, 230, size: 8);
  }

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, zw, zh, ui.PixelFormat.rgba8888, done.complete);
  final img = await done.future;
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  File('tool/out/line_$key.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}
