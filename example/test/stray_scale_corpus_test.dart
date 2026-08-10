// 붉은 잉크 테두리 관문이 **굽기 해상도에 안 흔들리는지** 정본으로 잠근다.
//
//   `detector.dart` 의 `strayInkMaxPixels = 12` 는 출력 픽셀 개수를 세는 **절대값**이다.
//   같은 파일에서 기하를 재는 X 관문들(거리비·면적비)은 전부 캔버스 대비 비율이라, 이것만
//   해상도가 바뀌면 뜻이 달라질 위험이 있어 보였다.
//
//   ⚠️ **합성 도형을 확대해 보면 깨지는 것처럼 보인다 — 그건 확대이지 재표본화가 아니다.**
//   `stray_ink_test.dart` 의 픽스처를 최근접으로 s 배 키우면 조각 면적이 정확히 s² 로 자라
//   3× 에서 관문을 넘는다. 하지만 진짜 굽기는 원본 879×1065 을 새 격자로 **다시 뽑는다** —
//   안티에일리어싱 띠가 그때그때 새로 생기고 두께는 대체로 출력 1픽셀이다. 그래서 조각
//   **개수**는 둘레를 따라 늘지만(210→1260 에서 47→470, 대략 ∝ s) **크기는 안 자란다.**
//
//   실측(정본 10종 × 4해상도, 규칙 끄고 잰 「붉은 것에 닿은 길 덩어리」 중 본체 제외 최대):
//
//       해상도   배율   지도별 최대의 최대   중앙값
//         210    0.5            6            4
//         420    1.0            5            3
//         840    2.0            5            4
//        1260    3.0            8            6
//
//   6배 해상도 범위에서 2~8px 이다. 관문 12 는 여유가 충분하고, 지수를 붙여 키우면
//   오히려 진짜 짧은 길 조각을 삼킬 위험만 생긴다 — **그래서 상수를 안 건드린다.**
//   대신 그 판단의 근거인 이 불변을 여기서 잠근다. 리샘플러나 색 임계를 손대서 테두리가
//   갑자기 굵어지면 여기서 걸린다.
//
//   자산이 없으면 스스로 skip 한다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 재 본 굽기 해상도들 — 기본값 420 을 가운데 두고 0.5×~3× 를 훑는다.
const _sides = [210, 420, 840, 1260];

/// 「붉은 것에 닿은 길 덩어리」 중 **본체를 뺀** 최대 크기의 상한.
///
///   실측 최대는 1260 에서 8px 이다. 관문(12)보다 낮게 잡으면 이 시험이 "관문이 전부
///   잡아낸다" 를 뜻하게 된다 — 그게 지키려는 성질이다. 여유 4px 만 준다.
const _maxStrayPixels = 12;

/// `_absorbStrayInk` 이 보는 모집단 그대로 — 붉은 것에 8-이웃으로 닿은 길 덩어리 크기들.
List<int> _accentTouchingRoadBlobs(RevealPlan p, int w, int h) {
  final kindOf = <int, RevealSegmentKind>{
    for (final s in p.segments) s.id: s.kind,
  };
  final isRoad = Uint8List(w * h);
  final isAccent = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final kind = kindOf[p.segmentId[i]];
    if (kind == null) continue;
    if (kind == RevealSegmentKind.primaryStroke) {
      isRoad[i] = 1;
    } else {
      isAccent[i] = 1;
    }
  }

  final seen = Uint8List(w * h);
  final out = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (isRoad[start] == 0 || seen[start] == 1) continue;
    var n = 0;
    var touches = false;
    final stack = <int>[start];
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      n++;
      final x = q % w;
      final y = q ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (isAccent[j] == 1) touches = true;
          if (isRoad[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
    }
    if (touches) out.add(n);
  }
  return out..sort();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '테두리 조각은 굽기 해상도를 0.5×~3× 로 흔들어도 관문 안에 머문다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다 — example/assets/maps 를 채운다');
        return;
      }

      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        try {
          for (final side in _sides) {
            final size = fitImageLongSide(pair.composed, side);
            final base = await rgbaAt(pair.base, size.width, size.height);
            final composed = await rgbaAt(pair.composed, size.width, size.height);
            // 규칙을 **끄고** 날것을 본다 — 켜면 흡수된 뒤라 아무것도 안 보인다.
            final plan = detectReveal(
              RevealDetectInput(
                baseRgba: base,
                composedRgba: composed,
                width: size.width,
                height: size.height,
                config: const RevealDetectConfig(strayInkMaxPixels: 0),
              ),
            );
            final touching =
                _accentTouchingRoadBlobs(plan, size.width, size.height);
            expect(
              touching,
              isNotEmpty,
              reason: '$key@$side — 길이 붉은 것에 하나도 안 닿았다. '
                  '탐지가 통째로 어긋난 것이지 좋아진 게 아니다',
            );
            // 마지막 하나는 길 본체다 — 길은 X 와 실제로 맞닿고, 크기 상한이 그걸 지킨다.
            final body = touching.last;
            expect(
              body,
              greaterThan(_maxStrayPixels),
              reason: '$key@$side — 길 본체($body px)가 관문 안에 들어왔다. '
                  '이대로면 길이 통째로 잉크로 흡수된다',
            );
            final stray = touching.sublist(0, touching.length - 1);
            if (stray.isEmpty) continue;
            expect(
              stray.last,
              lessThanOrEqualTo(_maxStrayPixels),
              reason: '$key@$side — 테두리 조각이 ${stray.last}px 로 자라 관문을 넘었다. '
                  '해상도를 따라 굵어졌다면 관문을 절대값으로 두면 안 된다',
            );
          }
        } finally {
          pair.base.dispose();
          pair.composed.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
