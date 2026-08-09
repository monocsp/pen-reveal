// 일정 → 단계 경계. **없는 단계를 앞으로 접는 규칙**이 이 파일의 본론이다.
//
//   X 탐지는 관문 넷을 다 통과해야 성공한다(`detector.dart`). 실패하면 붉은 픽셀이 전부
//   덩어리로 돌아가 X 세그먼트가 아예 없는 계획이 나온다. 그때 crossEnd 를 0 으로 두면
//   "X 까지 감기" 가 연출을 되감아 버리므로, 단조성을 지키는 쪽이 언제나 안전하다.
@Tags(['regression'])
library;

import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

RevealSegment _seg(int id, RevealSegmentKind kind, {double? relativeLength}) =>
    RevealSegment(
      id: id,
      kind: kind,
      pixelCount: 100,
      left: 0,
      top: 0,
      right: 9,
      bottom: 9,
      measure: 50,
      relativeLength: relativeLength,
    );

RevealPlan _plan(List<RevealSegment> segments) => RevealPlan(
      width: 4,
      height: 4,
      segmentId: Uint8List(16),
      within: Uint16List(16),
      segments: segments,
    );

void main() {
  const timing = HandwritingRevealTiming();

  group('단계 경계', () {
    test('길 → X → 덩어리가 다 있으면 셋이 순서대로 벌어진다', () {
      final plan = _plan([
        _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0.5),
        _seg(1, RevealSegmentKind.crossBackslash),
        _seg(2, RevealSegmentKind.crossSlash),
        _seg(3, RevealSegmentKind.annotation),
        _seg(4, RevealSegmentKind.annotation),
      ]);
      final marks = RevealStageMarks.of(plan, timing.schedule(plan));

      expect(marks.primaryEnd, greaterThan(0));
      expect(marks.crossEnd, greaterThan(marks.primaryEnd));
      expect(marks.annotationEnd, greaterThan(marks.crossEnd));
      expect(marks.annotationEnd, closeTo(1, 1e-9));
      expect(marks.hasCross, isTrue);
      expect(marks.hasAnnotation, isTrue);
    });

    test('경계는 언제나 0~1 안에서 단조 증가한다', () {
      final plan = _plan([
        _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 1),
        _seg(1, RevealSegmentKind.crossBackslash),
        _seg(2, RevealSegmentKind.crossSlash),
        _seg(3, RevealSegmentKind.annotation),
      ]);
      final marks = RevealStageMarks.of(plan, timing.schedule(plan));

      expect(marks.inOrder, orderedEquals(<double>[...marks.inOrder]..sort()));
      for (final v in marks.inOrder) {
        expect(v, inInclusiveRange(0, 1));
      }
    });

    test(
      'X 가 없으면 crossEnd 가 primaryEnd 로 접힌다 — 되감기지 않는다',
      () {
        final plan = _plan([
          _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0.5),
          _seg(1, RevealSegmentKind.annotation),
        ]);
        final marks = RevealStageMarks.of(plan, timing.schedule(plan));

        expect(marks.crossEnd, marks.primaryEnd);
        expect(marks.hasCross, isFalse);
        expect(marks.annotationEnd, greaterThan(marks.crossEnd));
        // 되감김 금지 — 이게 이 규칙의 존재 이유다.
        expect(marks.crossEnd, greaterThanOrEqualTo(marks.primaryEnd));
      },
    );

    test('덩어리가 없으면 annotationEnd 가 crossEnd 로 접힌다', () {
      final plan = _plan([
        _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0.2),
        _seg(1, RevealSegmentKind.crossBackslash),
        _seg(2, RevealSegmentKind.crossSlash),
      ]);
      final marks = RevealStageMarks.of(plan, timing.schedule(plan));

      expect(marks.annotationEnd, marks.crossEnd);
      expect(marks.hasAnnotation, isFalse);
      expect(marks.crossEnd, closeTo(1, 1e-9));
    });

    test('빈 계획이면 셋 다 0 — 컨트롤러가 0초짜리를 받는 상황과 맞는다', () {
      final plan = _plan([]);
      final marks = RevealStageMarks.of(plan, timing.schedule(plan));

      expect(marks.primaryEnd, 0);
      expect(marks.crossEnd, 0);
      expect(marks.annotationEnd, 0);
      expect(marks.hasCross, isFalse);
    });

    test('길만 있으면 셋 다 1 로 모인다', () {
      final plan =
          _plan([_seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0)]);
      final marks = RevealStageMarks.of(plan, timing.schedule(plan));

      expect(marks.primaryEnd, closeTo(1, 1e-9));
      expect(marks.crossEnd, closeTo(1, 1e-9));
      expect(marks.annotationEnd, closeTo(1, 1e-9));
    });

    test('경계가 실제 창 끝과 일치한다 — 눈대중이 아니다', () {
      final plan = _plan([
        _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0.5),
        _seg(1, RevealSegmentKind.crossBackslash),
        _seg(2, RevealSegmentKind.crossSlash),
        _seg(3, RevealSegmentKind.annotation),
      ]);
      final schedule = timing.schedule(plan);
      final marks = RevealStageMarks.of(plan, schedule);

      expect(marks.primaryEnd, schedule.windows[0].end);
      expect(marks.crossEnd, schedule.windows[2].end);
      expect(marks.annotationEnd, schedule.windows[3].end);
    });

    test('single 은 단계 구분이 없는 한 덩어리다', () {
      expect(RevealStageMarks.single.primaryEnd, 1);
      expect(RevealStageMarks.single.hasCross, isFalse);
      expect(RevealStageMarks.single.hasAnnotation, isFalse);
    });
  });
}
