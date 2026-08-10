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
///   ⚠️ **커널은 캔버스가 아니라 잉크 상자(ROI)에서만 돈다.** 길은 캔버스의 1.5~6.9%
///   밖에 안 되는데 형태 정리·세선화는 `w*h` 를 통째로 여러 번 훑는다. 잉크 bbox 에
///   [_roiPad] 만큼 여백을 두고 잘라 돌리면 결과가 **바이트 단위로 같으면서** 두 배 빠르다
///   (실측 420: 16.3 → 8.4 ms). 여백은 닫힘 2회가 바깥으로 밀 수 있는 최대치보다 넉넉하다.
OneStrokeResult bakeOneStrokeOrder(StrokeMask input) {
  final fullW = input.width;
  final fullH = input.height;

  // 이진화하면서 잉크 상자를 같이 잡는다 — 어차피 한 번 훑는다.
  var minX = fullW;
  var minY = fullH;
  var maxX = -1;
  var maxY = -1;
  var maskCount = 0;
  for (var y = 0; y < fullH; y++) {
    for (var x = 0; x < fullW; x++) {
      if (input.alpha[y * fullW + x] <= 128) continue;
      maskCount++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maskCount == 0) return _blank(fullW, fullH);

  final left = minX - _roiPad < 0 ? 0 : minX - _roiPad;
  final top = minY - _roiPad < 0 ? 0 : minY - _roiPad;
  final right = maxX + _roiPad >= fullW ? fullW - 1 : maxX + _roiPad;
  final bottom = maxY + _roiPad >= fullH ? fullH - 1 : maxY + _roiPad;
  final w = right - left + 1;
  final h = bottom - top + 1;

  final mask = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final src = (top + y) * fullW + left;
    final dst = y * w;
    for (var x = 0; x < w; x++) {
      if (input.alpha[src + x] > 128) mask[dst + x] = 1;
    }
  }

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

  final out = Uint8List(fullW * fullH)..fillRange(0, fullW * fullH, 255);
  if (order == null || order.isEmpty) {
    // 형태정리에 뼈대가 통째로 지워졌다(아주 가는 그림). 순서를 못 매길 뿐이지
    //   안 그릴 이유는 없다 — 한 번에 드러낸다.
    _blit(out, fullW, left, top, _atOnce(mask), w, h);
    return OneStrokeResult(out, 0);
  }

  // ⚠️ **길이는 평활 전에, 그것도 순회 시계에서 잰다.** 평활은 시간장의 이음매를 퍼뜨리므로
  //   최댓값이 조금 내려간다 — 그걸 길이로 쓰면 재생 시간이 같이 흔들린다. 길이는
  //   "펜이 지나간 거리" 라 뼈대 순회가 낸 시계가 정본이다.
  var maxT = 0.0;
  for (final v in order.values) {
    if (v > maxT) maxT = v;
  }
  final field = _smoothField(_brushSweep(order, mask, w, h), mask, w, h);
  final roi = Uint8List(w * h);
  for (var i = 0; i < roi.length; i++) {
    if (mask[i] == 0) {
      roi[i] = 255;
      continue;
    }
    // 뼈대에서 못 닿은 섬 — 버리지 않고 맨 끝에 붙인다.
    roi[i] = field[i] < 0
        ? 254
        : (field[i] / (maxT <= 0 ? 1 : maxT) * 254).round().clamp(0, 254);
  }
  _blit(out, fullW, left, top, roi, w, h);
  return OneStrokeResult(out, maxT);
}

/// 잉크 상자 둘레 여백.
///
///   **실측 하한은 1 이다.** 594,368 케이스(4×4 전수 + 랜덤 + 퍼지 + 정본 30)에서
///   pad 1~8 은 캔버스 전체와 **바이트 동일**이고, **pad 0 은 13.3~13.7% 가 깨진다.**
///
///   왜 1 인가: `_dilate` 는 패스당 1px 밖으로 밀지만, 뒤따르는 `_erode` 는 3×3 이 전부 1 인
///   픽셀만 남기므로 살아남는 것은 원래 bbox 안이다. 단계별 실측도 같다 —
///   `dilate1`·`dilate2` 만 정확히 1px 나갔다가 침식에 되돌아오고, 열림·세선화는 0px.
///   즉 **ROI ⊇ bbox+1 이면 캔버스 전체와 항등**이다. 4 는 3px 여유다.
///
///   ⚠️ **정본 코퍼스만으로는 이걸 못 잡는다.** 정본 10종의 bbox 는 캔버스 경계에 하나도
///   안 닿아(가장 가까운 것도 210 에서 좌 23px) pad 0 에서도 30/30 통과한다. 그래서
///   `roi_pad_test.dart` 가 **경계에 닿는 최소 반례**를 따로 잠근다. 여백을 줄이려면
///   그 시험부터 볼 것.
const int _roiPad = 4;

/// ROI 결과를 원래 크기 배열에 되붙인다.
void _blit(
  Uint8List dst,
  int dstWidth,
  int left,
  int top,
  Uint8List src,
  int w,
  int h,
) {
  for (var y = 0; y < h; y++) {
    dst.setRange(
      (top + y) * dstWidth + left,
      (top + y) * dstWidth + left + w,
      src,
      y * w,
    );
  }
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
  var cursor = 0.0;
  for (final start in _traversalStarts(adj)) {
    if (t.containsKey(start)) continue;
    t[start] = cursor;
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
        cursor += diag ? 1.4142 : 1.0;
        t[nxt] = cursor;
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

/// 붓이 지나간 자리를 칠한다 — **먼저 지나간 붓이 이긴다.**
///
///   [_spread] 는 픽셀마다 *가장 가까운* 뼈대의 시각을 가져온다. 획이 자기 위를 지나가는
///   자리에서는 그게 틀린다. 고리를 그리다 앞서 그은 데를 다시 밟으면 그 겹친 자리의 잉크는
///   **첫 붓이 이미 칠한 것**인데, 최근접 규칙은 그 자리를 두 팔이 반씩 나눠 갖게 하고
///   경계를 1px 톱니로 남긴다. 재생 중에는 한쪽 팔만 드러나 있으므로 그 톱니가 그대로
///   **하얀 길에 물어뜯긴 자국**으로 보인다 — 사장님이 map_deep_04 에서 본 것이 이것이다.
///
///   실측(굽기 420, 길 세그먼트, 선단 폭 10.6 코드를 넘는 이웃 점프):
///     · basic 3종 0~6개 · deep 6종 28~477개. 길 픽셀은 4배인데 점프는 30~80배다.
///     · map_deep_04 의 192개가 전부 `x=109..217, y=164..185` — 고리가 자기 자신과
///       접하는 가로 띠 하나에 몰려 있다. 곧은 구간에는 하나도 없다.
///
///   그래서 최근접이 아니라 **붓 자국의 합집합**으로 칠한다. 뼈대 픽셀 `s` 는 자기 붓 반경
///   `R(s)`(= 그 자리에서 길 가장자리까지의 거리) 만큼을 칠하고, 시각이 이른 붓부터
///   칠하되 **이미 칠해진 자리는 덮지 않는다.** 결과는
///
///       F(x) = min { t(s) : dist(x, s) ≤ R(s) }
///
///   이고, 이것이 실제 펜의 물리다. 겹친 자리는 나뉘지 않고 먼저 지나간 시각을 갖는다 —
///   X 의 겹치는 자리를 `\` 와 `/` 에 다 준 것과 같은 규칙이다.
///
///   ⚠️ **반경을 상수로 두면 안 된다.** 두 팔이 붙어 굵어진 자리는 가장자리까지의 거리가
///   저절로 커져서 붓이 그만큼 넓게 칠한다 — 겹침을 덮으려면 정확히 그만큼이 필요하다.
///   상수로 두면 좁은 데선 새고 넓은 데선 모자란다.
///
///   ⚠️ 붓이 못 닿은 픽셀(뼈대 끝의 바깥쪽 등)은 [_spread] 의 최근접 값으로 메운다.
///   버리면 영영 안 드러나는 픽셀이 생긴다.
Float32List _brushSweep(Map<int, double> t, Uint8List mask, int w, int h) {
  final out = Float32List(w * h)..fillRange(0, w * h, -1);
  if (t.isEmpty) return out;

  final radius = _boundaryDistance(mask, w, h);
  final seeds = t.keys.toList()
    ..sort((a, b) {
      final c = t[a]!.compareTo(t[b]!);
      // 시각이 같으면 인덱스로 — 결정적이어야 골든이 흔들리지 않는다.
      return c != 0 ? c : a.compareTo(b);
    });

  // 씨앗마다 새로 칠하는 범위 표시. `-1` 로 채우고 씨앗 번호를 적으면 매번 지울 필요가 없다.
  final touched = Int32List(w * h)..fillRange(0, w * h, -1);
  final stack = <int>[];

  for (var si = 0; si < seeds.length; si++) {
    final s = seeds[si];
    final at = t[s]!;
    // 뼈대는 길 안이라 반경이 0 일 수 없지만, 1px 두께 그림에서는 0.x 가 나온다.
    //   최소 1 을 줘서 씨앗 자신은 반드시 칠하게 한다.
    final r = radius[s] < 1 ? 1.0 : radius[s];
    final rr = r * r;
    final sx = s % w;
    final sy = s ~/ w;
    stack
      ..clear()
      ..add(s);
    touched[s] = si;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (out[p] < 0) out[p] = at;
      final px = p % w;
      final py = p ~/ w;
      for (var k = 0; k < 8; k++) {
        final nx = px + _dx[k];
        final ny = py + _dy[k];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (mask[j] != 1 || touched[j] == si) continue;
        final ddx = nx - sx;
        final ddy = ny - sy;
        if (ddx * ddx + ddy * ddy > rr) continue;
        touched[j] = si;
        stack.add(j);
      }
    }
  }

  // 붓이 못 닿은 자리만 최근접으로 메운다.
  var missing = false;
  for (var i = 0; i < out.length; i++) {
    if (mask[i] == 1 && out[i] < 0) {
      missing = true;
      break;
    }
  }
  if (missing) {
    final near = _spread(t, mask, w, h);
    for (var i = 0; i < out.length; i++) {
      if (mask[i] == 1 && out[i] < 0) out[i] = near[i];
    }
  }
  return out;
}

/// 마스크 안 각 픽셀에서 **바깥까지의 거리** — 8-이웃 경로 계량(직교 1, 대각 √2).
///
///   두 패스 챔퍼로 이 계량에서는 **정확히** 나온다. (유클리드를 근사하려 들면 오차가 남지만
///   여기서 필요한 것은 전파에 쓰는 것과 같은 8-이웃 계량이라 근사가 아니다.)
///
///   캔버스 밖은 바깥으로 친다 — 잉크가 화면 끝에 붙으면 붓 반경이 거기서 줄어드는 게 맞다.
Float32List _boundaryDistance(Uint8List mask, int w, int h) {
  const diag = 1.4142135623730951;
  const far = 1e9;
  final d = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    d[i] = mask[i] == 1 ? far : 0.0;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      var best = d[i];
      // 왼위·위·오른위·왼 — 이미 지나온 이웃 넷.
      if (y > 0) {
        if (x > 0 && d[i - w - 1] + diag < best) best = d[i - w - 1] + diag;
        if (d[i - w] + 1 < best) best = d[i - w] + 1;
        if (x + 1 < w && d[i - w + 1] + diag < best) best = d[i - w + 1] + diag;
      } else {
        best = 1; // 캔버스 위쪽 밖이 바깥이다.
      }
      if (x > 0) {
        if (d[i - 1] + 1 < best) best = d[i - 1] + 1;
      } else if (best > 1) {
        best = 1;
      }
      d[i] = best;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (mask[i] != 1) continue;
      var best = d[i];
      if (y + 1 < h) {
        if (x + 1 < w && d[i + w + 1] + diag < best) best = d[i + w + 1] + diag;
        if (d[i + w] + 1 < best) best = d[i + w] + 1;
        if (x > 0 && d[i + w - 1] + diag < best) best = d[i + w - 1] + diag;
      } else if (best > 1) {
        best = 1;
      }
      if (x + 1 < w) {
        if (d[i + 1] + 1 < best) best = d[i + 1] + 1;
      } else if (best > 1) {
        best = 1;
      }
      d[i] = best;
    }
  }
  return d;
}

/// 전파된 시간장의 **이음매를 퍼뜨린다** — 마스크 안에서만 3×3 평균을 [_smoothPasses] 회.
///
///   왜 아직 필요한가: [_brushSweep] 이 겹침 이음매는 없앴지만, 붓 자국의 합집합은 여전히
///   씨앗 단위 계단을 남긴다 — 붓 반경 R 만큼 앞선 시각이 통째로 들어오므로 경계가 서다.
///   평균 필터는 선형 경사에서 항등에 가까워 정상 구간은 안 건드리고 불연속만 퍼뜨린다.
///
///   ⚠️ 뼈대에 못 닿은 픽셀(`-1`)은 이웃으로도 안 쓰고 값도 안 바꾼다 — 맨 끝(254) 계약 유지.
///
///   ⚠️ **잉크 픽셀만 훑는다.** ROI 안이라도 잉크는 그중 일부다(정본에서 캔버스 14만 px 중
///   길은 1만 px). 매 패스 캔버스 전체를 돌면 열 배 넘게 헛돈다 — 자리 목록을 한 번 만들어
///   재사용하고, 버퍼 두 벌을 번갈아 쓴다.
Float32List _smoothField(Float32List field, Uint8List mask, int w, int h) {
  if (_smoothPasses <= 0) return field;

  var count = 0;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 1 && field[i] >= 0) count++;
  }
  if (count == 0) return field;
  final at = Int32List(count);
  var n = 0;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 1 && field[i] >= 0) at[n++] = i;
  }

  var src = field;
  var dst = Float32List.fromList(src);
  for (var pass = 0; pass < _smoothPasses; pass++) {
    for (var s = 0; s < count; s++) {
      final i = at[s];
      final y = i ~/ w;
      final x = i - y * w;
      var sum = src[i];
      var used = 1;
      for (var k = 0; k < 8; k++) {
        final ny = y + _dy[k];
        final nx = x + _dx[k];
        if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
        final j = ny * w + nx;
        if (mask[j] != 1 || src[j] < 0) continue;
        sum += src[j];
        used++;
      }
      dst[i] = sum / used;
    }
    // 두 벌을 번갈아 쓴다 — 패스마다 새로 할당하면 그것만으로도 비싸다.
    final swap = src;
    src = dst;
    dst = swap;
  }
  return src;
}

/// 평활 횟수.
///
///   ⚠️ **여기 "3 회면 점프가 0" 이라고 적혀 있었는데 거짓이었다.** 합성 도형에서만 참이고
///   정본 deep 계열에서는 3 회로 한참 모자랐다(codex 지적). 합성만 보고 상수를 정한 대가다.
///
///   정본 10종 실측(굽기 420, 길 세그먼트, 열 지도 합계):
///
///       패스   선단 계단   만 최대 합   구멍 합
///         0       287         37         43
///         1       259         39         27
///         2       161         40         25
///         3       106         39         20
///         4        88         29         18
///         5        62         24         18      ← 여기
///         6        43         26         18
///
///   6 회가 계단은 더 줄이지만 **만이 다시 늘어난다**(24 → 26) — 진짜 시각 불연속까지 뭉개기
///   시작한다는 신호다. 계단만 보고 올리면 안 되는 이유가 이것이고, 그래서 두 지표를 같이 본다.
const int _smoothPasses = 5;

/// 뼈대의 시각을 길 픽셀 전체로 — **가장 가까운** 뼈대의 값을 받는다.
///
///   ⚠️ 예전엔 8-이웃 FIFO BFS 로 "먼저 닿은 이웃의 값"을 복사했다. 그건 대각 이동도 1홉으로
///   세는 **체비쇼프 거리**라, 소유권 경계가 축·45° 계단으로 갈리며 이미 드러난 길 안쪽에
///   규칙적인 **대각 빗살**이 남았다(실측: 이웃 간 순서값 차이 최대 60, 선단 폭 10.6 코드를
///   넘는 픽셀 44개 / 길 2,505 px). 뼈대 순회는 대각을 1.4142 로 세는데 전파만 1.0 으로
///   세던 불일치이기도 했다 — 한 파이프라인 안에 거리 정의가 둘이었다.
///
///   **손으로 짠 이진 힙 다익스트라**를 쓴다. 의존성이 0 이라 `package:collection` 의
///   우선순위 큐를 못 가져오기 때문이다.
///
///   ⚠️ **체임퍼 2-패스로 하지 마라.** 힙을 피하려고 그렇게 짰다가 되돌렸다 —
///   `dist` 가 `Float32List` 인데 `dist[j] + cost` 는 float64 로 계산돼 되쓸 때마다
///   1 ULP 씩 깎인다. 그래서 `changed` 가 **영원히 참**이다(실측: 300 패스에서도 참).
///   패스 상한은 보험이 아니라 항상 걸리는 조기 중단이 되고, 못 닿은 픽셀이 254(맨 끝)로
///   떨어져 **고치려던 증상을 새로 만든다.** 게다가 마스크가 캔버스의 2% 인데 매 패스
///   `w*h` 를 통째로 훑어 힙보다 두 배 느리다.
///
///   힙 키를 `dist` 와 **같은 float32 정밀도**로 두는 것이 중요하다 — 다르면 pop 순서와
///   비교가 어긋나 같은 문제가 되돌아온다.
Float32List _spread(Map<int, double> t, Uint8List mask, int w, int h) {
  const diag = 1.4142135623730951;
  final out = Float32List(w * h)..fillRange(0, w * h, -1);
  final dist = Float32List(w * h)..fillRange(0, w * h, double.infinity);

  // 이진 최소 힙 — (거리, 인덱스) 쌍을 평면 배열 둘에 담는다.
  var cap = 1024;
  var heapDist = Float32List(cap);
  var heapAt = Int32List(cap);
  var size = 0;

  void push(double d, int i) {
    if (size == cap) {
      cap *= 2;
      heapDist = Float32List(cap)..setRange(0, size, heapDist);
      heapAt = Int32List(cap)..setRange(0, size, heapAt);
    }
    var c = size++;
    heapDist[c] = d;
    heapAt[c] = i;
    while (c > 0) {
      final p = (c - 1) >> 1;
      if (heapDist[p] <= heapDist[c]) break;
      final td = heapDist[p];
      final ti = heapAt[p];
      heapDist[p] = heapDist[c];
      heapAt[p] = heapAt[c];
      heapDist[c] = td;
      heapAt[c] = ti;
      c = p;
    }
  }

  int pop() {
    final top = heapAt[0];
    size--;
    heapDist[0] = heapDist[size];
    heapAt[0] = heapAt[size];
    var p = 0;
    while (true) {
      final l = p * 2 + 1;
      if (l >= size) break;
      final r = l + 1;
      final m = (r < size && heapDist[r] < heapDist[l]) ? r : l;
      if (heapDist[p] <= heapDist[m]) break;
      final td = heapDist[p];
      final ti = heapAt[p];
      heapDist[p] = heapDist[m];
      heapAt[p] = heapAt[m];
      heapDist[m] = td;
      heapAt[m] = ti;
      p = m;
    }
    return top;
  }

  t.forEach((i, v) {
    out[i] = v;
    dist[i] = 0;
    push(0, i);
  });

  while (size > 0) {
    final head = heapDist[0];
    final i = pop();
    // 낡은 항목 — 더 짧은 길로 이미 확정됐다.
    if (head > dist[i]) continue;
    final y = i ~/ w;
    final x = i % w;
    for (var k = 0; k < 8; k++) {
      final ny = y + _dy[k];
      final nx = x + _dx[k];
      if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
      final j = ny * w + nx;
      if (mask[j] != 1) continue;
      final step = (_dy[k] != 0 && _dx[k] != 0) ? diag : 1.0;
      final cand = dist[i] + step;
      if (cand < dist[j]) {
        dist[j] = cand;
        out[j] = out[i];
        push(dist[j], j);
      }
    }
  }
  return out;
}
