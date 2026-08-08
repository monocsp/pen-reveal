/// `pen_reveal` 의 Flutter 경계.
///
///   순수 코어가 낸 순서 텍스처를 `ui.Image` 로 부풀리고, base/composed/reveal 세 장을
///   알파 임계로 합성해 그린다. 엔진에 닿는 코드는 이 패키지에만 있다.
///
///   ⚠️ **임계 가파르기 상수를 여기서 선언하지 마라.** `PreparedReveal` 이 자기가 구워진
///   `RevealSharpness` 를 들고 다니고, 페인터는 거기서 받아 쓴다. 원본은 이 값을 굽는
///   쪽과 그리는 쪽에 따로 뒀다가 "연출이 끝나도 마지막 획이 반투명하게 남는" 버그를
///   안고 있었다(`pen_reveal` 의 `test/timing/sharpness_binding_test.dart` 참고).
library;

export 'package:pen_reveal/pen_reveal.dart';

export 'src/image_bytes.dart';
export 'src/reveal_preparer.dart';
export 'src/sequential_reveal.dart';
