// 붉은 잉크의 테두리가 **길로 새지 않는지** 잠근다.
//
//   ⚠️ 이게 무너지면 화면에 붉은 점이 뜬다. 빨간 글씨의 안티에일리어싱 테두리는 바닥과
//   충분히 다르면서(diff > 18) 아직 붉지는 않아(R−G ≤ 35) **길로 분류**된다. 뼈대에서 끊긴
//   섬이라 굽기가 길 단계의 **맨 끝** 시각을 주고, 글씨 차례가 오기도 전에 글씨 윤곽을 따라
//   점이 켜진다. 정본 map_basic_01(420)에서 길 덩어리 104개 중 101개(122px)가 그 잡티였고,
//   시뮬레이터 화면에서 진행도 0.45 에 붉은 점 84개로 보였다.
//
//   ⚠️ **반대 방향도 같이 잠근다.** 길은 X 와 실제로 맞닿는다. 규칙을 픽셀 단위로 만들면
//   그 자리에서 길 끝이 깎여 나가므로 덩어리 단위로 판정하고, 크기 상한이 진짜 길을 지킨다.
//
//   합성 입력이라 자산 없이 공개 CI 에서 늘 돈다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

const _w = 60;
const _h = 60;

/// 바닥은 균일한 갈색 — 정본과 같은 값(R−G = 19 라 붉은 관문을 못 넘는다).
Uint8List _base() {
  final a = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    a[i * 4] = 139;
    a[i * 4 + 1] = 120;
    a[i * 4 + 2] = 104;
    a[i * 4 + 3] = 255;
  }
  return a;
}

void _put(Uint8List rgba, int x, int y, int r, int g, int b) {
  final j = (y * _w + x) * 4;
  rgba[j] = r;
  rgba[j + 1] = g;
  rgba[j + 2] = b;
  rgba[j + 3] = 255;
}

/// 세그먼트 [id] 의 연결 덩어리 크기들.
List<int> _blobs(RevealPlan plan, int id) {
  final seen = Uint8List(_w * _h);
  final out = <int>[];
  for (var s = 0; s < _w * _h; s++) {
    if (plan.segmentId[s] != id || seen[s] == 1) continue;
    var n = 0;
    final st = <int>[s];
    seen[s] = 1;
    while (st.isNotEmpty) {
      final p = st.removeLast();
      n++;
      final x = p % _w;
      final y = p ~/ _w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= _w || ny >= _h) continue;
          final j = ny * _w + nx;
          if (plan.segmentId[j] == id && seen[j] == 0) {
            seen[j] = 1;
            st.add(j);
          }
        }
      }
    }
    out.add(n);
  }
  out.sort();
  return out;
}

RevealPlan _plan(Uint8List composed, {int strayMax = 12}) => detectReveal(
      RevealDetectInput(
        baseRgba: _base(),
        composedRgba: composed,
        width: _w,
        height: _h,
        config: RevealDetectConfig(strayInkMaxPixels: strayMax),
      ),
    );

void main() {
  group('붉은 잉크 테두리', () {
    // 세로 길 + 그 아래에 붉은 글씨 한 획, 글씨 둘레는 갈색과 붉은색의 중간(테두리).
    //   테두리 값 (170,140,120): 바닥과의 diff = 31+20+16 = 67 > 18 이라 "변한 곳"이고,
    //   R−G = 30 ≤ 35 라 붉지 않다 — 정확히 길로 새는 조건이다.
    Uint8List withFringe({required bool fringe}) {
      final c = _base();
      for (var y = 4; y < 30; y++) {
        _put(c, 30, y, 250, 248, 245);
      }
      for (var y = 40; y < 50; y++) {
        for (var x = 20; x < 34; x++) {
          _put(c, x, y, 232, 92, 88);
        }
      }
      if (!fringe) return c;
      // 실제 안티에일리어싱 테두리는 **이어진 고리가 아니라 흩어진 점**이다 — 리샘플러가
      //   잉크 가장자리를 물 때마다 픽셀 하나씩 어중간한 색이 남는다. 한 칸 걸러 찍어
      //   서로 안 붙게 만든다(붙으면 덩어리가 커져 크기 상한에 걸리지 않는다).
      for (var x = 19; x <= 34; x += 2) {
        _put(c, x, 39, 170, 140, 120);
        _put(c, x, 50, 170, 140, 120);
      }
      for (var y = 41; y <= 49; y += 2) {
        _put(c, 19, y, 170, 140, 120);
        _put(c, 34, y, 170, 140, 120);
      }
      return c;
    }

    test('테두리가 있어도 길 덩어리가 늘지 않는다', () {
      final clean = _blobs(_plan(withFringe(fringe: false)), 0);
      final fringed = _blobs(_plan(withFringe(fringe: true)), 0);
      expect(fringed.length, clean.length, reason: '테두리가 길로 샜다 — $fringed');
      expect(fringed.where((n) => n <= 12), isEmpty, reason: '길에 잡티가 남았다');
    });

    test('규칙을 끄면 실제로 샌다 — 이 테스트가 무엇을 지키는지', () {
      final off = _blobs(_plan(withFringe(fringe: true), strayMax: 0), 0);
      expect(
        off.where((n) => n <= 12).length,
        greaterThan(0),
        reason: '반례가 반례가 아니다 — 합성 테두리가 길로 안 새면 이 테스트는 아무것도 안 지킨다',
      );
    });

    test('테두리를 흡수해도 길 본체는 그대로다', () {
      final clean = _blobs(_plan(withFringe(fringe: false)), 0);
      final fringed = _blobs(_plan(withFringe(fringe: true)), 0);
      expect(fringed.last, clean.last, reason: '길 본체가 깎였다');
    });

    test('길이 붉은 것과 맞닿아도 길은 안 깎인다', () {
      // 길이 붉은 덩어리를 뚫고 지나간다 — 실제 지도에서 길이 X 를 만나는 모양이다.
      final c = _base();
      for (var y = 4; y < 56; y++) {
        _put(c, 30, y, 250, 248, 245);
      }
      for (var y = 24; y < 34; y++) {
        for (var x = 24; x < 38; x++) {
          if (x == 30) continue; // 길은 그대로 두고 그 둘레만 붉게.
          _put(c, x, y, 232, 92, 88);
        }
      }
      final road = _blobs(_plan(c), 0);
      expect(road, isNotEmpty);
      expect(
        road.reduce((a, b) => a + b),
        greaterThan(40),
        reason: '붉은 것과 맞닿았다고 길이 먹혔다 — 덩어리 단위 판정이 깨졌나',
      );
    });

    test('붉은 것이 하나도 없으면 아무것도 안 바꾼다', () {
      final c = _base();
      for (var y = 4; y < 40; y++) {
        _put(c, 30, y, 250, 248, 245);
      }
      final withRule = _blobs(_plan(c), 0);
      final without = _blobs(_plan(c, strayMax: 0), 0);
      expect(withRule, without);
    });
  });
}
