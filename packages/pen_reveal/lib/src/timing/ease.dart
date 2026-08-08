// src/timing/ease.dart — 덩어리 **안**의 가감속.
//
//   ⚠️ 이건 `Curve` 가 아니다. `Curve` 는 "시간 → 그려진 정도" 인데 여기서 필요한 건 그
//   **역함수**("진행도 `within` 인 이 픽셀은 창의 어느 시점에 나타나나")다. 두 방향을 한
//   타입으로 묶으면 부호가 조용히 뒤집힌다.
//
//   순수 Dart 다.
import 'dart:math' as math;

/// "진행도 `within` 인 픽셀은 창의 어느 시점에 나타나나".
abstract interface class RevealEase {
  /// [within] (0~1) → 창 안의 시점(0~1). 0→0, 1→1 이고 단조증가여야 한다.
  double timeOf(double within);
}

/// 일정한 속도. 손글씨 덩어리처럼 짧은 구간의 기본값이다.
class LinearEase implements RevealEase {
  const LinearEase();

  @override
  double timeOf(double within) => within.clamp(0.0, 1.0);
}

/// 사람이 펜을 그을 때의 속도감 — 짧게 붙었다 떼고, 가운데는 일정한 속도.
///
///   전 구간 easing(easeInOut 계열)을 걸면 가운데가 확 빨라져 손그림 같지 않다.
///   앞뒤 [edgeFraction] 만 가감속하고 나머지는 선형으로 둔다.
///
///   ⚠️ 이건 속도 사다리꼴 적분의 **역함수**다. 해석적으로 뒤집을 수 있어서 수치 탐색이
///   필요 없다.
class PenEase implements RevealEase {
  const PenEase({this.edgeFraction = 0.12});

  /// 가감속에 쓰는 앞뒤 구간의 비율(0~0.5).
  final double edgeFraction;

  @override
  double timeOf(double within) {
    final y = within.clamp(0.0, 1.0);
    final e = edgeFraction;
    if (e <= 0) return y;
    final peak = 1 / (1 - e);
    final rampEnd = peak * e / 2;
    if (y <= rampEnd) return math.sqrt(2 * e * y / peak);
    final tailStart = peak * (1 - 1.5 * e);
    if (y >= tailStart) return 1 - math.sqrt(2 * e * (1 - y) / peak);
    return y / peak + e / 2;
  }
}
