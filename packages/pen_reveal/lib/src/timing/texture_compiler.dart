// src/timing/texture_compiler.dart — 구조(계획) + 시간(정책) → **순서 텍스처 한 장**.
//
//   왜 여러 장이 아니라 한 장인가: 세그먼트가 전부 같은 색·같은 합성 규칙이고, 한 전역
//   진행도로 한 번씩만 순차 재생되고, 재생 중 되감기·반복이 없다. 그런 조건에선 마스크를
//   N 장 들고 매 프레임 `saveLayer` × N 을 쌓는 것보다 **준비할 때 한 번** 21만 픽셀을
//   훑어 한 장으로 굽는 편이 훨씬 싸다.
//
//   마스크가 여러 장이어야 하는 건 이런 때다 — 세그먼트마다 blend mode·색이 다르거나,
//   일부만 반복·역재생·일시정지하거나, 사용자 입력이 세그먼트 진행도를 따로 움직이거나,
//   재생 도중 타이밍 정책이 계속 바뀔 때.
//
//   ⚠️ **프레임마다 부르면 안 된다.** 계획과 정책이 바뀔 때만 다시 굽는다.
//
//   순수 Dart 다 — 바이트를 텍스처로 부풀리는 것은 렌더 패키지 몫이다.
import 'dart:typed_data';

import 'package:pen_reveal/src/plan/reveal_plan.dart';
import 'package:pen_reveal/src/timing/ease.dart';
import 'package:pen_reveal/src/timing/sharpness.dart';
import 'package:pen_reveal/src/timing/timing_policy.dart';

/// 계획과 일정을 0~[RevealSharpness.maxOrderValue] 시간축 한 장으로 굽는다.
///
///   렌더가 `alpha = k·(progress·255 − order)` 계단 임계로 읽는 그 맵이다. 값이 작을수록
///   먼저 드러나고 [kRevealHiddenSegment] 는 영영 안 드러난다.
class RevealTextureCompiler {
  const RevealTextureCompiler({this.sharpness = RevealSharpness.standard});

  /// 굽는 쪽과 그리는 쪽이 **같은 값을 봐야 한다**. 그래서 double 이 아니라 이 타입을 받고,
  ///   굽기 결과(`PreparedReveal`)가 이 객체를 그대로 들고 렌더까지 간다 — 렌더가 자기
  ///   상수를 갖지 않으므로 어긋날 수가 없다.
  final RevealSharpness sharpness;

  /// 이 값까지만 쓴다 — 그 위는 렌더가 불투명하게 못 만드는 구간이다.
  int get maxOrderValue => sharpness.maxOrderValue;

  /// `plan.width * plan.height` 바이트.
  Uint8List compile(RevealPlan plan, RevealSchedule schedule) {
    final out = Uint8List(plan.width * plan.height)
      ..fillRange(0, plan.width * plan.height, kRevealHiddenSegment);
    if (plan.isEmpty || schedule.windows.isEmpty) return out;

    // 세그먼트 id 는 0..254 라 배열 조회가 맵보다 싸고 확실하다.
    final starts = Float64List(kRevealHiddenSegment);
    final spans = Float64List(kRevealHiddenSegment);
    final eases = List<RevealEase?>.filled(kRevealHiddenSegment, null);
    for (final window in schedule.windows) {
      if (window.segmentId < 0 || window.segmentId >= kRevealHiddenSegment) {
        continue;
      }
      starts[window.segmentId] = window.start;
      spans[window.segmentId] = window.end - window.start;
      eases[window.segmentId] = window.ease;
    }

    final top = maxOrderValue;
    for (var i = 0; i < out.length; i++) {
      final id = plan.segmentId[i];
      if (id == kRevealHiddenSegment) continue;
      final ease = eases[id];
      if (ease == null) continue;
      final within = plan.within[i] / kRevealWithinScale;
      final time = starts[id] + spans[id] * ease.timeOf(within);
      final value = (time.clamp(0.0, 1.0) * top).round();
      out[i] = value >= kRevealHiddenSegment ? top : value;
    }
    return out;
  }

  // 값 동등성 — [sharpness] 가 값으로 같으면 같은 컴파일러다. 굽기를 다시 할지 정하는
  //   쪽(계측대의 가파르기 손잡이 등)이 이걸 본다. 참조 동등성이면 매 build 마다
  //   "바뀌었다" 가 되어 열 때마다 두 번 굽는다 — `HandwritingRevealTiming` 이 같은
  //   이유로 이미 값 동등성을 갖고 있다.
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevealTextureCompiler && other.sharpness == sharpness);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => sharpness.hashCode;
}

/// 순서맵을 회색 RGBA 로 부풀린다 — 이미지 디코더에 그대로 넣는 형태다.
///
///   ⚠️ 알파를 255 로 채운다. 텍스처의 **색 채널**이 시간이고, 알파는 렌더의 색행렬이
///   새로 계산한다.
Uint8List revealOrderToRgba(Uint8List order) {
  final rgba = Uint8List(order.length * 4);
  for (var i = 0; i < order.length; i++) {
    final j = i * 4;
    rgba[j] = order[i];
    rgba[j + 1] = order[i];
    rgba[j + 2] = order[i];
    rgba[j + 3] = 255;
  }
  return rgba;
}
