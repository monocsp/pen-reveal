/// 표현 층 — **언제 그릴지**. 시간은 전부 여기에 있다.
///
///   `plan.dart` 가 낸 순서표에 리듬을 씌워(`RevealTimingPolicy`) 시간축 텍스처 한 장으로
///   굽는다(`RevealTextureCompiler`). 화면마다 다른 리듬을 주고 싶으면 정책만 갈아 끼운다.
///
///   ⚠️ 임계 가파르기(`RevealSharpness`)도 여기 있다. 그 값 하나가 **굽는 쪽의 순서값
///   상한**과 **그리는 쪽의 알파 임계**를 동시에 정하기 때문에, 두 곳에 상수를 복제하면
///   조용히 어긋나 "연출이 끝나도 마지막 획이 반투명하게 남는" 버그가 된다. 그래서 이
///   패키지에는 그 값을 아는 타입이 하나뿐이고, 렌더 패키지는 자기 상수를 갖지 않는다.
library;

export 'src/timing/ease.dart';
export 'src/timing/sharpness.dart';
export 'src/timing/texture_compiler.dart';
export 'src/timing/timing_policy.dart';
