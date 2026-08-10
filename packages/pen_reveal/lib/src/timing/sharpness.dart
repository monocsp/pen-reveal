// src/timing/sharpness.dart — 임계 가파르기 **하나가 사는 곳**.
//
//   이 값은 두 곳에서 동시에 쓰인다:
//     ① 굽는 쪽 — 쓸 수 있는 순서값의 상한([maxOrderValue])
//     ② 그리는 쪽 — 알파 임계 색행렬([thresholdMatrix])
//
//   ⚠️ **그래서 타입 하나가 둘 다 소유한다.** 원래 구현은 굽는 쪽에 `painterSharpness = 24`,
//   그리는 쪽에 `_edgeSharpness = 24` 를 따로 두고 둘을 묶는 테스트가 없었다. 한쪽만 바꾸면
//   **연출이 끝나도 마지막 획이 반투명하게 남는다** — k=24 인데 순서값을 254 까지 쓰면
//   progress=1 에서 마지막 픽셀의 알파가 24/255 밖에 안 되기 때문이다. 그 어긋남을
//   문법적으로 불가능하게 만드는 것이 이 파일의 존재 이유다.
//
//   `thresholdMatrix` 가 `List<double>` 을 돌려주는 순수 함수라는 점이 이걸 가능하게 한다 —
//   색행렬 자체는 Flutter 를 모른다. 렌더 패키지는 이 값을 `ColorFilter.matrix` 에 넣기만
//   하고 자기 상수를 갖지 않는다.
//
//   순수 Dart 다.
import 'package:pen_reveal/src/plan/reveal_plan.dart' show kRevealHiddenSegment;

/// 임계의 가파르기 `k` — 크면 칼같이 잘리고, 작으면 선단이 번진다.
class RevealSharpness {
  const RevealSharpness([this.k = 24]) : assert(k > 0, '가파르기는 양수여야 한다');

  /// 기본값. 표현 계약이라 함부로 열지 않는다(열면 같은 그림이 화면마다 달라 보인다).
  static const RevealSharpness standard = RevealSharpness();

  final double k;

  /// 순서값으로 쓸 수 있는 최대치 — 그 위는 페인터가 불투명하게 못 만드는 구간이다.
  ///
  ///   임계식이 `alpha = k·(progress·255 − order)` 라, progress=1 에서 마지막 픽셀이
  ///   불투명해지려면 `k·(255 − order) ≥ 255`, 즉 `order ≤ 255 − ⌈255/k⌉` 여야 한다.
  ///   k=24 면 244 다.
  int get maxOrderValue {
    final headroom = (255 / k).ceil();
    final top = 255 - headroom;
    return top < 1 ? 1 : top;
  }

  /// 선단이 번지는 폭(순서값 코드 단위) — 대략 `255/k`.
  ///
  ///   k=24 면 10.6 코드(시간축의 4.2%)라 짧은 덩어리 여럿을 촘촘히 놓으면 다음 글자가
  ///   미리 비친다. 덩어리가 10개를 넘으면 k 를 128 쯤으로 올려 선단을 2코드로 좁히는 게
  ///   맞다(간격을 벌려 때우면 연출 정책과 렌더 정밀도가 다시 엉킨다).
  double get leadingEdgeCodes => 255 / k;

  /// 계단 임계 색행렬 — `out.A = k·(progress·255 − order)`.
  ///
  ///   `ColorFilter.matrix` 가 먹는 20개 값(4행 × 5열)이다. 순서 텍스처의 **R 채널**을
  ///   시간으로 읽고, RGB 는 흰색으로 밀어 알파만 남긴다.
  ///
  ///   ⚠️ 함정 둘: 이 행렬을 쓰는 `Paint` 에 **`blendMode` 를 같이 두면 안 된다**(실기 확인 —
  ///   레이어를 따로 나눠야 한다). 그리고 translation 열은 **0~255 공간**이라 `×255` 를
  ///   빠뜨리면 마스크가 통째로 사라진다.
  List<double> thresholdMatrix(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return <double>[
      0, 0, 0, 0, 255, //
      0, 0, 0, 0, 255, //
      0, 0, 0, 0, 255, //
      -k, 0, 0, 0, k * t * 255, //
    ];
  }

  /// 순서값 [order] 인 픽셀이 [progress] 에서 갖는 알파(0~255) — 테스트·검증용.
  ///
  ///   렌더가 실제로 하는 계산을 Dart 로 그대로 복제한 것이다. `hidden` 은 언제나 0 이다.
  double alphaAt({required int order, required double progress}) {
    if (order >= kRevealHiddenSegment) return 0;
    final a = k * (progress.clamp(0.0, 1.0) * 255 - order);
    return a.clamp(0.0, 255.0);
  }
  // 값 동등성 — 손잡이로 `k` 를 갈아 끼우는 쪽에서 **값이 같으면 다시 굽지 않게** 한다.
  //   참조 동등성이면 매 build 마다 "바뀌었다" 가 되어 열 때마다 두 번 굽는다
  //   (`HandwritingRevealTiming` 이 같은 이유로 이미 갖고 있다).
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      identical(this, other) || (other is RevealSharpness && other.k == k);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => k.hashCode;

}
