// src/plan/one_stroke_bake.dart — 길 마스크에서 **reveal(그리는 순서) 맵을 앱이 직접 만든다**.
//
// 왜: 그리는 순서를 **미리 만들어 두지 않아도** 되게 하려는 것이다. 입력은 알파 마스크
//   하나뿐이고, 출력은 0~254 순서값 텍스처다(값이 작을수록 먼저 드러난다).
//
//   ⚠️ **이 파일이 순서 알고리즘의 정본이다.** 예전에 같은 알고리즘의 python 사본이
//   있었는데 갈라졌다(단일 뼈대 덩어리만 순회 / 형태정리된 마스크에 전파). 그래서 이
//   레포는 python 사본을 두지 않는다 — `tool/` 의 python 은 캘리브레이션 굽기와 GIF·MP4
//   내보내기만 하고, 순서는 이 구현이 낸 것을 받아 쓴다. 쌍둥이를 다시 만들지 말 것.
//
// 비용: 세선화가 이미지를 여러 번 훑는 반복 연산이라 싸지 않다. 그래서
//   ① 그림당 **한 번만** 계산하고 캐시하는 것을 전제로 하고,
//   ② 별도 isolate 로 돌려 UI 스레드를 안 막는 것을 전제로 한다
//      (`pen_reveal_flutter` 의 `RevealPreparer` 가 `compute` 로 감싼다).
//
// 순수 Dart 다 — `package:flutter` 를 안 쓴다(isolate 로 넘길 수 있어야 한다).
import 'dart:math' as math;
import 'dart:typed_data';

/// 세선화를 돌릴 해상도(긴 변). 낮으면 짧은 갈래가 뭉개진다.
const int kBakeLongSide = 420;

/// 길 폭의 이 배수보다 짧은 가지 = 세선화 잡음.
const double kSpurWidths = 1.5;

/// 굽기 결과 — reveal 바이트맵과 **길 길이**.
///
///   길이는 연출 시간을 정하는 데 쓴다. 긴 길을 짧은 길과 같은 시간에 그으면 펜이 너무
///   빨라 보인다(실측: 지도 10종의 길이가 469~1745 로 **3.7배** 벌어진다).
class OneStrokeResult {
  const OneStrokeResult(this.bytes, this.length);
  final Uint8List bytes;

  /// 한 붓 경로의 누적 길이(입력 픽셀 단위). 되짚는 구간은 안 센다.
  final double length;
}

/// 길 알파 채널(0~255)에서 reveal 맵을 만든다. 입력 크기는 [StrokeMask] 가 들고 있다.
///
/// 반환은 같은 크기의 0~255 바이트맵 — 길 안은 0~254(그리는 순서), 길 밖은 255.
///
///   ⚠️ **마스크 픽셀은 하나도 255 로 남지 않는다.** 진행도 1 에서 최종본과 100% 같아져야
///   하기 때문이다(2026-08-07 회귀). 그래서 두 군데를 원본 마스크 기준으로 본다:
///     · [_spread] 를 형태정리본이 아니라 **원본 마스크**로 퍼뜨린다(열림 연산에 깎인
///       가장자리·가는 조각이 영영 안 드러나던 것을 되찾는다)
///     · 그래도 뼈대와 안 이어진 섬은 **맨 끝(254)** 에 함께 드러낸다
OneStrokeResult bakeOneStrokeOrder(StrokeMask input) {
  final w = input.width;
  final h = input.height;
  final mask = Uint8List(w * h);
  var maskCount = 0;
  for (var i = 0; i < mask.length; i++) {
    if (input.alpha[i] > 128) {
      mask[i] = 1;
      maskCount++;
    }
  }
  if (maskCount == 0) return _blank(w, h);

  // 가장자리 톱니를 죽인다 — 안 하면 세선화가 잔가시를 만든다.
  var m = mask;
  for (var i = 0; i < 2; i++) {
    m = _erode(_dilate(m, w, h), w, h);
  }
  for (var i = 0; i < 2; i++) {
    m = _dilate(_erode(m, w, h), w, h);
  }

  final skel = _zhangSuen(Uint8List.fromList(m), w, h);
  final order = _oneStrokeOrder(skel, m, w, h);
  if (order == null || order.isEmpty) {
    // 형태정리에 뼈대가 통째로 지워졌다(아주 가는 그림). 순서를 못 매길 뿐이지
    //   안 그릴 이유는 없다 — 한 번에 드러낸다.
    return OneStrokeResult(_atOnce(mask), 0);
  }

  final field = _spread(order, mask, w, h);
  var maxT = 0.0;
  for (final v in field) {
    if (v > maxT) maxT = v;
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    if (mask[i] == 0) {
      out[i] = 255;
      continue;
    }
    // 뼈대에서 못 닿은 섬 — 버리지 않고 맨 끝에 붙인다.
    out[i] = field[i] < 0
        ? 254
        : (field[i] / (maxT <= 0 ? 1 : maxT) * 254).round().clamp(0, 254);
  }
  return OneStrokeResult(out, maxT);
}

OneStrokeResult _blank(int w, int h) =>
    OneStrokeResult(Uint8List(w * h)..fillRange(0, w * h, 255), 0);

/// 마스크 안은 0(한 번에), 밖은 255.
Uint8List _atOnce(Uint8List mask) {
  final out = Uint8List(mask.length);
  for (var i = 0; i < mask.length; i++) {
    out[i] = mask[i] == 1 ? 0 : 255;
  }
  return out;
}

/// 길 알파 마스크 — isolate 경계를 넘길 수 있는 최소 형태.
class StrokeMask {
  const StrokeMask(this.alpha, this.width, this.height);
  final Uint8List alpha;
  final int width;
  final int height;
}

const List<int> _dy = [-1, -1, -1, 0, 1, 1, 1, 0];
const List<int> _dx = [-1, 0, 1, 1, 1, 0, -1, -1];

Uint8List _dilate(Uint8List m, int w, int h) {
  final o = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (m[y * w + x] == 1) {
        o[y * w + x] = 1;
        continue;
      }
      for (var k = 0; k < 8; k++) {
        final ny = y + _dy[k];
        final nx = x + _dx[k];
        if (ny >= 0 && ny < h && nx >= 0 && nx < w && m[ny * w + nx] == 1) {
          o[y * w + x] = 1;
          break;
        }
      }
    }
  }
  return o;
}

Uint8List _erode(Uint8List m, int w, int h) {
  final o = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (m[y * w + x] == 0) continue;
      var all = true;
      for (var k = 0; k < 8; k++) {
        final ny = y + _dy[k];
        final nx = x + _dx[k];
        if (ny < 0 || ny >= h || nx < 0 || nx >= w || m[ny * w + nx] == 0) {
          all = false;
          break;
        }
      }
      o[y * w + x] = all ? 1 : 0;
    }
  }
  return o;
}

int _at(Uint8List m, int w, int h, int y, int x) =>
    (y < 0 || y >= h || x < 0 || x >= w) ? 0 : m[y * w + x];

/// P2..P9 를 한 바퀴 돌 때의 0→1 전이 수(crossing number).
int _crossing(Uint8List m, int w, int h, int y, int x) {
  const oy = [-1, -1, 0, 1, 1, 1, 0, -1, -1];
  const ox = [0, 1, 1, 1, 0, -1, -1, -1, 0];
  var a = 0;
  for (var i = 0; i < 8; i++) {
    if (_at(m, w, h, y + oy[i], x + ox[i]) == 0 &&
        _at(m, w, h, y + oy[i + 1], x + ox[i + 1]) == 1) {
      a++;
    }
  }
  return a;
}

int _nbrs(Uint8List m, int w, int h, int y, int x) {
  var c = 0;
  for (var k = 0; k < 8; k++) {
    c += _at(m, w, h, y + _dy[k], x + _dx[k]);
  }
  return c;
}

Uint8List _zhangSuen(Uint8List img, int w, int h) {
  final kill = <int>[];
  while (true) {
    var changed = false;
    for (var step = 0; step < 2; step++) {
      kill.clear();
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (img[y * w + x] == 0) continue;
          final b = _nbrs(img, w, h, y, x);
          if (b < 2 || b > 6) continue;
          if (_crossing(img, w, h, y, x) != 1) continue;
          final p2 = _at(img, w, h, y - 1, x);
          final p4 = _at(img, w, h, y, x + 1);
          final p6 = _at(img, w, h, y + 1, x);
          final p8 = _at(img, w, h, y, x - 1);
          final ok = step == 0
              ? (p2 * p4 * p6 == 0 && p4 * p6 * p8 == 0)
              : (p2 * p4 * p8 == 0 && p2 * p6 * p8 == 0);
          if (ok) kill.add(y * w + x);
        }
      }
      if (kill.isNotEmpty) {
        for (final i in kill) {
          img[i] = 0;
        }
        changed = true;
      }
    }
    if (!changed) return img;
  }
}

/// 뼈대를 훑어 픽셀별 '펜이 닿는 시각'을 매긴다.
///
///   시각은 **새로 그은 길이**의 누적 — 되짚는 구간은 시계를 안 돌린다.
///   시작점은 **언제나 뼈대 최상단**(사용자 지정: 획은 언제나 맨 위에서 시작).
///
///   ⚠️ **뼈대가 여러 덩어리면 전부 훑는다.** 예전엔 최상단이 든 덩어리 하나만 훑어
///   나머지 픽셀이 진행도 1 에서도 안 드러났다(실측: 길 픽셀의 3.5~22.4%). 순서는
///   ① 최상단이 든 덩어리 ② 나머지는 큰 것부터, 같으면 위에서부터 — 시계는 이어서 돈다
///   (펜을 뗐다 다시 붙이는 것이라 쉼은 없다).
Map<int, double>? _oneStrokeOrder(
  Uint8List skel,
  Uint8List mask,
  int w,
  int h,
) {
  final adj = <int, List<int>>{};
  var skelCount = 0;
  var area = 0;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 1) area++;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (skel[y * w + x] == 0) continue;
      skelCount++;
      final list = <int>[];
      for (var k = 0; k < 8; k++) {
        final ny = y + _dy[k];
        final nx = x + _dx[k];
        if (_at(skel, w, h, ny, nx) == 1) list.add(ny * w + nx);
      }
      adj[y * w + x] = list;
    }
  }
  if (adj.isEmpty) return null;

  final width = area / (skelCount == 0 ? 1 : skelCount);
  _pruneSpurs(adj, (width * kSpurWidths).round().clamp(6, 1 << 30));
  if (adj.isEmpty) return null;

  final t = <int, double>{};
  final used = <int>{};
  var clock = 0.0;
  for (final start in _traversalStarts(adj)) {
    if (t.containsKey(start)) continue;
    t[start] = clock;
    final stack = <int>[start];
    while (stack.isNotEmpty) {
      final v = stack.last;
      int? nxt;
      for (final cand in adj[v]!) {
        if (!used.contains(v * 1000003 + cand)) {
          nxt = cand;
          break;
        }
      }
      if (nxt == null) {
        stack.removeLast();
        continue;
      }
      used
        ..add(v * 1000003 + nxt)
        ..add(nxt * 1000003 + v);
      if (!t.containsKey(nxt)) {
        final diag = (v ~/ w != nxt ~/ w) && (v % w != nxt % w);
        clock += diag ? 1.4142 : 1.0;
        t[nxt] = clock;
      }
      stack.add(nxt);
    }
  }
  return t;
}

/// 뼈대 덩어리마다 시작점 하나 — **재생 순서대로**.
///
///   최상단 픽셀(= 인덱스 최솟값, 행 우선 저장이라 y 가 먼저 작아진다)이 든 덩어리가
///   맨 앞이고, 나머지는 큰 것부터다. 각 덩어리 안의 시작점도 그 덩어리의 최상단이다.
List<int> _traversalStarts(Map<int, List<int>> adj) {
  final seen = <int>{};
  // (크기, 최상단) — 최상단이 그대로 시작점이다.
  final components = <(int size, int top)>[];
  for (final key in adj.keys) {
    if (!seen.add(key)) continue;
    var top = key;
    var size = 0;
    final queue = <int>[key];
    for (var head = 0; head < queue.length; head++) {
      final v = queue[head];
      size++;
      if (v < top) top = v;
      for (final n in adj[v]!) {
        if (seen.add(n)) queue.add(n);
      }
    }
    components.add((size, top));
  }
  if (components.isEmpty) return const <int>[];

  final globalTop = components.map((c) => c.$2).reduce(math.min);
  components.sort((a, b) {
    // ① 최상단이 든 덩어리가 언제나 먼저 — "획은 언제나 맨 위에서 시작".
    if (a.$2 == globalTop) return -1;
    if (b.$2 == globalTop) return 1;
    // ② 그다음은 큰 것부터, 같으면 위에서부터.
    final bySize = b.$1.compareTo(a.$1);
    return bySize != 0 ? bySize : a.$2.compareTo(b.$2);
  });
  return [for (final c in components) c.$2];
}

void _pruneSpurs(Map<int, List<int>> adj, int minLen) {
  var changed = true;
  while (changed) {
    changed = false;
    final ends = [
      for (final e in adj.entries)
        if (e.value.length == 1) e.key,
    ];
    for (final e in ends) {
      if (!adj.containsKey(e)) continue;
      final path = <int>[e];
      var cur = e;
      int? prev;
      while (true) {
        final nxt = [
          for (final q in adj[cur] ?? const <int>[])
            if (q != prev) q,
        ];
        if (nxt.length != 1) break;
        prev = cur;
        cur = nxt.first;
        path.add(cur);
        if (path.length > minLen) break;
      }
      if (path.length <= minLen && (adj[cur]?.length ?? 0) >= 3) {
        for (final q in path.sublist(0, path.length - 1)) {
          for (final r in adj[q] ?? const <int>[]) {
            adj[r]?.remove(q);
          }
          adj.remove(q);
        }
        changed = true;
      }
    }
  }
}

/// 뼈대의 시각을 길 픽셀 전체로 — 가장 가까운 뼈대의 값을 받는다.
Float32List _spread(Map<int, double> t, Uint8List mask, int w, int h) {
  final out = Float32List(w * h)..fillRange(0, w * h, -1);
  final q = <int>[];
  t.forEach((i, v) {
    out[i] = v;
    q.add(i);
  });
  for (var head = 0; head < q.length; head++) {
    final i = q[head];
    final y = i ~/ w;
    final x = i % w;
    for (var k = 0; k < 8; k++) {
      final ny = y + _dy[k];
      final nx = x + _dx[k];
      if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
      final j = ny * w + nx;
      if (mask[j] == 1 && out[j] < 0) {
        out[j] = out[i];
        q.add(j);
      }
    }
  }
  return out;
}
