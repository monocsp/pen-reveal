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
//   실측(굽기 420, 지금 코드) — 획의 시작 y, 끝 무게중심, X 중심:
//
//       basic_01  77 · (160,213) → X(160,223)      basic_02  73 · (220,210) → (220,220)
//       basic_03  88 · (157,199) → X(157,209)      deep_01   99 · (106,276) → (105,287)
//       deep_02   82 · (104,281) → X(104,293)      deep_03   87 · (207,276) → (220,276)
//       deep_04   86 · (235,280) → X(240,295)      deep_05   79 · (172,292) → (175,305)
//       deep_06   82 · (104,281) → X(104,293)      special_01 81 · (109,293) → (108,305)
//
//   끝↔X 거리는 열 지도 모두 10~16px 이고, 시작 y 는 73~99 다.
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
///   실측 최악이 16 다. X 는 길 끝을 **덮고** 그려지므로 중심까지는 X 반지름만큼
///   떨어지는 것이 정상이다. 40 이면 그 여유를 주면서도, 되돌린 수정이 만든 어긋남
///   (deep_04 161px · deep_05 234px)은 확실히 건다.
const _endNearX = 40.0;

/// 길 시작이 위쪽 가장자리에서 이만큼 안쪽까지는 들어와도 된다.
///
///   실측 최악이 99 다(map_deep_01). 140 이면 여유를 주면서도 "아래에서 시작했다" 는
///   확실히 건다 — 지도 세로가 420 이니 아래쪽에서 시작하면 200 을 훌쩍 넘는다.
const _startNearTop = 140;

/// 펜이 **왔던 자리로 되돌아오나** — 되짚기를 잡는다.
///
///   ⚠️ 끝점·시작점 검사만으로는 못 잡는 것이 있다. 세선화가 교차점 하나를 갈래 3 둘로
///   쪼개면 그 사이를 두 번 지나야 짝이 맞고, 그러면 펜이 **올라갔다 다시 내려온다.**
///   걸음은 고르고 전선도 하나라 다른 검사는 전부 통과한다 — 화면에서만 보인다.
///
///   길 픽셀을 시각 순으로 `_bins` 칸에 세우고, 각 칸의 무게중심이 `_backGap` 칸보다
///   이전의 어느 자리와 `_backNear` px 안으로 다시 붙는지 센다.
const _bins = 60;
const _backGap = 4;

/// 앞뒤 `_backGap` 칸의 방향이 이보다 더 마주보면 "되돌아갔다" 로 센다.
///
///   −1 이 완전히 반대다. −0.5 는 120 도 넘게 꺾인 것 — 손으로는 그렇게 안 그린다.
const _backTurn = -0.5;

/// 지도별 되돌아감 상한 — **실측값**이다(굽기 420).
///
///   ⚠️ **map_special_01 이 이 시험이 겨냥한 자리다.** 쪼개진 교차점을 붙이기 전에는
///   **5** 였다 — 다리를 두 번 지나느라 펜이 올라갔다 내려왔다. 붙인 뒤 **4** 다.
///   `_mergeSplitCrossings` 를 없애는 뮤테이션이 여기서 걸린다.
///
///   나머지 값은 지금 그대로 못 박아 둔다. 0 인 지도(basic 셋·deep_01)는 곧은 길이라
///   뒤집힘이 아예 없어야 하고, 나머지는 하트·고리를 도는 정상적인 꺾임이다.
const _backBudget = <String, int>{
  'map_basic_01': 0,
  'map_basic_02': 0,
  'map_basic_03': 0,
  'map_deep_01': 0,
  'map_deep_02': 6,
  'map_deep_03': 1,
  'map_deep_04': 5,
  'map_deep_05': 9,
  'map_deep_06': 6,
  'map_special_01': 4,
};

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

          // ⚠️ **단일 최대 픽셀로 재지 않는다.** 한 점은 잡음에 흔들린다 —
          //   마지막 0.5% 의 무게중심으로 본다.
          // ⚠️ **`within == 0` 은 빼야 한다.** `_flattenNonStrokes` 가 찢어진 종이
          //   가장자리를 "처음부터 있던 것" 으로 눕히면서 시각 0 을 준다. 그걸 안 빼면
          //   "가장 먼저 드러나는 길 픽셀" 이 획의 시작이 아니라 **종이 가장자리**가 되어,
          //   펜이 어디서 시작하든 y 가 늘 71 로 나온다 — 시험이 아무것도 안 잰다.
          //   (`coverage_test.dart` 의 `startsNearTop` 이 지금 그 상태다.)
          final road = <int>[
            for (var i = 0; i < plan.segmentId.length; i++)
              if (roadIds.contains(plan.segmentId[i]) && plan.within[i] > 0) i,
          ]..sort((a, b) => plan.within[a].compareTo(plan.within[b]));
          if (road.isEmpty) {
            drift.add('$key 길 픽셀이 없다');
            continue;
          }
          final take = math.max(1, (road.length * 0.005).round());
          var sx = 0;
          var sy = 0;
          for (final i in road.sublist(road.length - take)) {
            sx += i % w;
            sy += i ~/ w;
          }
          final ex = sx ~/ take;
          final ey = sy ~/ take;
          final startY = road.first ~/ w;

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

          // 되돌아옴 — 칸별 무게중심으로 잰다.
          final tips = <(double, double)>[];
          for (var k = 0; k < _bins; k++) {
            final lo = road.length * k ~/ _bins;
            final hi = road.length * (k + 1) ~/ _bins;
            if (hi <= lo) continue;
            var tx = 0.0;
            var ty = 0.0;
            for (var j = lo; j < hi; j++) {
              tx += road[j] % w;
              ty += road[j] ~/ w;
            }
            tips.add((tx / (hi - lo), ty / (hi - lo)));
          }
          var back = 0;
          for (var i = _backGap; i + _backGap < tips.length; i++) {
            final ax = tips[i].$1 - tips[i - _backGap].$1;
            final ay = tips[i].$2 - tips[i - _backGap].$2;
            final bx = tips[i + _backGap].$1 - tips[i].$1;
            final by = tips[i + _backGap].$2 - tips[i].$2;
            final la = math.sqrt(ax * ax + ay * ay);
            final lb = math.sqrt(bx * bx + by * by);
            if (la < 1 || lb < 1) continue;
            if ((ax * bx + ay * by) / (la * lb) < _backTurn) back++;
          }
          final budget = _backBudget[key];
          if (budget != null && back > budget) {
            drift.add('$key 펜이 이미 지난 자리로 $back 번 되돌아왔다 (상한 $budget)');
          }

          if (startY > _startNearTop) {
            drift.add('$key 길이 위가 아니라 y=$startY 에서 시작한다');
          }

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
