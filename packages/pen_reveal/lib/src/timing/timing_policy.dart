// src/timing/timing_policy.dart — **시간은 전부 여기에 있다.** duration·간격·가감속이 이
//   파일 밖으로 새지 않는다.
//
//   짝이 되는 구조 층(`src/plan/detector.dart`)은 "무엇이 무엇보다 먼저" 와 "그 픽셀은 자기
//   덩어리 안에서 몇 % 지점" 만 안다. 같은 계획을 스플래시에선 느리게, 목록에선 빠르게
//   그리고 싶을 수 있어서 **주입 가능한 불변 정책 객체**로 갈라 뒀다.
//
//   ⚠️ **길이는 픽셀로 안 들어온다.** 구조 층(`length_profile.dart`)이 "코퍼스 안에서 얼마나
//   긴가"를 0~1(`RevealSegment.relativeLength`)로 접어 주고, 여기서는 그걸 밴드에 **선형으로
//   얹기만** 한다. 곡선(압축 지수)을 여기서 또 걸지 마라 — 밴드를 바꿀 때마다 곡선이 같이
//   흔들려 "0.5 = 밴드의 절반" 이라는 약속이 깨진다.
//
//   ⚠️ 이 정책으로 텍스처를 구웠으면 애니메이션 컨트롤러는 **선형**이어야 한다.
//   컨트롤러에 curve 를 또 걸면 가감속이 두 번 먹는다.
//
//   순수 Dart 다 — 굽기를 통째로 isolate 에 태울 수 있다.
import 'package:pen_reveal/src/plan/reveal_plan.dart';
import 'package:pen_reveal/src/timing/ease.dart';

/// 세그먼트 하나가 전체 타임라인에서 차지하는 구간.
class SegmentWindow {
  const SegmentWindow({
    required this.segmentId,
    required this.start,
    required this.end,
    required this.ease,
  });

  final int segmentId;

  /// 전체 진행도 0~1 안에서의 시작·끝.
  final double start;
  final double end;

  final RevealEase ease;
}

/// 계획 하나를 언제 어떻게 그릴지 — 창들과 전체 길이.
class RevealSchedule {
  const RevealSchedule({required this.windows, required this.total});

  /// ⚠️ **순서는 계약이 아니다.** 오늘 [HandwritingRevealTiming] 은 [RevealPlan.segments]
  ///   와 같은 순서로 내지만 그건 그 정책의 내부 사정이다. 읽는 쪽은 [SegmentWindow.segmentId]
  ///   로 짝지어야 한다 — 정책이 창을 거르거나 재정렬해도 안 깨진다.
  ///
  ///   `texture_compiler.dart` 와 `stage_marks.dart` 가 그렇게 짝짓고,
  ///   `stage_marks_test.dart` 의 "창이 세그먼트 순서와 달라도" 가 그 규약을 잠근다.
  final List<SegmentWindow> windows;

  /// 애니메이션 컨트롤러에 넣을 길이.
  final Duration total;
}

/// 계획 → 일정. 화면마다 다른 리듬을 주고 싶으면 이 인터페이스를 갈아 끼운다.
abstract interface class RevealTimingPolicy {
  RevealSchedule schedule(RevealPlan plan);
}

/// 손그림 연출의 기본 리듬 — 주 획 → X 두 획 → 문구 덩어리들.
///
///   ⚠️ 문구·X 값은 **굽기 해상도 420px 기준**이다(`kBakeLongSide`) — 그쪽만 아직
///   [RevealSegment.measure](픽셀 폭)를 자로 쓴다. 주 획은 해상도와 무관한 0~1 을 받는다.
///
///   ⚠️ 주 획 밴드(0.5~2.0초)만 확정값이고 나머지는 실측에서 나온 **출발점**이다.
///   지금 값으로 정본 지도 10종은 대략 이렇게 흐른다:
///     주 획 0.50~2.00초 → 120 → `\` 220 → 50 → `/` 220 → 160 → 덩어리 6~11개(총 0.8~1.6초)
class HandwritingRevealTiming implements RevealTimingPolicy {
  const HandwritingRevealTiming({
    this.primaryMinDuration = const Duration(milliseconds: 500),
    this.primaryMaxDuration = const Duration(milliseconds: 2000),
    this.primaryToCrossGap = const Duration(milliseconds: 120),
    this.crossStrokeDuration = const Duration(milliseconds: 220),
    this.crossStrokeGap = const Duration(milliseconds: 50),
    this.crossToAnnotationGap = const Duration(milliseconds: 160),
    this.annotationPerPixel = const Duration(milliseconds: 4),
    this.annotationMinDuration = const Duration(milliseconds: 70),
    this.annotationMaxDuration = const Duration(milliseconds: 220),
    this.annotationGap = const Duration(milliseconds: 30),
    this.strokeEase = const PenEase(),
    this.annotationEase = const LinearEase(),
  });

  /// 주 획을 긋는 시간의 **밴드** — 코퍼스 최단이 [primaryMinDuration], 최장이
  ///   [primaryMaxDuration] 이고 그 사이는 `relativeLength` 로 선형 보간한다.
  ///
  ///   ⚠️ **주 획 연출 시간을 바꾸려면 이 두 값만 고친다.** "최소 0.8초 최대 3초"면
  ///   `primaryMinDuration: 800ms, primaryMaxDuration: 3000ms` 로 끝이다 — 코퍼스 기준·압축
  ///   곡선은 구조 층(`length_profile.dart`)이 들고 있어 여기서 다시 잴 것이 없다.
  ///
  ///   기본값 500~2000 은 확정값이다. 앞서 1100~2206 은 승인 곡선을 정본 10종에 씌워 나온
  ///   실측 밴드였는데, 짧은 그림이 1.1초나 걸려 답답하다는 판단이었다. 곡선(기준 124.5·
  ///   지수 0.35)은 그대로고 밴드만 갈아 끼운 것이라 10종의 상대 간격은 그대로다:
  ///   0.50 / 0.70 / 0.73 / 1.28 / 1.71 / 1.77 / 1.92 / 1.92 / 1.95 / 2.00초.
  ///
  ///   ⚠️ 뒤집힌 밴드(min > max)는 **정렬해서 받는다** — 그리는 시간이 음수가 되거나
  ///   런타임에 터지는 것보다 낫다(연출은 부가물이다).
  final Duration primaryMinDuration;
  final Duration primaryMaxDuration;

  /// 주 획을 다 긋고 X 를 긋기까지의 쉼.
  final Duration primaryToCrossGap;

  /// X 획 하나를 긋는 시간.
  final Duration crossStrokeDuration;

  /// `\` 와 `/` 사이 — 진짜 펜도 여기서 한 번 뗀다.
  final Duration crossStrokeGap;

  /// X 를 다 긋고 문구를 쓰기까지의 쉼.
  final Duration crossToAnnotationGap;

  /// 덩어리 가로 폭 1px 당 시간.
  final Duration annotationPerPixel;
  final Duration annotationMinDuration;
  final Duration annotationMaxDuration;

  /// 덩어리 사이의 쉼.
  final Duration annotationGap;

  /// 주 획·X 획의 가감속(펜을 붙였다 떼는 느낌).
  final RevealEase strokeEase;

  /// 문구 덩어리의 가감속 — 짧아서 가감속이 오히려 어색하다.
  final RevealEase annotationEase;

  @override
  RevealSchedule schedule(RevealPlan plan) {
    if (plan.isEmpty) {
      return const RevealSchedule(
        windows: <SegmentWindow>[],
        total: Duration.zero,
      );
    }

    // ① 세그먼트마다 (앞 쉼, 길이) 를 밀리초로 뽑는다.
    final gaps = <int>[];
    final spans = <int>[];
    final eases = <RevealEase>[];
    var sawAnnotation = false;
    for (var i = 0; i < plan.segments.length; i++) {
      final segment = plan.segments[i];
      switch (segment.kind) {
        case RevealSegmentKind.primaryStroke:
          gaps.add(0);
          // 픽셀은 안 본다 — 구조 층이 접어 준 0~1 만.
          spans.add(_primaryMillis(segment.relativeLength, segment.id));
          eases.add(strokeEase);
        case RevealSegmentKind.crossBackslash:
          gaps.add(i == 0 ? 0 : primaryToCrossGap.inMilliseconds);
          spans.add(crossStrokeDuration.inMilliseconds);
          eases.add(strokeEase);
        case RevealSegmentKind.crossSlash:
          gaps.add(i == 0 ? 0 : crossStrokeGap.inMilliseconds);
          spans.add(crossStrokeDuration.inMilliseconds);
          eases.add(strokeEase);
        case RevealSegmentKind.annotation:
          gaps.add(
            i == 0
                ? 0
                : (sawAnnotation ? annotationGap : crossToAnnotationGap)
                    .inMilliseconds,
          );
          spans.add(_annotationMillis(segment.measure));
          eases.add(annotationEase);
          sawAnnotation = true;
      }
    }

    // ② 밀리초를 0~1 로 정규화한다. 총 길이는 그대로 컨트롤러에 넘긴다.
    var total = 0;
    for (var i = 0; i < spans.length; i++) {
      total += gaps[i] + spans[i];
    }
    if (total <= 0) {
      return const RevealSchedule(
        windows: <SegmentWindow>[],
        total: Duration.zero,
      );
    }
    final windows = <SegmentWindow>[];
    var at = 0;
    for (var i = 0; i < spans.length; i++) {
      at += gaps[i];
      windows.add(
        SegmentWindow(
          segmentId: plan.segments[i].id,
          start: at / total,
          end: (at + spans[i]) / total,
          ease: eases[i],
        ),
      );
      at += spans[i];
    }
    return RevealSchedule(
      windows: windows,
      total: Duration(milliseconds: total),
    );
  }

  /// 0~1 → 밴드 위의 한 점. **이게 전부다** — 지수도 기준 길이도 여기 없다.
  ///
  ///   [relativeLength] 가 `null` 이면 정규화를 안 거친 계획이다. 조용히 밴드 최소로
  ///   떨어뜨리면 모든 그림이 같은 속도로 그려지는데 아무 데서도 안 잡힌다 — 그래서 던진다.
  int _primaryMillis(double? relativeLength, int segmentId) {
    if (relativeLength == null) {
      throw ArgumentError.value(
        segmentId,
        'segment.relativeLength',
        '주 획 세그먼트에 상대 길이(0~1)가 없다 — 정규화를 거친 계획이 아니다',
      );
    }
    final low = primaryMinDuration.inMilliseconds;
    final high = primaryMaxDuration.inMilliseconds;
    final from = low <= high ? low : high;
    final to = low <= high ? high : low;
    return (from + (to - from) * relativeLength.clamp(0.0, 1.0)).round();
  }

  int _annotationMillis(double widthPixels) =>
      (widthPixels * annotationPerPixel.inMilliseconds)
          .clamp(
            annotationMinDuration.inMilliseconds,
            annotationMaxDuration.inMilliseconds,
          )
          .round();

  /// ⚠️ **값 동등성이 있어야 한다.** 이 타입은 "주입 가능한 불변 정책 객체"인데, 동등성이
  ///   없으면 같은 리듬을 담은 두 인스턴스가 서로 다른 것으로 잡힌다. 그러면 호출부가
  ///   `timing` 이 바뀌었는지 볼 때마다 거짓 양성이 나고, 위젯 key 에 `hashCode` 를 쓰면
  ///   identity 해시라 **build 마다 State 가 통째로 파괴·재생성**된다(계측대 실측:
  ///   슬라이더 한 번 끌면 최대 28회 재굽기·재생 중단).
  ///
  ///   `@immutable` 을 안 붙이는 이유: 그 애너테이션은 `package:meta` 인데 이 패키지는
  ///   의존성이 0 이다(README §패키지). 필드가 전부 `final` 이고 생성자가 `const` 라
  ///   실제로 불변이므로 린트만 끈다.
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandwritingRevealTiming &&
          other.primaryMinDuration == primaryMinDuration &&
          other.primaryMaxDuration == primaryMaxDuration &&
          other.primaryToCrossGap == primaryToCrossGap &&
          other.crossStrokeDuration == crossStrokeDuration &&
          other.crossStrokeGap == crossStrokeGap &&
          other.crossToAnnotationGap == crossToAnnotationGap &&
          other.annotationPerPixel == annotationPerPixel &&
          other.annotationMinDuration == annotationMinDuration &&
          other.annotationMaxDuration == annotationMaxDuration &&
          other.annotationGap == annotationGap &&
          other.strokeEase == strokeEase &&
          other.annotationEase == annotationEase;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(
        primaryMinDuration,
        primaryMaxDuration,
        primaryToCrossGap,
        crossStrokeDuration,
        crossStrokeGap,
        crossToAnnotationGap,
        annotationPerPixel,
        annotationMinDuration,
        annotationMaxDuration,
        annotationGap,
        strokeEase,
        annotationEase,
      );
}
