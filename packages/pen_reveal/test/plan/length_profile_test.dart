// 길이(픽셀) → **0.0~1.0** 을 잠근다. 여기가 "얼마나 긴가"의 유일한 기준이다.
//
//   ⚠️ 기대값은 전부 **리터럴**이다. 구현 공식을 다시 쓰면 "구현이 곧 기대값"이 되어
//   지수·기준값을 바꿔도 아무것도 안 잡는다.
import 'dart:io';
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

/// 정본 10종 실측 길이(굽기 해상도 420) → 접힌 값. 사람이 손으로 계산해 박은 표다.
///
///   양 끝의 `0`·`1` 은 원본에서 `0.000`·`1.000` 이었다 — 뜻은 같고, double 문맥의
///   정수값은 정수 리터럴로 적는 것이 이 레포의 린트(`prefer_int_literals`)다.
const List<(double length, double relative)> _fixed = <(double, double)>[
  (124.5, 0),
  (177.3, 0.131),
  (186.4, 0.151),
  (410.6, 0.517),
  (674.5, 0.804),
  (721.6, 0.847),
  (839.2, 0.947),
  (859.6, 0.964),
  (905.7, 1),
];

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

/// 세로로 [height] 만큼 뻗은 길 하나짜리 그림.
Uint8List _road(int height) {
  final rgba = _page();
  for (var y = 10; y < 10 + height; y++) {
    for (var x = 30; x < 36; x++) {
      final j = (y * _w + x) * 4;
      rgba[j] = 40;
      rgba[j + 1] = 38;
      rgba[j + 2] = 36;
      rgba[j + 3] = 255;
    }
  }
  return rgba;
}

RevealPlan _detect(Uint8List composed) => detectReveal(
      RevealDetectInput(
        baseRgba: _page(),
        composedRgba: composed,
        width: _w,
        height: _h,
      ),
    );

double _relativeOf(RevealPlan plan) => plan.segments
    .firstWhere((s) => s.kind == RevealSegmentKind.primaryStroke)
    .relativeLength!;

void main() {
  group('접는 함수', () {
    test('고정표 — 정본 10종의 길이가 정확히 이 자리에 온다', () {
      for (final (length, relative) in _fixed) {
        expect(
          normalizeStrokeLength(length),
          closeTo(relative, 0.01),
          reason: '길이 $length 의 자리가 움직였다',
        );
      }
    });

    test('끝점은 딱 붙는다 — 밴드를 다 쓰려면 0 과 1 이어야 한다', () {
      expect(normalizeStrokeLength(124.5), lessThanOrEqualTo(0.01));
      expect(normalizeStrokeLength(905.7), greaterThanOrEqualTo(0.99));
    });

    test('길수록 커진다 — 0~2000 을 1 씩 훑어도 한 번도 안 뒤집힌다', () {
      var previous = -1.0;
      for (var length = 0.0; length <= 2000; length += 1) {
        final t = normalizeStrokeLength(length);
        expect(t, greaterThanOrEqualTo(previous), reason: '$length 에서 뒤집혔다');
        previous = t;
      }
    });

    test('가운데가 평평해지지 않는다 — 200~900 은 1px 만 길어도 값이 움직인다', () {
      // ⚠️ 임계 5e-4 는 실측에서 나왔다. 지수 0.35 라 기울기가 길이에 따라 떨어지는데,
      //   최장 부근(900)이 7.7e-4 로 가장 낮다. 1e-3 을 걸면 정당한 구현이 빨개진다.
      for (var length = 200.0; length < 900; length += 1) {
        final step =
            normalizeStrokeLength(length + 1) - normalizeStrokeLength(length);
        expect(
          step,
          greaterThanOrEqualTo(5e-4),
          reason: '$length 부근이 평평하다 — 길이 차이가 시간에 안 실린다',
        );
      }
    });

    test('말도 안 되는 입력에도 0~1 · NaN·무한 없음', () {
      for (final length in const [-1.0, 0.0, 1e-9, 50.0, 1500.0, 1e9]) {
        final t = normalizeStrokeLength(length);
        expect(t.isNaN, isFalse, reason: '$length → NaN');
        expect(t.isFinite, isTrue, reason: '$length → 무한');
        expect(t, inInclusiveRange(0, 1), reason: '$length → 범위 밖');
      }
    });

    test('길이가 0 이면 0 — 뼈대가 통째로 지워진 갈래도 안 터진다', () {
      expect(normalizeStrokeLength(0), 0);
    });

    test('같은 길이는 비트까지 같다 — 839.2 두 지도가 갈리면 안 된다', () {
      expect(normalizeStrokeLength(839.2), normalizeStrokeLength(839.2));
    });

    test('퇴화한 자(최단==최장)도 0 으로 나누지 않는다', () {
      const flat = StrokeLengthProfile(shortest: 300, longest: 300);
      for (final length in const [0.0, 300.0, 5000.0]) {
        final t = normalizeStrokeLength(length, profile: flat);
        expect(t.isNaN, isFalse);
        expect(t, 0);
      }
    });
  });

  group('코퍼스 밖 — 서버가 새 지도를 주면', () {
    test('더 길면 포화(1.0), 더 짧으면 0.0 — 재정규화하지 않는다', () {
      expect(normalizeStrokeLength(1500), 1.0);
      expect(normalizeStrokeLength(1000000), 1.0);
      expect(normalizeStrokeLength(50), 0.0);
      expect(normalizeStrokeLength(0), 0.0);
    });

    test('포화가 시작되는 길이는 이름 있는 값이다 — 관측할 수 있어야 한다', () {
      const profile = kStrokeLengthProfile;
      expect(normalizeStrokeLength(profile.longest), 1.0);
      expect(normalizeStrokeLength(profile.longest - 1), lessThan(1.0));
      expect(normalizeStrokeLength(profile.shortest), 0.0);
      expect(normalizeStrokeLength(profile.shortest + 1), greaterThan(0.0));
    });
  });

  group('자의 출처는 한 곳', () {
    /// reveal 파이프라인에서 시간·길이를 만지는 파일 전부.
    ///
    ///   원본(앱)의 목록에는 화면 둘(`bag_map_reveal_loader`·`exploration_collage`)이
    ///   더 있었다 — 앱 UI 라 이 레포엔 없다. 나머지 넷은 그대로 옮겼고 그중 렌더 쪽
    ///   둘은 이웃 패키지에 있다(테스트는 패키지 루트에서 도니 `../` 로 건너간다).
    const pipeline = <String>[
      'lib/src/timing/timing_policy.dart',
      'lib/src/timing/texture_compiler.dart',
      '../pen_reveal_flutter/lib/src/reveal_preparer.dart',
      '../pen_reveal_flutter/lib/src/sequential_reveal.dart',
    ];

    String code(String path) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('$path 가 없다 — 테스트를 패키지 루트에서 돌리고 있는지 확인하라');
      }
      return file
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
    }

    test('코퍼스 상수는 정규화 파일에 한 번씩만 있다', () {
      final source = code('lib/src/plan/length_profile.dart');
      for (final literal in const ['124.5', '905.7', '0.35']) {
        expect(
          RegExp(RegExp.escape(literal)).allMatches(source).length,
          1,
          reason: '$literal 이 정규화 파일 안에서도 여러 번 나온다 — 출처가 갈렸다',
        );
      }
    });

    test('표현 계층엔 코퍼스 숫자가 한 톨도 없다', () {
      for (final path in pipeline) {
        final source = code(path);
        for (final literal in const ['124.5', '905.7', '124', '469']) {
          expect(
            source,
            isNot(contains(literal)),
            reason: '$path: 길이의 자($literal)가 표현 계층에 새어 나왔다',
          );
        }
      }
    });
  });

  group('탐지가 실어 보낸다', () {
    test('길 세그먼트엔 언제나 상대 길이가 있다', () {
      final plan = _detect(_road(60));
      final road = plan.segments.firstWhere(
        (s) => s.kind == RevealSegmentKind.primaryStroke,
      );
      expect(road.relativeLength, isNotNull);
      expect(road.relativeLength, inInclusiveRange(0, 1));
    });

    test('정규화를 안 거친 계획은 조용히 넘어가지 않고 실패한다', () {
      // ⚠️ 이걸 안 막으면 모든 지도가 밴드 최소로 붙는다 — 화면에선 "다 같은 속도"인데
      //   테스트는 전부 초록이다(값이 없어서 0 으로 떨어진 것과 최단 지도가 구별 안 된다).
      final bare = RevealPlan(
        width: 2,
        height: 1,
        segmentId: Uint8List(2),
        within: Uint16List(2),
        segments: const [
          RevealSegment(
            id: 0,
            kind: RevealSegmentKind.primaryStroke,
            pixelCount: 2,
            left: 0,
            top: 0,
            right: 1,
            bottom: 0,
            measure: 400,
          ),
        ],
      );
      expect(
        () => const HandwritingRevealTiming().schedule(bare),
        throwsArgumentError,
      );
    });

    test('두 번 재도 같고, 정책이 달라도 계획은 안 변한다', () {
      final composed = _road(70);
      final first = _detect(composed);
      final second = _detect(composed);

      expect(_relativeOf(first), _relativeOf(second));
      expect(first.segmentId, second.segmentId);
      expect(first.within, second.within);

      const narrow = HandwritingRevealTiming();
      const wide = HandwritingRevealTiming(
        primaryMinDuration: Duration(milliseconds: 800),
        primaryMaxDuration: Duration(milliseconds: 3000),
      );
      expect(
        narrow.schedule(first).windows.map((w) => w.segmentId),
        wide.schedule(first).windows.map((w) => w.segmentId),
      );
      expect(
        narrow.schedule(first).total,
        isNot(wide.schedule(first).total),
        reason: '밴드를 바꿨는데 시간이 그대로면 0~1 이 안 쓰인 것이다',
      );
      // 정책을 돌려도 계획은 읽기 전용이다.
      expect(_relativeOf(first), _relativeOf(second));
    });

    test('순서를 섞거나 여러 번 재도 값이 안 흔들린다 — 전역 상태가 없다', () {
      const heights = [20, 30, 40, 55, 65, 70, 80, 90, 100, 105];
      final inOrder = {
        for (final h in heights) h: _relativeOf(_detect(_road(h))),
      };
      for (final h in heights.reversed) {
        expect(_relativeOf(_detect(_road(h))), inOrder[h], reason: '$h 가 흔들렸다');
      }
      final repeated = heights[4];
      final again = [
        for (var i = 0; i < 3; i++) _relativeOf(_detect(_road(repeated))),
      ];
      expect(again.toSet(), hasLength(1));
    });
  });
}
