// **실지도가 있어야 도는** Flutter 쪽 시험 — 굽기 다리 전체를 정본 10종으로 한 번 돌린다.
//
//   인공 마스크 시험은 "알고리즘이 도는가"만 본다. 여기는 리샘플·임계·필터품질처럼
//   **엔진에 닿는 것들**이 실제 그림에서 어떤 값을 내는지를 못 박는다.
//
//   두 시험이 왜 코어가 아니라 이쪽에 있나:
//     · 재생 시간 실측 — `RevealPreparer` 가 있어야 한다(ui.Image → RGBA → 계획 → 일정).
//     · 해상도 210·420·840 — **리샘플러가 필요하다.** 순수 Dart 는 PNG 도 못 풀고 크기도
//       못 바꿔서, 코어의 코퍼스 통로는 프리베이크 RGBA 420 한 장뿐이다. 그래서 원본에서
//       구조 층 옆에 있던 해상도 시험이 여기로 넘어왔다
//       (`pen_reveal/test/corpus/length_corpus_test.dart` 꼬리 주석 참고).
//
//   ⚠️ 정본 지도 10종은 디자인 자산이라 이 레포에 없다. 자산이 없으면 `corpusSkip` 으로
//   **테스트가 스스로** 빠진다 — 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
@Tags(['corpus', 'regression'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

import 'corpus_maps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    '실제 땅속 지도 자산 — 값이 안 흔들리는지 붙잡아 둔다',
    () {
      // 인공 마스크는 "알고리즘이 도는가"만 본다. 리샘플·임계·필터품질 중 **하나만 건드려도**
      //   값이 눈에 띄게 움직이므로, 실측값을 못 박아 두면 그게 곧 파이프라인 지문이다.
      //   (2026-08-07 실측 — 길 + X 두 획 + 문구 덩어리를 다 합친 재생 시간.)
      //
      //   ⚠️ 값이 바뀌면 **맹목적으로 다시 박지 마라.** 2026-08-07 정규화 이관 때 셋 다
      //   움직였는데(2654→2799 · 2702→3274 · 3104→3688) 그건 `옛 총합 − 옛 길시간 +
      //   새 길시간` 과 정확히 맞았다 — 길 구간만 바뀌었다는 뜻이다. 계산과 안 맞으면
      //   X·문구까지 함께 움직인 것이니 원인을 찾아라.
      //
      //   같은 날 길 밴드를 사용자 확정값(1100~2206 → 500~2000)으로 갈아 끼우며 또 한 번
      //   줄었다(2799→2251 · 3274→2877 · 3688→3468). 줄어든 폭 548·397·220 은 전부
      //   `(1100+1106t) − (500+1500t) = 600 − 394t` 와 맞는다(t=0.132·0.515·0.964) —
      //   역시 길 구간만 움직였다.
      const cases = <String, int>{
        'map_basic_01': 2251,
        'map_deep_01': 2877,
        'map_special_01': 3468,
      };

      for (final entry in cases.entries) {
        test(
          '${entry.key} — 재생 ${entry.value}ms',
          () async {
            final base = await loadCorpusImage(entry.key, composed: false);
            final composed = await loadCorpusImage(entry.key, composed: true);
            addTearDown(base.dispose);
            addTearDown(composed.dispose);
            expect(
              base.width,
              composed.width,
              reason: '바닥과 최종본은 같은 크기여야 한다(어긋나면 화면 전체가 획이 된다)',
            );
            expect(base.height, composed.height);

            final prepared = await const RevealPreparer().prepare(
              base: base,
              composed: composed,
            );
            addTearDown(prepared.dispose);

            expect(prepared.reveal.height, 420, reason: '긴 변이 굽기 해상도');
            expect(
              prepared.revealDuration.inMilliseconds,
              closeTo(entry.value, 120),
              reason: '값이 크게 움직였다면 마스크 유도·리샘플·임계·타이밍 중 하나가 바뀐 것이다',
            );
          },
          timeout: const Timeout(Duration(minutes: 2)),
          skip: corpusSkip,
        );
      }
    },
    skip: corpusSkip,
  );

  test(
    '굽는 해상도를 210·420·840 으로 바꿔도 같은 지도는 같은 자리에 온다',
    () async {
      // ⚠️ **밴드 양끝에 붙은 지도는 빼고 잰다.** 포화 구간에서는 자를 아무리 틀리게
      //   잡아도 값이 같아 시험이 통과한다(최단 basic_03·최장 deep_05·거의 최장인 셋).
      const policy = HandwritingRevealTiming();
      final floor = policy.primaryMinDuration.inMilliseconds;
      final ceiling = policy.primaryMaxDuration.inMilliseconds;
      final band = ceiling - floor;

      var interior = 0;
      for (final key in kCorpusKeys) {
        final relatives = <double>[];
        final millis = <int>[];
        for (final longSide in const [210, 420, 840]) {
          final pair = await loadCorpusRgba(key, longSide);
          final plan = detectReveal(
            RevealDetectInput(
              baseRgba: pair.baseRgba,
              composedRgba: pair.composedRgba,
              width: pair.width,
              height: pair.height,
            ),
          );
          final schedule = policy.schedule(plan);
          final road = schedule.windows.first;
          relatives.add(
            plan.segments
                .firstWhere((s) => s.kind == RevealSegmentKind.primaryStroke)
                .relativeLength!,
          );
          millis.add(
            ((road.end - road.start) * schedule.total.inMilliseconds).round(),
          );
        }
        final saturated = millis.any(
          (m) => m - floor < 100 || ceiling - m < 100,
        );
        printOnFailure('$key\t$relatives\t$millis');
        if (saturated) continue;
        interior++;

        final sortedRelative = [...relatives]..sort();
        final sortedMillis = [...millis]..sort();
        expect(
          sortedRelative.last - sortedRelative.first,
          lessThanOrEqualTo(0.05),
          reason: '$key: 해상도만 바꿨는데 상대 길이가 흔들렸다 $relatives',
        );
        expect(
          sortedMillis.last - sortedMillis.first,
          lessThanOrEqualTo((band * 0.05).round()),
          reason: '$key: 해상도만 바꿨는데 길 시간이 밴드의 5% 넘게 움직였다 $millis',
        );
      }
      expect(
        interior,
        greaterThanOrEqualTo(4),
        reason: '밴드 안쪽에 있는 지도가 너무 적다 — 시험이 사실상 비었다',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: corpusSkip,
  );

  // X 를 고르는 관문 넷이 **전부 비율**이라는 것을 실지도로 잠근다.
  //
  //   `RevealDetectConfig` 의 관문은 면적비·거리비·우세비다. 절대 픽셀 기준을 쓰면
  //   `RevealPreparer.longSide` 를 바꾸는 순간 조용히 무력화되는데, 조용해서 아무 데서도
  //   안 잡힌다 — 다른 덩어리를 X 로 골라도 연출은 그냥 이상해질 뿐 터지지 않는다.
  //   (그래서 `CrossCalibration` 의 `minComponentPixels` 류 절대 기준은 런타임에서 안 쓴다.)
  //
  //   ⚠️ 240·420·1065 는 원본이 고른 폭이다 — 굽기 기본값(420)의 위아래로 **4.4배** 벌어져
  //   있어야 비율 기준과 픽셀 기준이 갈린다. 210·840 처럼 좁게 잡으면 둘 다 통과한다.
  //
  //   원본에서는 구조 층 옆(`bag_reveal_coverage_test`)에 있었다. 리샘플러가 필요해서
  //   이쪽으로 넘어왔다 — `pen_reveal/test/corpus/coverage_corpus_test.dart` 꼬리 주석 참고.
  group(
    'X 고르기는 굽기 해상도에 안 흔들린다',
    () {
      /// X 두 획을 감싸는 상자의 중심 — **캔버스 크기로 나눈 비율**이라 해상도끼리 견줄 수
      ///   있다. 두 획이 다 안 잡히면 `null`(=X 를 못 찾았다).
      ({double cx, double cy})? xCentre(RevealPlan plan) {
        final strokes = plan.segments.where(
          (s) =>
              s.kind == RevealSegmentKind.crossBackslash ||
              s.kind == RevealSegmentKind.crossSlash,
        );
        if (strokes.length != 2) return null;
        final left = strokes.map((s) => s.left).reduce((a, b) => a < b ? a : b);
        final right =
            strokes.map((s) => s.right).reduce((a, b) => a > b ? a : b);
        final top = strokes.map((s) => s.top).reduce((a, b) => a < b ? a : b);
        final bottom =
            strokes.map((s) => s.bottom).reduce((a, b) => a > b ? a : b);
        return (
          cx: (left + right) / 2 / plan.width,
          cy: (top + bottom) / 2 / plan.height,
        );
      }

      for (final key in const [
        'map_basic_03',
        'map_deep_05',
        'map_special_01',
      ]) {
        test(
          key,
          () async {
            final centres = <int, ({double cx, double cy})>{};
            for (final longSide in const [240, 420, 1065]) {
              final pair = await loadCorpusRgba(key, longSide);
              final plan = detectReveal(
                RevealDetectInput(
                  baseRgba: pair.baseRgba,
                  composedRgba: pair.composedRgba,
                  width: pair.width,
                  height: pair.height,
                ),
              );
              final centre = xCentre(plan);
              expect(centre, isNotNull, reason: '$key @$longSide: X 를 못 찾았다');
              centres[longSide] = centre!;
            }
            final reference = centres[420]!;
            for (final entry in centres.entries) {
              expect(
                entry.value.cx,
                closeTo(reference.cx, 0.02),
                reason: '$key @${entry.key}: 다른 덩어리를 X 로 골랐다(가로)',
              );
              expect(
                entry.value.cy,
                closeTo(reference.cy, 0.02),
                reason: '$key @${entry.key}: 다른 덩어리를 X 로 골랐다(세로)',
              );
            }
          },
          timeout: const Timeout(Duration(minutes: 5)),
          skip: corpusSkip,
        );
      }
    },
    skip: corpusSkip,
  );
}
