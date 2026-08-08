// **진행도 1 에서 최종본과 100% 같아진다** — 이 한 줄을 잠근다.
//
//   전에는 한 붓 순회가 뼈대 덩어리 **하나만** 훑고, 형태정리(열림 연산)에 깎인 가장자리를
//   버려서 길 픽셀의 3.5~22.4%(정본 지도 10종 실측 2026-08-07)가 끝까지 안 드러났다. 화면에선
//   "지도가 다 안 그려진다"로 보인다. 인공 마스크는 알고리즘을, 정본 지도 10종은 현실을 본다.
//
//   ⚠️ 이 파일에 있는 것은 그중 **인공 마스크 갈래**뿐이다. 실지도 갈래는 프리베이크 RGBA 를
//   읽는 `test/corpus/`(`@Tags(['corpus'])`)로 갔고, 자산이 없는 공개 CI 에선 스스로 빠진다 —
//   그래서 **언제나 도는 잠금은 여기다.** 여기를 약하게 만들면 공개 CI 에는 이 회귀를 잡는
//   그물이 하나도 안 남는다.
//
//   ⚠️ 여기가 빨개지면 **드러내는 쪽이 아니라 버리는 쪽**을 의심해라 — 연결요소 순회,
//   `one_stroke_bake.dart` 의 `_spread` 가 쓰는 마스크, 문구 조각 붙이기,
//   세그먼트 자리(255) 넷 중 하나다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

/// 바뀐 픽셀의 평면 인덱스 — 탐지기가 쓰는 것과 **같은 기준**이다.
List<int> changedPixels(
  Uint8List base,
  Uint8List composed,
  int w,
  int h, [
  RevealDetectConfig cfg = const RevealDetectConfig(),
]) {
  final out = <int>[];
  for (var i = 0; i < w * h; i++) {
    final j = i * 4;
    final diff = (composed[j] - base[j]).abs() +
        (composed[j + 1] - base[j + 1]).abs() +
        (composed[j + 2] - base[j + 2]).abs();
    if (diff <= cfg.differenceThreshold ||
        composed[j + 3] < cfg.composedAlphaThreshold) {
      continue;
    }
    out.add(i);
  }
  return out;
}

/// 바뀐 픽셀 중 계획에 안 든 것.
List<int> uncovered(RevealPlan plan, List<int> changed) => [
      for (final i in changed)
        if (plan.segmentId[i] == kRevealHiddenSegment) i,
    ];

/// 길이 **처음 그어지는 지점**이 그 길 bbox 의 위쪽 [fraction] 안에 있는지.
///
///   ⚠️ "진행도 0 픽셀의 y == 길 픽셀 최소 y" 로 잠그면 안 된다. 뼈대 값을 길 전체로
///   퍼뜨리는 `_spread`(`one_stroke_bake.dart`)가 BFS 라, 형태정리에 깎인 조각·떨어진
///   덩어리의 최상단 픽셀이 시작점 값을 그대로 받는다는 보장이 없다. 사용자 지정
///   ("획은 언제나 맨 위에서")을 지키는지는 **위쪽 밴드 안인가**로 본다.
bool startsNearTop(RevealPlan plan, {double fraction = 0.10}) {
  final road = plan.segments.firstWhere(
    (s) => s.kind == RevealSegmentKind.primaryStroke,
  );
  var firstWithin = kRevealWithinScale + 1;
  var firstY = -1;
  for (var i = 0; i < plan.segmentId.length; i++) {
    if (plan.segmentId[i] != road.id) continue;
    if (plan.within[i] < firstWithin) {
      firstWithin = plan.within[i];
      firstY = i ~/ plan.width;
    }
  }
  return firstY >= 0 && firstY <= road.top + road.height * fraction;
}

/// 굽은 텍스처에서 진행도 1 에도 안 드러나는 픽셀.
///
///   ⚠️ 상한(`maxOrderValue`)을 여기서 다시 계산하지 않는다. 그 값은 임계 가파르기
///   `RevealSharpness` 하나가 소유하고 컴파일러가 그대로 물려받는다 — 테스트가 제 상수를
///   들면 "굽는 쪽과 그리는 쪽이 같은 k 를 본다" 는 계약을 이 파일이 먼저 깬다.
///
///   구조 층 테스트가 시간 층(`timing.dart`)을 import 하는 것은 괜찮다. 순수성 제약은
///   `lib/src/plan/` **소스**에만 걸리고, 그건 `test/purity_test.dart` 가 따로 본다.
List<int> unrevealedAtEnd(Uint8List order, List<int> changed) {
  const compiler = RevealTextureCompiler();
  final top = compiler.maxOrderValue;
  return [
    for (final i in changed)
      if (order[i] > top) i,
  ];
}

const int _w = 120;
const int _h = 120;

Uint8List _page() {
  final rgba = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    rgba[i * 4] = 240;
    rgba[i * 4 + 1] = 238;
    rgba[i * 4 + 2] = 230;
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}

void _paint(Uint8List rgba, int x, int y, int r, int g, int b) {
  if (x < 0 || x >= _w || y < 0 || y >= _h) return;
  final j = (y * _w + x) * 4;
  rgba[j] = r;
  rgba[j + 1] = g;
  rgba[j + 2] = b;
  rgba[j + 3] = 255;
}

void _bar(Uint8List rgba, int left, int top, int width, int height) {
  for (var y = top; y < top + height; y++) {
    for (var x = left; x < left + width; x++) {
      _paint(rgba, x, y, 40, 38, 36);
    }
  }
}

void main() {
  group('인공 마스크 — 덩어리가 여럿이어도 하나도 안 남는다', () {
    test('길이 세 토막으로 끊겨 있어도 전부 드러난다', () {
      final base = _page();
      final composed = _page();
      // 서로 안 닿는 세 토막 + 아래쪽에 외딴 점 하나.
      _bar(composed, 20, 10, 6, 30);
      _bar(composed, 60, 20, 6, 40);
      _bar(composed, 90, 50, 6, 25);
      _bar(composed, 40, 100, 3, 3);

      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      );
      final changed = changedPixels(base, composed, _w, _h);

      expect(changed, isNotEmpty);
      expect(uncovered(plan, changed), isEmpty, reason: '계획에서 빠진 픽셀이 있다');

      const policy = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final order = compiler.compile(plan, policy.schedule(plan));
      expect(
        unrevealedAtEnd(order, changed),
        isEmpty,
        reason: '진행도 1 에서도 안 드러나는 픽셀이 있다',
      );
    });

    test('토막마다 차례로 **그어진다** — 뒤늦게 통째로 튀어나오지 않는다', () {
      // ⚠️ 커버리지만 보면 안 된다. 안 훑은 토막도 "맨 끝에 한꺼번에" 드러나면 커버리지는
      //   100% 인데 화면에선 지도 반쪽이 **팝** 하고 나타난다. 토막 안에서 진행도가 퍼지는지,
      //   토막끼리 순서가 지켜지는지를 같이 본다.
      final base = _page();
      final composed = _page();
      _bar(composed, 20, 10, 6, 30); // A — 맨 위(여기서 시작해야 한다)
      _bar(composed, 60, 20, 6, 40); // B — 제일 크다
      _bar(composed, 90, 50, 6, 25); // C

      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      );
      final road = plan.segments.firstWhere(
        (s) => s.kind == RevealSegmentKind.primaryStroke,
      );

      ({int lo, int hi}) rangeOfColumn(int left, int right) {
        var lo = kRevealWithinScale + 1;
        var hi = -1;
        for (var i = 0; i < plan.segmentId.length; i++) {
          if (plan.segmentId[i] != road.id) continue;
          final x = i % _w;
          if (x < left || x > right) continue;
          if (plan.within[i] < lo) lo = plan.within[i];
          if (plan.within[i] > hi) hi = plan.within[i];
        }
        return (lo: lo, hi: hi);
      }

      final a = rangeOfColumn(20, 25);
      final b = rangeOfColumn(60, 65);
      final c = rangeOfColumn(90, 95);

      for (final entry in {'A': a, 'B': b, 'C': c}.entries) {
        expect(
          entry.value.hi,
          greaterThan(entry.value.lo),
          reason: '${entry.key} 토막이 한 시점에 통째로 떴다 — 그어지지 않았다',
        );
      }
      // 순서: 최상단이 든 A → 큰 것부터(B: 40칸 → C: 25칸).
      expect(a.hi, lessThanOrEqualTo(b.lo), reason: 'A 가 B 보다 먼저 그어져야 한다');
      expect(b.hi, lessThanOrEqualTo(c.lo), reason: 'B 가 C 보다 먼저 그어져야 한다');
      expect(a.lo, 0, reason: '펜은 맨 위 토막에서 시작한다');
    });

    test('첫 획은 언제나 맨 위에서 시작한다 — 큰 토막이 아래에 있어도', () {
      final base = _page();
      final composed = _page();
      // 위에 작은 토막, 아래에 훨씬 큰 토막.
      _bar(composed, 20, 8, 5, 12);
      _bar(composed, 60, 60, 8, 45);

      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      );
      final road = plan.segments.firstWhere(
        (s) => s.kind == RevealSegmentKind.primaryStroke,
      );

      var firstAt = -1;
      var firstWithin = kRevealWithinScale + 1;
      for (var i = 0; i < plan.segmentId.length; i++) {
        if (plan.segmentId[i] != road.id) continue;
        if (plan.within[i] < firstWithin) {
          firstWithin = plan.within[i];
          firstAt = i;
        }
      }
      expect(firstWithin, 0);
      expect(
        firstAt ~/ _w,
        lessThan(30),
        reason: '펜이 아래쪽 큰 토막에서 시작했다 — "획은 언제나 맨 위에서 시작"이 깨졌다',
      );
      expect(startsNearTop(plan), isTrue, reason: '시작점이 길 bbox 위쪽 10% 밖이다');
    });

    test('문구 조각이 멀리 떨어져 있어도 안 버린다', () {
      final base = _page();
      final composed = _page();
      _bar(composed, 20, 10, 6, 60);
      // 붉은 문구 한 덩어리 + 저 멀리 떨어진 점 하나(느낌표의 점·반짝임 자리).
      for (var y = 90; y < 100; y++) {
        for (var x = 20; x < 34; x++) {
          _paint(composed, x, y, 205, 45, 50);
        }
      }
      _paint(composed, 100, 30, 205, 45, 50);
      _paint(composed, 101, 30, 205, 45, 50);

      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      );
      expect(
        uncovered(plan, changedPixels(base, composed, _w, _h)),
        isEmpty,
        reason: '붙일 데 없는 조각을 잡티로 버렸다',
      );
    });
  });
}

// 실지도 갈래(원본의 `실지도 10종 …` · `X 고르기는 굽기 해상도에 안 흔들린다` 두 그룹)는
//   PNG 디코더가 필요해 순수 Dart 로 못 온다 — 프리베이크 RGBA 를 읽는 `test/corpus/` 로 갔다.
