// src/timing/reveal_speed.dart — **단계마다 몇 배로 빠르게 그릴지.**
//
//   왜 따로 두나: [HandwritingRevealTiming] 은 손잡이가 열둘인데 전부 저수준이다.
//   "길만 두 배 빠르게" 하려면 `primaryMinDuration` 과 `primaryMaxDuration` 을 **같이**
//   맞춰야 하고, 글씨는 `annotationPerPixel`·`Min`·`Max` 셋을 맞춰야 한다. 하나만 고치면
//   실측으로 잡아 둔 비율이 조용히 깨진다.
//
//   이 값은 그 비율을 **건드리지 않고** 단계를 통째로 늘이거나 줄인다. 바깥에서 쓸 때
//   알아야 하는 것은 "길·X·글씨" 셋과 "사이 쉼" 하나뿐이다.
//
//   순수 Dart 다 — 이 패키지는 의존성이 없다. `@immutable` 하나 때문에 `meta` 를
//   들이지 않고, 값 동등성 린트는 레포 관례대로 `// ignore:` 로 넘긴다.
/// 단계별 배속 — **1 이 기본, 2 면 두 배 빠르게, 0.5 면 절반 속도.**
///
///   큰 값이 빠른 쪽이다 — 배속이므로 `2` 면 그 단계의 **길이가 절반**이 된다.
///
///   ⚠️ **여기 쓰라고 있는 것은 "단계끼리의 비율" 이다.** 연출 전체를 느리게 하려면
///   컨트롤러 `duration` 을 늘리면 된다 — 일정은 0~1 로 정규화돼 있고 컨트롤러는 선형이라
///   전체가 고르게 늘어난다(예전에 이 주석이 "컨트롤러를 늘리면 안 된다" 고 적혀 있었는데
///   **틀렸다**). 이 값은 "글씨만 빠르게" 처럼 **단계마다 다르게** 하고 싶을 때 쓴다.
///
///   ```dart
///   // 글씨만 두 배 빠르게, 사이 쉼은 절반으로.
///   const RevealPreparer(
///     timing: HandwritingRevealTiming(
///       speed: RevealSpeed(annotation: 2, gaps: 0.5),
///     ),
///   );
///   ```
///
///   ⚠️ **0 이나 음수는 못 준다.** 0 배속은 "무한히 오래" 라는 뜻이라 재생 시간이 발산하고,
///   음수는 시간을 거꾸로 돌리라는 말이다. 둘 다 조용히 이상한 연출이 되므로 막는다.
class RevealSpeed {
  const RevealSpeed({
    this.road = 1,
    this.cross = 1,
    this.annotation = 1,
    this.gaps = 1,
  })  : assert(road > 0, '길 배속은 0 보다 커야 한다'),
        assert(cross > 0, 'X 배속은 0 보다 커야 한다'),
        assert(annotation > 0, '글씨 배속은 0 보다 커야 한다'),
        assert(gaps > 0, '쉼 배속은 0 보다 커야 한다');

  /// 셋을 한 값으로 — 연출 전체를 같은 비율로 빠르게/느리게.
  ///
  ///   쉼도 같이 움직인다. 쉼만 그대로 두고 획만 빠르게 하고 싶으면 각각 준다.
  const RevealSpeed.all(double speed)
      : this(road: speed, cross: speed, annotation: speed, gaps: speed);

  /// 기본 — 어디도 안 건드린다.
  static const RevealSpeed normal = RevealSpeed();

  /// 흰 길(주 획).
  final double road;

  /// 붉은 X 두 획.
  final double cross;

  /// 붉은 글씨 덩어리들.
  final double annotation;

  /// 단계 사이의 쉼과 덩어리 사이의 쉼.
  final double gaps;

  /// 밀리초에 배속을 먹인다 — 빠를수록 짧아진다.
  ///
  ///   ⚠️ **0 으로 내려가지 않게 막는다.** 아주 빠른 배속에서 span 이 0 이 되면 그
  ///   세그먼트는 창이 없는 것과 같아져 **영영 안 드러난다**. 1ms 는 남긴다.
  int scale(int millis, double by) {
    if (millis <= 0) return millis;
    final out = (millis / by).round();
    return out < 1 ? 1 : out;
  }

  RevealSpeed copyWith({
    double? road,
    double? cross,
    double? annotation,
    double? gaps,
  }) =>
      RevealSpeed(
        road: road ?? this.road,
        cross: cross ?? this.cross,
        annotation: annotation ?? this.annotation,
        gaps: gaps ?? this.gaps,
      );

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevealSpeed &&
          other.road == road &&
          other.cross == cross &&
          other.annotation == annotation &&
          other.gaps == gaps);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(road, cross, annotation, gaps);

  @override
  String toString() => 'RevealSpeed(road: $road, cross: $cross, '
      'annotation: $annotation, gaps: $gaps)';
}
