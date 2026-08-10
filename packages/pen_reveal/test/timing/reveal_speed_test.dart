// 단계별 배속 — 바깥에서 "길·X·글씨" 를 따로 빠르게/느리게 하는 손잡이.
//
//   왜 필요한가: `HandwritingRevealTiming` 의 손잡이 열둘은 전부 저수준이라, 한 단계를
//   옮기려면 여러 값을 **같이** 맞춰야 한다("길만 두 배 빠르게" = min·max 둘 다,
//   "글씨만" = perPixel·min·max 셋). 하나만 고치면 실측 비율이 조용히 깨진다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

RevealSegment _seg(
  int id,
  RevealSegmentKind kind, {
  double relativeLength = 0.5,
}) =>
    RevealSegment(
      id: id,
      kind: kind,
      pixelCount: 100,
      left: 0,
      top: 0,
      right: 99,
      bottom: 9,
      measure: 100,
      relativeLength: relativeLength,
    );

RevealPlan _plan() => RevealPlan(
      width: 4,
      height: 4,
      segmentId: Uint8List(16),
      within: Uint16List(16),
      segments: [
        _seg(0, RevealSegmentKind.primaryStroke),
        _seg(1, RevealSegmentKind.crossBackslash),
        _seg(2, RevealSegmentKind.crossSlash),
        _seg(3, RevealSegmentKind.annotation),
        _seg(4, RevealSegmentKind.annotation),
      ],
    );

/// 한 세그먼트가 차지하는 **밀리초** — 창은 0~1 이라 총 길이를 곱해야 견줄 수 있다.
double _millisOf(RevealSchedule s, int id) {
  final w = s.windows.firstWhere((w) => w.segmentId == id);
  return (w.end - w.start) * s.total.inMilliseconds;
}

void main() {
  final plan = _plan();
  const base = HandwritingRevealTiming();
  final baseline = base.schedule(plan);

  group('배속은 그 단계만 움직인다', () {
    test('길 2배속 — 길만 절반, X·글씨는 그대로', () {
      final fast = const HandwritingRevealTiming(
        speed: RevealSpeed(road: 2),
      ).schedule(plan);

      expect(
        _millisOf(fast, 0),
        closeTo(_millisOf(baseline, 0) / 2, 1.5),
        reason: '길이 절반으로 안 줄었다',
      );
      for (final id in [1, 2, 3, 4]) {
        expect(
          _millisOf(fast, id),
          closeTo(_millisOf(baseline, id), 1.5),
          reason: '세그먼트 $id 가 같이 움직였다 — 배속이 단계를 넘어 샜다',
        );
      }
    });

    test('글씨 2배속 — 글씨만 절반', () {
      final fast = const HandwritingRevealTiming(
        speed: RevealSpeed(annotation: 2),
      ).schedule(plan);

      for (final id in [3, 4]) {
        expect(
          _millisOf(fast, id),
          closeTo(_millisOf(baseline, id) / 2, 1.5),
          reason: '글씨 $id 가 안 줄었다',
        );
      }
      expect(_millisOf(fast, 0), closeTo(_millisOf(baseline, 0), 1.5));
      expect(_millisOf(fast, 1), closeTo(_millisOf(baseline, 1), 1.5));
    });

    test('X 2배속 — X 두 획만 절반', () {
      final fast = const HandwritingRevealTiming(
        speed: RevealSpeed(cross: 2),
      ).schedule(plan);

      for (final id in [1, 2]) {
        expect(
          _millisOf(fast, id),
          closeTo(_millisOf(baseline, id) / 2, 1.5),
          reason: 'X 획 $id 가 안 줄었다',
        );
      }
      expect(_millisOf(fast, 3), closeTo(_millisOf(baseline, 3), 1.5));
    });

    test('전체 2배속이면 재생 시간이 대략 절반이다', () {
      final fast = const HandwritingRevealTiming(
        speed: RevealSpeed.all(2),
      ).schedule(plan);
      expect(
        fast.total.inMilliseconds,
        closeTo(baseline.total.inMilliseconds / 2, 6),
        reason: '반올림 오차를 빼면 절반이어야 한다',
      );
    });

    test('쉼 배속은 획 길이를 안 건드린다', () {
      final tight = const HandwritingRevealTiming(
        speed: RevealSpeed(gaps: 4),
      ).schedule(plan);
      for (final id in [0, 1, 2, 3, 4]) {
        expect(
          _millisOf(tight, id),
          closeTo(_millisOf(baseline, id), 1.5),
          reason: '쉼만 줄였는데 세그먼트 $id 의 길이가 바뀌었다',
        );
      }
      expect(
        tight.total.inMilliseconds,
        lessThan(baseline.total.inMilliseconds),
        reason: '쉼이 줄었으면 총 길이는 짧아져야 한다',
      );
    });
  });

  group('무너지지 않게 막는 것', () {
    test('0 이나 음수는 못 준다', () {
      expect(() => RevealSpeed(road: 0), throwsA(isA<AssertionError>()));
      expect(() => RevealSpeed(cross: -1), throwsA(isA<AssertionError>()));
      expect(() => RevealSpeed.all(0), throwsA(isA<AssertionError>()));
    });

    // ⚠️ 아주 빠른 배속에서 span 이 0 이 되면 그 세그먼트는 창이 없는 것과 같아져
    //   **영영 안 드러난다.** 1ms 를 남긴다.
    test('말도 안 되게 빠르게 해도 세그먼트가 사라지지 않는다', () {
      final blur = const HandwritingRevealTiming(
        speed: RevealSpeed.all(100000),
      ).schedule(plan);
      expect(blur.windows.length, plan.segments.length);
      for (final w in blur.windows) {
        expect(
          w.end,
          greaterThan(w.start),
          reason: '세그먼트 ${w.segmentId} 의 창이 0 이다 — 영영 안 드러난다',
        );
      }
    });

    test('경계는 여전히 순서대로다', () {
      final fast = const HandwritingRevealTiming(
        speed: RevealSpeed(road: 3, annotation: 0.5),
      ).schedule(plan);
      final marks = RevealStageMarks.of(plan, fast);
      expect(marks.primaryEnd, lessThan(marks.crossEnd));
      expect(marks.crossEnd, lessThan(marks.annotationEnd));
    });
  });

  group('값 동등성 — 없으면 다시 굽지 않는다', () {
    test('같은 배속이면 정책도 같다', () {
      RevealSpeed s(double v) => RevealSpeed(road: v);
      expect(
        HandwritingRevealTiming(speed: s(2)),
        HandwritingRevealTiming(speed: s(2)),
      );
      expect(
        HandwritingRevealTiming(speed: s(2)).hashCode,
        HandwritingRevealTiming(speed: s(2)).hashCode,
      );
    });

    // ⚠️ 이게 무너지면 계측대가 손잡이를 돌려도 옛 텍스처를 그대로 쓴다.
    test('배속이 다르면 정책도 다르다', () {
      RevealSpeed s(double v) => RevealSpeed(annotation: v);
      expect(
        HandwritingRevealTiming(speed: s(2)),
        isNot(HandwritingRevealTiming(speed: s(3))),
      );
      // 기본값과 "명시적으로 1" 이 같아야 손잡이를 되돌렸을 때 다시 안 굽는다.
      //   ⚠️ 런타임에 만든다 — const 두 개는 컴파일러가 한 객체로 접어
      //   `identical` 가지에서 통과하므로 `==` 를 지워도 초록이다.
      expect(
        const HandwritingRevealTiming(),
        HandwritingRevealTiming(speed: s(1)),
      );
    });

    test('copyWith 는 준 것만 바꾼다', () {
      const from = RevealSpeed(road: 2, annotation: 3);
      final to = from.copyWith(cross: 4);
      expect(to.road, 2);
      expect(to.annotation, 3);
      expect(to.cross, 4);
      expect(to.gaps, 1);
    });
  });
}
