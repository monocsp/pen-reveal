// src/timing/stage_marks.dart — 일정에서 **단계 경계**만 뽑아 낸다.
//
//   `RevealSchedule.windows` 는 세그먼트 하나하나의 창을 다 들고 있다(길 1 + X 2 + 덩어리
//   6~11). 그런데 밖에서 알고 싶은 것은 대개 셋뿐이다 — "길이 다 파진 순간", "X 를 다 그은
//   순간", "전부 끝난 순간". 데모의 단계 정지, 소리·햅틱 얹기, 연출 중간에 다른 것을
//   띄우는 일이 전부 그 셋에 걸린다.
//
//   창 목록을 통째로 밖에 내보내지 않는 이유: 세그먼트 개수는 그림마다 다르고(덩어리가
//   6개인지 11개인지) 호출부가 그걸 알아야 할 이유가 없다. 종류로 접어 주면 그림이 달라져도
//   호출부 코드가 안 바뀐다.
//
//   ⚠️ **값은 0~1 진행도지 시간이 아니다.** 컨트롤러가 선형이라 진행도와 시간이 비례하므로
//   밀리초가 필요하면 호출부가 `revealDuration` 을 곱하면 된다. 여기에 Duration 을 두면
//   같은 정보가 두 벌이 되고, 속도 배율을 걸었을 때 한쪽이 거짓말을 한다.
import 'package:pen_reveal/src/plan/reveal_plan.dart';
import 'package:pen_reveal/src/timing/timing_policy.dart';

/// 연출을 셋으로 접은 경계 — 전부 0~1 진행도다.
///
///   `0 ≤ primaryEnd ≤ crossEnd ≤ annotationEnd ≤ 1` 이 언제나 성립한다.
class RevealStageMarks {
  const RevealStageMarks({
    required this.primaryEnd,
    required this.crossEnd,
    required this.annotationEnd,
  });

  /// 계획과 일정에서 경계를 뽑는다.
  ///
  ///   [schedule] 은 [plan] 을 그대로 넣어 만든 것이어야 한다.
  ///
  ///   ⚠️ **창과 세그먼트를 인덱스로 짝짓지 않는다.** 오늘은 `RevealSchedule.windows` 가
  ///   `plan.segments` 와 평행하지만 그건 `timing_policy.dart` 의 내부 사정이고, 정작
  ///   `texture_compiler.dart` 는 `segmentId` 로 짝짓는다. 한쪽만 인덱스에 기대면 나중에
  ///   창을 거르거나 순서를 바꾸는 순간 **여기만 조용히 어긋난다** — 단계 표시가 실제 연출과
  ///   다른 자리를 가리키게 된다. 같은 열쇠를 쓴다.
  factory RevealStageMarks.of(RevealPlan plan, RevealSchedule schedule) {
    // 빈 계획: 드러낼 것이 없으니 셋 다 처음이자 끝이다.
    if (schedule.windows.isEmpty) {
      return const RevealStageMarks(
        primaryEnd: 0,
        crossEnd: 0,
        annotationEnd: 0,
      );
    }

    final kindOf = <int, RevealSegmentKind>{
      for (final seg in plan.segments) seg.id: seg.kind,
    };

    var primaryEnd = 0.0;
    var crossEnd = 0.0;
    var annotationEnd = 0.0;
    for (final window in schedule.windows) {
      final kind = kindOf[window.segmentId];
      if (kind == null) continue;
      final end = window.end;
      switch (kind) {
        case RevealSegmentKind.primaryStroke:
          if (end > primaryEnd) primaryEnd = end;
        case RevealSegmentKind.crossBackslash:
        case RevealSegmentKind.crossSlash:
          if (end > crossEnd) crossEnd = end;
        case RevealSegmentKind.annotation:
          if (end > annotationEnd) annotationEnd = end;
      }
    }

    // ⚠️ 없는 단계는 **앞 단계로 접는다.** X 탐지가 실패하면 붉은 픽셀이 전부 덩어리로
    //   돌아가 X 세그먼트가 아예 없는데(`detector.dart` 의 관문 넷), 그때 crossEnd 를 0 으로
    //   두면 "X 까지 감기" 가 연출을 되감아 버린다. 단조성을 지키는 편이 언제나 안전하다.
    if (crossEnd < primaryEnd) crossEnd = primaryEnd;
    if (annotationEnd < crossEnd) annotationEnd = crossEnd;

    return RevealStageMarks(
      primaryEnd: primaryEnd,
      crossEnd: crossEnd,
      annotationEnd: annotationEnd,
    );
  }

  /// 단계 구분이 없는 연출 — 처음부터 끝까지 한 덩어리다.
  ///
  ///   손으로 만든 텍스처를 그려 볼 때(페인터 시험 등) 쓴다. 굽기를 거친 결과에는
  ///   [RevealStageMarks.of] 가 낸 진짜 경계가 들어간다.
  static const RevealStageMarks single = RevealStageMarks(
    primaryEnd: 1,
    crossEnd: 1,
    annotationEnd: 1,
  );

  /// 길이 다 파진 순간. 주 획이 없으면 `0`.
  final double primaryEnd;

  /// X 두 획을 다 그은 순간. X 가 없으면 [primaryEnd] 와 같다.
  final double crossEnd;

  /// 마지막 덩어리까지 끝난 순간. 보통 `1`.
  final double annotationEnd;

  /// 단계 경계를 재생 순서대로 — 되감기 UI 가 그대로 쓸 수 있게.
  List<double> get inOrder => <double>[primaryEnd, crossEnd, annotationEnd];

  /// X 세그먼트가 실제로 잡혔나. 아니면 붉은 표시가 전부 덩어리로 갔다는 뜻이다.
  bool get hasCross => crossEnd > primaryEnd;

  /// 덩어리가 실제로 있나.
  bool get hasAnnotation => annotationEnd > crossEnd;
}
