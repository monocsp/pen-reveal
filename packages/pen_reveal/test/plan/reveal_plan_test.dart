// 계획이 들고 다니는 두 값 — **픽셀 자(measure)** 와 **0~1 상대 길이** 의 역할 분담.
//
//   해상도 환산은 픽셀 자에만 걸어야 한다. 0~1 은 이미 기준 해상도로 접힌 값이라 다시
//   곱하면 같은 그림이 굽기 해상도마다 다른 속도로 그려진다.
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

RevealSegment _road(double measure, double relative) => RevealSegment(
      id: 0,
      kind: RevealSegmentKind.primaryStroke,
      pixelCount: 10,
      left: 0,
      top: 0,
      right: 9,
      bottom: 9,
      measure: measure,
      relativeLength: relative,
    );

RevealSegment _other(int id, RevealSegmentKind kind, double measure) =>
    RevealSegment(
      id: id,
      kind: kind,
      pixelCount: 10,
      left: 0,
      top: 0,
      right: 9,
      bottom: 9,
      measure: measure,
    );

void main() {
  test('자를 2배 해도 길의 0~1 은 그대로 — 문구·X 의 픽셀 자만 늘어난다', () {
    final plan = RevealPlan(
      width: 4,
      height: 4,
      segmentId: Uint8List(16)..fillRange(0, 16, kRevealHiddenSegment),
      within: Uint16List(16),
      segments: [
        _road(400, 0.42),
        _other(1, RevealSegmentKind.crossBackslash, 30),
        _other(2, RevealSegmentKind.annotation, 25),
      ],
    );

    final scaled = plan.scaleMeasures(2);

    expect(scaled.segments[0].relativeLength, 0.42, reason: '0~1 에 해상도를 또 곱했다');
    expect(scaled.segments[0].measure, 800);
    expect(scaled.segments[1].measure, 60);
    expect(scaled.segments[2].measure, 50);
    // 픽셀 배열은 공유한다(21만 개를 다시 복사할 이유가 없다).
    expect(identical(scaled.segmentId, plan.segmentId), isTrue);
    expect(identical(scaled.within, plan.within), isTrue);
  });

  test('길이 아닌 세그먼트엔 0~1 이 없다 — 문구 시간은 픽셀 자로 정한다', () {
    expect(_other(1, RevealSegmentKind.annotation, 25).relativeLength, isNull);
    expect(
      _other(
        1,
        RevealSegmentKind.annotation,
        25,
      ).scaleMeasure(3).relativeLength,
      isNull,
    );
  });
}
