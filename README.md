# pen-reveal

그림 두 장의 차이를 읽어 **손으로 그리는 순서**를 복원하고, 그 순서대로 그림을 드러내는 연출 엔진.

선을 새로 그리는 근사가 아니다. 완성된 그림이 이미 있고, 픽셀마다 "너는 언제 나타날 차례야"를 적어둔 회색 텍스처 한 장으로 그걸 마스킹한다. 진행도를 0에서 1로 올리면 임계를 넘은 픽셀만 차례로 불투명해져서, 펜이 지나가는 것처럼 보인다. 픽셀이 전부 원본 한 장에서 나오므로 색·질감이 어긋날 여지가 없다.

```
base(빈 그림)  +  composed(완성 그림)
        │
        ├─ ① 두 장 diff ─────────── 변한 곳을 "주 획" 과 "붉은 표시" 로 가른다
        ├─ ② 세선화 + 한 붓 순회 ── 주 획에 "펜이 닿는 시각" 을 매긴다
        ├─ ③ 방향 스윕 ─────────── 붉은 X 를 `\` / `/` 두 획으로 가른다
        ├─ ④ 연결요소 + 줄 묶기 ── 손글씨를 읽는 순서 덩어리로 나눈다
        │
        ▼
   RevealPlan  ← 순서와 공간만. 시간이 한 톨도 없다.
        │
        ├─ ⑤ RevealTimingPolicy ── 순서에 리듬을 얹는다(밀리초는 여기서만)
        ├─ ⑥ RevealTextureCompiler ─ 0~244 회색 텍스처 한 장으로 굽는다
        │
        ▼
   알파 임계 합성 ── alpha = k·(progress·255 − order)
```

## 두 층으로 갈려 있다

```dart
import 'package:pen_reveal/plan.dart';    // 순서만. Duration 이 없다.
import 'package:pen_reveal/timing.dart';  // 시간은 전부 여기.
```

`plan` 은 "이 획이 저 획보다 먼저", "이 픽셀은 자기 획 안에서 30% 지점"까지만 안다. 몇 밀리초에 그릴지는 모른다. 같은 그림을 스플래시에선 느리게, 목록에선 빠르게 그리고 싶을 수 있어서다. 한 장의 회색맵에 의미와 시간을 뭉쳐 두면 둘을 따로 못 바꾼다.

이 분리는 관례가 아니라 **계약이다.** `test/purity_test.dart` 가 `lib/src/plan/` 아래 소스를 직접 읽어서 `Duration`·`Curve`·`milliseconds` 같은 타입은 물론 `duration`·`millis`·`_ms` 처럼 **이름만 시간인 식별자**까지 막고, 의존 방향이 `timing → plan` 한쪽뿐인지도 확인한다.

## 패키지

| | 무엇 | 의존 |
|---|---|---|
| [`pen_reveal`](packages/pen_reveal) | 알고리즘 전부 | `dart:math`·`dart:typed_data` 뿐 |
| [`pen_reveal_flutter`](packages/pen_reveal_flutter) | `ui.Image` ↔ RGBA, 합성 렌더 | Flutter |

엔진에 닿는 코드는 두 번째 패키지에만 있다. 알고리즘은 Flutter 없이 `dart test` 로 돈다.

## 쓰는 법

```dart
final prepared = await RevealPreparer().prepare(base: base, composed: composed);

// 가감속은 이미 텍스처에 구워져 있다 — 컨트롤러는 반드시 선형.
controller.animateTo(1, duration: prepared.revealDuration);

SequentialReveal(
  base: base,
  composed: composed,
  prepared: prepared,
  progress: controller.value,
  size: size,
);
```

리듬을 바꾸려면 정책만 갈아 끼운다:

```dart
RevealPreparer(
  timing: HandwritingRevealTiming(
    primaryMinDuration: Duration(milliseconds: 800),
    primaryMaxDuration: Duration(seconds: 3),
  ),
);
```

## 주의할 것

**컨트롤러에 curve 를 걸지 마라.** 가감속이 텍스처에 구워져 있어서 두 번 먹는다.

**임계 가파르기 상수를 복제하지 마라.** 그 값 하나가 굽는 쪽의 순서값 상한과 그리는 쪽의 알파 임계를 동시에 정한다. `RevealSharpness` 가 둘 다 소유하고, `PreparedReveal` 이 자기가 구워진 것을 들고 다닌다. 원본 구현은 이걸 두 파일에 나눠 뒀다가 "연출이 끝나도 마지막 획이 반투명하게 남는" 버그를 안고 있었다 — 어느 테스트도 잡지 못했다. 지금은 `sharpness_binding_test.dart` 가 잠근다.

**손글씨는 실제 획순이 아니다.** 래스터에 시간 정보가 없어서 한글 획순은 복원할 수 없다. 덩어리를 읽는 순서로 내고, 덩어리 안은 왼→오 wipe 로 때운다. 정직하게 "덩어리"라고 부르는 이유다.

## 코퍼스와 캘리브레이션

`StrokeLengthProfile` 의 상수(최단 124.5 · 최장 905.7 · 압축 0.35)와 `CrossCalibration` 의 관문 값들은 **정본 그림 10종을 420px 에서 실측한 값이다.** 그 계보는 [`corpus/manifest.json`](corpus/manifest.json) 에 적혀 있다 — 어떤 리샘플러로, 어떤 해상도에서, 어느 구현으로 쟀는지.

그 상수를 잰 원본 그림은 **이 레포에 없다.** 디자인 자산이라서다. 규칙은 하나다:

> PNG 에서 픽셀 단위로 나온 것은 ignore, 재서 얻은 스칼라(각도·비율·길이)만 커밋.

그래서 실측 숫자와 manifest 는 들어 있고, 그림·프리베이크 RGBA·RLE 픽셀 픽스처는 없다. 자산이 필요한 테스트는 `@Tags(['corpus'])` 로 묶여 있어 자산이 없으면 스스로 skip 한다 — 빠뜨린 게 아니라 설계다. 공개 CI 는 합성 입력으로만 돌고, 실측 대조는 자산을 갖춘 로컬에서 `dart test -t corpus` 로 돈다.

코퍼스 밖 그림은 **클램프**한다. 최장보다 긴 획은 최장과 같은 시간에 그려진다. 런타임 재정규화를 일부러 안 하는 이유: 같은 그림이 목록 구성에 따라 다른 속도로 그려지면 연출이 재현되지 않는다.

## 개발

```bash
cd packages/pen_reveal        && dart pub get    && dart analyze && dart test
cd packages/pen_reveal_flutter && flutter pub get && flutter analyze && flutter test
```

## 상태

`pen_reveal`(순수 코어)과 `pen_reveal_flutter`(엔진 경계 + 합성 렌더) 둘 다 돌아간다 — 굽고(`RevealPreparer`) 그리는(`SequentialReveal`) 길이 끝까지 이어져 있고, 두 패키지 모두 CI 게이트가 초록이다.

`example/` 데모와 GIF/MP4 exporter 가 남았다. 코퍼스 대조 테스트는 자산이 있는 로컬에서만 도는 상태다(위 §코퍼스).
