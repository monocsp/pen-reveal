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
  final field = _smoothField(_spread(order, mask, w, h), mask, w, h);
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

/// 전파된 시간장의 **이음매를 퍼뜨린다** — 마스크 안에서만 3×3 평균을 [_smoothPasses] 회.
///
///   왜 필요한가: [_spread] 는 가장 가까운 뼈대의 시각을 **그대로 복사**한다. 거리는 소유권을
///   정하는 데만 쓰고 값에는 안 쓴다. 그래서 시간장이 매끄러운 경사가 아니라 **뼈대 픽셀마다
///   한 칸씩인 보로노이 판**이 된다 — 길 폭이 10px 이면 `10×1` 짜리 같은 값 덩어리다.
///   그 판들이 선단을 지날 때 한꺼번에 열려 **블록 계단**으로 보인다(사용자 보고).
///
///   ⚠️ 홉 수 BFS 를 다익스트라로 바꿔 고립 구멍은 −92% 가 됐지만, 소유권 경계가 더 정확해진
///   만큼 **경계가 길고 뚜렷해져** 선단 계단은 오히려 커졌다(실측: 선단 폭을 넘는 이웃 점프가
///   44 → 65). 거리 정확도가 시간 연속성을 보장하지 않는다 — 그래서 두 단계가 다 필요하다.
///
///   평균 필터는 선형 경사에서는 항등에 가까워 정상 구간을 안 건드리고, 불연속만 퍼뜨린다.
///   뼈대에 못 닿은 픽셀(`-1`)은 이웃으로도 안 쓰고 값도 안 바꾼다 — 맨 끝(254) 계약 유지.
Float32List _smoothField(Float32List field, Uint8List mask, int w, int h) {
  var src = field;
  for (var pass = 0; pass < _smoothPasses; pass++) {
    final dst = Float32List.fromList(src);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] != 1 || src[i] < 0) continue;
        var sum = src[i];
        var n = 1;
        for (var k = 0; k < 8; k++) {
          final ny = y + _dy[k];
          final nx = x + _dx[k];
          if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
          final j = ny * w + nx;
          if (mask[j] != 1 || src[j] < 0) continue;
          sum += src[j];
          n++;
        }
        dst[i] = sum / n;
      }
    }
    src = dst;
  }
  return src;
}

/// 평활 횟수. 3 회면 선단 폭(255/k ≈ 10.6 코드)을 넘는 이웃 점프가 0 이 된다(실측).
///   더 돌리면 진짜 시각 불연속(획이 갈라졌다 만나는 자리)까지 뭉갠다.
const int _smoothPasses = 3;

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
