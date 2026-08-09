// fixtures/synthetic_map.dart — 자산 없이 코드로 그리는 땅속 지도 두 장.
//
//   정본 지도는 디자인 자산이라 레포에 없다. 그런데 계측대가 자산을 요구하면 아무도 못
//   돌려 본다 — 그래서 **엔진이 요구하는 성질만 갖춘 최소 지도**를 절차적으로 그린다.
//
//   엔진이 요구하는 성질은 넷이다:
//     ① base 와 composed 의 **바닥이 픽셀 단위로 같아야** 한다. 탐지는 색이 아니라 두 장의
//        차이로 길을 찾으므로, 바닥을 따로 그리면(난수 씨앗이 다르거나 순서가 다르면)
//        화면 전체가 '변한 곳'으로 잡힌다. 그래서 같은 `_paintGround` 를 둘 다 부른다.
//     ② 길은 **붉지 않아야** 한다(R−G ≤ 35). 흰색이면 R−G=0 이라 넉넉하다.
//     ③ X 는 붉고(R−G > 35), 길 끝에 붙어 있고, 캔버스 면적의 0.50~1.05% 여야 한다.
//        네 관문 중 면적과 위치가 가장 까다롭다 — `detector.dart` 의 `_pickCross`.
//     ④ 문구는 붉되 길에서 **충분히 멀어야** 한다. X 보다 1.6배 이상 멀지 않으면
//        "길에 가장 가까운 붉은 덩어리" 경쟁에서 X 를 밀어낸다.
//
//   ⚠️ 바닥에 일부러 얼룩을 넣었다. 진짜 지도에도 나무·언덕 그림자가 있고, 그것이 두 장에
//   똑같이 들어 있어 뺄 때 상쇄된다는 것이 이 설계의 핵심이라서다. 얼룩이 없으면 계측대가
//   실제보다 쉬운 문제를 푸는 셈이 된다.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 굽기 해상도와 같게 그린다 — 리샘플이 끼지 않아 계측이 선명하다.
const double kMapSide = 420;

/// 땅(갈색). 진짜 지도의 `#897664` 계열.
const Color kSoil = Color(0xFF8A7765);

/// 길(흰색). R−G = 2 라 붉기 판정에서 한참 멀다.
const Color kRoad = Color(0xFFFFFDF8);

/// 붉은 표시. R−G = 125.
const Color kMark = Color(0xFFF97C7C);

/// 계측대가 고를 수 있는 길 모양.
enum RoadShape {
  /// 짧은 S 자 — 코퍼스의 `map_basic_*` 계열.
  gentle,

  /// 긴 뱀꼴 — `map_deep_04` 계열. 재생 시간이 밴드 위끝에 붙는다.
  serpentine,

  /// 고리를 한 번 그린다 — 한 붓 순회가 되짚는 경우를 만든다.
  loop,
}

/// 계측대에 넘길 지도 한 벌. 둘 다 **호출부가 소유**한다(다 쓰면 dispose).
typedef MapPair = ({ui.Image base, ui.Image composed});

/// 두 장을 그려 낸다.
///
///   [roadWidth] 는 길 두께(px). 너무 가늘면 세선화가 끊고, 너무 굵으면 X 면적 관문과
///   경쟁한다. 12~18 이 실측으로 안전한 범위다.
Future<MapPair> buildSyntheticMap({
  RoadShape shape = RoadShape.serpentine,
  double roadWidth = 14,
  String note = '발견한곳',
  bool withNote = true,
  bool withCross = true,
}) async {
  final path = _roadPath(shape);
  final end = _roadEnd(shape);

  final base = await _render(_paintGround);
  final composed = await _render((canvas) {
    _paintGround(canvas);
    canvas.drawPath(
      path,
      Paint()
        ..color = kRoad
        ..style = PaintingStyle.stroke
        ..strokeWidth = roadWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (withCross) _paintCross(canvas, end);
    if (withNote) _paintNote(canvas, end, note);
  });

  return (base: base, composed: composed);
}

// ─────────────────────────────────────────────────────────────────────────────

Future<ui.Image> _render(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, kMapSide, kMapSide),
  );
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(kMapSide.toInt(), kMapSide.toInt());
  picture.dispose();
  return image;
}

/// 바닥 — **base 와 composed 가 이 함수를 똑같이 부른다.** 얼룩까지 같아야 상쇄된다.
void _paintGround(Canvas canvas) {
  const rect = Rect.fromLTWH(0, 0, kMapSide, kMapSide);
  canvas.drawRect(rect, Paint()..color = kSoil);

  // 씨앗 고정 — 두 장이 같은 얼룩을 갖게 하는 유일한 방법이다.
  final rng = math.Random(20260809);
  final blot = Paint()..color = Colors.black.withValues(alpha: 0.045);
  for (var i = 0; i < 28; i++) {
    canvas.drawCircle(
      Offset(rng.nextDouble() * kMapSide, rng.nextDouble() * kMapSide),
      18 + rng.nextDouble() * 42,
      blot,
    );
  }
  final ridge = Paint()
    ..color = Colors.white.withValues(alpha: 0.03)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 9;
  for (var i = 0; i < 6; i++) {
    final y = 40.0 + i * 62;
    canvas.drawPath(
      Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(kMapSide / 2, y - 22, kMapSide, y + 8),
      ridge,
    );
  }
}

Path _roadPath(RoadShape shape) {
  final path = Path();
  switch (shape) {
    case RoadShape.gentle:
      path
        ..moveTo(210, 24)
        ..cubicTo(196, 96, 250, 130, 236, 196)
        ..cubicTo(226, 244, 196, 250, 200, 286);
    case RoadShape.serpentine:
      path
        ..moveTo(126, 20)
        ..cubicTo(130, 74, 320, 60, 322, 116)
        ..cubicTo(324, 172, 96, 150, 98, 208)
        ..cubicTo(100, 264, 320, 240, 318, 292)
        ..cubicTo(316, 330, 214, 320, 202, 338);
    case RoadShape.loop:
      path
        ..moveTo(210, 22)
        ..cubicTo(210, 90, 300, 96, 300, 160)
        ..cubicTo(300, 226, 150, 226, 150, 160)
        ..cubicTo(150, 104, 240, 118, 244, 200)
        ..cubicTo(248, 270, 206, 286, 202, 320);
  }
  return path;
}

/// 길이 끝나는 자리 — X 는 여기 붙어야 위치 관문(중심→길 ≤ 폭의 5%)을 통과한다.
Offset _roadEnd(RoadShape shape) => switch (shape) {
      RoadShape.gentle => const Offset(200, 286),
      RoadShape.serpentine => const Offset(202, 338),
      RoadShape.loop => const Offset(202, 320),
    };

/// 붉은 X — 두 막대가 **하나의 연결요소**여야 한다(떨어지면 X 로 안 잡힌다).
///
///   면적 목표: 420² × 0.0069 ≈ 1,217px. 막대 62×12 두 개가 겹쳐 대략 그쯤이다.
void _paintCross(Canvas canvas, Offset at) {
  final paint = Paint()
    ..color = kMark
    ..style = PaintingStyle.stroke
    ..strokeWidth = 12
    ..strokeCap = StrokeCap.round;
  const arm = 22.0;
  canvas
    // `\` 를 먼저 그린다 — 재생 순서와 같아 보기에도 자연스럽다.
    ..drawLine(
      at + const Offset(-arm, -arm),
      at + const Offset(arm, arm),
      paint,
    )
    ..drawLine(
      at + const Offset(arm, -arm),
      at + const Offset(-arm, arm),
      paint,
    );
}

/// 붉은 손글씨 — 길에서 **멀리** 둔다. X 보다 1.6배 이상 멀어야 X 를 안 밀어낸다.
void _paintNote(Canvas canvas, Offset roadEnd, String note) {
  final painter = TextPainter(
    text: TextSpan(
      text: note,
      style: const TextStyle(
        color: kMark,
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // 길 끝에서 오른쪽 아래로 충분히 띄운다(≈ 70px). X 는 0px 이므로 우세비가 넉넉하다.
  final origin = Offset(
    (roadEnd.dx + 56).clamp(8, kMapSide - painter.width - 8),
    (roadEnd.dy + 34).clamp(8, kMapSide - painter.height - 8),
  );
  painter
    ..paint(canvas, origin)
    ..dispose();
}
