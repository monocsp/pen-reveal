// 전파된 시간장의 **두 지표를 함께** 잠근다.
//
//   ⚠️ 하나만 보면 반드시 놓친다. 실제로 그랬다 — `_spread` 를 홉 수 BFS 에서 다익스트라로
//   바꿨더니 **고립 구멍은 −92%** 인데 **선단 계단은 커졌다**(선단 폭을 넘는 이웃 점프
//   44 → 65). 소유권 경계가 정확해진 만큼 경계가 길고 뚜렷해져서, 작은 구멍 대신 넓은 판이
//   한꺼번에 열린 것이다. 사용자가 "더 심해졌다"고 본 자리가 여기다.
//
//   그래서 둘을 같이 본다:
//     · **고립 구멍** — 주변이 다 드러났는데 혼자 안 드러난 픽셀. 화면에 점으로 보인다.
//     · **선단 점프** — 이웃 간 순서값 차가 선단 폭(255/k)을 넘는 자리. 계단으로 보인다.
//
//   ⚠️ **선단 점프의 정답은 0 이 아니다.** 되돌아오는 획은 두 팔이 공간적으로 이웃하면서
//   시각은 획 길이만큼 떨어져 있다 — 그 이음매의 단차는 결함이 아니라 물리적으로 옳다.
//   그래서 0 을 요구하지 않고 **실측한 값을 상한으로 못 박는다**(굽기는 결정적이라 값이
//   흔들리지 않는다). 좋아지는 것은 통과하고, 나빠지는 것만 걸린다. 상한을 올려야 한다면
//   연출이 바뀐 것이니 왜 바뀌었는지를 커밋에 적는다.
//
//   합성 입력이라 자산 없이 공개 CI 에서 늘 돈다.
@Tags(['regression'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

const _w = 120;
const _h = 120;

/// 굵은 획을 그린다 — 폭이 있어야 전파가 일어나고, 그래야 이 지표가 의미를 갖는다.
Uint8List _stroke(List<(double, double)> path, double radius) {
  final a = Uint8List(_w * _h);
  for (var s = 0; s < path.length - 1; s++) {
    final (x0, y0) = path[s];
    final (x1, y1) = path[s + 1];
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs()).ceil() * 2;
    for (var t = 0; t <= steps; t++) {
      final cx = x0 + (x1 - x0) * t / steps;
      final cy = y0 + (y1 - y0) * t / steps;
      final r = radius.ceil();
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue;
          final x = (cx + dx).round();
          final y = (cy + dy).round();
          if (x < 0 || y < 0 || x >= _w || y >= _h) continue;
          a[y * _w + x] = 255;
        }
      }
    }
  }
  return a;
}

/// 선단 폭을 넘는 이웃 점프 (개수, 최댓값) — 계단으로 보이는 자리.
(int, int) _edgeJumps(Uint8List order, Uint8List mask, double leadingEdge) {
  var n = 0;
  var worst = 0;
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final i = y * _w + x;
      if (mask[i] == 0 || order[i] >= 254) continue;
      for (final (dx, dy) in const [(1, 0), (0, 1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx >= _w || ny >= _h) continue;
        final j = ny * _w + nx;
        if (mask[j] == 0 || order[j] >= 254) continue;
        final d = (order[j] - order[i]).abs();
        if (d > leadingEdge) n++;
        if (d > worst) worst = d;
      }
    }
  }
  return (n, worst);
}

/// 진행도 [p] 에서의 고립 구멍 수 — 점으로 보이는 자리.
int _holes(Uint8List order, Uint8List mask, double p) {
  const sharp = RevealSharpness.standard;
  bool open(int i) => sharp.alphaAt(order: order[i], progress: p) > 200;
  var n = 0;
  for (var y = 1; y < _h - 1; y++) {
    for (var x = 1; x < _w - 1; x++) {
      final i = y * _w + x;
      if (mask[i] == 0 || open(i)) continue;
      var road = 0;
      var lit = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final j = (y + dy) * _w + (x + dx);
          if (mask[j] == 0) continue;
          road++;
          if (open(j)) lit++;
        }
      }
      if (road >= 6 && lit >= 6) n++;
    }
  }
  return n;
}

void main() {
  const leadingEdge = 255 / 24; // = 10.625 코드

  // (그림, 선단 초과 점프 상한, 최대 점프 상한) — 전부 실측값이다.
  final shapes = <String, (Uint8List, int, int)>{
    // 되돌아오는 머리핀 — 시각이 먼 두 갈래가 공간적으로 이웃한다. 이음매가 생기는 자리다.
    //   여기의 큰 점프는 정상이고, 평활이 그 단차를 3px 에 걸쳐 풀어 38 까지 낮춘 상태다.
    '머리핀': (
      _stroke(
        const [(30, 15), (30, 75), (34, 90), (48, 90), (52, 75), (52, 15)],
        6,
      ),
      81,
      38,
    ),
    // 뱀꼴 — 굽이마다 소유권 경계가 돈다.
    '뱀꼴': (
      _stroke(const [(20, 20), (95, 30), (25, 55), (95, 75), (25, 100)], 7),
      97,
      37,
    ),
    // 굵은 직선 — 이음매가 없다. 여기는 진짜로 0 이어야 하고, 보로노이 판이 돌아오면 깨진다.
    '굵은 직선': (_stroke(const [(20, 60), (100, 60)], 11), 0, 4),
  };

  group('전파된 시간장', () {
    shapes.forEach((name, spec) {
      final (mask, jumpBudget, worstBudget) = spec;
      final bin = Uint8List(_w * _h);
      for (var i = 0; i < mask.length; i++) {
        if (mask[i] > 128) bin[i] = 1;
      }
      final baked = bakeOneStrokeOrder(StrokeMask(mask, _w, _h));

      test('$name — 선단 계단이 실측 상한을 안 넘는다', () {
        final (count, worst) = _edgeJumps(baked.bytes, bin, leadingEdge);
        expect(
          count,
          lessThanOrEqualTo(jumpBudget),
          reason: '전파 뒤 평활이 빠졌거나 약하다 — 선단이 판 단위로 열린다',
        );
        expect(
          worst,
          lessThanOrEqualTo(worstBudget),
          reason:
              '한 자리에서 선단 폭의 ${(worst / leadingEdge).toStringAsFixed(1)}배가 한꺼번에 열린다',
        );
      });

      test('$name — 어느 진행도에도 고립 구멍이 없다 (점)', () {
        for (var p = 0.05; p <= 0.95; p += 0.05) {
          expect(
            _holes(baked.bytes, bin, p),
            0,
            reason: 'p=${p.toStringAsFixed(2)} 에서 구멍 — 전파가 홉 수로 돌아갔나',
          );
        }
      });

      test('$name — 진행도 1 에서 마스크가 하나도 안 남는다', () {
        for (var i = 0; i < bin.length; i++) {
          if (bin[i] == 0) continue;
          expect(baked.bytes[i], lessThan(255), reason: '잉크가 영영 안 드러난다');
        }
      });
    });

    test('평활이 길이를 흔들지 않는다 — 길이는 순회 시계에서 온다', () {
      // 같은 그림을 두 번 구워도 길이가 같아야 하고(결정적), 0 보다 커야 한다.
      final snake = shapes['뱀꼴']!.$1;
      final a = bakeOneStrokeOrder(StrokeMask(snake, _w, _h));
      final b = bakeOneStrokeOrder(StrokeMask(snake, _w, _h));
      expect(a.length, b.length);
      expect(a.length, greaterThan(0));
    });
  });
}
