// 되찾은 순서가 **한 붓으로 그린 것처럼 보이는가** — 정본으로 잠근다.
//
//   ⚠️ **이 파일이 생긴 이유.** 순회 순서를 고쳤다고 보고했다가 되돌린 적이 있다. 회색조
//   순서 그림을 눈으로 보고 "내려간 뒤 하트로 들어간다" 고 해석했는데, 좌표로 재 보니
//   두 지도에서 **길이 끝나는 자리가 엉뚱한 데로 옮겨져 있었다.** 눈대중으로 통과 판정을
//   내린 대가다. 다시 손대기 전에 **기계가 읽는 합격 기준**을 먼저 못 박는다.
//
//   길은 지도 위쪽에서 시작해 붉은 X 까지 내려가는 한 획이다. 그러니:
//     · 시작은 위쪽 가장자리 근처여야 하고,
//     · **끝은 X 옆이어야 한다** — X 는 도착지라 맨 마지막에 닿는다.
//
//   실측(굽기 420, 지금 코드):
//
//       지도             길 시작      길 끝        X 중심      끝↔X 거리
//       map_basic_01    (139,71)   (110,205)   (113,216)      11
//       map_deep_04     (139,71)   (239,275)   (240,295)      20
//       map_deep_05     (139,71)   (177,283)   (175,305)      22
//       map_special_01  (139,71)   (105,294)   (108,305)      11
//
//   ⚠️ 되돌린 그 수정은 여기서 이렇게 어긋났다 — deep_04 끝이 (122,186) 으로, deep_05 는
//   (136,74) 로 갔다. deep_05 는 **시작점에서 3px** 다. 한 바퀴 돌아 제자리에서 끝난
//   것이라 "한 붓 그리기" 가 아니었다. 그 상태가 이 시험을 통과할 수는 없다.
//
//   자산이 없으면 스스로 skip 한다.
@Tags(['corpus'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;

/// 길 끝과 X 중심이 이만큼까지는 떨어져 있어도 된다(굽기 420 픽셀).
///
///   실측 최악이 22 다(map_deep_05). X 는 길 끝을 **덮고** 그려지므로 중심까지는 X 반지름
///   만큼 떨어지는 것이 정상이다. 40 이면 그 여유를 주면서도, 되돌린 수정이 만든
///   어긋남(deep_04 는 약 110px, deep_05 는 약 230px)은 확실히 건다.
const _endNearX = 40.0;

/// 길 시작이 위쪽 가장자리에서 이만큼 안쪽까지는 들어와도 된다.
///
///   실측은 넷 다 y=71 이고 그게 지도 상단이다. 120 이면 넉넉하면서도 "아래에서
///   시작했다" 는 확실히 건다.
const _startNearTop = 120;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '길은 위에서 시작해 X 에서 끝난다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }

      final drift = <String>[];
      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        try {
          final size = fitImageLongSide(pair.composed, _side);
          final base = await rgbaAt(pair.base, size.width, size.height);
          final composed = await rgbaAt(pair.composed, size.width, size.height);
          final plan = detectReveal(
            RevealDetectInput(
              baseRgba: base,
              composedRgba: composed,
              width: size.width,
              height: size.height,
            ),
          );
          final w = size.width;
          final roadIds = <int>{
            for (final s in plan.segments)
              if (s.kind == RevealSegmentKind.primaryStroke) s.id,
          };
          if (roadIds.isEmpty) {
            drift.add('$key 길 세그먼트가 없다');
            continue;
          }

          // 가장 먼저 / 가장 나중에 드러나는 길 픽셀.
          var lo = 1 << 30;
          var hi = -1;
          var loAt = 0;
          var hiAt = 0;
          for (var i = 0; i < plan.segmentId.length; i++) {
            if (!roadIds.contains(plan.segmentId[i])) continue;
            final v = plan.within[i];
            if (v < lo) {
              lo = v;
              loAt = i;
            }
            if (v > hi) {
              hi = v;
              hiAt = i;
            }
          }

          // X 중심 — 두 획의 상자 가운데를 평균한다.
          var cx = 0;
          var cy = 0;
          var n = 0;
          for (final s in plan.segments) {
            if (s.kind != RevealSegmentKind.crossBackslash &&
                s.kind != RevealSegmentKind.crossSlash) {
              continue;
            }
            cx += (s.left + s.right) ~/ 2;
            cy += (s.top + s.bottom) ~/ 2;
            n++;
          }
          if (n == 0) {
            // X 를 못 찾은 지도는 이 시험의 대상이 아니다 — 도착지가 없다.
            continue;
          }
          cx = cx ~/ n;
          cy = cy ~/ n;

          final startY = loAt ~/ w;
          if (startY > _startNearTop) {
            drift.add('$key 길이 위가 아니라 y=$startY 에서 시작한다');
          }

          final ex = hiAt % w;
          final ey = hiAt ~/ w;
          final dx = (ex - cx).toDouble();
          final dy = (ey - cy).toDouble();
          final away = math.sqrt(dx * dx + dy * dy);
          if (away > _endNearX) {
            drift.add(
              '$key 길이 X($cx,$cy) 가 아니라 ($ex,$ey) 에서 끝난다 '
              '— ${away.toStringAsFixed(0)}px 어긋남',
            );
          }
        } finally {
          pair.base.dispose();
          pair.composed.dispose();
        }
      }

      expect(
        drift,
        isEmpty,
        reason: '\n한 붓 그리기가 아니다 — X 는 도착지라 맨 마지막에 닿아야 한다.\n'
            '${drift.join('\n')}\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
