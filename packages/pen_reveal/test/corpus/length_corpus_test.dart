// 정규화의 **자(코퍼스)** 가 실제 자산과 계속 맞는지 — 굽기 해상도 420 에서 10종을 다시 재
//   `StrokeLengthProfile` 의 최단·최장과 대조한다.
//
//   왜 필요한가: `t = 0~1` 은 "코퍼스 최단~최장 사이 어디"라는 뜻이다. 자산이 바뀌거나
//   굽기(세선화·형태정리) 알고리즘이 바뀌어 실측 범위가 움직이면 t 의 뜻이 조용히 달라진다
//   — 최단 지도가 t=0.3 에서 시작하거나, 최장이 포화에 걸려 여럿이 2.2초에 뭉친다.
//   여기가 빨개지면 "테스트를 고치는" 게 아니라 **프로필 값을 다시 재서** 고친다.
//
//   ⚠️ 정본 지도 10종은 디자인 자산이라 이 레포에 없다. PNG 대신 프리베이크 RGBA
//   (`corpus_fixtures.dart`, 420 고정)를 읽고, 자산이 없으면 `corpusSkip` 으로 **스스로**
//   빠진다 — 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
@Tags(['corpus', 'regression'])
library;

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

import 'corpus_fixtures.dart';

/// 실측 t — 2026-08-07 굽기 해상도 420, composed−base.
///
///   ⚠️ 리터럴이다. 구현 공식을 다시 쓰면 "구현이 곧 기대값"이 되어 아무것도 안 잡는다.
///   양끝의 `0`·`1` 은 실측 `0.000`·`1.000` 이다 — `prefer_int_literals` 가 double 자리의
///   `0.000` 을 막아 정수 리터럴로 적었을 뿐 값은 그대로다.
const Map<String, double> kExpectedRelativeLength = <String, double>{
  'map_basic_03': 0,
  'map_basic_01': 0.131,
  'map_basic_02': 0.151,
  'map_deep_01': 0.517,
  'map_deep_03': 0.804,
  'map_deep_04': 0.847,
  'map_deep_02': 0.947,
  'map_deep_06': 0.947,
  'map_special_01': 0.964,
  'map_deep_05': 1,
};

/// 실측 길 길이(굽기 해상도 420 픽셀).
const Map<String, double> kExpectedRoadLength = <String, double>{
  'map_basic_03': 124.5,
  'map_basic_01': 177.3,
  'map_basic_02': 186.4,
  'map_deep_01': 410.6,
  'map_deep_03': 674.5,
  'map_deep_04': 721.6,
  'map_deep_02': 839.2,
  'map_deep_06': 839.2,
  'map_special_01': 859.6,
  'map_deep_05': 905.7,
};

void main() {
  test(
    '10종을 다시 재도 코퍼스가 그대로다 — 프로필 최단·최장이 실측과 ±2%',
    () {
      final measured = <String, double>{};
      final relative = <String, double>{};
      for (final key in kCorpusKeys) {
        final pair = loadCorpusPair(key);
        final plan = detectReveal(
          RevealDetectInput(
            baseRgba: pair.baseRgba,
            composedRgba: pair.composedRgba,
            width: pair.width,
            height: pair.height,
          ),
        );
        final road = plan.segments.firstWhere(
          (s) => s.kind == RevealSegmentKind.primaryStroke,
        );
        measured[key] = road.measure;
        expect(
          road.relativeLength,
          isNotNull,
          reason: '$key: 탐지가 상대 길이를 안 실었다',
        );
        relative[key] = road.relativeLength!;
      }

      // 사람이 읽을 표 — 값이 움직였을 때 새 프로필을 바로 뜰 수 있게 남긴다.
      printOnFailure(
        measured.entries
            .map((e) => '${e.key}\t${e.value}\t${relative[e.key]}')
            .join('\n'),
      );

      const profile = kStrokeLengthProfile;
      final lengths = measured.values.toList()..sort();
      expect(
        lengths.first,
        closeTo(profile.shortest, profile.shortest * 0.02),
        reason: '코퍼스 최단이 움직였다 — StrokeLengthProfile.shortest 를 다시 재라',
      );
      expect(
        lengths.last,
        closeTo(profile.longest, profile.longest * 0.02),
        reason: '코퍼스 최장이 움직였다 — StrokeLengthProfile.longest 를 다시 재라',
      );

      for (final entry in kExpectedRoadLength.entries) {
        expect(
          measured[entry.key],
          closeTo(entry.value, entry.value * 0.02),
          reason: '${entry.key}: 잰 길이가 움직였다',
        );
      }
      for (final entry in kExpectedRelativeLength.entries) {
        expect(
          relative[entry.key],
          closeTo(entry.value, 0.01),
          reason: '${entry.key}: 상대 길이(t)가 움직였다',
        );
      }

      // 끝점이 정확히 붙어 있어야 밴드를 다 쓴다.
      expect(relative['map_basic_03'], lessThanOrEqualTo(0.01));
      expect(relative['map_deep_05'], greaterThanOrEqualTo(0.99));
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: corpusSkip,
  );
}

// 원본의 둘째 시험 '굽는 해상도를 210·420·840 으로 바꿔도 같은 지도는 같은 자리에 온다' 는
//   여기 없다 — 순수 Dart 는 PNG 도 리샘플러도 못 다뤄 210·840 을 새로 구울 수 없다
//   (프리베이크는 420 한 장뿐이다). `packages/pen_reveal_flutter/test/corpus/` 가 맡는다.
