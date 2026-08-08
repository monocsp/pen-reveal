// src/sequential_reveal.dart — 그림 두 장(바닥/최종)과 구워 둔 순서 텍스처를 주면
//   최종본이 **순차로 그려지듯** 드러나는 표현 프리미티브.
//
//   바닥을 깔고 그 위에 최종본을 얹되, 순서 텍스처가 `progress` 보다 이른 곳만 `dstIn` 으로
//   남긴다. 픽셀이 전부 최종본 한 장에서 나오므로 색·해상도·질감이 어긋날 여지가 없다 —
//   획을 다시 그리는 근사가 아니라 **원본을 드러내는** 방식이다.
//
//   [progress] 만 받는 순수 표현이다. "무엇을 언제 드러낼지"(굽기)는 `reveal_preparer.dart`,
//   "얼마나 오래"는 굽기 결과의 `revealDuration` 이 답한다.
//
//   ⚠️ **임계 가파르기 상수를 이 파일에 만들지 마라.** [PreparedReveal] 이 자기가 구워진
//   `RevealSharpness` 를 들고 오니 그걸 받아 쓴다. 원본은 같은 24 를 굽는 쪽과 그리는 쪽에
//   따로 뒀다가 "연출이 끝나도 마지막 획이 반투명하게 남는" 버그를 안고 있었다.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pen_reveal_flutter/src/reveal_preparer.dart';

/// 순서 텍스처를 임계로 잘라 최종본을 드러낸다.
///
///   [base]·[composed] 는 **같은 구도**여야 하고, [prepared] 는 그 둘을 구운 결과
///   (`RevealPreparer.prepare`)여야 한다. 세 장 모두 [size] 에 늘여 그린다
///   (`BoxFit.fill` 상당) — 원본 비율과 다르면 그대로 찌그러진다.
class SequentialReveal extends StatelessWidget {
  const SequentialReveal({
    required this.base,
    required this.composed,
    required this.prepared,
    required this.progress,
    required this.size,
    super.key,
  });

  /// 아무것도 드러나지 않은 상태(진행도 0 에서 보이는 그림).
  final ui.Image base;

  /// 다 드러난 상태(진행도 1 에서 보이는 그림).
  final ui.Image composed;

  /// 구워 둔 순서 텍스처와 **그 텍스처를 구울 때 쓴 가파르기** 한 벌.
  ///
  ///   ⚠️ 텍스처와 가파르기를 **따로 받지 않는다.** 따로 받는 순간 호출부가 굽지 않은 k 를
  ///   섞어 넣을 수 있고, 그러면 마지막 획이 반투명하게 남는 그 버그가 되돌아온다.
  final PreparedReveal prepared;

  /// 0=바닥만, 1=최종본. 범위를 벗어나도 안쪽에서 잘라 쓴다.
  final double progress;

  final Size size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: size,
        painter: SequentialRevealPainter(
          base: base,
          composed: composed,
          prepared: prepared,
          progress: progress,
        ),
      );
}

/// [SequentialReveal] 의 합성 규칙. 위젯 없이 캔버스에 직접 그릴 때도 쓴다.
class SequentialRevealPainter extends CustomPainter {
  const SequentialRevealPainter({
    required this.base,
    required this.composed,
    required this.prepared,
    required this.progress,
  });

  final ui.Image base;
  final ui.Image composed;
  final PreparedReveal prepared;
  final double progress;

  Rect _src(ui.Image i) =>
      Offset.zero & Size(i.width.toDouble(), i.height.toDouble());

  /// ⚠️ 합성 순서의 함정 둘:
  ///   · **`blendMode` 와 `colorFilter` 를 한 `Paint` 에 같이 두면 안 된다**(실기 확인) —
  ///     레이어를 따로 나눠야 마스크가 먹는다.
  ///   · 임계 행렬의 translation 열은 **0~255 공간**이라 `×255` 를 빠뜨리면 마스크가 통째로
  ///     사라진다. 그 계산은 `RevealSharpness` 가 소유하므로 여기서 다시 쓰지 않는다.
  @override
  void paint(ui.Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas
      ..drawImageRect(base, _src(base), dst, Paint())
      ..saveLayer(dst, Paint())
      ..drawImageRect(composed, _src(composed), dst, Paint())
      ..saveLayer(dst, Paint()..blendMode = BlendMode.dstIn)
      ..drawImageRect(
        prepared.reveal,
        _src(prepared.reveal),
        dst,
        Paint()
          ..colorFilter = ColorFilter.matrix(
            prepared.sharpness.thresholdMatrix(progress),
          ),
      )
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(SequentialRevealPainter old) =>
      old.progress != progress ||
      old.composed != composed ||
      old.prepared != prepared ||
      old.base != base;
}
