// src/plan/reveal_plan.dart — "무엇을 어떤 순서로 드러낼지"만 담는 구조 모델.
//
//   ⚠️ **여기에 시간은 없다.** duration·간격·curve 한 톨도 없고, 그런 타입을 import 하지도
//   않는다. 계획은 *공간과 순서*만 말하고("이 획이 저 획보다 먼저", "이 픽셀은 획 안에서
//   30% 지점"), 그걸 몇 밀리초에 그릴지는 표현 계층(`src/timing/timing_policy.dart`)이
//   정한다. 한 장의 0~255 회색맵에 의미와 시간을 같이 뭉쳐 두면 둘을 따로 못 바꾼다.
//
//   `test/purity_test.dart` 가 이 분리를 소스 수준에서 잠근다.
//
//   표현은 **평면 배열**이다 — 세그먼트마다 `List<int> pixelIndices` 를 들면 21만 개의
//   boxed int 가 흩어진다. 픽셀당 1바이트(어느 세그먼트) + 2바이트(그 안에서 몇 %)면
//   같은 정보가 연속 메모리에 들어가고 isolate 로 넘기기도 싸다.
import 'dart:typed_data';

/// 세그먼트의 종류 — 타이밍 정책이 "이건 획이고 저건 글씨" 를 알아야 리듬을 정한다.
enum RevealSegmentKind {
  /// 지도의 길. 한 붓 순서를 그대로 물려받는다.
  primaryStroke,

  /// 빨간 X 의 `\` 획. 언제나 [RevealSegmentKind.crossSlash] 보다 먼저다.
  crossBackslash,

  /// 빨간 X 의 `/` 획.
  crossSlash,

  /// X 를 뺀 붉은 표시 한 덩어리 — 손글씨 한 뭉치이거나 작은 그림이다.
  ///
  ///   ⚠️ 이름이 `character` 가 아닌 이유: 연결요소는 음절과 1:1 이 아니다. 한글 손글씨는
  ///   이웃 음절과 붙고(실측: "발견한곳" 이 굽기 해상도에서 2 덩어리), 아예 그림인
  ///   경우도 있다(map_deep_05 는 문구 대신 육각형 얼굴). 덩어리라고 부르는 게 정직하다.
  annotation,
}

/// 픽셀 하나가 어느 세그먼트에도 안 속함을 뜻하는 값 — 영영 안 드러난다.
///
///   세그먼트 id 는 0~254 라 최대 255 개다. 실측 최대는 지도 하나당 14 개(길 1 + X 2 +
///   덩어리 11)라 한참 남는다.
const int kRevealHiddenSegment = 255;

/// 세그먼트 id 로 쓸 수 있는 최대값.
const int kRevealMaxSegmentId = 254;

/// [RevealPlan.within] 이 놓이는 정수 범위의 위끝(0~65535).
///
///   `Float32List` 는 같은 정보에 두 배를 쓰는데, 최종 산출물이 8비트 시간축이라
///   16비트면 이미 256배 여유다.
const int kRevealWithinScale = 65535;

/// 한 번에 드러나는 덩어리 하나.
class RevealSegment {
  const RevealSegment({
    required this.id,
    required this.kind,
    required this.pixelCount,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.measure,
    this.relativeLength,
  });

  /// [RevealPlan.segmentId] 에 찍히는 값. 재생 순서이기도 하다(작을수록 먼저).
  final int id;

  final RevealSegmentKind kind;
  final int pixelCount;

  /// bbox — 양끝 **포함**.
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// "펜이 이만큼 간다" 는 구조적 자 — **굽기 해상도 픽셀 단위**.
  ///
  ///   길은 한 붓 경로 길이, X 획은 축 방향 길이, 덩어리는 가로 폭이다. 셋 다 *펜이
  ///   지나는 거리*라 같은 자로 잴 수 있고, 타이밍 정책이 이 값 하나로 "긴 건 더 오래"
  ///   를 판단한다. **시간이 아니라 거리다** — 시간으로 바꾸는 건 표현 계층 몫이다.
  ///
  ///   ⚠️ **길의 연출 길이는 이제 이 값이 아니라 [relativeLength] 로 정한다.** 여기 남은
  ///   길의 measure 는 "얼마나 길었나" 라는 기록일 뿐이라 해상도 환산에만 쓰인다.
  final double measure;

  /// 코퍼스 안에서 이 길이 **얼마나 긴가** — `0.0`(최단)~`1.0`(최장). 길에만 있다.
  ///
  ///   `bag_reveal_normalize.dart` 가 접어 넣는다. 표현 계층은 이 값만 보고 자기 밴드
  ///   (최소~최대)로 환산한다 — 픽셀도 지수도 안 본다. `null` 이면 **정규화를 안 거친
  ///   계획**이라는 뜻이라, 표현 계층은 조용히 최소값으로 떨어뜨리지 말고 실패해야 한다.
  final double? relativeLength;

  int get width => right - left + 1;
  int get height => bottom - top + 1;

  /// 자만 [factor] 배 한 사본 — 굽기 해상도를 기준 해상도로 환산할 때 쓴다.
  ///
  ///   ⚠️ [relativeLength] 는 **안 건드린다.** 이미 기준 해상도로 접힌 0~1 이라
  ///   해상도 환산의 대상이 아니다(다시 곱하면 같은 그림이 해상도마다 다르게 그려진다).
  RevealSegment scaleMeasure(double factor) => RevealSegment(
        id: id,
        kind: kind,
        pixelCount: pixelCount,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        measure: measure * factor,
        relativeLength: relativeLength,
      );
}

/// 그림 한 장을 어떤 순서로 드러낼지 적어 둔 계획.
class RevealPlan {
  const RevealPlan({
    required this.width,
    required this.height,
    required this.segmentId,
    required this.within,
    required this.segments,
  });

  final int width;
  final int height;

  /// `width*height` 바이트. 값은 세그먼트 id, [kRevealHiddenSegment] 는 안 드러난다.
  final Uint8List segmentId;

  /// `width*height` 개. 그 픽셀이 **자기 세그먼트 안에서** 갖는 진행도
  ///   (0~[kRevealWithinScale]). 세그먼트 밖 픽셀의 값은 의미 없다.
  final Uint16List within;

  /// 재생 순서대로 — `segments[i].id == i` 다.
  final List<RevealSegment> segments;

  /// 계획이 비었나(드러낼 것이 없다).
  bool get isEmpty => segments.isEmpty;

  /// 세그먼트의 자([RevealSegment.measure])만 [factor] 배 한 사본.
  ///
  ///   픽셀 배열은 **그대로 공유한다** — 21만 개를 다시 복사할 이유가 없다. 굽기 해상도가
  ///   기준과 다를 때 "긴 획은 더 오래" 판단이 해상도에 흔들리지 않게 맞추는 용도다.
  RevealPlan scaleMeasures(double factor) => RevealPlan(
        width: width,
        height: height,
        segmentId: segmentId,
        within: within,
        segments: [for (final s in segments) s.scaleMeasure(factor)],
      );
}
