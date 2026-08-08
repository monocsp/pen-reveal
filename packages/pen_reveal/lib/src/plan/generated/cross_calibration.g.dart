// GENERATED CODE — DO NOT MODIFY BY HAND.
// 손으로 고치지 말 것. `python3 tool/bake_cross_calibration.py` 로 다시 굽는다.
//

// 지도 10종(`assets/home/bag_maps/map_*.png`)을 굽기 해상도 420px 에서 잰 값이다.
// 비트맵 템플릿이 아니라 **방향 불변 파라메트릭 템플릿**이다 — X 가 회전돼 있어도 통한다.
//
// 실측 요약:
//   map_basic_01    X= 1066px  2위=  738px  \= 38°( 567px)  /=137°( 499px)
//   map_basic_02    X= 1065px  2위=  412px  \= 38°( 565px)  /=138°( 500px)
//   map_basic_03    X= 1069px  2위=  521px  \= 38°( 558px)  /=138°( 511px)
//   map_deep_01     X= 1059px  2위=  740px  \= 37°( 554px)  /=137°( 505px)
//   map_deep_02     X= 1065px  2위=  741px  \= 38°( 568px)  /=138°( 497px)
//   map_deep_03     X= 1058px  2위=  268px  \= 38°( 565px)  /=137°( 493px)
//   map_deep_04     X= 1075px  2위=  263px  \= 32°( 509px)  /=115°( 566px)
//   map_deep_05     X= 1068px  2위=  883px  \= 19°( 557px)  /=116°( 511px)
//   map_deep_06     X= 1065px  2위=  741px  \= 38°( 568px)  /=138°( 497px)
//   map_special_01  X= 1060px  2위=  714px  \= 38°( 560px)  /=138°( 500px)

/// 붉은 X 를 두 획으로 가르는 방향 스윕의 실측 캘리브레이션.
///
///   상수를 손으로 만지지 말 것 — 지도가 바뀌면 스크립트를 다시 돌린다.
abstract final class CrossCalibration {
  /// 스윕 각도 수(0~179°, 1° 간격). 180° 는 0° 와 같은 축이라 뺀다.
  static const int angleSteps = 180;

  /// 두 축이 이만큼은 떨어져 있어야 서로 다른 획으로 본다.
  static const int minAxisSeparationDegrees = 25;

  /// 획 폭 추정 — `W = 픽셀 수 / (divisor × 대각 길이)`.
  static const double bandWidthDivisor = 1.5;

  /// 획 폭이 X 크기에서 차지하는 비율의 실측 범위 (관측 0.185~0.255).
  static const double minBandWidthRatio = 0.1296;
  static const double maxBandWidthRatio = 0.3319;

  /// X 연결요소의 픽셀 수 실측 범위 (관측 1058~1075 @ 420px).
  static const int minComponentPixels = 634;
  static const int maxComponentPixels = 1720;

  /// 최대 축의 윈도우가 X 픽셀 중 차지하는 비율 (관측 0.468~0.585).
  ///   이보다 낮으면 '두 획으로 된 X' 가 아니다 — 뭉친 축이 없다는 뜻이다.
  static const double minAxisScoreRatio = 0.3509;

  /// X 가 2위 연결요소보다 몇 배 큰지 (관측 1.21~4.09배).
  ///   1 에 가까우면 '최대 연결요소 = X' 라는 가정 자체가 위태롭다.
  static const double minDominance = 1.028;

  /// 캘리브레이션을 잰 굽기 해상도(긴 변).
  static const int measuredLongSide = 420;

  /// 잰 지도 수.
  static const int measuredMapCount = 10;
}
