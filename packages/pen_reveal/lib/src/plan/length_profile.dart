// src/plan/length_profile.dart — 잰 길 길이(픽셀)를 **0.0~1.0 상대값**으로 접는다.
//
//   사용자 지정(2026-08-07): "지도 파악하는 쪽에서 0.0~1.0 상대적인 길이값을 주고, 위젯
//   쪽에서 0 에 가까우면 짧게 1 에 가까우면 길게 시간을 조절한다." 그래서 경계가 이렇다:
//     · **여기(코어)** = "이 길이 코퍼스 안에서 얼마나 긴가" 를 0~1 로만 답한다. 밀리초를
//       모르고, 밀리초를 만들지도 않는다.
//     · **표현 계층**(`src/timing/timing_policy.dart`) = 그 0~1 을 자기 밴드(최소~최대
//       시간)로 선형 환산만 한다. 디자이너가 "최소 0.8초 최대 3초" 라고 하면 위젯 생성자
//       인자 두 개만 바뀐다.
//
//   ⚠️ **곡선(압축 지수)은 여기 몫이다.** 0~1 이 "코퍼스 안에서의 자리"를 뜻하려면 접는
//   방식까지 한쪽이 소유해야 한다. 위젯이 다시 `pow` 를 걸면 밴드를 바꿀 때마다 곡선이
//   같이 흔들리고 "t=0.5 = 밴드의 절반" 이라는 약속이 깨진다.
//
//   ⚠️ 코퍼스 밖(서버가 새 지도를 준다) → **클램프**다. 최장보다 긴 길은 t=1.0 으로 붙어
//   최장 지도와 같은 시간에 그려지고, 최단보다 짧은 길은 t=0.0 이다. 재정규화(코퍼스를
//   런타임에 다시 잡기)는 **일부러 안 한다** — 같은 지도가 목록에 무엇이 있느냐에 따라
//   다른 속도로 그려지면 연출이 재현되지 않는다. 코퍼스가 실제로 넓어지면
//   [StrokeLengthProfile] 의 값을 사람이 다시 재서 고친다(`bag_reveal_corpus_test` 가 알려준다).
//
//   순수 Dart 다 — `package:flutter` 도, 시간 타입도 안 쓴다.
import 'dart:math' as math;

import 'package:pen_reveal/src/plan/one_stroke_bake.dart' show kBakeLongSide;

/// 길 길이를 0~1 로 접을 때 쓰는 자 — **정본 지도 10종 실측**(굽기 해상도 420px,
///   composed−base 로 다시 잰 값, 2026-08-07).
///
///   · 최단 `map_basic_03` 124.5 · 최장 `map_deep_05` 905.7 (7.3배)
///   · 압축 0.35 = 사용자 승인 곡선의 지수. 1 이면 정비례(짧은 넷이 바닥에 뭉친다),
///     0 이면 길이를 무시한다.
///
///   ⚠️ **이 세 값이 유일한 출처다.** 표현 계층에도, 테스트 기대값에도 다시 쓰지 않는다.
class StrokeLengthProfile {
  const StrokeLengthProfile({
    this.shortest = 124.5,
    this.longest = 905.7,
    this.compression = 0.35,
    this.referenceLongSide = kBakeLongSide,
  });

  /// t=0 이 되는 길이(코퍼스 최단).
  final double shortest;

  /// t=1 이 되는 길이(코퍼스 최장). **여기부터 포화**다 — 더 길어도 t 는 1 이다.
  final double longest;

  /// 길이가 t 에 반영되는 정도. 1=정비례, 0=길이 무시.
  final double compression;

  /// [shortest]·[longest] 를 잰 캔버스의 긴 변. 다른 해상도에서 잰 길이는 이 값 기준으로
  ///   환산한 뒤 접는다 — 안 하면 품질만 올렸는데 연출이 느려진다.
  final int referenceLongSide;
}

/// 기본 자 — 코드 전반이 같은 코퍼스를 본다.
const StrokeLengthProfile kStrokeLengthProfile = StrokeLengthProfile();

/// 길이(기준 해상도 픽셀) → **0.0~1.0**. 코퍼스 밖은 잘라 붙인다.
///
///   음수·0·아주 큰 값에도 예외 없이 0~1 을 준다(NaN·무한 안 나온다).
double normalizeStrokeLength(
  double length, {
  StrokeLengthProfile profile = kStrokeLengthProfile,
}) {
  final low = _compress(profile.shortest, profile.compression);
  final high = _compress(profile.longest, profile.compression);
  final span = high - low;
  // 퇴화(최단==최장)면 나눌 것이 없다 — 전부 같은 자리로 본다.
  if (!span.isFinite || span <= 0) return 0;
  final folded = (_compress(length, profile.compression) - low) / span;
  if (folded.isNaN) return 0;
  return folded.clamp(0.0, 1.0);
}

/// [longSide] 해상도에서 잰 길이를 기준 해상도로 환산해 접는다.
///
///   탐지는 굽기 해상도(`RevealPreparer.longSide`)에서 도는데 그 값은 화면
///   사정에 따라 바뀐다. 같은 그림이 해상도 때문에 다른 t 를 받으면 안 되므로 **여기서**
///   기준 해상도로 맞춘다.
double normalizeStrokeLengthAt(
  double length, {
  required int longSide,
  StrokeLengthProfile profile = kStrokeLengthProfile,
}) {
  if (longSide <= 0 || longSide == profile.referenceLongSide) {
    return normalizeStrokeLength(length, profile: profile);
  }
  return normalizeStrokeLength(
    length * profile.referenceLongSide / longSide,
    profile: profile,
  );
}

double _compress(double length, double exponent) =>
    length <= 0 ? 0 : math.pow(length, exponent).toDouble();
