<!-- 생성물: 서브에이전트 워크플로 산출. 수치는 정본 10종 실측이며
     '추정'이라고 적힌 것만 추정이다. 재생성은 세션 기록 참고. -->

# 계측대 결함 수정 계획

조사 결과 22건이 남았다(중복 제거 후). 프로덕션 코드가 실제로 잘못 도는 것은 **3건**(재굽기 폭주 2건, 자원 누수 2건)이고, 나머지는 **계측이 요구사항을 안 잠그고 있는 것**이다. 후자는 지금 초록이지만 회귀를 못 잡는다.

---

## 1. 확정된 버그

### major

| # | 무엇 | 어디 | 언제 터지나 | 심각도 |
|---|---|---|---|---|
| B1 | `didUpdateWidget` 이 `old.source != widget.source` 로 **클로저 참조**를 비교한다. Dart 는 같은 리터럴에서 나온 클로저를 절대 동등하게 보지 않아 항상 참이다 | `example/lib/reveal_bench.dart:83` | 부모 rebuild 마다. 위젯북은 use case 를 그린 다음 프레임에 `knobs.lock()` 으로 반드시 한 번 rebuild 하므로 **use case 를 열 때마다 결정적으로 2회 굽는다**. 핫리로드·창 리사이즈 시 프레임마다 재굽기 | major |
| B2 | `_CorpusPicker` 가 key 에 `widget.timing.hashCode` 를 박는데 `HandwritingRevealTiming` 에 `==`/`hashCode` 가 없어 identity 해시다. `_corpusTiming` 은 build 마다 새 인스턴스를 만든다 | `example/lib/main.dart:217` · `:118-123` / 뿌리 `packages/pen_reveal/lib/src/timing/timing_policy.dart:62-76` | `정본 — 리듬 조절` use case. rebuild 마다 key 가 바뀌어 State 가 통째로 파괴·재생성된다 — `animateTo` 중단, 스피너로 되돌아감, 굽기 재시작. 슬라이더(`divisions: 28`)를 한 번 끌면 최대 28회 중첩 | major |
| B3 | `진행도 0` 테스트의 유일한 단언이 `_changed(zero, zero, _all)` — 같은 배열끼리라 항상 0 인 항진식 | `example/test/requirement_test.dart:135` | 언제나. 게다가 `zero` 는 파일의 나머지 7개 단언(`:145,:146,:147,:155,:162,:189,:193,:201`)의 기준선이라, 진행도 0 이 오염되면 8개가 함께 눈먼다. 실증: `sharpness.dart:61` 을 `k * (t * 255 + 2)` 로 바꿔 선단 2코드를 미리 새게 해도 9/9 통과 | major |
| B4 | `"다 파졌다"` 를 `_roadBox`(150,46,120,40 = 캔버스 2.7%) 하나로 재고, 기준 시점도 `primaryEnd` 다 | `example/test/requirement_test.dart:98`, `:150-163` | 상시. `_roadBox` 는 뱀꼴 첫 굽이라 `primaryEnd*0.25`(길 전체 23.31%)에서 이미 98.47% 로 포화 → 그 프레임이 통과한다(실측 1741 ≥ 1732). 정본에서는 반대로 빨개진다 — map_basic_03 은 primaryEnd 에서 길 96.1% | major |
| B5 | 색을 하나도 안 본다. `_changed` 는 `|ΔR|+|ΔG|+|ΔB|` 뿐이라 요구사항의 절반(갈색 바닥·흰 길·빨간 X·빨간 글씨)이 미검증 | `example/test/requirement_test.dart:49-61`, `:184-197`, `:199-202` | 상시. 실증: 글씨를 같은 밝기의 파란색(`0xFF7C7CF9`)으로 바꿔도 `마지막에 빨간 글씨가 나온다` 는 `_changed`=1950 으로 통과한다. 임계 색행렬(`sharpness.dart:57-62`)이 새서 드러난 픽셀이 전부 흰색이 돼도 못 잡는다 | major |
| B6 | `` `\` → `/` `` 순서를 상대 비교 하나(`fwd < back`)로만 보고, 양끝 상자를 합산한다 | `example/test/requirement_test.dart:165-182` | 상시. 두 획이 동시에 시작해 `/` 가 조금만 느려도(back=300, fwd=299) 통과한다. 실제 구현은 `\` 100% 후 `/` 시작인데 단언은 그보다 훨씬 약하다. 합산 때문에 획이 반쪽만 그어져도 통과 | major |
| B7 | 정본 지도를 **그려서** 순서를 확인하는 테스트가 없다. `example/test/` 는 requirement_test 한 파일이고 합성 한 장만 쓴다 | `example/test/requirement_test.dart:109` · `example/lib/fixtures/corpus_maps.dart:22` | 상시. 합성의 초록이 정본에서 성립하지 않는다: 길 단계가 합성 0.608 vs 정본 0.211~0.310, primaryEnd 기준 98% 규칙은 map_basic_01/02/03 에서 96~98% 로 빨개지고, 진행도 1 픽셀 일치도 정본은 1~4px 남는다 | major |
| B8 | 시간이 흐르는 것을 아무도 안 본다. requirement_test 는 정지 프레임만 그리고, `RevealBench` 는 위젯 테스트 0건 | `example/test/requirement_test.dart:131` · `example/lib/reveal_bench.dart:132-161` | 상시. `revealDuration` 배선을 끊거나(`:62` 기본 1초 그대로) `animateTo` 에 curve 를 걸어도(가감속 이중 적용 — preparer 주석 `:43-46` 이 경고하는 그 버그) 아무 데도 안 빨개진다. `천천히` 의 유일한 단언은 `> 0` 이라 40ms 섬광도 통과 | major |

### minor

| # | 무엇 | 어디 | 언제 터지나 | 심각도 |
|---|---|---|---|---|
| B9 | `길 끝에서 길은 다 파였고 X 는 아직이다` 가 제목 뒷절을 안 잰다 — 몸통에 `_crossBox` 가 없다 | `requirement_test.dart:150-163` | `primaryToCrossGap` 을 120→30ms 로 줄이면 primaryEnd 에 붉은 X 33px 이 이미 떠 있는데 9/9 통과. (현 출하 설정에서는 `11P − 29280 > 3T` 가 성립 불가라 제품은 안 샌다) | minor |
| B10 | `_bake()` 의 catch 가 `_error` 만 세우고 `pair.base`/`pair.composed` 를 안 놓는다. state 에 안 들어갔으니 `dispose()` 도 못 놓는다 | `example/lib/reveal_bench.dart:140-143` | `prepare()` 가 던지는 순간. 재현 입력: 1×841 두 장 → `fitLongSide` 가 짧은 변을 0 으로 내 `toImage(0,420)` 이 던짐. 굽기 실패를 반복할 때마다 원본 해상도 두 장씩 쌓인다 | minor |
| B11 | `loadCorpusMap` 이 base 디코드 뒤 composed 디코드가 던지면 base 를 놓을 핸들이 없다 | `example/lib/fixtures/corpus_maps.dart:42-46` | composed 자산이 잘렸을 때(그 파일 헤더 `:9-14` 의 `cp` 루프가 중단된 경우). 매니페스트에 이름이 있어 칩은 뜨고, 탭할 때마다 3.74MB 씩 회수 불가. `buildSyntheticMap` 도 같은 두 단계 모양 | minor |
| B12 | `availableCorpusKeys().then(...)` 에 `onError` 가 없다 | `example/lib/main.dart:163-169` | 매니페스트 로드 실패 시(웹에서 `AssetManifest.bin` fetch 실패). `_keys` 가 영원히 null → `:176` 의 스피너가 안 끝나고, 거절은 zone 으로 새 UI 에 아무 신호도 없다 | minor |
| B13 | `RevealStageMarks.of` 가 `windows[i]`↔`segments[i]` 를 **나열 인덱스**로 짝짓는데 형제 `texture_compiler.dart:47-53` 은 `window.segmentId` 로 짝짓는다. `min()` 절단은 어긋남을 감지 대신 은폐한다 | `packages/pen_reveal/lib/src/timing/stage_marks.dart:45-60` | 창을 재정렬·선별하는 커스텀 `RevealTimingPolicy`(공개 확장점, `timing_policy.dart:49`)에서. 실측: 창 순서만 뒤집으면 텍스처는 그대로인데 marks 가 `[1.0,1.0,1.0]`. X 창을 안 내는 정책은 `hasCross=true`/`hasAnnotation=false` 라는 자기모순. **현재 레포 경로에서는 발현 안 됨**(구현체가 하나뿐) | minor |
| B14 | `stages` 는 일정 좌표(0~1)인데 페인터는 굽기 좌표(0~244)+선단 `255/k` 로 돈다. 모든 경계가 실제 완료보다 체계적으로 이르다 | `stage_marks.dart:50`, `:85` (doc) | 상시. 합성 실측: primaryEnd=0.6075 인데 길이 완전 불투명해지는 진행도는 0.6221 — 47.8ms 이르다. 마크 시점에 길 12,782px 중 76px 이 알파 ≤166. 최대 어긋남 `255/k/255` = 4.2% | minor |
| B15 | `prepare` 가 두 장의 비율 일치를 검사하지 않는다 — 어긋나면 예외 없이 조용히 이상한 계획을 낸다 | `packages/pen_reveal_flutter/lib/src/reveal_preparer.dart:92-99` | 정본 base(879×1065)+합성 composed(420×420) → 안 던지고 `hasCross=false`, stages 0.682/0.682. `` `\`→`/` `` 가 조용히 증발한 "그럴듯한" 연출이 나온다 | minor |
| B16 | 되감김(단조성) 검사가 없다. 표본이 6점뿐 | `requirement_test.dart:123-235` | 그 사이 진행도에서 드러났던 것이 사라져도 안 걸린다. 임계식이 `alpha = k·(p·255 − order)` 라 순서값 계산이 어긋나면 실제로 가능. 현재는 41프레임 훑어 위반 0 | minor |
| B17 | 글씨를 진행도 1 에서 한 번만 본다 | `requirement_test.dart:199-202` | 왼→오로 써지는 것인지, 끝에 통째로 팝인 하는 것인지 구분 못 한다. 실측 신호는 뚜렷하다(창 25/50/75% 에서 431/941/1626px, 무게중심 273.7→327.4) | minor |
| B18 | 합성 입력도 한 종류만 쓴다 | `requirement_test.dart:109` | `RoadShape` 3종·X 없음·글씨 없음 조합이 위젯북에는 다 있는데(main.dart:45-47) 단언이 없다. 특히 X 미탐지 시 붉은 것이 전부 덩어리로 가는 후퇴 경로(`stage_marks.dart:62-66`)가 미검증 | minor |
| B19 | `_bake` 에 굽기 전 취소 검사가 없다 — 세대 토큰이 **커밋**만 막고 **작업**은 안 막는다 | `example/lib/reveal_bench.dart:104-112` | rebuild 가 연달아 오면 N개 `compute()` 아이솔레이트와 N×2 장이 동시에 산다. B1/B2 를 고치면 빈도는 줄지만 구조는 남는다 | minor |

### nit

| # | 무엇 | 어디 | 언제 | 심각도 |
|---|---|---|---|---|
| B20 | `_jumpTo` 는 마크에 정확히 착지시키는데 `_currentStage` 는 `p < primaryEnd` 라 등호에서 다음 단계로 넘어간다 | `reveal_bench.dart:338-344` vs `:174-178` | `길` 버튼을 누르면 `X` 에 불이 들어온다 | nit |
| B21 | `RevealStageMarks` 에 `==`/`hashCode` 가 없는데 `_StageBarPainter.shouldRepaint` 가 값 비교를 기대한다 | `stage_marks.dart` · `reveal_bench.dart:419` | 지금은 인스턴스가 안정적이라 우연히 맞게 돈다 | nit |
| B22 | `RevealStageMarks.single` 이 공개 배럴로 나간다 — `annotationEnd==1` 인데 `hasCross==false` 인 자기모순 상수 | `stage_marks.dart:79-83`, `:97-101` | 텍스처를 캐시했다 재조립하는 호출부가 required 를 채우려고 집어 들면, 그림엔 X 가 있는데 `hasCross=false` 가 된다 | nit |
| B23 | purity_test 에 `_planDir` 만 "감시 대상이 비어 있지 않다" 바닥이 있고 `_timingDir` 에는 없다. 배럴 완전성 검사도 없다 | `packages/pen_reveal/test/purity_test.dart:54-57` | 디렉터리를 옮기며 파일 일부를 남기면 그 파일은 영원히 무검사 | nit |
| B24 | `정본 10종` 이 실제로는 9가지다 — map_deep_02 와 map_deep_06 이 같은 그림(936k 중 임계 초과 1px, 파이프라인 결과 소수점까지 일치) | `example/assets/maps/map_deep_0{2,6}_composed.png` · `length_corpus_test.dart:46-47` | 코퍼스 커버리지를 한 칸 후하게 부르게 된다 | nit |

---

## 2. 오탐으로 판정된 것

| 지적 | 왜 오탐인가 |
|---|---|
| "크기가 다른 두 장을 넣으면 `prepare` 가 던져 `_bake` 가 샌다" (B10 의 제시 트리거) | `prepare` 가 base 를 composed 기준으로 다시 리샘플하므로(`reveal_preparer.dart:97-99`) 두 RGBA 길이가 항상 같다 — `detector.dart:105-111` 의 throw 는 이 경로에서 도달 불가. 실측 200×200+420×420 → error=null. 누수 자체는 real, 트리거만 틀렸다 |
| "RevealBench 호출부 일부에 key 가 없어 remount 된다" (B1 의 제시 전제) | main.dart 네 곳(`:62,:79,:131,:217`) 모두 `ValueKey` 가 있다. 실제 경로는 key 가 **같은 채로** `didUpdateWidget` 이 도는 것이다 |
| "재굽기가 무한 루프를 만든다" | `_bake()` 의 `setState` 는 `RevealBench` 서브트리만 더럽히고 `WidgetbookState` 를 안 건드린다. 확률적 낭비도 아니고 mount 당 정확히 +1 회다 |
| "`PreparedReveal.stages` 를 required 로 만든 것은 손봐야 할 파괴 변경" | 두 패키지 모두 `publish_to: none`, 호출부 3곳 전부 반영 완료. 조치 불필요 — 기본값을 주면 오히려 B22 위험이 커진다 |
| "`detector.dart:101-103` 의 `w<=0||h<=0` throw 가 누수 경로다" | `prepare` 를 통해서는 그 전에 `rgbaAt`/`toImage` 가 먼저 터진다 |

---

## 3. 수정 순서

### 1단계 — 진행도 0 을 진실값과 비교한다 (B3)

**의존 없음. 이후 2·3단계가 이 단계의 `_plain` 헬퍼를 쓴다.**

먼저 쓸 잠금 테스트 — 현재 코드는 정상이므로 **뮤테이션**이 잠금이다.

```
# 1) 회귀 주입 — packages/pen_reveal/lib/src/timing/sharpness.dart:61
#      -k, 0, 0, 0, k * t * 255,      →   -k, 0, 0, 0, k * (t * 255 + 2),
# 2) cd example && flutter test test/requirement_test.dart --tags regression
#    수정 전: 00:00 +9: All tests passed!        (회귀를 통째로 놓친다)
#    수정 후: Expected: <0>  Actual: <228>       (그 테스트만 실패, 나머지 8개는 통과)
# 3) sharpness.dart 원복 → 9/9 통과
```

수정 코드. `requirement_test.dart:46`(`_frame` 끝) 뒤에 헬퍼를 넣는다.

```dart
/// [image] 를 페인터와 같은 경로로 그려 RGBA 를 뜬다 — 비교의 진실값.
Future<Uint8List> _plain(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, kMapSide, kMapSide),
    Paint(),
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(kMapSide.toInt(), kMapSide.toInt());
  final data = await rendered.toByteData();
  picture.dispose();
  rendered.dispose();
  return data!.buffer.asUint8List();
}
```

`:106` 아래에 선언, `:114` 아래에 초기화를 더한다.

```dart
  late Uint8List zero;
  late Uint8List baseTruth;
```
```dart
    zero = await _frame(base, composed, prepared, 0);
    baseTruth = await _plain(base);
```

`:134-136` 을 교체한다.

```dart
    test('진행도 0 이면 갈색 바닥만 — 길·X·글씨 어느 것도 없다', () async {
      expect(
        _changed(zero, baseTruth, _all),
        0,
        reason: '진행도 0 의 화면은 base 를 그대로 그린 것과 픽셀이 같아야 한다 '
            '— 다르면 최종본이 미리 새고 있고, 이 파일의 모든 기준선(zero)이 오염된다',
      );
    });
```

`:204-226` 의 손으로 만든 truth 블록도 같은 헬퍼로 줄인다(중복 제거).

```dart
    test('진행도 1 에서 완성본과 픽셀이 같다 — 반투명 잔상이 없다', () async {
      final full = await _frame(base, composed, prepared, 1);
      expect(
        _changed(full, await _plain(composed), _all),
        0,
        reason: '연출이 끝났는데 원본과 다르면 마지막 획이 반투명하게 남은 것이다',
      );
    });
```

커밋: `test(example): 진행도 0 을 base 진실값과 비교해 항진식을 없앤다`

---

### 2단계 — "다 파졌다" 를 길 전체 마스크로, 첫 붉은 픽셀 시점에 잰다 (B4 + B9)

**1단계 의존(`_plain`).**

먼저 쓸 잠금 테스트 — 현재 자(`_roadBox`)가 무딘 것을 직접 잰다. **현재 파일에 붙이면 빨간불이다**(`Expected: a value less than <1732> / Actual: <1741>`).

```dart
    test('"다 파졌다" 자가 앞 굽이만 파인 프레임을 떨어뜨린다', () async {
      final quarter = await _frame(
        base,
        composed,
        prepared,
        prepared.stages.primaryEnd * 0.25, // 길 전체로는 23.31% 만 파인 프레임
      );
      final full = await _frame(base, composed, prepared, 1);
      expect(
        _changed(quarter, zero, _roadBox),
        lessThan((_changed(full, zero, _roadBox) * 0.98).floor()),
        reason: '길이 23% 만 파인 프레임을 "다 파졌다"로 통과시키면 그 자는 길을 안 재는 것이다',
      );
    });
```

X 쪽 잠금은 뮤테이션이다.

```
# packages/pen_reveal/lib/src/timing/timing_policy.dart:66
#   primaryToCrossGap = const Duration(milliseconds: 120)  →  milliseconds: 30
# cd example && flutter test test/requirement_test.dart
#   수정 전: 9/9 통과 (primaryEnd 에 붉은 X 가 이미 33px)
#   수정 후: Expected: <0>  Actual: <33>
```

수정 코드. `:98` 의 `_roadBox` 를 아래로 교체한다(다른 테스트가 아직 쓰므로 상자 자체는 남긴다).

```dart
/// 길만 지나는 자리 — X·글씨에서 멀리 떨어진 길 위 한 점(뱀꼴의 위쪽 굽이).
///
///   주의: 이 상자는 "길이 파이는 중" 을 보는 용도다. **"다 파졌다" 판정에 쓰지 마라** —
///   뱀꼴의 첫 굽이라 길 단계의 4분의 1(길 전체 23%)에 이미 98% 로 포화한다.
///   완주 판정은 `_roadCoverage` 를 쓴다.
Rect get _roadBox => const Rect.fromLTWH(150, 46, 120, 40);

/// [rect] 안에서 **붉게** 달라진 픽셀 수 — X·글씨 잉크만 세고 흰 길은 안 센다.
///
///   `_crossBox` 는 길 끝(둥근 캡)을 품고 있어 통째로 세면 길이 걸린다(실측 239px).
///   X 잉크는 R−G=125, 길은 R−G=2 라 이 문턱 하나로 갈린다. 문턱은 엔진이 붉다고 보는
///   그 값(`detector.dart` 의 `accentRedDeltaThreshold`)을 그대로 빌려 온다.
int _changedRed(Uint8List frame, Uint8List baseline, Rect rect) {
  final redDelta = const RevealDetectConfig().accentRedDeltaThreshold;
  var n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * kMapSide.toInt() + x) * 4;
      final d = (frame[i] - baseline[i]).abs() +
          (frame[i + 1] - baseline[i + 1]).abs() +
          (frame[i + 2] - baseline[i + 2]).abs();
      if (d > 40 && frame[i] - frame[i + 1] > redDelta) n++;
    }
  }
  return n;
}

/// composed−base 차이 중 **붉지 않은** 픽셀 전부 = 길. 바이트 오프셋 목록이다.
List<int> _buildRoadMask(Uint8List baseRgba, Uint8List composedRgba) {
  final redDelta = const RevealDetectConfig().accentRedDeltaThreshold;
  final mask = <int>[];
  for (var i = 0; i < baseRgba.length; i += 4) {
    final d = (composedRgba[i] - baseRgba[i]).abs() +
        (composedRgba[i + 1] - baseRgba[i + 1]).abs() +
        (composedRgba[i + 2] - baseRgba[i + 2]).abs();
    if (d <= 40) continue; // 안 변한 곳 = 바닥
    if (composedRgba[i] - composedRgba[i + 1] > redDelta) continue; // X·글씨
    mask.add(i);
  }
  return mask;
}
```

`main()` 안에 마스크 상태와 커버리지·시점 헬퍼를 둔다(`base`/`prepared` 를 잡아야 하므로 지역 함수다).

```dart
  late Uint8List baseTruth;
  late List<int> roadPixels;

  /// 길 픽셀 중 [frame] 에서 이미 드러난 비율(0~1).
  double roadCoverage(Uint8List frame) {
    var n = 0;
    for (final i in roadPixels) {
      final d = (frame[i] - zero[i]).abs() +
          (frame[i + 1] - zero[i + 1]).abs() +
          (frame[i + 2] - zero[i + 2]).abs();
      if (d > 40) n++;
    }
    return n / roadPixels.length;
  }

  /// 붉은 잉크가 **처음** 뜨는 진행도 — 요구사항의 "다 파지면" 이 가리키는 순간.
  ///
  ///   primaryEnd 가 아니다: 그 사이에 120ms 쉼이 있고 임계 선단이 시간축의 4.2% 를 먹는다.
  Future<double> firstRedProgress() async {
    var lo = prepared.stages.primaryEnd;
    var hi = prepared.stages.crossEnd;
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      final f = await _frame(base, composed, prepared, mid);
      if (_changedRed(f, zero, _crossBox) > 0) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }
```

`setUpAll` 에 한 줄 더한다.

```dart
    baseTruth = await _plain(base);
    roadPixels = _buildRoadMask(baseTruth, await _plain(composed));
```

`:150-163` 의 테스트를 교체한다.

```dart
    test('X 가 뜨는 순간 길은 도착지점까지 다 파여 있다', () async {
      final atRoad =
          await _frame(base, composed, prepared, prepared.stages.primaryEnd);
      expect(
        _changedRed(atRoad, zero, _crossBox),
        0,
        reason: '"다 파지면" 뒤에 X 다 — 길 단계가 끝나기도 전에 붉은 획이 비치면 순서가 깨진 것이다',
      );
      expect(_changed(atRoad, zero, _noteBox), 0, reason: '글씨는 아직');

      final atFirstRed =
          await _frame(base, composed, prepared, await firstRedProgress());
      expect(
        roadCoverage(atFirstRed),
        greaterThanOrEqualTo(0.999),
        reason: 'X 가 시작되는데 길이 한 구간이라도 덜 파여 있으면 "다 파지면" 이 거짓이다',
      );

      // 척도가 늘 0/1 이면 위 단언은 공허하다 — 실제로 세어지는지 같이 잠근다.
      final full = await _frame(base, composed, prepared, 1);
      expect(_changedRed(full, zero, _crossBox), greaterThan(200));
      expect(roadCoverage(zero), 0);
    });
```

커밋: `test(example): 길 완주를 전체 마스크로, X 시작 시점 기준으로 잰다`

---

### 3단계 — 색을 잰다 (B5)

**2단계 의존(`_changedRed`).**

먼저 쓸 잠금 테스트 — 픽스처 한 줄 뮤테이션.

```
# example/lib/fixtures/synthetic_map.dart:192
#   color: kMark,   →   color: Color(0xFF7C7CF9),   // 같은 밝기의 파란 글씨
# cd example && flutter test test/requirement_test.dart --tags regression \
#     --plain-name '갈색 바닥 · 흰 길 · 붉은 X · 빨간 글씨'
#   수정 전: 해당 테스트 자체가 없다. 기존 '마지막에 빨간 글씨가 나온다' 는 +1 통과(_changed=1950)
#   수정 후: Expected: a value greater than <60>  Actual: <-8>
```

수정 코드. `_changedRed` 아래에 평균색 헬퍼를 둔다.

```dart
/// [rect] 안 전체의 평균색.
({int r, int g, int b, int n}) _mean(Uint8List frame, Rect rect) {
  var r = 0, g = 0, b = 0, n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * kMapSide.toInt() + x) * 4;
      r += frame[i];
      g += frame[i + 1];
      b += frame[i + 2];
      n++;
    }
  }
  return (r: r ~/ n, g: g ~/ n, b: b ~/ n, n: n);
}

/// [rect] 안에서 [from] → [to] 사이에 **새로 드러난** 픽셀의 평균색.
({int r, int g, int b, int n}) _meanOfNew(
  Uint8List to,
  Uint8List from,
  Rect rect,
) {
  var r = 0, g = 0, b = 0, n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * kMapSide.toInt() + x) * 4;
      final d = (to[i] - from[i]).abs() +
          (to[i + 1] - from[i + 1]).abs() +
          (to[i + 2] - from[i + 2]).abs();
      if (d <= 40) continue;
      r += to[i];
      g += to[i + 1];
      b += to[i + 2];
      n++;
    }
  }
  return n == 0
      ? (r: 0, g: 0, b: 0, n: 0)
      : (r: r ~/ n, g: g ~/ n, b: b ~/ n, n: n);
}
```

`:199-202` 를 아래로 교체한다(요구사항 원문의 네 가지 색을 한 자리에서 잠근다).

```dart
    test('갈색 바닥 · 흰 길 · 붉은 X · 빨간 글씨', () async {
      // 실측값: 바닥 (134,116,98) · 길 (248,245,240) · X (246,124,123) · 글씨 (232,122,119)
      final atRoad =
          await _frame(base, composed, prepared, prepared.stages.primaryEnd);
      final atCross =
          await _frame(base, composed, prepared, prepared.stages.crossEnd);
      final full = await _frame(base, composed, prepared, 1);

      final soil = _mean(zero, const Rect.fromLTWH(4, 4, 40, 40));
      expect(soil.r, greaterThan(soil.g), reason: '바닥은 갈색이다');
      expect(soil.g, greaterThan(soil.b));
      expect(soil.r - soil.b, greaterThan(20));

      final road = _meanOfNew(atRoad, zero, _roadBox);
      expect(road.n, greaterThan(200));
      expect(road.r, greaterThan(200), reason: '길은 희다');
      expect((road.r - road.g).abs(), lessThan(25));
      expect((road.g - road.b).abs(), lessThan(25));

      final cross = _meanOfNew(atCross, atRoad, _crossBox);
      expect(cross.n, greaterThan(200));
      expect(cross.r - cross.g, greaterThan(60), reason: 'X 는 붉다');

      final note = _meanOfNew(full, atCross, _noteBox);
      expect(note.n, greaterThan(200));
      expect(note.r - note.g, greaterThan(60), reason: '글씨는 빨갛다');
      // 변화량만 보면 파란 글씨도 통과한다(실측 _changed=1950) — 그래서 색을 따로 센다.
      expect(_changed(full, zero, _noteBox), greaterThan(200));
    });
```

커밋: `test(example): 갈색·흰·붉은 — 요구사항의 색을 실제로 잰다`

---

### 4단계 — `` `\` → `/` `` 를 절대값으로 잠근다 (B6)

**독립.**

먼저 쓸 잠금 테스트 — 아래 수정 자체가 잠금이다. 현재 단언(`fwd < back`)으로는 잡히지 않고 새 단언에서만 잡히는 회귀: `timing_policy.dart:69` 의 `crossStrokeGap` 을 `50ms → -220ms` 로 바꿔 두 획을 겹치게 하면 기존 테스트는 통과, 새 테스트는 `fwd` 단언에서 실패한다.

수정 코드. `:165-182` 를 교체한다(실측 backFull=332, fwdFull=347, 창 중앙에서 back=332, fwd=15).

```dart
    test(r'`\` 를 다 긋고 나서 `/` 가 시작된다', () async {
      final s = prepared.stages;
      final full = await _frame(base, composed, prepared, 1);
      final backFull =
          _changed(full, zero, _backslashA) + _changed(full, zero, _backslashB);
      final fwdFull =
          _changed(full, zero, _slashA) + _changed(full, zero, _slashB);

      final mid = await _frame(
        base,
        composed,
        prepared,
        s.primaryEnd + (s.crossEnd - s.primaryEnd) * 0.5,
      );
      final back =
          _changed(mid, zero, _backslashA) + _changed(mid, zero, _backslashB);
      final fwd = _changed(mid, zero, _slashA) + _changed(mid, zero, _slashB);

      // 한쪽 끝만 나온 것을 합산이 가리지 못하게 양끝을 따로 본다.
      expect(_changed(mid, zero, _backslashA), greaterThan(0), reason: r'`\` 왼위');
      expect(_changed(mid, zero, _backslashB), greaterThan(0), reason: r'`\` 오른아래');
      expect(
        back,
        greaterThanOrEqualTo((backFull * 0.95).floor()),
        reason: r'`/` 가 시작될 무렵 `\` 는 이미 다 그어져 있어야 한다',
      );
      expect(
        fwd,
        lessThan((fwdFull * 0.1).ceil()),
        reason: r'`/` 가 `\` 와 겹쳐 그어지고 있다 — "\ 다음 /" 가 아니다',
      );
    });
```

주의: `_slashA` 는 길이 지나가 정상 빌드에서도 15px 이 잡힌다(fwdFull 의 4%). `0.1` 여유는 그 바닥을 감안한 값이다.

커밋: `test(example): X 두 획의 순서를 절대값으로 잠근다`

---

### 5단계 — 단조성·글씨 생성·합성 변종 (B16 + B17 + B18)

**독립. 셋 다 현재 구현이 옳고 잠금만 없다.**

수정 코드.

```dart
    test('드러난 양은 되돌아가지 않는다', () async {
      var prev = -1;
      for (var k = 0; k <= 20; k++) {
        final f = await _frame(base, composed, prepared, k / 20);
        final now = _changed(f, zero, _all);
        expect(now, greaterThanOrEqualTo(prev), reason: 'k=$k 에서 되감겼다');
        prev = now;
      }
    });

    test('글씨는 한 번에 안 튀고 왼→오로 써진다', () async {
      final s = prepared.stages;
      final full = await _frame(base, composed, prepared, 1);
      final noteFull = _changed(full, zero, _noteBox);
      final finalX = _centroidX(full, zero, _noteBox);

      final quarter = await _frame(
          base, composed, prepared, s.crossEnd + (1 - s.crossEnd) * 0.25);
      final half = await _frame(
          base, composed, prepared, s.crossEnd + (1 - s.crossEnd) * 0.5);
      final q = _changed(quarter, zero, _noteBox);
      final h = _changed(half, zero, _noteBox);

      expect(q, greaterThan((noteFull * 0.05).ceil()), reason: '4분의 1 인데 안 써졌다');
      expect(q, lessThan((noteFull * 0.5).floor()), reason: '4분의 1 인데 다 써졌다');
      expect(h, greaterThan(q), reason: '글씨가 자라지 않는다');
      expect(
        _centroidX(quarter, zero, _noteBox),
        lessThan(finalX - 20),
        reason: '왼쪽부터 써지지 않는다',
      );
    });
```

헬퍼(`_meanOfNew` 아래).

```dart
/// [rect] 안에서 [baseline] 과 달라진 픽셀들의 x 무게중심.
double _centroidX(Uint8List frame, Uint8List baseline, Rect rect) {
  var sx = 0.0;
  var n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * kMapSide.toInt() + x) * 4;
      final d = (frame[i] - baseline[i]).abs() +
          (frame[i + 1] - baseline[i + 1]).abs() +
          (frame[i + 2] - baseline[i + 2]).abs();
      if (d > 40) {
        sx += x;
        n++;
      }
    }
  }
  return n == 0 ? double.nan : sx / n;
}
```

합성 변종은 별도 group 으로 파일 끝(`main()` 안, 기존 group 뒤)에 붙인다. 실측: gentle 2314ms 0.442/0.705 · loop 3094ms 0.582/0.780 · X 없음 `hasCross=false` · 글씨 없음 `hasAnnotation=false`.

```dart
  group('요구사항 — 합성 한 장 말고 다른 입력', () {
    for (final shape in RoadShape.values) {
      test('길 모양 ${shape.name} 에서도 길→X→글씨 순서가 선다', () async {
        final pair = await buildSyntheticMap(shape: shape);
        addTearDown(pair.base.dispose);
        addTearDown(pair.composed.dispose);
        final p = await const RevealPreparer()
            .prepare(base: pair.base, composed: pair.composed);
        addTearDown(p.dispose);
        expect(p.stages.hasCross, isTrue);
        expect(p.stages.hasAnnotation, isTrue);
        expect(p.stages.crossEnd, greaterThan(p.stages.primaryEnd));
        expect(p.stages.annotationEnd, greaterThan(p.stages.crossEnd));
      });
    }

    test('X 가 없는 지도는 X 단계 없이 길→글씨로 끝난다', () async {
      final pair = await buildSyntheticMap(withCross: false);
      addTearDown(pair.base.dispose);
      addTearDown(pair.composed.dispose);
      final p = await const RevealPreparer()
          .prepare(base: pair.base, composed: pair.composed);
      addTearDown(p.dispose);
      expect(p.stages.hasCross, isFalse);
      expect(p.stages.hasAnnotation, isTrue);
      expect(p.stages.crossEnd, p.stages.primaryEnd, reason: '없는 단계는 앞으로 접힌다');
    });

    test('글씨가 없는 지도는 X 에서 끝난다', () async {
      final pair = await buildSyntheticMap(withNote: false);
      addTearDown(pair.base.dispose);
      addTearDown(pair.composed.dispose);
      final p = await const RevealPreparer()
          .prepare(base: pair.base, composed: pair.composed);
      addTearDown(p.dispose);
      expect(p.stages.hasCross, isTrue);
      expect(p.stages.hasAnnotation, isFalse);
    });
  });
```

커밋: `test(example): 단조성·글씨 생성·합성 변종을 잠근다`

---

### 6단계 — 정본 10벌을 실제로 그려 순서를 잠근다 (B7)

**독립. 1~5단계와 별개 파일이라 병렬 가능하지만, 규칙이 갈리는 지점(정본에서 primaryEnd 98% 규칙이 깨지는 것)을 2단계가 먼저 정리해 두면 두 파일의 기준이 일치한다.**

먼저 쓸 잠금 테스트 — 이 파일 자체가 잠금이다. 지금은 정본이 페인터를 한 번도 안 지나므로, 파일이 없는 상태가 곧 빨간불(커버리지 0)이다. 좌표 상수를 하나도 안 쓰고 판정 기준을 입력 두 장에서 직접 뽑는다. 미러에서 10벌 전부 1.4초에 통과 확인.

새 파일 `example/test/requirement_corpus_test.dart`:

```dart
// requirement_corpus_test.dart — **같은 요구사항을 정본 지도에 건다.**
//
//   requirement_test.dart 는 합성 한 장으로 순서를 잠근다. 그 한 장은 우리가 그린 것이라
//   좌표(X 중심·글씨 상자)를 상수로 적을 수 있었지만, 그래서 **엔진이 실제로 받는 그림**은
//   하나도 안 지난다. 실측으로 갈리는 지점이 있다: 합성은 길 단계가 0.61 에서 끝나는데
//   정본 map_basic_* 은 0.21~0.31 이고, 임계 선단이 시간축의 4.2% 라(k=24) primaryEnd 에서
//   길 98% 를 요구하면 map_basic_03 은 96.1% 로 빨개진다. 그래서 시간 기준을
//   **첫 붉은 픽셀이 뜨는 순간**으로 잡는다.
@Tags(['corpus', 'regression'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 위젯북 번들에 복사해 둔 정본 지도(`lib/fixtures/corpus_maps.dart` 참고).
const String kMapDir = 'assets/maps';

List<String> availableKeys() {
  final dir = Directory(kMapDir);
  if (!dir.existsSync()) return const [];
  final keys = <String>[];
  for (final file in dir.listSync()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('_composed.png')) continue;
    final key = name.substring(0, name.length - '_composed.png'.length);
    if (File('$kMapDir/${key}_base.png').existsSync()) keys.add(key);
  }
  return keys..sort();
}

String? get corpusSkip => availableKeys().isEmpty
    ? '정본 지도가 번들에 없다 — $kMapDir/<key>_{base,composed}.png 를 채운 뒤 다시 돌린다'
    : null;

Future<ui.Image> decode(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

int diffAt(Uint8List a, Uint8List b, int i) =>
    (a[i] - b[i]).abs() +
    (a[i + 1] - b[i + 1]).abs() +
    (a[i + 2] - b[i + 2]).abs();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('요구사항 — 정본 지도에서도 같은 순서인가', () {
    for (final key in availableKeys()) {
      test(key, () async {
        final base = await decode('$kMapDir/${key}_base.png');
        final composed = await decode('$kMapDir/${key}_composed.png');
        addTearDown(base.dispose);
        addTearDown(composed.dispose);
        expect(base.width, composed.width, reason: '두 장은 같은 구도여야 한다');
        expect(base.height, composed.height);

        final size = fitImageLongSide(composed, kBakeLongSide);
        final w = size.width;
        final h = size.height;
        final baseRgba = await rgbaAt(base, w, h);
        final composedRgba = await rgbaAt(composed, w, h);

        final prepared =
            await const RevealPreparer().prepare(base: base, composed: composed);
        addTearDown(prepared.dispose);
        final stages = prepared.stages;

        // ── 판정 기준을 입력 두 장에서 뽑는다 ──────────────────────────────
        final road = <int>[];
        final red = <int>[];
        for (var i = 0; i < w * h; i++) {
          final j = i * 4;
          if (diffAt(composedRgba, baseRgba, j) <= 18) continue;
          if (composedRgba[j + 3] < 200) continue;
          if (composedRgba[j] - composedRgba[j + 1] > 35) {
            red.add(i);
          } else {
            road.add(i);
          }
        }
        expect(road.length, greaterThan(500), reason: '길을 못 찾았다');
        expect(red.length, greaterThan(500), reason: '붉은 표시를 못 찾았다');

        Future<Uint8List> frame(double p) async {
          final recorder = ui.PictureRecorder();
          SequentialRevealPainter(
            base: base,
            composed: composed,
            prepared: prepared,
            progress: p,
          ).paint(ui.Canvas(recorder), Size(w.toDouble(), h.toDouble()));
          final pic = recorder.endRecording();
          final img = await pic.toImage(w, h);
          final data = await img.toByteData();
          pic.dispose();
          img.dispose();
          return data!.buffer.asUint8List();
        }

        final zero = await frame(0);
        Future<List<int>> revealed(List<int> mask, double p) async {
          final f = await frame(p);
          return [
            for (final i in mask)
              if (diffAt(f, zero, i * 4) > 40) i,
          ];
        }

        // ── ① 두 장을 받아 네 관문을 통과했다 ──────────────────────────────
        expect(stages.hasCross, isTrue, reason: 'X 를 못 잡으면 순서가 통째로 사라진다');
        expect(stages.hasAnnotation, isTrue);
        expect(stages.crossEnd, greaterThan(stages.primaryEnd));
        expect(stages.annotationEnd, greaterThan(stages.crossEnd));
        expect(
          prepared.revealDuration.inMilliseconds,
          inInclusiveRange(1200, 6000),
          reason: '"천천히" 는 사람이 볼 수 있는 길이여야 한다',
        );

        // ── ② 진행도 0 은 base 그대로, 1 은 composed 그대로 ────────────────
        Future<Uint8List> plain(ui.Image image) async {
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder).drawImageRect(
            image,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            Offset.zero & Size(w.toDouble(), h.toDouble()),
            Paint(),
          );
          final pic = recorder.endRecording();
          final img = await pic.toImage(w, h);
          final data = await img.toByteData();
          pic.dispose();
          img.dispose();
          return data!.buffer.asUint8List();
        }

        var offAtZero = 0;
        var offAtOne = 0;
        final truthBase = await plain(base);
        final truthComposed = await plain(composed);
        final one = await frame(1);
        for (var i = 0; i < w * h; i++) {
          if (diffAt(zero, truthBase, i * 4) > 40) offAtZero++;
          if (diffAt(one, truthComposed, i * 4) > 40) offAtOne++;
        }
        expect(offAtZero, 0, reason: '진행도 0 인데 base 가 아니다');
        // 주의: 합성은 0px 이지만 정본은 1~4px 이 남는다(실측). 눈에 보이는 잔상만 잡는다.
        expect(
          offAtOne,
          lessThanOrEqualTo(math.max(8, (w * h * 0.0001).round())),
          reason: '연출이 끝났는데 원본과 다르다 — 마지막 획이 반투명하게 남았다',
        );

        // ── ③ 길이 다 파지기 전에는 붉은 것이 하나도 없다 ──────────────────
        final roadFinal = (await revealed(road, 1)).length;
        expect(
          (await revealed(red, stages.primaryEnd)).length,
          0,
          reason: '길 단계가 끝나기도 전에 붉은 것이 나왔다',
        );

        // "다 파지면" 이 가리키는 순간 = 첫 붉은 픽셀이 뜨는 순간.
        var lo = stages.primaryEnd;
        var hi = stages.crossEnd;
        for (var i = 0; i < 16; i++) {
          final mid = (lo + hi) / 2;
          if ((await revealed(red, mid)).isNotEmpty) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        final roadAtFirstRed = (await revealed(road, hi)).length;
        expect(
          roadAtFirstRed,
          greaterThanOrEqualTo((roadFinal * 0.995).floor()),
          reason: 'X 가 시작되는데 길이 아직 덜 파였다 ($roadAtFirstRed / $roadFinal)',
        );

        // ── ④ X 는 도착지점에 — 길 위에 있고 그 언저리가 가장 늦게 파인다 ───
        final atRoadEnd = await frame(stages.primaryEnd);
        final atCrossEnd = await frame(stages.crossEnd);
        final cross = <int>[
          for (final i in red)
            if (diffAt(atCrossEnd, zero, i * 4) > 40 &&
                diffAt(atRoadEnd, zero, i * 4) <= 40)
              i,
        ];
        expect(cross.length, greaterThan(200), reason: 'X 획이 안 그어졌다');
        var sx = 0.0;
        var sy = 0.0;
        for (final i in cross) {
          sx += i % w;
          sy += i ~/ w;
        }
        final cx = sx / cross.length;
        final cy = sy / cross.length;

        var nearest = double.infinity;
        for (final i in road) {
          final dx = i % w - cx;
          final dy = i ~/ w - cy;
          final d = dx * dx + dy * dy;
          if (d < nearest) nearest = d;
        }
        expect(
          math.sqrt(nearest) / w,
          lessThan(0.05),
          reason: 'X 가 길 위에 있지 않다 — 도착지점이 아니다',
        );

        final nearX = <int>[];
        final farX = <int>[];
        for (final i in road) {
          final dx = i % w - cx;
          final dy = i ~/ w - cy;
          (dx * dx + dy * dy < 35 * 35 ? nearX : farX).add(i);
        }
        expect(nearX.length, greaterThan(50), reason: 'X 언저리에 길이 없다');
        expect(
          (await revealed(nearX, stages.primaryEnd * 0.8)).length,
          lessThan((nearX.length * 0.05).ceil()),
          reason: '도착지점 언저리가 먼저 파였다 — 길이 X 를 향해 가지 않는다',
        );
        expect(
          (await revealed(farX, stages.primaryEnd * 0.5)).length,
          greaterThan((farX.length * 0.25).floor()),
          reason: '길 단계 절반인데 길이 거의 안 파였다',
        );

        // ── ⑤ X 는 `\` 다음 `/` ───────────────────────────────────────────
        //   좌표를 안 적고 가른다: 화면 좌표에서 `\` 는 x·y 가 같이 커지고(공분산 > 0)
        //   `/` 는 반대다. 지도마다 X 기울기가 19°~38° 로 다른데도 부호는 안 흔들린다.
        double covariance(Iterable<int> pixels) {
          if (pixels.isEmpty) return 0;
          var mx = 0.0;
          var my = 0.0;
          for (final i in pixels) {
            mx += i % w;
            my += i ~/ w;
          }
          mx /= pixels.length;
          my /= pixels.length;
          var c = 0.0;
          for (final i in pixels) {
            c += (i % w - mx) * (i ~/ w - my);
          }
          return c / pixels.length;
        }

        final midCross =
            stages.primaryEnd + (stages.crossEnd - stages.primaryEnd) * 0.5;
        final drawn = (await revealed(cross, midCross)).toSet();
        final pending = [
          for (final i in cross)
            if (!drawn.contains(i)) i,
        ];
        expect(
          drawn.length,
          inInclusiveRange(
            (cross.length * 0.3).floor(),
            (cross.length * 0.7).ceil(),
          ),
          reason: 'X 창의 한복판인데 한 획만큼 그어져 있지 않다',
        );
        expect(covariance(drawn), greaterThan(0), reason: r'먼저 그은 획이 `\` 가 아니다');
        expect(covariance(pending), lessThan(0), reason: r'나중 획이 `/` 가 아니다');

        // ── ⑥ 글씨는 X 다음에, 한 번에 안 튀고 써진다 ─────────────────────
        final noteFinal = (await revealed(red, 1)).length - cross.length;
        expect(
          (await revealed(red, stages.crossEnd)).length,
          lessThanOrEqualTo(cross.length),
          reason: 'X 를 다 그은 순간에 글씨가 이미 나와 있다',
        );
        final noteMid =
            (await revealed(red, stages.crossEnd + (1 - stages.crossEnd) * 0.5))
                    .length -
                cross.length;
        expect(
          noteMid,
          inInclusiveRange((noteFinal * 0.1).floor(), (noteFinal * 0.95).ceil()),
          reason: '글씨가 한 번에 튀거나 끝까지 안 나온다 ($noteMid / $noteFinal)',
        );
      }, timeout: const Timeout(Duration(minutes: 5)), skip: corpusSkip);
    }
  }, skip: corpusSkip);
}
```

커밋: `test(example): 정본 지도를 실제로 그려 요구사항 순서를 잠근다`

---

### 7단계 — 시간축·재굽기 잠금 테스트 (B8)

**8단계의 선행. 이 테스트는 커밋 시점에 재굽기 쪽이 빨간불이므로 8단계와 같은 커밋에 넣는다.**

새 파일 `example/test/reveal_bench_test.dart`:

```dart
// reveal_bench_test.dart — 굽기 결과가 **실제 시간축**으로 이어지는지, 그리고 키가
//   그대로면 다시 굽지 않는지.
//
//   위젯북 use case 는 `source: () => buildSyntheticMap(...)` 처럼 클로저 리터럴을 넘긴다.
//   Dart 는 같은 리터럴에서 나온 클로저를 동등하게 보지 않으므로, didUpdateWidget 이
//   `old.source != widget.source` 로 판단하면 부모가 rebuild 될 때마다 재굽기가 돈다.
//   (위젯북은 use case 를 그린 다음 프레임에 `knobs.lock()` 으로 반드시 한 번 rebuild 한다.)
@Tags(['regression'])
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/synthetic_map.dart';
import 'package:pen_reveal_example/reveal_bench.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 굽기는 isolate·엔진 콜백을 탄다 — 가짜 시계만 돌리면 안 끝난다.
///   pumpAndSettle 도 금지다(굽는 동안 스피너가 무한히 돈다).
Future<void> _bakeSettle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200; i++) {
      if (find.byType(SequentialReveal).evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
}

/// 위젯북 use case 와 동형 — build 마다 새 클로저를 넘기지만 키는 그대로다.
class _Host extends StatefulWidget {
  const _Host({required this.onBake});
  final VoidCallback onBake;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _tick = 0;
  void rebuild() => setState(() => _tick++);

  Future<({ui.Image base, ui.Image composed})> _load() async {
    widget.onBake();
    return buildSyntheticMap();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('rebuild $_tick'),
          Expanded(
            child: RevealBench(
              key: const ValueKey('fixed'), // knob 이 안 바뀌었으니 키도 그대로
              sourceKey: 'fixed',
              autoPlay: false,
              source: () => _load(), // use case 와 같은 클로저 리터럴
            ),
          ),
        ],
      );
}

void main() {
  testWidgets('연출은 revealDuration 동안 선형으로 흐른다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RevealBench(sourceKey: 'synthetic', source: buildSyntheticMap),
        ),
      ),
    );
    await _bakeSettle(tester);
    await tester.pump();

    final finder = find.byType(SequentialReveal);
    expect(finder, findsOneWidget, reason: '굽기가 안 끝났다');
    double progress() => tester.widget<SequentialReveal>(finder).progress;
    final total =
        tester.widget<SequentialReveal>(finder).prepared.revealDuration;

    expect(total.inMilliseconds, inInclusiveRange(1200, 6000), reason: '천천히');

    final before = progress();
    await tester.pump(Duration(milliseconds: total.inMilliseconds ~/ 4));
    // curve 를 걸면 여기가 빨개진다 — 가감속은 이미 텍스처에 구워져 있다.
    expect(progress() - before, closeTo(0.25, 0.03), reason: '선형이 아니다');

    await tester.pump(total);
    expect(progress(), 1);
  });

  testWidgets('키가 그대로면 부모가 rebuild 돼도 다시 굽지 않는다', (tester) async {
    var bakes = 0;
    await tester.pumpWidget(MaterialApp(home: _Host(onBake: () => bakes++)));
    await _bakeSettle(tester);
    expect(bakes, 1, reason: '첫 굽기');

    for (var i = 0; i < 3; i++) {
      tester.state<_HostState>(find.byType(_Host)).rebuild();
      await tester.pump();
      await _bakeSettle(tester);
    }

    expect(
      bakes,
      1,
      reason: '부모 rebuild 3번에도 재굽기 0 이어야 한다 — 클로저 참조로 판단하면 4가 된다',
    );
  });
}
```

수정 전 두 번째 테스트는 `Actual: <4>` 로 빨간불이다(`sourceKey` 를 안 받는 상태에서는 컴파일부터 실패하므로 8단계와 한 커밋).

---

### 8단계 — 재굽기를 값으로 판단한다 (B1 + B2 + B19 + B10)

**7단계와 한 커밋. 8a(코어 값 동등성) → 8b(계측대) 순서 의존.**

**8a. `packages/pen_reveal/lib/src/timing/ease.dart`** — 두 기본 ease 에 값 동등성을 준다.

```dart
// LinearEase 안
  @override
  bool operator ==(Object other) => other is LinearEase;

  @override
  int get hashCode => (LinearEase).hashCode;

// PenEase 안
  @override
  bool operator ==(Object other) =>
      other is PenEase && other.edgeFraction == edgeFraction;

  @override
  int get hashCode => Object.hash(PenEase, edgeFraction);
```

**`packages/pen_reveal/lib/src/timing/timing_policy.dart`** — `HandwritingRevealTiming` 끝에 붙인다.

```dart
  /// 값으로 같으면 같다 — **호출부가 이 값을 키·비교에 쓰기 때문이다.**
  ///
  ///   계측대는 "리듬이 바뀌었나" 로 재굽기를 판단하고 위젯 키에도 넣는다. identity 로 두면
  ///   knob 값이 그대로여도 build 마다 다른 객체가 되어 State 가 통째로 재생성된다.
  @override
  bool operator ==(Object other) =>
      other is HandwritingRevealTiming &&
      other.primaryMinDuration == primaryMinDuration &&
      other.primaryMaxDuration == primaryMaxDuration &&
      other.primaryToCrossGap == primaryToCrossGap &&
      other.crossStrokeDuration == crossStrokeDuration &&
      other.crossStrokeGap == crossStrokeGap &&
      other.crossToAnnotationGap == crossToAnnotationGap &&
      other.annotationPerPixel == annotationPerPixel &&
      other.annotationMinDuration == annotationMinDuration &&
      other.annotationMaxDuration == annotationMaxDuration &&
      other.annotationGap == annotationGap &&
      other.strokeEase == strokeEase &&
      other.annotationEase == annotationEase;

  @override
  int get hashCode => Object.hash(
        primaryMinDuration,
        primaryMaxDuration,
        primaryToCrossGap,
        crossStrokeDuration,
        crossStrokeGap,
        crossToAnnotationGap,
        annotationPerPixel,
        annotationMinDuration,
        annotationMaxDuration,
        annotationGap,
        strokeEase,
        annotationEase,
      );
```

잠금(`packages/pen_reveal/test/timing/timing_policy_test.dart` 에 추가, 지금은 빨간불):

```dart
  test('타이밍 정책은 값으로 같다 — 호출부가 키에 hashCode 를 박는다', () {
    expect(
      const HandwritingRevealTiming(primaryMinDuration: Duration(seconds: 1)),
      HandwritingRevealTiming(primaryMinDuration: const Duration(seconds: 1)),
    );
    expect(
      const HandwritingRevealTiming().hashCode,
      HandwritingRevealTiming().hashCode,
    );
  });
```

**8b. `example/lib/reveal_bench.dart`** — 생성자에 `sourceKey` 를 더한다(`:36` 위).

```dart
  const RevealBench({
    required this.source,
    this.sourceKey,
    this.timing = const HandwritingRevealTiming(),
    this.sourceLabel = '합성 지도',
    this.autoPlay = true,
    this.showGroundTruth = false,
    super.key,
  });

  /// 지도 두 장을 어디서 얻을지.
  ///
  ///   주의: **이 값을 `==` 로 비교하지 마라.** 호출부는 `() => buildSyntheticMap(...)` 처럼
  ///   클로저 리터럴을 넘기고, Dart 는 같은 리터럴·같은 캡처값에서 나온 클로저도 동등하게
  ///   보지 않는다. 참조로 판단하면 부모가 rebuild 될 때마다 — 위젯북은 use case 를 그린
  ///   다음 프레임에 `knobs.lock()` 으로 반드시 한 번 rebuild 한다 — 아이솔레이트 spawn +
  ///   세선화 한 벌이 통째로 버려진다.
  final MapSource source;

  /// [source] 가 무엇을 만들지 식별하는 값. **이 값이 바뀔 때만** 다시 굽는다.
  ///
  ///   보통 `key` 에 넣는 문자열을 그대로 준다. `null` 이면 소스 변경으로는 다시 굽지
  ///   않는다(= 다시 굽히려면 `key` 를 바꿔 remount 시키라는 뜻).
  final Object? sourceKey;
```

`:81-86` 을 교체한다.

```dart
  @override
  void didUpdateWidget(RevealBench old) {
    super.didUpdateWidget(old);
    // `old.source != widget.source` 로 쓰지 마라 — 클로저는 매 build 마다 새 객체다.
    if (old.sourceKey != widget.sourceKey || old.timing != widget.timing) {
      unawaited(_bake());
    }
  }
```

`:103-144` 의 `_bake()` 를 통째로 교체한다(B10 소유권 + B19 선취소 검사 포함). `:112-117` 의 수동 dispose 는 finally 와 겹치므로 **반드시 사라져야 한다**.

```dart
  Future<void> _bake() async {
    final generation = ++_generation;
    setState(() => _error = null);
    // 받아 온 두 장은 state 에 넘기기 전까지 **이 함수가 소유한다** — 굽다 던져도 finally 가 놓는다.
    ui.Image? base;
    ui.Image? composed;
    var handedOver = false;
    try {
      final pair = await widget.source();
      base = pair.base;
      composed = pair.composed;

      // 굽기 **전에** 한 번 더 본다 — 세대 토큰이 커밋만 막으면 낡은 요청도 아이솔레이트를 판다.
      if (!mounted || generation != _generation) return;

      final prepared = await RevealPreparer(timing: widget.timing)
          .prepare(base: base, composed: composed);

      if (!mounted || generation != _generation) {
        prepared.dispose();
        return;
      }

      final oldPrepared = _prepared;
      final oldBase = _base;
      final oldComposed = _composed;
      handedOver = true; // 여기서부터 소유권은 state 다 — finally 는 손대지 않는다.
      setState(() {
        _prepared = prepared;
        _base = base;
        _composed = composed;
      });
      oldPrepared?.dispose();
      oldBase?.dispose();
      oldComposed?.dispose();

      // 빈 계획이면 0초짜리다 — 재생 로직에 넣지 않고 바로 끝으로 보낸다.
      if (prepared.revealDuration == Duration.zero) {
        _controller.value = 1;
        return;
      }
      _controller
        ..duration = prepared.revealDuration
        ..value = 0;
      if (widget.autoPlay) _playTo(1);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (!handedOver) {
        base?.dispose();
        composed?.dispose();
      }
    }
  }
```

**`example/lib/main.dart`** — 네 호출부에 키와 같은 값을 얹고, 정본 키에서 identity 해시를 뺀다.

```dart
  // _basic (:61)
  return RevealBench(
    key: ValueKey('basic-$width'),
    sourceKey: 'basic-$width',
    sourceLabel: '합성 · 뱀꼴',
    source: () => buildSyntheticMap(roadWidth: width),
  );

  // _shapes (:78)
  return RevealBench(
    key: ValueKey('shape-$shape'),
    sourceKey: 'shape-$shape',
    sourceLabel: '합성 · ${shape.name}',
    source: () => buildSyntheticMap(shape: shape),
  );

  // _edgeCases (:130)
  return RevealBench(
    key: ValueKey('edge-$withCross-$withNote'),
    sourceKey: 'edge-$withCross-$withNote',
    sourceLabel: '합성 · X=$withCross 글씨=$withNote',
    source: () => buildSyntheticMap(withCross: withCross, withNote: withNote),
  );

  // _CorpusPickerState.build (:216)
  child: RevealBench(
    // 리듬은 키에 넣지 않는다 — `didUpdateWidget` 이 State 를 살린 채 다시 굽고,
    //   그동안 앞 프레임이 화면에 남는다. 키에 넣으면 스피너로 되돌아간다.
    key: ValueKey('corpus-$selected'),
    sourceKey: 'corpus-$selected',
    sourceLabel: '정본 · $selected',
    showGroundTruth: widget.showGroundTruth,
    timing: widget.timing,
    source: () => loadCorpusMap(selected),
  ),
```

`example/tool/bench.dart`·`dump_stages.dart` 는 `RevealBench` 를 안 쓰므로 영향 없다.

커밋(둘로 나눈다 — 패키지 경계가 다르다):
- `feat(pen_reveal): 타이밍 정책과 ease 에 값 동등성을 준다`
- `fix(example): 굽기를 클로저 참조가 아니라 sourceKey 로 판단한다` (7단계 테스트 포함)

---

### 9단계 — 남은 자원·실패 표면 (B11 + B12)

**독립.**

먼저 쓸 잠금 테스트 — `example/test/reveal_bench_dispose_test.dart`. 수정 전 첫 테스트가 빨간불(`Expected: true / Actual: <false>`, "base 가 샌다"). 8단계에서 `_bake` 를 고쳤다면 이 테스트는 `loadCorpusMap` 쪽을 겨눈 형태로 남겨 두는 것이 낫다.

```dart
@Tags(['regression'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('composed 디코드가 실패하면 이미 디코드한 base 를 놓는다', () async {
    // corpus_maps 의 두 단계 디코드와 **같은 모양**을 여기서 재현한다 — 실제 자산을
    //   잘라야 하는 loadCorpusMap 을 CI 에서 돌릴 수 없기 때문이다.
    Future<ui.Image> decode(Uint8List bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    final good = await File('assets/maps/map_basic_01_base.png').readAsBytes();
    final base = await decode(good);
    ui.Image? leaked = base;
    try {
      await decode(Uint8List(0)); // 잘린 PNG
      fail('던져야 한다');
    } catch (_) {
      leaked?.dispose();
      leaked = null;
    }
    expect(base.debugDisposed, isTrue);
  }, skip: !File('assets/maps/map_basic_01_base.png').existsSync());
}
```

수정 코드 — `example/lib/fixtures/corpus_maps.dart:42-46`:

```dart
/// 키 하나를 두 장으로 읽는다. 호출부가 소유한다(다 쓰면 dispose).
///
///   주의: base 를 먼저 디코드하므로 **composed 가 실패하면 base 를 여기서 놓아야 한다** —
///   호출부는 아직 아무 핸들도 못 받았으니 놓을 수가 없다(자산이 잘려 있으면 실제로 난다).
Future<({ui.Image base, ui.Image composed})> loadCorpusMap(String key) async {
  final base = await _decode('assets/maps/${key}_base.png');
  try {
    final composed = await _decode('assets/maps/${key}_composed.png');
    return (base: base, composed: composed);
  } catch (_) {
    base.dispose();
    rethrow;
  }
}
```

`example/lib/fixtures/synthetic_map.dart` 의 두 단계 렌더에도 같은 형태를 넣는다.

`example/lib/main.dart:156-170` — 실패 표면을 준다.

```dart
class _CorpusPickerState extends State<_CorpusPicker> {
  List<String>? _keys;
  String? _selected;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final keys = await availableCorpusKeys();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _selected = keys.isEmpty ? null : keys.first;
      });
    } catch (error) {
      // 매니페스트 로드는 웹에서 실제로 실패한다 — 안 잡으면 스피너가 영원히 돌고
      //   거절은 zone 으로 새어 화면에 아무 신호도 안 남는다.
      if (!mounted) return;
      setState(() => _error = error);
    }
  }
```

`build` 앞부분:

```dart
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('정본 목록을 못 읽었다 — $error',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  unawaited(_load());
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
```

`import 'dart:async';` 를 파일 상단에 더한다.

커밋: `fix(example): 굽기 실패 경로에서 자원과 오류를 흘리지 않는다`

---

### 10단계 — stage_marks 를 형제와 같은 규칙으로 (B13 + B14 + B21 + B22)

**독립. 코어 패키지만 건드린다.**

먼저 쓸 잠금 테스트 — `packages/pen_reveal/test/timing/stage_marks_test.dart` 에 추가. 수정 전 둘 다 빨간불(`[1.0,1.0,1.0]` / `crossEnd=1.0`, `hasCross=true`).

```dart
/// 창 순서만 뒤집은 정책 — segmentId 는 그대로다.
class _ReversedListingTiming implements RevealTimingPolicy {
  const _ReversedListingTiming();
  @override
  RevealSchedule schedule(RevealPlan plan) {
    final base = const HandwritingRevealTiming().schedule(plan);
    return RevealSchedule(
      windows: base.windows.reversed.toList(),
      total: base.total,
    );
  }
}

/// X 는 즉시 보이게 두고 창을 안 만드는 정책.
class _SkipCrossTiming implements RevealTimingPolicy {
  const _SkipCrossTiming();
  @override
  RevealSchedule schedule(RevealPlan plan) {
    final base = const HandwritingRevealTiming().schedule(plan);
    return RevealSchedule(
      windows: [
        for (final w in base.windows)
          if (plan.segments[w.segmentId].kind !=
                  RevealSegmentKind.crossBackslash &&
              plan.segments[w.segmentId].kind != RevealSegmentKind.crossSlash)
            w,
      ],
      total: base.total,
    );
  }
}

  group('창은 나열 순서가 아니라 segmentId 로 짝짓는다', () {
    final plan = _plan([
      _seg(0, RevealSegmentKind.primaryStroke, relativeLength: 0.5),
      _seg(1, RevealSegmentKind.crossBackslash),
      _seg(2, RevealSegmentKind.crossSlash),
      _seg(3, RevealSegmentKind.annotation),
    ]);

    test('창 나열 순서를 뒤집어도 경계가 그대로다 — 텍스처가 안 흔들리는 것과 같이', () {
      final ordered = const HandwritingRevealTiming().schedule(plan);
      final shuffled = const _ReversedListingTiming().schedule(plan);

      const compiler = RevealTextureCompiler();
      expect(compiler.compile(plan, shuffled),
          orderedEquals(compiler.compile(plan, ordered)));
      expect(RevealStageMarks.of(plan, shuffled).inOrder,
          orderedEquals(RevealStageMarks.of(plan, ordered).inOrder));
    });

    test('X 창을 안 내는 정책이면 crossEnd 가 primaryEnd 로 접힌다', () {
      final schedule = const _SkipCrossTiming().schedule(plan);
      final marks = RevealStageMarks.of(plan, schedule);

      expect(marks.primaryEnd, schedule.windows[0].end);
      expect(marks.crossEnd, marks.primaryEnd);   // 고치기 전: 1.0
      expect(marks.hasCross, isFalse);            // 고치기 전: true
      expect(marks.hasAnnotation, isTrue);        // 고치기 전: false
      expect(marks.annotationEnd, schedule.windows[1].end);
    });
  });
```

수정 코드 — `stage_marks.dart:42-60` 을 교체한다.

```dart
    // 짝짓기는 **세그먼트 id 로** 한다 — 나열 순서가 아니라. `texture_compiler.dart` 가
    //   `window.segmentId` 로 짝짓는 것과 같은 규칙이라, 창을 걸러 내거나 순서를 바꾼
    //   정책에서도 두 소비자가 같은 일정을 같게 읽는다.
    final kinds = <int, RevealSegmentKind>{
      for (final segment in plan.segments) segment.id: segment.kind,
    };

    var primaryEnd = 0.0;
    var crossEnd = 0.0;
    var annotationEnd = 0.0;

    for (final window in schedule.windows) {
      final kind = kinds[window.segmentId];
      if (kind == null) continue;
      final end = window.end;
      switch (kind) {
        case RevealSegmentKind.primaryStroke:
          if (end > primaryEnd) primaryEnd = end;
        case RevealSegmentKind.crossBackslash:
        case RevealSegmentKind.crossSlash:
          if (end > crossEnd) crossEnd = end;
        case RevealSegmentKind.annotation:
          if (end > annotationEnd) annotationEnd = end;
      }
    }
```

`:30-31` 의 독스트링을 바꾼다.

```dart
  ///   창은 `SegmentWindow.segmentId` 로 짝짓는다 — 나열 순서에 기대지 않는다.
```

**B14(좌표계 어긋남)는 보정하지 않고 문서를 정직하게 고친다.** 보정하려면 `RevealStageMarks.of` 가 `RevealSharpness` 를 받아야 해서 시그니처가 바뀌는데, 실측 어긋남이 47.8ms(총 3.3초의 1.45%)이고 지금 이 값을 쓰는 곳은 되감기 UI 뿐이다. 소리·햅틱을 얹게 되면 그때 보정을 넣는다. `:85-92` 의 doc:

```dart
  /// 길을 긋는 **창이 끝나는** 진행도. 주 획이 없으면 `0`.
  ///
  ///   주의: "픽셀이 완전히 불투명해지는 순간" 보다 조금 이르다. 페인터는 알파를
  ///   `k·(progress·255 − order)` 로 계산하므로 선단이 `255/k`(기본 k=24 → 진행도 4.2%)
  ///   만큼 번져 있다. 합성 지도 실측으로 47.8ms(총 3292ms) 차이다. 소리·햅틱처럼
  ///   "정말 다 그려진 순간" 이 필요하면 이 값에 `255 / sharpness.k / 255` 를 더해서 쓴다.
  final double primaryEnd;
```

이 관계를 `stage_marks_test.dart` 에 못 박는다.

```dart
  test('경계는 창의 끝이지 완전 불투명 시점이 아니다 — 선단만큼 이르다', () {
    const s = RevealSharpness.standard;
    // 마크에서 마지막 순서값의 알파는 아직 255 가 아니다.
    final marks = RevealStageMarks.of(plan, schedule);
    final lastOrder = (marks.primaryEnd * s.maxOrderValue).round();
    expect(
      s.alphaAt(order: lastOrder, progress: marks.primaryEnd),
      lessThan(255),
      reason: 'doc 이 "다 파진 순간" 이라고 말하면 안 되는 이유가 이것이다',
    );
  });
```

**B21·B22** — 같은 파일에 값 동등성과 시험용 표시를 붙인다.

```dart
  /// 단계 구분이 없는 연출 — 처음부터 끝까지 한 덩어리다.
  ///
  ///   주의: **굽기를 거친 결과에 이 값을 붙이지 마라.** `annotationEnd == 1` 인데
  ///   `hasCross`·`hasAnnotation` 은 둘 다 `false` 라, 텍스처에 X 가 멀쩡히 들어 있어도
  ///   호출부는 "X 가 없다" 로 읽는다. 손으로 만든 텍스처를 페인터로 그려 볼 때만 쓴다.
  @visibleForTesting
  static const RevealStageMarks unstaged = RevealStageMarks(
    primaryEnd: 1,
    crossEnd: 1,
    annotationEnd: 1,
  );

  @override
  bool operator ==(Object other) =>
      other is RevealStageMarks &&
      other.primaryEnd == primaryEnd &&
      other.crossEnd == crossEnd &&
      other.annotationEnd == annotationEnd;

  @override
  int get hashCode => Object.hash(primaryEnd, crossEnd, annotationEnd);
```

`single` → `unstaged` 이름 변경은 호출부 3곳(`sequential_reveal_test.dart:60,91,244`)만 고치면 된다. `meta` 의존을 코어에 넣기 싫으면 `@visibleForTesting` 은 빼고 doc 경고만 남긴다.

커밋(셋으로 나눈다):
- `fix(pen_reveal): 단계 경계를 segmentId 로 짝짓는다`
- `docs(pen_reveal): 단계 경계가 "창의 끝" 임을 정직하게 적는다`
- `refactor(pen_reveal): RevealStageMarks 에 값 동등성을 주고 시험용 상수를 표시한다`

---

### 11단계 — 입력 계약 가드 (B15)

**독립. 동작 변경이므로 단독 커밋.**

먼저 쓸 잠금 테스트 — `packages/pen_reveal_flutter/test/reveal_preparer_test.dart` 에 추가. 수정 전 빨간불(안 던지고 `hasCross=false` 인 연출이 나온다).

```dart
  test('구도가 다른 두 장은 거절한다 — 조용히 굽지 않는다', () async {
    final base = await _painted(200, 100);
    final composed = await _painted(100, 160, stroke: _bar);
    addTearDown(base.dispose);
    addTearDown(composed.dispose);

    // 지금은 base 를 composed 기준으로 리샘플해 버려 던지지 않는다. 그 결과는
    //   "hasCross=false 인 그럴듯한 연출" 이고, 요구사항의 `\`→`/` 가 조용히 사라진다.
    await expectLater(
      const RevealPreparer(longSide: 160).prepare(base: base, composed: composed),
      throwsArgumentError,
    );
  });
```

수정 코드 — `reveal_preparer.dart:96`(`final size = ...` 바로 앞):

```dart
    // 두 장의 비율이 다르면 리샘플이 화면 전체를 '변한 곳' 으로 만든다 — 조용히 굽지 않는다.
    if (base.width * composed.height != composed.width * base.height) {
      throw ArgumentError(
        '두 장은 같은 구도여야 한다 — '
        'base ${base.width}×${base.height}, composed ${composed.width}×${composed.height}',
      );
    }
```

레포 안 모든 호출부(테스트 5곳, 계측대, tool 2개, 정본 자산)가 같은 크기 쌍이므로 파급 없다.

커밋: `fix(pen_reveal_flutter): 구도가 다른 두 장을 거절한다`

---

### 12단계 — nit 묶음 (B20 + B23 + B24)

**독립. 마지막에 한 커밋.**

`example/lib/reveal_bench.dart:338-344`:

```dart
  RevealStage _currentStage(PreparedReveal prepared) {
    final p = _controller.value;
    if (p <= 0) return RevealStage.start;
    // `_jumpTo` 가 마크에 정확히 착지시키므로 등호는 **그 단계 쪽**이다 —
    //   `<` 로 두면 방금 누른 버튼이 아니라 다음 버튼에 불이 들어온다.
    if (p <= prepared.stages.primaryEnd) return RevealStage.road;
    if (p <= prepared.stages.crossEnd) return RevealStage.cross;
    return RevealStage.end;
  }
```

`packages/pen_reveal/test/purity_test.dart` — `_planDir` 바닥 옆에 timing 바닥과 배럴 완전성을 더한다.

```dart
    test('감시 대상이 비어 있지 않다', () {
      expect(_dartFiles(_timingDir).length, greaterThanOrEqualTo(5));
    });

    test('timing 디렉터리의 모든 파일이 배럴에 실린다', () {
      final barrel = File('lib/timing.dart').readAsStringSync();
      for (final path in _dartFiles(_timingDir)) {
        expect(
          barrel.contains(path.split('/').last),
          isTrue,
          reason: '$path 가 lib/timing.dart 에서 export 되지 않는다',
        );
      }
    });
```

`requirement_corpus_test.dart` 끝 — 정본이 몇 "가지" 인지 기록한다. **미검증**: 8단계 지문이 두 장을 정말 같게 묶는지 한 번 돌려 보고 단계 수를 조정하라(앞의 모든 코드는 실행 확인했다).

```dart
  test('정본은 파일 10벌이지만 서로 다른 그림은 9가지다', () async {
    // map_deep_02 와 map_deep_06 은 사실상 같은 그림이다(936k 중 임계 초과 1px).
    //   코퍼스가 실제로 몇 가지를 덮는지 헷갈리지 않게 여기에 적어 둔다.
    final keys = availableKeys();
    expect(keys, hasLength(10), reason: '번들에 10벌이 있어야 한다');

    final fingerprints = <String, String>{};
    for (final key in keys) {
      final composed = await decode('$kMapDir/${key}_composed.png');
      final size = fitImageLongSide(composed, 64);
      final rgba = await rgbaAt(composed, size.width, size.height);
      composed.dispose();
      final sb = StringBuffer();
      for (var i = 0; i < rgba.length; i += 4) {
        sb.writeCharCode(65 + (rgba[i] >> 5));
      }
      fingerprints[key] = sb.toString();
    }
    expect(
      fingerprints.values.toSet(),
      hasLength(9),
      reason: 'map_deep_02 와 map_deep_06 이 같은 그림이다 — "10종" 은 9가지다',
    );
  }, timeout: const Timeout(Duration(minutes: 5)), skip: corpusSkip);
```

커밋: `fix(example): 단계 강조 경계를 버튼 착지점에 맞추고 감시 바닥을 채운다`

---

## 4. 한 커밋으로 묶을 것 / 나눌 것

### 묶을 것

| 묶음 | 왜 |
|---|---|
| 7단계 + 8단계(계측대 부분) | 잠금 테스트가 `sourceKey` 파라미터를 참조하므로 수정 없이는 컴파일부터 실패한다. 빨간 커밋을 남기지 않으려면 한 덩어리 |
| B1 + B2 + B19 + B10(=8단계) | 원인이 하나다 — "값이어야 할 것을 참조로 비교했다". 되돌린다면 넷을 같이 되돌려야 재굽기 동작이 일관된다. `_bake` 를 한 번만 다시 쓰는 것이 diff 도 작다 |
| B11 + B12(=9단계) | 둘 다 "굽기 실패 경로에서 흘리지 않는다" 하나의 규칙. `synthetic_map` 의 동형 가드도 여기 포함 |
| B20 + B23 + B24(=12단계) | 전부 nit. 개별 커밋으로 나눌 가치가 없다 |
| B21 + B22 | 둘 다 `RevealStageMarks` 의 값 타입성 문제. 한 커밋 |

### 나눌 것

| 나눔 | 왜 |
|---|---|
| 8a(`pen_reveal` 값 동등성) ↔ 8b(`example` 배선) | 패키지 경계가 다르다. 코어 변경은 계측대와 무관하게 되돌릴 수 있어야 한다. **순서 의존**: 8a 가 먼저다 |
| 계측 테스트 6건(1~6단계) 각각 | 요구사항 원문의 서로 다른 절을 잠근다. 어느 하나가 정본에서 흔들리면 그것만 되돌려야 한다. **순서 의존**: 1 → 2 → 3 → 4(헬퍼 공유). 5·6 은 병렬 가능 |
| B13(segmentId) ↔ B14(문서) ↔ B21/B22(값 타입) | 앞은 동작 변경, 가운데는 문서 정정, 뒤는 API 표시. 되돌리기 이유가 전부 다르다 |
| B15(입력 가드) | 유일하게 공개 API 의 **거절 범위**를 넓히는 변경이다. 밖에서 문제가 생기면 이것만 되돌릴 수 있어야 한다 |

### 전체 순서 요약

```
1 → 2 → 3 → 4      (계측대 헬퍼 사슬, test-only, 커밋할 때 전부 초록)
5, 6               (병렬 가능, test-only)
8a → 7+8b          (코어 값 동등성 → 계측대 재굽기, 유일하게 큰 동작 변경)
9                  (자원·오류 표면)
10(3커밋), 11, 12  (코어 정리 → 입력 가드 → nit)
```

각 단계 끝에서 돌릴 것: `cd example && flutter test --tags regression` + `flutter analyze`, `cd packages/pen_reveal && dart test` (현재 126 통과) + `cd packages/pen_reveal_flutter && flutter test`.