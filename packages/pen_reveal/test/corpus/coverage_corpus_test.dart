// **진행도 1 에서 최종본과 100% 같아진다** — 정본 지도 10종으로 잠근다.
//
//   전에는 한 붓 순회가 뼈대 덩어리 **하나만** 훑고, 형태정리(열림 연산)에 깎인 가장자리를
//   버려서 길 픽셀의 3.5~22.4%(정본 지도 10종 실측 2026-08-07)가 끝까지 안 드러났다. 화면에선
//   "지도가 다 안 그려진다"로 보인다. 인공 마스크는 알고리즘을, 정본 지도 10종은 현실을 본다.
//
//   ⚠️ 이 파일은 그중 **실지도 갈래**다. 인공 마스크 갈래는 `test/plan/coverage_test.dart`
//   에 있고 그쪽은 자산 없이도 언제나 돈다. 여기서만 잡히는 것은 "합성 마스크로는 안 나오는
//   모양" — 갈라진 뼈대, 얇은 지선, 붙어 버린 손글씨 같은 현실의 형태다.
//
//   ⚠️ 여기가 빨개지면 **드러내는 쪽이 아니라 버리는 쪽**을 의심해라 — 연결요소 순회,
//   `one_stroke_bake.dart` 의 `_spread` 가 쓰는 마스크, 문구 조각 붙이기,
//   세그먼트 자리(255) 넷 중 하나다.
//
//   ⚠️ 정본 지도 10종은 디자인 자산이라 이 레포에 없다. PNG 대신 프리베이크 RGBA
//   (`corpus_fixtures.dart`, 420 고정)를 읽고, 자산이 없으면 `corpusSkip` 으로 **스스로**
//   빠진다 — 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
@Tags(['corpus', 'regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

import 'corpus_fixtures.dart';

/// 바뀐 픽셀의 평면 인덱스 — 탐지기가 쓰는 것과 **같은 기준**이다.
///
///   ⚠️ 합성 쪽(`test/plan/coverage_test.dart`)에도 같은 헬퍼가 있다. 일부러 복제한다 —
///   코퍼스 파일은 자산이 하나도 없어도 **컴파일은 돼야** 하는데, 언제나 도는 잠금 파일에
///   기대게 만들면 두 파일이 서로 얽혀 한쪽을 못 고친다.
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
List<int> unrevealedAtEnd(Uint8List order, List<int> changed) {
  const compiler = RevealTextureCompiler();
  final top = compiler.maxOrderValue;
  return [
    for (final i in changed)
      if (order[i] > top) i,
  ];
}

void main() {
  group(
    '정본 지도 10종 — 굽기 해상도 420 에서 하나도 안 남는다',
    () {
      for (final key in kCorpusKeys) {
        test(
          key,
          () {
            final pair = loadCorpusPair(key);
            final plan = detectReveal(
              RevealDetectInput(
                baseRgba: pair.baseRgba,
                composedRgba: pair.composedRgba,
                width: pair.width,
                height: pair.height,
              ),
            );
            final changed = changedPixels(
              pair.baseRgba,
              pair.composedRgba,
              pair.width,
              pair.height,
            );
            expect(changed.length, greaterThan(1000));
            expect(
              uncovered(plan, changed),
              isEmpty,
              reason: '$key: 계획에서 빠진 픽셀',
            );

            const policy = HandwritingRevealTiming();
            const compiler = RevealTextureCompiler();
            final order = compiler.compile(plan, policy.schedule(plan));
            expect(
              unrevealedAtEnd(order, changed),
              isEmpty,
              reason: '$key: 진행도 1 에서도 안 드러나는 픽셀',
            );
            expect(
              startsNearTop(plan),
              isTrue,
              reason: '$key: 길이 맨 위에서 시작하지 않는다(사용자 지정)',
            );
          },
          timeout: const Timeout(Duration(minutes: 2)),
          skip: corpusSkip,
        );
      }
    },
    skip: corpusSkip,
  );
}

// 원본의 셋째 그룹은 `pen_reveal_flutter/test/corpus/preparer_corpus_test.dart` 로 옮겼다.
// 'X 고르기는 굽기 해상도에 안 흔들린다'(240·420·1065 에서 고른 X 덩어리의
//   중심이 ±0.02 안에 머문다)는 여기 없다 — 순수 Dart 는 PNG 도 리샘플러도 못 다뤄 420 말고
//   다른 해상도를 새로 구울 수 없다(프리베이크는 420 한 장뿐이다).
//   `packages/pen_reveal_flutter/test/corpus/` 가 맡는다.
