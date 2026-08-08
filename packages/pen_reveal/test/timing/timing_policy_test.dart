// 타이밍 정책의 경계값을 잠근다 — 시간에 관한 모든 결정이 여기 한 곳에 있는지.
//
//   ⚠️ 2026-08-07 부터 **길이는 픽셀로 안 들어온다.** 구조 층(`length_profile.dart`)이
//   "코퍼스 안에서 얼마나 긴가"를 0~1(`RevealSegment.relativeLength`)로 접어 주고, 여기서는
//   그걸 밴드(최소~최대)에 선형으로 얹기만 한다. 그래서 이 파일이 보는 것은 두 가지다:
//     · **환산이 진짜 선형인가**(지수·기준 길이가 몰래 다시 들어오지 않았나)
//     · **밴드를 갈아 끼우면 주 획 시간만 움직이는가**(X·문구·쉼은 그대로)
import 'dart:io';
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

RevealSegment segment(
  int id,
  RevealSegmentKind kind, {
  double measure = 20,
  double? relativeLength,
}) {
  return RevealSegment(
    id: id,
    kind: kind,
    pixelCount: 10,
    left: 0,
    top: 0,
    right: 9,
    bottom: 9,
    measure: measure,
    relativeLength: relativeLength ??
        (kind == RevealSegmentKind.primaryStroke ? 0.0 : null),
  );
}

RevealPlan planOf(List<RevealSegment> segments) {
  return RevealPlan(
    width: 4,
    height: 4,
    segmentId: Uint8List(16)..fillRange(0, 16, kRevealHiddenSegment),
    within: Uint16List(16),
    segments: segments,
  );
}

/// 주 획 + X 두 획 + 문구 둘 — 실제 지도와 같은 모양의 계획.
RevealPlan fullPlan(double relativeLength) {
  return planOf([
    segment(0, RevealSegmentKind.primaryStroke, relativeLength: relativeLength),
    segment(1, RevealSegmentKind.crossBackslash),
    segment(2, RevealSegmentKind.crossSlash),
    segment(3, RevealSegmentKind.annotation, measure: 30),
    segment(4, RevealSegmentKind.annotation, measure: 30),
  ]);
}

/// 창 하나의 **절대 시간**(ms) — 정규화 좌표가 아니라 실제로 몇 밀리초인지.
double spanMillis(RevealSchedule schedule, int index) {
  final window = schedule.windows[index];
  return (window.end - window.start) * schedule.total.inMilliseconds;
}

/// 창 앞의 쉼(ms).
double gapMillis(RevealSchedule schedule, int index) {
  final previousEnd = index == 0 ? 0.0 : schedule.windows[index - 1].end;
  return (schedule.windows[index].start - previousEnd) *
      schedule.total.inMilliseconds;
}

/// 주 획 창의 절대 시간 — **X·문구가 다 있는 계획**에서 잰다.
int primaryMillis(HandwritingRevealTiming policy, double relativeLength) =>
    spanMillis(policy.schedule(fullPlan(relativeLength)), 0).round();

/// 정본 10종의 (이름, 상대 길이, 밴드 500~2000 에서의 주 획 시간).
///   밴드는 사용자 확정값이다(2026-08-07 — "가장 짧은시간은 500milisecond 긴시간은 2초").
///
///   ⚠️ 시간은 **손으로 계산해 박은 리터럴**이다. `lerp` 를 다시 부르면 "구현이 곧
///   기대값"이 되어 아무것도 안 잡는다.
const List<(String name, double relative, int millis)> corpus = [
  ('map_basic_03', 0.000, 500),
  ('map_basic_01', 0.131, 697),
  ('map_basic_02', 0.151, 727),
  ('map_deep_01', 0.517, 1276),
  ('map_deep_03', 0.804, 1706),
  ('map_deep_04', 0.847, 1771),
  ('map_deep_02', 0.947, 1921),
  ('map_deep_06', 0.947, 1921),
  ('map_special_01', 0.964, 1946),
  ('map_deep_05', 1.000, 2000),
];

const HandwritingRevealTiming wideBand = HandwritingRevealTiming(
  primaryMinDuration: Duration(milliseconds: 800),
  primaryMaxDuration: Duration(milliseconds: 3000),
);

void main() {
  const policy = HandwritingRevealTiming();

  group('일정 짜기', () {
    test('창은 순서대로 겹치지 않고 늘어선다', () {
      final schedule = policy.schedule(fullPlan(0.6));

      expect(schedule.windows, hasLength(5));
      for (var i = 0; i < schedule.windows.length; i++) {
        final window = schedule.windows[i];
        expect(window.segmentId, i);
        expect(window.start, lessThan(window.end));
        if (i > 0) {
          expect(
            window.start,
            greaterThanOrEqualTo(schedule.windows[i - 1].end),
            reason: '$i 번 창이 앞 창과 겹친다',
          );
        }
      }
      expect(schedule.windows.first.start, 0);
      expect(schedule.windows.last.end, closeTo(1, 1e-9));
    });

    test(r'`\` 창이 `/` 창보다 앞서고, 문구는 X 가 끝난 뒤에 시작한다', () {
      final schedule = policy.schedule(fullPlan(0.5));

      expect(
        schedule.windows[1].end,
        lessThanOrEqualTo(schedule.windows[2].start),
      );
      expect(
        schedule.windows[3].start,
        greaterThan(schedule.windows[2].end),
        reason: '문구가 X 를 다 긋기 전에 시작한다',
      );
    });

    test('두 획 사이에 쉼이 있다 — 진짜 펜도 여기서 뗀다', () {
      final schedule = policy.schedule(
        planOf([
          segment(0, RevealSegmentKind.crossBackslash),
          segment(1, RevealSegmentKind.crossSlash),
        ]),
      );

      expect(
        schedule.windows[1].start,
        greaterThan(schedule.windows[0].end),
        reason: r'`\` 가 끝나자마자 `/` 가 시작하면 한 획처럼 보인다',
      );
    });

    test('빈 계획은 빈 일정 + 0 길이', () {
      final schedule = policy.schedule(planOf(const []));
      expect(schedule.windows, isEmpty);
      expect(schedule.total, Duration.zero);
    });

    test('세그먼트가 하나뿐이어도 온전한 일정이 나온다', () {
      for (final kind in RevealSegmentKind.values) {
        final schedule = policy.schedule(planOf([segment(0, kind)]));
        expect(schedule.windows, hasLength(1), reason: '$kind');
        expect(schedule.windows.single.start, 0, reason: '$kind — 앞에 쉼이 붙었다');
        expect(schedule.windows.single.end, closeTo(1, 1e-9), reason: '$kind');
        expect(schedule.total, greaterThan(Duration.zero), reason: '$kind');
      }
    });
  });

  group('0~1 → 밴드', () {
    test('선형이다 — 0·0.25·0.5·0.75·1 이 밴드를 정확히 4등분한다', () {
      const expected = <(double, int)>[
        (0.0, 500),
        (0.25, 875),
        (0.5, 1250),
        (0.75, 1625),
        (1.0, 2000),
      ];
      for (final (relative, millis) in expected) {
        expect(
          primaryMillis(policy, relative),
          closeTo(millis, 1),
          reason: '$relative 가 밴드 위 제자리에 없다 — 지수가 다시 끼어들었다',
        );
      }
    });

    test('정본 10종 — 손계산 표와 ±3ms', () {
      for (final (name, relative, millis) in corpus) {
        expect(
          primaryMillis(policy, relative),
          closeTo(millis, 3),
          reason: name,
        );
      }
    });

    test('주 획 창은 total 이 아니라 **창**으로 재도 같다', () {
      // ⚠️ 주 획만 있는 계획의 total 로 재면 X·문구가 없어 함정을 지나친다.
      for (final relative in const [0.0, 0.3, 0.7, 1.0]) {
        final lone = planOf([
          segment(0, RevealSegmentKind.primaryStroke, relativeLength: relative),
        ]);
        final total = policy.schedule(lone).total.inMilliseconds;
        expect(primaryMillis(policy, relative), closeTo(total, 2));
      }
    });

    test('밴드를 갈아 끼우면 주 획만 움직인다 — X·문구·쉼의 절대 ms 는 그대로', () {
      const relative = 0.42;
      final narrow = policy.schedule(fullPlan(relative));
      final wide = wideBand.schedule(fullPlan(relative));

      expect(spanMillis(wide, 0), closeTo(800 + 2200 * relative, 2));
      expect(spanMillis(narrow, 0), closeTo(500 + 1500 * relative, 2));

      expect(wide.windows.length, narrow.windows.length);
      for (var i = 1; i < narrow.windows.length; i++) {
        expect(
          spanMillis(wide, i),
          closeTo(spanMillis(narrow, i), 1),
          reason: '$i 번 창의 길이가 밴드에 딸려 움직였다',
        );
        expect(
          gapMillis(wide, i),
          closeTo(gapMillis(narrow, i), 1),
          reason: '$i 번 창 앞의 쉼이 밴드에 딸려 움직였다',
        );
        expect(wide.windows[i].segmentId, narrow.windows[i].segmentId);
      }
    });

    test('다른 밴드에서도 끝점이 정확하다 — 클램프가 안 끼어든다', () {
      expect(primaryMillis(wideBand, 0), closeTo(800, 1));
      expect(primaryMillis(wideBand, 0.5), closeTo(1900, 1));
      expect(primaryMillis(wideBand, 1), closeTo(3000, 1));
    });

    test('0~1 밖은 잘라 쓴다', () {
      expect(primaryMillis(policy, -0.5), 500);
      expect(primaryMillis(policy, 1.5), 2000);
    });

    test('길수록 오래 — 0~1 을 훑어도 안 뒤집힌다', () {
      var previous = 0;
      for (var i = 0; i <= 100; i++) {
        final millis = primaryMillis(policy, i / 100);
        expect(millis, greaterThanOrEqualTo(previous));
        previous = millis;
      }
    });

    test('퇴화한 밴드(1500~1500)면 전부 1500 — 0 으로 나누지 않는다', () {
      const flat = HandwritingRevealTiming(
        primaryMinDuration: Duration(milliseconds: 1500),
        primaryMaxDuration: Duration(milliseconds: 1500),
      );
      for (final (name, relative, _) in corpus) {
        expect(primaryMillis(flat, relative), 1500, reason: name);
        expect(
          flat.schedule(fullPlan(relative)).total.inMilliseconds,
          greaterThan(0),
        );
      }
    });

    test('뒤집힌 밴드(min > max)는 정렬해 받는다 — 터지지도, 음수도 아니다', () {
      const flipped = HandwritingRevealTiming(
        primaryMinDuration: Duration(milliseconds: 2000),
        primaryMaxDuration: Duration(milliseconds: 500),
      );
      for (final (name, relative, millis) in corpus) {
        expect(
          primaryMillis(flipped, relative),
          closeTo(millis, 3),
          reason: name,
        );
      }
    });

    test('정규화를 안 거친 주 획은 밴드 최소로 떨어지지 않고 실패한다', () {
      final bare = planOf([
        const RevealSegment(
          id: 0,
          kind: RevealSegmentKind.primaryStroke,
          pixelCount: 10,
          left: 0,
          top: 0,
          right: 9,
          bottom: 9,
          measure: 400,
        ),
      ]);
      expect(() => policy.schedule(bare), throwsArgumentError);
    });
  });

  group('뭉치지 않는다 — 사용자가 지적한 결함', () {
    List<int> durationsOf(HandwritingRevealTiming p) {
      return [
        for (final (_, relative, _) in corpus) primaryMillis(p, relative),
      ];
    }

    /// ±[slack] ms 로 묶은 값들의 크기.
    List<int> clusterSizes(List<int> values, {int slack = 3}) {
      final sorted = [...values]..sort();
      final sizes = <int>[];
      var count = 1;
      for (var i = 1; i < sorted.length; i++) {
        if (sorted[i] - sorted[i - 1] <= slack) {
          count++;
        } else {
          sizes.add(count);
          count = 1;
        }
      }
      return sizes..add(count);
    }

    test('간격이 상대 길이 차이를 그대로 옮긴다', () {
      const band = 2000 - 500;
      final durations = durationsOf(policy);
      for (var i = 0; i < corpus.length; i++) {
        for (var j = i + 1; j < corpus.length; j++) {
          final gap = (durations[i] - durations[j]).abs() / band;
          final expected = (corpus[i].$2 - corpus[j].$2).abs();
          expect(
            gap,
            closeTo(expected, 0.005),
            reason: '${corpus[i].$1} ↔ ${corpus[j].$1}',
          );
        }
      }
    });

    test('열 지도가 아홉 자리로 흩어진다 — 동률은 같은 길이인 둘뿐', () {
      final sizes = clusterSizes(durationsOf(policy));
      expect(sizes.length, greaterThanOrEqualTo(9), reason: '고유값이 아홉보다 적다');
      expect(
        sizes.reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(2),
        reason: '셋 이상이 같은 속도로 그려진다',
      );
    });

    test('밴드 양끝에 하나씩만 붙는다 — 바닥 뭉침이 여기서 잡힌다', () {
      final durations = durationsOf(policy);
      expect(durations.where((d) => (d - 500).abs() <= 3).length, 1);
      expect(durations.where((d) => (d - 2000).abs() <= 3).length, 1);
    });

    test('밴드를 거의 다 쓰고, 이웃 사이가 밴드의 45% 를 안 넘는다', () {
      for (final p in const [policy, wideBand]) {
        final low = p.primaryMinDuration.inMilliseconds;
        final band = p.primaryMaxDuration.inMilliseconds - low;
        final sorted = durationsOf(p)..sort();
        expect(
          (sorted.last - sorted.first) / band,
          greaterThanOrEqualTo(0.90),
          reason: '밴드를 다 안 쓴다',
        );
        var widest = 0;
        for (var i = 1; i < sorted.length; i++) {
          final gap = sorted[i] - sorted[i - 1];
          if (gap > widest) widest = gap;
        }
        expect(widest / band, lessThanOrEqualTo(0.45), reason: '가운데가 텅 비었다');
      }
    });

    test('넓은 밴드에서도 같은 성질 — 특정 밴드에 기댄 것이 아니다', () {
      final durations = durationsOf(wideBand);
      final sizes = clusterSizes(durations);
      expect(sizes.length, greaterThanOrEqualTo(9));
      expect(sizes.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(2));
      expect(durations.where((d) => (d - 800).abs() <= 3).length, 1);
      expect(durations.where((d) => (d - 3000).abs() <= 3).length, 1);
    });

    test('⚠️ 자를 옛 값(469)으로 되돌리면 위 세 판정이 전부 뒤집힌다', () {
      // 이 시험이 없으면 위 판정들이 "아무것도 안 잡는 초록"일 수 있다.
      //   옛 자 = 코퍼스 최단을 469 로 본 것 — 실제 최단 넷이 전부 바닥에 붙는다.
      const old = StrokeLengthProfile(shortest: 469);
      const lengths = <double>[
        124.5,
        177.3,
        186.4,
        410.6,
        674.5,
        721.6,
        839.2,
        839.2,
        859.6,
        905.7,
      ];
      final durations = [
        for (final length in lengths)
          primaryMillis(policy, normalizeStrokeLength(length, profile: old)),
      ];
      expect(
        durations.where((d) => (d - 500).abs() <= 3).length,
        greaterThan(1),
        reason: '옛 자인데도 바닥에 하나만 붙는다 — 뭉침 판정이 무력하다',
      );
      expect(
        clusterSizes(durations).length,
        lessThan(9),
        reason: '옛 자인데도 아홉 자리로 흩어진다 — 흩어짐 판정이 무력하다',
      );
      expect(
        clusterSizes(durations).reduce((a, b) => a > b ? a : b),
        greaterThan(2),
        reason: '옛 자인데도 동률이 둘 이하다',
      );
    });
  });

  group('문구 덩어리 → 시간 (픽셀 자 그대로)', () {
    int chunkMillis(double width) {
      final plan = planOf([
        segment(0, RevealSegmentKind.annotation, measure: width),
      ]);
      return spanMillis(policy.schedule(plan), 0).round();
    }

    test('넓은 덩어리가 더 오래 써진다 — 가운데 값도 잠근다', () {
      expect(chunkMillis(40), greaterThan(chunkMillis(20)));
      expect(chunkMillis(30), 120, reason: '4ms/px 가 바뀌었다');
    });

    test('위아래로 묶인다 — 1px 덩어리도 보이고, 큰 그림도 안 늘어진다', () {
      expect(chunkMillis(1), 70);
      expect(chunkMillis(10000), 220);
    });

    test('X 두 획과 그 사이 쉼은 주 획 밴드와 무관하다', () {
      for (final p in const [policy, wideBand]) {
        final schedule = p.schedule(fullPlan(0.9));
        expect(spanMillis(schedule, 1).round(), 220);
        expect(spanMillis(schedule, 2).round(), 220);
        expect(gapMillis(schedule, 2).round(), 50);
        expect(gapMillis(schedule, 1).round(), 120);
        expect(gapMillis(schedule, 3).round(), 160);
        expect(gapMillis(schedule, 4).round(), 30);
      }
    });
  });

  group('가감속', () {
    test('선형은 그대로', () {
      const ease = LinearEase();
      expect(ease.timeOf(0), 0);
      expect(ease.timeOf(0.5), 0.5);
      expect(ease.timeOf(1), 1);
    });

    test('펜 가감속은 양끝을 고정하고 단조증가한다', () {
      const ease = PenEase();
      expect(ease.timeOf(0), closeTo(0, 1e-9));
      expect(ease.timeOf(1), closeTo(1, 1e-9));

      var previous = -1.0;
      for (var i = 0; i <= 100; i++) {
        final value = ease.timeOf(i / 100);
        expect(value, greaterThanOrEqualTo(previous));
        expect(value, inInclusiveRange(0, 1));
        previous = value;
      }
    });

    test('앞뒤가 느리다 — 같은 시간에 가운데가 더 많이 그어진다', () {
      const ease = PenEase();
      final head = ease.timeOf(0.1) - ease.timeOf(0);
      final middle = ease.timeOf(0.55) - ease.timeOf(0.45);
      final tail = ease.timeOf(1) - ease.timeOf(0.9);

      expect(head, greaterThan(middle));
      expect(tail, greaterThan(middle));
      expect(head, closeTo(tail, 1e-9), reason: '앞뒤가 대칭이어야 한다');
    });

    test('가감속 구간이 0 이면 선형', () {
      const ease = PenEase(edgeFraction: 0);
      expect(ease.timeOf(0.3), closeTo(0.3, 1e-9));
    });

    test('범위를 벗어난 입력은 잘라 쓴다', () {
      const ease = PenEase();
      expect(ease.timeOf(-5), 0);
      expect(ease.timeOf(5), 1);
    });
  });

  group('소유 지점', () {
    test('주 획 관련 생성자 인자는 밴드 둘뿐이다', () {
      const path = 'lib/src/timing/timing_policy.dart';
      const head = 'const HandwritingRevealTiming({';
      final source = File(path).readAsStringSync();
      final from = source.indexOf(head);
      final constructor = source.substring(from, source.indexOf('});', from));
      final matches = RegExp(r'this\.(primary\w+)').allMatches(constructor);
      final primaryArgs = matches.map((m) => m.group(1)).toList();
      expect(
        primaryArgs,
        const ['primaryMinDuration', 'primaryMaxDuration', 'primaryToCrossGap'],
        reason: '주 획 길이의 자가 다시 생성자에 들어왔다',
      );
    });

    // 원본의 둘째 시험 '밴드 기본값을 만드는 곳은 lib 전체에서 한 군데' 는 여기 없다 —
    //   `lib/design_system`·`lib/feature`·`lib/core` 를 훑는 단언이라 경로가 앱 폴더
    //   구조에 묶여 있었다. 이 패키지에서 같은 경계(구조 층 vs 표현 층, 그리고 상수를
    //   한 곳만 소유하는 것)는 `test/purity_test.dart` 가 소스를 직접 읽어 지킨다.

    // 「기대값을 공식으로 다시 쓰지 않았다」(이 파일이 지수 함수를 안 부른다)는
    //   `purity_test` 가 본다 — 여기서 자기 소스를 읽으면 검사 문자열 자체가 걸려
    //   영영 빨갛다.
  });

  test('정책을 갈아 끼우면 시간만 바뀐다 — 순서는 계획이 정한다', () {
    final plan = fullPlan(0.3);
    const slow = HandwritingRevealTiming(
      crossStrokeDuration: Duration(milliseconds: 900),
    );

    expect(slow.schedule(plan).total, greaterThan(policy.schedule(plan).total));
    expect(
      slow.schedule(plan).windows.map((w) => w.segmentId),
      policy.schedule(plan).windows.map((w) => w.segmentId),
    );
    expect(
      wideBand.schedule(plan).windows.map((w) => w.segmentId),
      policy.schedule(plan).windows.map((w) => w.segmentId),
    );
  });
}
