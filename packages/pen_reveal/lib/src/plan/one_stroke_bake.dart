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
  final order = _oneStrokeOrder(skel, m, w, h, left, top);

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
  // 획이 아닌 조각은 **처음부터 있던 것**으로 돌린다.
  _flattenNonStrokes(field, mask, w, h);
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

/// 굵기가 획이라 하기엔 너무 얇은 덩어리를 **시각 0 으로 눕힌다** — 처음부터 있던 것으로.
///
///   ⚠️ 무엇을 고치나: 정본의 바닥과 최종본은 따로 내보낸 PNG 라, 지도 위쪽 **찢어진 종이
///   가장자리**가 서로 미세하게 어긋난다. 그 어긋남이 "변한 곳" 으로 잡혀 길이 되고,
///   본체와 **끊긴** 덩어리라 세선화가 거기에도 뼈대를 만들어 **독립된 획**으로 순서를 받는다.
///   실측(굽기 420): 길 덩어리가 네 개인데 셋이 y 71~78 의 가장자리 조각이다 —
///   map_deep_05 는 203·20·1px, map_deep_04 는 129·19·1px. 순서값은 지도마다 제멋대로라
///   deep_05 는 140(길의 맨 끝), deep_04 는 0(맨 처음)에 켜졌다.
///
///   화면에서는 **펜이 저 아래 있는데 위쪽 띠 200px 이 한 프레임에 통째로 켜지는** 것으로
///   보인다. 사장님이 "선이 진행되는 곳이 아닌데 자라난다" 고 한 것이 이것이다.
///
///   ⚠️ **버리지 않는다.** 시각 0 이면 진행도 0 부터 불투명하므로 진행도 1 의 최종본은
///   그대로다(픽셀 하나도 안 버린다는 규약). 종이 가장자리는 그리는 것이 아니라 원래
///   거기 있던 것이니 의미로도 맞다.
///
///   ⚠️ **크기가 아니라 굵기로 가른다.** 크기로 자르면 짧지만 진짜인 획(반짝임·서명)을
///   같이 눕힌다. 가장자리 조각은 8px 두께인데 정본의 길은 20px 다 — 굵기는 두 배 넘게
///   갈린다. 굵기는 그 덩어리 안에서 가장자리까지 가장 먼 거리(= 붓 반경의 최댓값)로 잰다.
void _flattenNonStrokes(Float32List field, Uint8List mask, int w, int h) {
  final radius = _boundaryDistance(mask, w, h);
  final seen = Uint8List(w * h);
  final members = <int>[];
  // 먼저 가장 굵은 덩어리를 찾는다 — 기준은 그림마다 다르므로 상대값으로 잡는다.
  final peaks = <double>[];
  final groups = <List<int>>[];
  for (var start = 0; start < w * h; start++) {
    if (mask[start] == 0 || seen[start] == 1) continue;
    members.clear();
    var peak = 0.0;
    final stack = <int>[start];
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      members.add(p);
      if (radius[p] > peak) peak = radius[p];
      final x = p % w;
      final y = p ~/ w;
      for (var k = 0; k < 8; k++) {
        final nx = x + _dx[k];
        final ny = y + _dy[k];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (mask[j] == 1 && seen[j] == 0) {
          seen[j] = 1;
          stack.add(j);
        }
      }
    }
    peaks.add(peak);
    groups.add([...members]);
  }
  if (groups.length < 2) return;

  var thickest = 0.0;
  for (final p in peaks) {
    if (p > thickest) thickest = p;
  }
  if (thickest <= 0) return;

  for (var g = 0; g < groups.length; g++) {
    if (peaks[g] >= thickest * _strokeThicknessRatio) continue;
    for (final i in groups[g]) {
      field[i] = 0;
    }
  }
}

/// 획으로 치는 최소 굵기 — 가장 굵은 덩어리 대비 비율.
///
///   실측(정본 10종, 굽기 420): 길 본체의 최대 반경은 9~11 이고 찢어진 가장자리 조각은
///   2~4 다. 0.5 면 둘 사이가 넉넉히 갈린다. 값을 올리면 진짜로 가는 획을 눕히기 시작한다.
const double _strokeThicknessRatio = 0.5;

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
  int left,
  int top, {
  bool merge = true,
}) {
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
        if (_at(skel, w, h, ny, nx) != 1) continue;
        // ⚠️ **모서리를 가로지르는 대각선은 갈래가 아니다.** 두 직교 이웃이 살아 있으면
        //   그 사이 대각선은 삼각형을 닫는 **지름길**이다. 안 걷어내면 그래프가 오염되어
        //   어떤 순서 규칙도 성립하지 않는다(실측: 합성 뱀꼴 선단 계단 442).
        if (_dy[k] != 0 && _dx[k] != 0) {
          if (_at(skel, w, h, ny, x) == 1 || _at(skel, w, h, y, nx) == 1) {
            continue;
          }
        }
        list.add(ny * w + nx);
      }
      adj[y * w + x] = list;
    }
  }
  if (adj.isEmpty) return null;

  final width = area / (skelCount == 0 ? 1 : skelCount);
  _pruneSpurs(adj, (width * kSpurWidths).round().clamp(6, 1 << 30));
  if (adj.isEmpty) return null;

  // ⚠️ **쪼개진 교차점을 도로 한 점으로 붙인다.** 이걸 먼저 해야 짝이 맞는다.
  //   자세한 이유는 [_mergeSplitCrossings] 주석에 있다.
  final merged =
      merge ? _mergeSplitCrossings(adj, w, width) : <int, _MergedCrossing>{};

  final t = <int, double>{};
  // 변마다 "몇 번 더 지날 수 있나" 를 센다. 붙이고도 홀수가 남으면 [_pairOddVertices]
  //   가 그 사이를 두 번 지나게 채운다.
  final remaining = <int, int>{};
  for (final e in adj.entries) {
    for (final n in e.value) {
      remaining[e.key * 1000003 + n] = 1;
    }
  }
  // 진단 — 얇게 깎은 선과 인접 관계를 그대로 흘려보낸다.
  {
    debugSkeletonSink?.call(
      DebugSkeleton(
        width: w,
        height: h,
        left: left,
        top: top,
        pixels: <int>[...adj.keys],
        degrees: <int>[for (final e in adj.entries) e.value.length],
      ),
    );
  }
  if (debugRouteSink != null) {
    final js = <String>[
      for (final e in adj.entries)
        if (e.value.length >= 3)
          '(${e.key % w},${e.key ~/ w})×${e.value.length}',
    ];
    final ends = <String>[
      for (final e in adj.entries)
        if (e.value.length == 1) '(${e.key % w},${e.key ~/ w})',
    ];
    debugRouteSink!('갈림 ${js.join(" ")} · 끝점 ${ends.join(" ")}');
  }
  _pairOddVertices(adj, remaining, w);
  var cursor = 0.0;
  for (final start in _traversalStarts(adj)) {
    if (t.containsKey(start)) continue;
    // ⚠️ **시각은 "걷기" 를 따라 매긴다 — 탐색 중에 매기지 않는다.**
    //
    //   예전엔 DFS 가 내려가면서 첫 방문에 찍었다. 그러면 가지 하나를 끝까지 그리고
    //   갈림길로 되돌아온 순간 다음 가지가 시작되어, 화면에서 붓끝이 **순간이동**한다.
    //   걷기의 이웃한 두 점은 언제나 8-이웃이라 그럴 수가 없다.
    // ① 짝을 먼저 정해 두고 잇는다. 안 되면 ② 예전 방식.
    final traced =
        _transitionRoute(adj, start, Map<int, int>.from(remaining), w, width) ??
            _eulerRoute(adj, start, remaining, w);
    final route = _expandMerged(traced, merged);
    for (var i = 0; i < route.length; i++) {
      final v = route[i];
      if (i > 0) {
        final p = route[i - 1];
        final diag = (p ~/ w != v ~/ w) && (p % w != v % w);
        cursor += diag ? 1.4142 : 1.0;
      }
      // 되짚는 자리는 이미 그려졌다 — 시각을 다시 안 매긴다.
      t.putIfAbsent(v, () => cursor);
    }
  }
  return t;
}

/// 뼈대 덩어리마다 시작점 하나 — **재생 순서대로**.
///
///   최상단 픽셀(= 인덱스 최솟값, 행 우선 저장이라 y 가 먼저 작아진다)이 든 덩어리가
///   맨 앞이고, 나머지는 큰 것부터다. 각 덩어리 안의 시작점도 그 덩어리의 최상단이다.

/// 교차로에서 **직진을 우선**한다 — 90도 넘게 꺾지 않는다.
///
///   손으로 그릴 때 교차로에서 급히 되꺾지 않는다. 들어온 방향과의 코사인이 0 이상인
///   후보(= 90도 이내)만 보고, 그중 가장 덜 꺾는 것을 고른다. 그런 후보가 없으면
///   (막다른 길이라 되짚어야 하면) 어쩔 수 없이 전부에서 고른다.
///
///   ⚠️ **오일러 경로 위에서만 뜻이 있다.** 어느 변을 먼저 고르든 걷기는 모든 변을
///   덮으므로, 이 선택은 **순서만** 바꾸고 덮개를 깨지 않는다. 예전에 DFS 위에 각도를
///   얹었을 때는 그 보장이 없어 실제 지도에서 끝나는 자리가 망가졌다.
///
///   ⚠️ 첫 걸음은 들어온 방향이 없다 — 아래로 본다. 걷기는 위쪽 끝점에서 시작하므로
///   손이 아래로 내려가는 것이 자연스럽다.
int? _straightestNext(
  List<int> candidates,
  int v,
  int? prev,
  Map<int, int> remaining,
  int w,
) {
  final iny = prev == null ? 1.0 : (v ~/ w - prev ~/ w).toDouble();
  final inx = prev == null ? 0.0 : (v % w - prev % w).toDouble();
  final inLen = math.sqrt(iny * iny + inx * inx);

  int? best;
  var bestScore = -2.0;
  int? fallback;
  var fallbackScore = -2.0;
  for (final cand in candidates) {
    if ((remaining[v * 1000003 + cand] ?? 0) <= 0) continue;
    final dy = (cand ~/ w - v ~/ w).toDouble();
    final dx = (cand % w - v % w).toDouble();
    final outLen = math.sqrt(dy * dy + dx * dx);
    final score = inLen <= 0 || outLen <= 0
        ? 0.0
        : (iny * dy + inx * dx) / (inLen * outLen);
    if (score > fallbackScore) {
      fallbackScore = score;
      fallback = cand;
    }
    // 90도 이내만 "직진" 으로 친다.
    if (score >= 0 && score > bestScore) {
      bestScore = score;
      best = cand;
    }
  }
  return best ?? fallback;
}

/// 히어홀저 — [start] 에서 출발해 **모든 변을 한 번씩** 지나는 걷기.
///
///   돌아오는 것은 정점의 차례다. 이웃한 두 항목은 언제나 8-이웃이라, 이 차례대로
///   시각을 매기면 붓끝이 건너뛸 수 없다.
/// 교차로에서 **가장 덜 꺾는 팔**을 실제로 그려지는 순서에 적용한다.
///
///   ⚠️ **탐욕적으로 고르는 것으로는 안 된다.** 히어홀저는 막히면 되돌아가 다른 고리를
///   끼워 넣는데, 그러면 갈림길에서 실제로 이어지는 두 팔이 탐욕 선택과 달라진다.
///   그래서 **먼저 짝을 정해 두고**(transition system) 그 짝을 지키며 잇는다.
///
///   자리마다 팔을 둘씩 묶는다 — "이 팔로 들어오면 저 팔로 나간다". 묶는 기준은
///   **얼마나 마주보나**다. 원래 한 곡선이었다면 두 팔은 서로 반대를 향한다.
///
///       비용(짝짓기) = Σ (1 + 접선ᵢ · 접선ⱼ)      ← 마주볼수록(−1) 작다
///
///   실측 map_special_01 교차점 (168,146): 들어온 방향에서
///   하트 아래 26° · 꼬리 47° · 하트 위 80° 다. 짝짓기는 (길↔하트아래),(하트위↔꼬리)
///   가 되어 **위끝 → 하트 한 바퀴 → 꼬리 → X** 한 붓이 나온다.
///
///   모든 변을 다 쓰지 못하면(따로 노는 고리가 남으면) null 을 주고, 부르는 쪽이
///   예전 방식으로 되돌아간다.
List<int>? _transitionRoute(
  Map<int, List<int>> adj,
  int start,
  Map<int, int> remaining,
  int w,
  double width,
) {
  final reach = width.round().clamp(4, 24);
  // 자리마다 팔 목록(중복 포함) 과 짝.
  final slots = <int, List<int>>{};
  final mate = <int, List<int>>{};
  var edgeCount = 0;
  for (final e in adj.entries) {
    final v = e.key;
    final list = <int>[];
    for (final n in e.value) {
      final m = remaining[v * 1000003 + n] ?? 0;
      for (var i = 0; i < m; i++) {
        list.add(n);
      }
    }
    edgeCount += list.length;
    slots[v] = list;
    mate[v] = _pairArms(adj, v, list, reach, w);
  }
  edgeCount ~/= 2;

  final used = <int, List<bool>>{
    for (final e in slots.entries)
      e.key: List<bool>.filled(e.value.length, false),
  };

  /// v 에서 u 로 가는, 아직 안 쓴 팔의 자리 번호.
  int slotOf(int v, int u) {
    final list = slots[v]!;
    for (var i = 0; i < list.length; i++) {
      if (list[i] == u && !used[v]![i]) return i;
    }
    return -1;
  }

  final route = <int>[start];
  var cur = start;
  var exit = 0;
  if (slots[start]!.isEmpty) return null;
  var walked = 0;
  while (walked <= edgeCount) {
    if (exit < 0 || exit >= slots[cur]!.length || used[cur]![exit]) {
      // 짝이 막혔으면 아무 안 쓴 팔이나 — 끝점에서만 일어난다.
      exit = used[cur]!.indexOf(false);
      if (exit < 0) break;
    }
    final nxt = slots[cur]![exit];
    used[cur]![exit] = true;
    final back = slotOf(nxt, cur);
    if (back < 0) return null;
    used[nxt]![back] = true;
    route.add(nxt);
    walked++;
    exit = mate[nxt]![back];
    cur = nxt;
  }
  // 다 못 썼으면 따로 노는 고리가 남았다는 뜻이다 — 이 짝짓기는 포기한다.
  // 다 못 썼으면 따로 노는 고리가 남았다는 뜻이다 — 이 짝짓기는 포기한다.
  if (walked != edgeCount) return null;
  return route;
}

/// 한 자리의 팔들을 **가장 마주보는 것끼리** 둘씩 묶는다.
///
///   되돌려 준 값 `mate[i]` 는 i 번 팔로 들어왔을 때 나갈 팔의 번호다. 홀수 개면
///   하나가 짝 없이 남는데(획의 시작·끝) 자기 자신을 가리켜 둔다 — 부르는 쪽이
///   "막혔다" 로 보고 아무 팔이나 고른다.
List<int> _pairArms(
  Map<int, List<int>> adj,
  int v,
  List<int> arms,
  int reach,
  int w,
) {
  final n = arms.length;
  final mate = List<int>.generate(n, (i) => i);
  if (n < 2) return mate;
  final dirs = <(double, double)?>[
    for (final a in arms) _armDirection(adj, v, a, reach, w),
  ];
  // 가장 마주보는 짝부터 차례로 묶는다 — n 이 작아서 이걸로 충분하다.
  final taken = List<bool>.filled(n, false);
  for (var round = 0; round + 1 < n; round += 2) {
    var bestCost = double.infinity;
    var bi = -1;
    var bj = -1;
    for (var i = 0; i < n; i++) {
      if (taken[i]) continue;
      for (var j = i + 1; j < n; j++) {
        if (taken[j]) continue;
        final a = dirs[i];
        final b = dirs[j];
        final c = (a == null || b == null) ? 2.0 : 1.0 + _dot(a, b);
        if (c < bestCost) {
          bestCost = c;
          bi = i;
          bj = j;
        }
      }
    }
    if (bi < 0) break;
    taken[bi] = true;
    taken[bj] = true;
    mate[bi] = bj;
    mate[bj] = bi;
  }
  return mate;
}

List<int> _eulerRoute(
  Map<int, List<int>> adj,
  int start,
  Map<int, int> remaining,
  int w,
) {
  final stack = <int>[start];
  final out = <int>[];
  while (stack.isNotEmpty) {
    final v = stack.last;
    final prev = stack.length >= 2 ? stack[stack.length - 2] : null;
    final nxt =
        _straightestNext(adj[v] ?? const <int>[], v, prev, remaining, w);
    if (nxt == null) {
      out.add(stack.removeLast());
      continue;
    }
    remaining[v * 1000003 + nxt] = remaining[v * 1000003 + nxt]! - 1;
    remaining[nxt * 1000003 + v] = remaining[nxt * 1000003 + v]! - 1;
    stack.add(nxt);
  }
  return out.reversed.toList();
}

/// 붙였던 교차점을 경로에서 **도로 펼친다.**
///
///   순회는 붙인 그래프에서 돌았으므로 대표 자리 [_MergedCrossing.a] 만 나온다. 그런데
///   그 자리를 드나드는 팔 중 일부는 실제로는 반대쪽 끝 `b` 에 붙어 있었다. 그대로 두면
///   펜이 a 와 b 사이를 순간이동한다.
///
///   앞뒤 팔이 어느 쪽인지 보고 되돌린다:
///     · 둘 다 a 쪽  → a 에 있는다
///     · 둘 다 b 쪽  → b 에 있는다
///     · 서로 다르면 → **다리를 실제로 걸어간다** (그 픽셀들이 시각을 받는다)
///
///   ⚠️ **정직하게 적는다: 지금 정본 열 장과 합성 도형 어느 것도 이 함수를 실제로
///   쓰지 않는다.** 이 함수를 통째로 무력화하는 뮤테이션을 넣어도 모든 관문이 초록이다.
///   지금 붙는 자리(map_special_01)에서는 펜이 a 쪽으로 들어와 a 쪽으로 나가고, 나중에
///   b 쪽으로 들어와 b 쪽으로 나가서 **양쪽을 가로지르는 일이 없기 때문**이다.
///   그래서 이건 증명된 코드가 아니라 **막아 두는 코드**다 — 가로지르는 그림이 들어오면
///   그때 물린다. 그런 그림을 합성으로 만들 수 있으면 시험을 붙이고 이 문구를 지운다.
List<int> _expandMerged(List<int> route, Map<int, _MergedCrossing> merged) {
  if (merged.isEmpty) return route;
  final out = <int>[];
  for (var i = 0; i < route.length; i++) {
    final v = route[i];
    final m = merged[v];
    if (m == null) {
      out.add(v);
      continue;
    }
    final before = i > 0 ? route[i - 1] : -1;
    final after = i + 1 < route.length ? route[i + 1] : -1;
    final fromB = m.bSide.contains(before);
    final toB = m.bSide.contains(after);
    if (before < 0) {
      out.add(toB ? m.b : m.a);
    } else if (after < 0) {
      out.add(fromB ? m.b : m.a);
    } else if (fromB == toB) {
      out.add(fromB ? m.b : m.a);
    } else if (fromB) {
      out.addAll(m.bridge.reversed);
    } else {
      out.addAll(m.bridge);
    }
  }
  return out;
}

/// 세선화가 쪼개 놓은 교차점을 **도로 한 점으로 붙인다.**
///
///   ⚠️ **왜 필요한가.** 매끄러운 도형의 중심축에서 정상적인 갈림점은 **갈래 3 뿐**이다.
///   갈래 4 는 네 경계점의 거리가 동시에 딱 맞아야 하는 사건이라, 픽셀화 오차만 있어도
///   **갈래 3 둘 + 짧은 가지**로 풀린다. 세선화는 굵은 영역의 위상(구멍 개수)만 보존할 뿐
///   "두 획이 한 점에서 만났다" 는 것은 보존하지 않는다. 그러니 밖에서 되돌려 줘야 한다.
///   문헌에서 부르는 이름: **X-junction splitting** · spurious bifurcation ·
///   "non-generic fourfold junction 이 generic triple junction 둘로 풀림".
///
///   되돌리는 연산의 이름은 그래프 이론의 **변 수축(edge contraction)** 이다. 갈래 3 인
///   두 점을 잇는 변을 수축하면 갈래 4 인 점 하나가 된다.
///
///   실측 map_special_01: A(168,146) 과 B(155,165) 사이 24 변. 붙이면 팔이 넷이 된다 —
///   위에서 내려온 길 · 하트 위 · 하트 아래 · X 로 가는 꼬리. 홀수 자리가 넷에서 둘로
///   줄어 복제 없이 한 붓이 된다.
///
///   ⚠️ **아무 다리나 붙이지 않는다.** 진짜로 갈래 3 이 둘 있는 그림도 있다. 그래서
///   바깥 팔 넷의 **접선**을 재서, 거의 마주보는 짝이 둘로 갈리는지 본다(§[_looksLikeCrossing]).
///
///   ⚠️ 다리 속 픽셀은 순회에서 빠진다. 지금은 `_spread` 가 가장 가까운 시각으로 메운다 —
///   24px 짜리라 관문 안에 들어온다(선단 계단 예산 그대로 초록). 더 긴 다리를 붙이게 되면
///   여기서 시각을 명시적으로 나눠 줘야 한다.
/// 붙인 교차점 하나 — 대표 자리 [a], 반대쪽 끝 [b], 그 사이 다리, 그리고 **어느 팔이
/// b 쪽에 붙어 있었는지**.
///
///   ⚠️ b 쪽 팔을 그냥 a 로 옮기면 순회는 맞지만 **펜이 24px 순간이동**한다. b 쪽으로
///   드나들 때는 펜이 실제로는 b 에 있으므로, 경로를 되펼 때 그 자리를 돌려줘야 한다.
class _MergedCrossing {
  _MergedCrossing(this.a, this.b, this.bridge);

  final int a;
  final int b;

  /// a 에서 b 까지의 자리들(양끝 포함).
  final List<int> bridge;

  /// b 쪽에 붙어 있던 팔의 첫 자리들.
  final Set<int> bSide = <int>{};
}

Map<int, _MergedCrossing> _mergeSplitCrossings(
  Map<int, List<int>> adj,
  int w,
  double width,
) {
  final merged = <int, _MergedCrossing>{};
  // 굵기의 몇 배까지를 "굵기가 만든 흔적" 으로 볼 것인가. 얕은 각도로 만나면 겹치는
  //   길이가 굵기/sin(각) 로 커지므로 넉넉히 잡고, 진짜 판정은 접선에 맡긴다.
  final maxLen = (width * _mergeWidths).round();
  if (maxLen < 2) return merged;
  for (var pass = 0; pass < 8; pass++) {
    final found = _findJunctionBridge(adj, maxLen);
    if (found == null) return merged;
    final a = found.first;
    final b = found.last;
    if (!_looksLikeCrossing(adj, found, w, width)) {
      // 진짜 갈래 3 둘이다 — 손대지 않는다. 더 볼 다리가 있어도 여기서 멈춘다.
      return merged;
    }
    final cross = _MergedCrossing(a, b, found);
    // ① b 의 바깥 팔을 a 로 옮긴다.
    final bOuter = <int>[
      for (final n in adj[b]!)
        if (n != found[found.length - 2]) n,
    ];
    for (final n in bOuter) {
      adj[n]!
        ..remove(b)
        ..add(a);
      adj[a]!.add(n);
      cross.bSide.add(n);
    }
    // ② 다리 속과 b 를 그래프에서 뺀다 — 픽셀은 a 가 떠안는다.
    adj[a]!.remove(found[1]);
    adj[found[1]]?.remove(a);
    for (var i = 1; i < found.length; i++) {
      adj.remove(found[i]);
    }
    merged[a] = cross;
    debugRouteSink?.call(
      '교차점 붙임 (${a % w},${a ~/ w}) ← (${b % w},${b ~/ w}) '
      '다리 ${found.length - 1} · 갈래 ${adj[a]!.length}',
    );
  }
  return merged;
}

/// 다리 길이를 굵기의 몇 배까지 후보로 볼 것인가.
///
///   ⚠️ 이 값은 **후보를 넓게 잡기 위한 것**이지 판정이 아니다. 판정은 접선이 한다.
///   실측(굽기 420): 굵기 ~12, map_special_01 다리 24 = 2.0 배 · map_deep_04 45 = 3.6 배.
const int _mergeWidths = 6;

/// 갈래 3 이상인 두 자리를 잇는, 속이 전부 갈래 2 인 가장 짧은 길. 없으면 null.
List<int>? _findJunctionBridge(Map<int, List<int>> adj, int maxLen) {
  List<int>? best;
  for (final e in adj.entries) {
    if (e.value.length < 3) continue;
    for (final first in e.value) {
      final path = <int>[e.key, first];
      var prev = e.key;
      var cur = first;
      while (path.length - 1 <= maxLen) {
        final d = adj[cur]?.length ?? 0;
        if (d >= 3) {
          if (cur != e.key && (best == null || path.length < best.length)) {
            best = [...path];
          }
          break;
        }
        if (d != 2) break;
        final nxt = adj[cur]!.firstWhere((n) => n != prev, orElse: () => -1);
        if (nxt < 0) break;
        prev = cur;
        cur = nxt;
        path.add(cur);
      }
    }
  }
  return best;
}

/// 이 다리가 **원래 교차점 하나**였나 — 바깥 팔 넷의 접선으로 가른다.
///
///   다리를 뺀 바깥 팔은 넷이다(양끝에서 둘씩). 이 넷을 둘씩 짝짓는 방법은 세 가지고,
///   짝마다 두 접선이 얼마나 **마주보는지**를 본다. 마주볼수록 "원래 한 곡선" 이다.
///
///       비용(짝짓기) = Σ (1 − |접선ᵢ · 접선ⱼ|)
///
///   ⚠️ 이긴 짝짓기가 **양끝을 가로질러야** 교차점이다. a 의 두 팔끼리 짝지어지면 그건
///   곧은 선에 가지 하나가 붙은 것 — 진짜 갈래 3 이다.
bool _looksLikeCrossing(
  Map<int, List<int>> adj,
  List<int> bridge,
  int w,
  double width,
) {
  final a = bridge.first;
  final b = bridge.last;
  final reach = width.round().clamp(4, 24);
  final arms = <(double, double)>[];
  final side = <int>[];
  for (final (node, inner) in <(int, int)>[
    (a, bridge[1]),
    (b, bridge[bridge.length - 2]),
  ]) {
    for (final n in adj[node]!) {
      if (n == inner) continue;
      final dir = _armDirection(adj, node, n, reach, w);
      if (dir == null) return false;
      arms.add(dir);
      side.add(node == a ? 0 : 1);
    }
  }
  if (arms.length != 4) return false;
  const pairings = <List<int>>[
    [0, 1, 2, 3],
    [0, 2, 1, 3],
    [0, 3, 1, 2],
  ];
  var bestCost = double.infinity;
  List<int>? bestPair;
  for (final p in pairings) {
    final c = (1 - _absDot(arms[p[0]], arms[p[1]])) +
        (1 - _absDot(arms[p[2]], arms[p[3]]));
    if (c < bestCost) {
      bestCost = c;
      bestPair = p;
    }
  }
  final p = bestPair!;
  debugRouteSink?.call(
    '교차 판정 짝 ${p.join(",")} · 마주봄 '
    '${_absDot(arms[p[0]], arms[p[1]]).toStringAsFixed(2)}/'
    '${_absDot(arms[p[2]], arms[p[3]]).toStringAsFixed(2)} · 쪽 ${side.join()}',
  );
  // 실측(굽기 420): map_special_01 1.00/1.00 → 붙임 · map_deep_04 0.78/0.93 →
  //   안 붙임 · map_deep_05 0.84/0.99 → 안 붙임. 이 문턱을 없애면 deep_04 를 잘못
  //   붙여 선단 계단이 20 > 11 로 터진다.
  final crosses = side[p[0]] != side[p[1]] && side[p[2]] != side[p[3]];
  final straight = _absDot(arms[p[0]], arms[p[1]]) >= _kCrossCollinear &&
      _absDot(arms[p[2]], arms[p[3]]) >= _kCrossCollinear;
  return crosses && straight;
}

/// 짝지은 두 팔이 이만큼은 마주봐야 "원래 한 곡선" 으로 본다(코사인 절댓값).
///
///   1.0 이 완전한 일직선이다. **0.99 는 일부러 빡빡하다.** 실측(굽기 420):
///
///       map_special_01  1.00 / 1.00   → 붙인다
///       map_deep_03     0.95 / 1.00   → 안 붙인다
///       map_deep_05     0.84 / 0.99   → 안 붙인다
///       map_deep_04     0.78 / 0.93   → 안 붙인다
///
///   합성 도형 '가로지르는 교차' 는 0.99 다.
///
///   ⚠️ **0.95 인 map_deep_03 을 왜 빼는가.** 기하만 보면 붙이는 게 맞다. 그런데 붙이면
///   경로가 35·42·33px **순간이동**한다 — [_expandMerged] 가 그 모양의 드나듦을 아직
///   못 다룬다(`pen_tip_corpus_test` 가 한 프레임 76px > 70 으로 잡는다). 원인을 잡기
///   전까지는 **증거가 확실한 것만** 붙인다. 고치고 나면 이 값을 0.9 근처로 내리고
///   여기를 다시 쓴다.
const double _kCrossCollinear = 0.96;

/// [from] 에서 [first] 쪽으로 [reach] 만큼 걸어가 얻은 방향(바깥쪽을 향한 단위 벡터).
(double, double)? _armDirection(
  Map<int, List<int>> adj,
  int from,
  int first,
  int reach,
  int w,
) {
  var prev = from;
  var cur = first;
  for (var i = 1; i < reach; i++) {
    final ns = adj[cur];
    if (ns == null || ns.length != 2) break;
    final nxt = ns.firstWhere((n) => n != prev, orElse: () => -1);
    if (nxt < 0) break;
    prev = cur;
    cur = nxt;
  }
  final dx = (cur % w - from % w).toDouble();
  final dy = (cur ~/ w - from ~/ w).toDouble();
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return null;
  return (dx / len, dy / len);
}

/// 두 방향의 내적. 팔은 전부 자리 바깥을 향하므로 **−1 이 서로 마주보는 것**이다.
double _dot((double, double) p, (double, double) q) =>
    p.$1 * q.$1 + p.$2 * q.$2;

double _absDot((double, double) p, (double, double) q) {
  final d = p.$1 * q.$1 + p.$2 * q.$2;
  return d < 0 ? -d : d;
}

/// 진단용 — 순회가 무엇을 정했는지 흘려보낸다. 평소엔 null 이라 아무 비용도 없다.
void Function(String)? debugRouteSink;

/// 얇게 깎은 선(가시 제거·대각선 정리까지 끝난 상태)과 자리마다의 갈래 수.
class DebugSkeleton {
  const DebugSkeleton({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.pixels,
    required this.degrees,
  });

  /// 잘라낸 창(ROI)의 크기와, 원본에서의 왼쪽 위 자리.
  final int width;
  final int height;
  final int left;
  final int top;

  /// 얇은 선을 이루는 자리들(창 안 좌표의 `y * width + x`)과 각 자리의 갈래 수.
  final List<int> pixels;
  final List<int> degrees;
}

/// 진단용 — 얇게 깎은 결과를 그대로 넘겨준다. 평소엔 null 이라 비용이 없다.
void Function(DebugSkeleton)? debugSkeletonSink;

/// 짝이 안 맞는 자리끼리 이어, 그 사이를 **두 번 지나게** 한다.
///
///   갈래가 홀수인 자리는 펜이 "거기서 시작하거나 끝나야" 만 괜찮다. 그런 자리가 셋
///   이상이면 한 붓으로 못 그린다. 획의 시작과 끝 둘만 남기고, 나머지를 둘씩 짝지어
///   그 사이 최단 경로의 변을 **한 번 더** 지날 수 있게 표시한다.
///
///   ⚠️ 짝짓는 것은 **끝점(차수 1)을 뺀** 홀수 자리들이다. 끝점 둘은 홀수로 남아야
///   거기서 시작하고 거기서 끝난다.
void _pairOddVertices(
  Map<int, List<int>> adj,
  Map<int, int> remaining,
  int w,
) {
  final odd = <int>[
    for (final e in adj.entries)
      if (e.value.length.isOdd && e.value.length != 1) e.key,
  ]..sort();
  // 가까운 것끼리 짝짓는다 — 되짚는 거리가 짧을수록 좋다.
  final open = [...odd];
  while (open.length >= 2) {
    final a = open.removeAt(0);
    var bestI = 0;
    var bestPath = <int>[];
    for (var i = 0; i < open.length; i++) {
      final path = _shortestPath(adj, a, open[i]);
      if (path.isEmpty) continue;
      if (bestPath.isEmpty || path.length < bestPath.length) {
        bestPath = path;
        bestI = i;
      }
    }
    if (bestPath.isEmpty) break;
    open.removeAt(bestI);
    for (var i = 0; i + 1 < bestPath.length; i++) {
      final u = bestPath[i];
      final v = bestPath[i + 1];
      remaining[u * 1000003 + v] = (remaining[u * 1000003 + v] ?? 0) + 1;
      remaining[v * 1000003 + u] = (remaining[v * 1000003 + u] ?? 0) + 1;
    }
  }
}

/// [from] 에서 [to] 까지 변 수가 가장 적은 길. 못 닿으면 빈 목록.
List<int> _shortestPath(Map<int, List<int>> adj, int from, int to) {
  final prev = <int, int>{from: from};
  final queue = <int>[from];
  for (var head = 0; head < queue.length; head++) {
    final v = queue[head];
    if (v == to) break;
    for (final n in adj[v] ?? const <int>[]) {
      if (prev.containsKey(n)) continue;
      prev[n] = v;
      queue.add(n);
    }
  }
  if (!prev.containsKey(to)) return const <int>[];
  final out = <int>[to];
  var cur = to;
  while (cur != from) {
    cur = prev[cur]!;
    out.add(cur);
  }
  return out.reversed.toList();
}

List<int> _traversalStarts(Map<int, List<int>> adj) {
  final seen = <int>{};
  // (크기, 최상단) — 최상단이 그대로 시작점이다.
  final components = <(int size, int top)>[];
  for (final key in adj.keys) {
    if (!seen.add(key)) continue;
    var top = key;
    // ⚠️ **끝점(차수 1)에서 출발한다.** 걷기가 획 한복판에서 시작하면 양쪽으로 갈라져
    //   엉뚱한 데서 끝난다. 대각 지름길을 걷어내고 나니 정본 열 지도가 **모두 끝점 둘**
    //   을 갖는다(그 전에는 0~1 개였다) — 위쪽 것에서 출발한다.
    int? topEnd;
    var size = 0;
    final queue = <int>[key];
    for (var head = 0; head < queue.length; head++) {
      final v = queue[head];
      size++;
      if (v < top) top = v;
      if (adj[v]!.length == 1 && (topEnd == null || v < topEnd)) topEnd = v;
      for (final n in adj[v]!) {
        if (seen.add(n)) queue.add(n);
      }
    }
    components.add((size, topEnd ?? top));
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

/// 뼈대 그래프의 생김새 — **한 붓이 가능한 모양인가**를 답한다.
///
///   순회를 고치기 전에 반드시 재야 하는 값이다. 오일러 경로는 **연결 요소가 하나이고
///   홀수 차수 정점이 0 개 또는 2 개일 때만** 존재한다. 그보다 많으면 되짚기 없이는
///   한 붓으로 못 그린다 — 갈래 선택을 아무리 잘 골라도 안 되고, 그걸 모르고 고치다
///   두 번 헛발질했다(각도 선택 · 되짚기 시계).
///
///   ## 재 보니 그래프가 오염돼 있었다
///
///   정본 10종 실측(굽기 420, 길 세그먼트):
///
///       그대로            홀수차수 30~222 · 끝점 0~1 · 한 붓 가능 0/10
///       대각 지름길 제거   홀수차수  2~  8 · 끝점 2   · 한 붓 가능 6/10
///
///   8-연결 뼈대는 대각선이 직교 두 변과 **작은 삼각형**을 닫는다. 그 지름길들이
///   차수를 부풀려 정점 151 개에 간선 180 개(평균 차수 2.38)를 만든다 — 깨끗한 1px
///   경로라면 차수가 2 여야 한다. 걷어내면 **끝점이 정확히 둘**로 드러나고(획의 진짜
///   시작과 끝이다) 홀수 차수는 2~8 로 떨어진다.
///
///   즉 **순회가 헤맨 것이 아니라 그래프가 잘못돼 있었다.** 남은 홀수 차수 4~8 개는
///   진짜 자기교차(map_deep_03·04·05·special_01 — 사장님이 지적한 바로 그 넷)라
///   패리티 보정이 조금 필요하다.
class StrokeGraphShape {
  const StrokeGraphShape({
    required this.vertices,
    required this.edges,
    required this.components,
    required this.oddDegree,
    required this.endpoints,
    this.degrees = const {},
    this.bridges = const [],
  });

  /// 가지치기 뒤 살아남은 뼈대 픽셀 수.
  final int vertices;

  /// 무향 간선 수.
  final int edges;

  /// 연결 요소 수. 2 이상이면 펜을 떼야 한다.
  final int components;

  /// 홀수 차수 정점 수. 0 이나 2 여야 오일러 경로가 있다.
  final int oddDegree;

  /// 차수 1 인 정점 수 — 획의 자연스러운 시작·끝 후보다.
  final int endpoints;

  /// 차수별 개수 — 3 은 T 갈림길, 4 는 X 교차다.
  final Map<int, int> degrees;

  /// 갈래 3 인 점끼리 이어진 **다리** 의 길이들(변 개수, 오름차순).
  ///
  ///   굵은 획이 겹친 자리를 얇게 깎으면 교차점이 한 점이 아니라 짧은 다리가 되고,
  ///   그 양끝이 각각 갈래 3 이 된다 — 원래 X 하나였는데 T 둘로 읽힌다.
  ///   다리가 짧으면 "이건 한 교차점이었다" 는 증거다.
  final List<int> bridges;

  /// 되짚기 없이 한 붓으로 그릴 수 있나.
  bool get eulerian => components == 1 && (oddDegree == 0 || oddDegree == 2);

  @override
  String toString() => '정점 $vertices · 간선 $edges · 요소 $components · '
      '홀수차수 $oddDegree · 끝점 $endpoints · '
      '${eulerian ? "한 붓 가능" : "한 붓 불가"} · 차수분포 $degrees · 다리 $bridges';
}

/// [mask] 의 뼈대 그래프를 재기만 한다 — 굽지 않는다.
///
///   `bakeOneStrokeOrder` 와 **같은 전처리**(형태정리 · 세선화 · 가지치기)를 쓴다.
///   그래야 실제로 순회가 보는 그래프를 재는 것이 된다.
StrokeGraphShape measureStrokeGraph(
  StrokeMask mask, {
  bool dropDiagonalShortcuts = false,
}) {
  final w = mask.width;
  final h = mask.height;
  var m = Uint8List(w * h);
  for (var i = 0; i < m.length; i++) {
    if (mask.alpha[i] > 128) m[i] = 1;
  }
  // 굽기와 **같은** 형태정리 — 닫힘 2회 뒤 열림 1회.
  m = _erode(_dilate(m, w, h), w, h);
  m = _erode(_dilate(m, w, h), w, h);
  m = _dilate(_erode(m, w, h), w, h);
  final cleaned = m;
  final skel = _zhangSuen(Uint8List.fromList(cleaned), w, h);

  final adj = <int, List<int>>{};
  var skelCount = 0;
  var area = 0;
  for (var i = 0; i < cleaned.length; i++) {
    if (cleaned[i] == 1) area++;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (skel[y * w + x] == 0) continue;
      skelCount++;
      final list = <int>[];
      for (var k = 0; k < 8; k++) {
        final ny = y + _dy[k];
        final nx = x + _dx[k];
        if (_at(skel, w, h, ny, nx) != 1) continue;
        if (dropDiagonalShortcuts && _dy[k] != 0 && _dx[k] != 0) {
          // 두 직교 이웃이 살아 있으면 그 사이 대각선은 삼각형을 닫는 지름길이다.
          if (_at(skel, w, h, ny, x) == 1 || _at(skel, w, h, y, nx) == 1) {
            continue;
          }
        }
        list.add(ny * w + nx);
      }
      adj[y * w + x] = list;
    }
  }
  if (adj.isEmpty) {
    return const StrokeGraphShape(
      vertices: 0,
      edges: 0,
      components: 0,
      oddDegree: 0,
      endpoints: 0,
    );
  }
  final width = area / (skelCount == 0 ? 1 : skelCount);
  _pruneSpurs(adj, (width * kSpurWidths).round().clamp(6, 1 << 30));

  var edges = 0;
  var odd = 0;
  var ends = 0;
  final degrees = <int, int>{};
  for (final entry in adj.entries) {
    final d = entry.value.length;
    edges += d;
    degrees[d] = (degrees[d] ?? 0) + 1;
    if (d.isOdd) odd++;
    if (d == 1) ends++;
  }
  edges ~/= 2;

  // 연결 요소.
  final seen = <int>{};
  var components = 0;
  for (final start in adj.keys) {
    if (!seen.add(start)) continue;
    components++;
    final stack = <int>[start];
    while (stack.isNotEmpty) {
      for (final n in adj[stack.removeLast()] ?? const <int>[]) {
        if (adj.containsKey(n) && seen.add(n)) stack.add(n);
      }
    }
  }

  return StrokeGraphShape(
    vertices: adj.length,
    edges: edges,
    components: components,
    oddDegree: odd,
    endpoints: ends,
    degrees: degrees,
    bridges: _bridgeLengths(adj),
  );
}

/// 갈래 3 인 점에서 출발해 **다른 갈래 3 인 점**에 닿을 때까지의 변 개수.
///
///   중간이 전부 갈래 2 여야 한다(곧은 구간). 짧을수록 "원래 한 교차점" 이라는 뜻이다.
List<int> _bridgeLengths(Map<int, List<int>> adj) {
  final junctions = <int>[
    for (final e in adj.entries)
      if (e.value.length >= 3) e.key,
  ];
  final out = <int>[];
  final seen = <int>{};
  for (final j in junctions) {
    for (final first in adj[j]!) {
      var prev = j;
      var cur = first;
      var steps = 1;
      while (steps < 200) {
        final d = adj[cur]?.length ?? 0;
        if (d >= 3) {
          final a = j <= cur ? j : cur;
          final b = j <= cur ? cur : j;
          final key = a * 1000003 + b + steps * 1000000007;
          if (seen.add(key)) out.add(steps);
          break;
        }
        if (d != 2) break;
        final nxt = adj[cur]!.firstWhere((n) => n != prev, orElse: () => -1);
        if (nxt < 0) break;
        prev = cur;
        cur = nxt;
        steps++;
      }
    }
  }
  out.sort();
  return out;
}

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
