/// 구조 층 — **무엇을 어떤 순서로 드러낼지**만 다룬다.
///
///   이 라이브러리에는 시간이 없다. `Duration`·curve·밀리초가 한 톨도 없고, 그런 타입을
///   전이 의존으로 끌어오지도 않는다. 계획은 *공간과 순서*만 말한다 — "이 획이 저 획보다
///   먼저", "이 픽셀은 자기 획 안에서 30% 지점".
///
///   "몇 밀리초에 그릴지"가 필요하면 `package:pen_reveal/timing.dart` 를 따로 import 한다.
///   나누어 둔 이유: 같은 계획을 스플래시에선 느리게, 목록에선 빠르게 그리고 싶을 수 있다.
///   한 장의 회색맵에 의미와 시간을 뭉쳐 두면 둘을 따로 못 바꾼다.
///
///   이 분리는 관례가 아니라 계약이다 — `test/purity_test.dart` 가 `lib/src/plan/` 아래
///   소스를 직접 읽어서 시간 타입의 침입을 막는다.
library;

export 'src/plan/annotation_segmenter.dart';
export 'src/plan/cross_stroke_detector.dart';
export 'src/plan/detector.dart';
export 'src/plan/generated/cross_calibration.g.dart';
export 'src/plan/length_profile.dart';
export 'src/plan/one_stroke_bake.dart';
export 'src/plan/reveal_plan.dart';
