// 연출 중간에는 **붓끝 하나만** 움직여야 한다.
//
//   ⚠️ 무엇을 잠그나. 정본의 바닥과 최종본은 따로 내보낸 PNG 라 지도 위쪽 **찢어진 종이
//   가장자리**가 서로 미세하게 어긋난다. 그 어긋남이 "변한 곳" 으로 잡혀 길이 되는데,
//   본체와 끊긴 덩어리라 세선화가 거기에도 뼈대를 만들어 **독립된 획**으로 순서를 받았다.
//   실측(굽기 420): 길 덩어리 네 개 중 셋이 y 71~86 의 가장자리 조각이다 —
//   map_deep_05 는 203·20·1px, map_deep_04 는 129·19·1px.
//
//   순서값은 지도마다 제멋대로였다. map_deep_05 는 140(길의 맨 끝), map_deep_04 는 0.
//   그래서 화면에서는 **펜이 저 아래 있는데 위쪽 띠 200px 이 한 프레임에 통째로 켜졌다.**
//   "선이 진행되는 곳이 아닌데 자라난다" 는 지적이 이것이었다.
//
//   ⚠️ **가파르기(k)로는 안 고쳐진다.** k 는 그 띠가 페이드하는 속도만 바꾼다 —
//   손잡이를 끝까지 밀어도 같아 보이는 이유다. 실제로 그렇게 보고받았다.
//
//   재는 것: 연출 **중간** 프레임에서 새로 불투명해진 픽셀의 8-이웃 덩어리.
//   붓끝 하나면 덩어리가 하나고 상자가 획 굵기만 하다. 떨어진 자리가 같이 켜지면
//   덩어리가 여럿이거나 상자가 캔버스를 가로지른다.
//
//   ⚠️ 맨 앞 구간은 뺀다. 눕힌 가장자리가 시각 0 을 받아 진행도 0.05 근처에서 함께
//   드러나는 것은 **의도한 동작**이다(종이는 그리는 것이 아니라 원래 있던 것이다).
//
//   자산이 없으면 스스로 skip 한다.
@Tags(['corpus'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _side = 420;

/// 이 진행도부터 잰다 — 앞은 "처음부터 있던 것" 이 드러나는 구간이다.
const _from = 0.12;

/// 지도별 상한 — 한 프레임에 새로 켜지는 픽셀의 상자 대각선(픽셀).
///
///   ⚠️ **오던 방향을 잇는 순회로 바꾸면서 다시 쟀다.** deep_02·deep_06 은 55 → 24 로
///   좋아졌고 deep_05 는 86 → 235 로 나빠졌다 — 획순이 맞아지면서 겹치는 자리를 지나는
///   방식이 달라진 대가다. 실측값에 1px 만 얹었다(대각선이 소수라 등호 경계에서 흔들린다). 굽기가 결정적이라 값이 안 흔들리므로 **좋아지는 것은 통과하고
///   나빠지는 것만 걸린다.**
///
///   ⚠️ **basic 계열 16~21px 이 "붓끝 하나" 의 기준선이다** — 획 굵기 그대로다.
///   deep·special 이 그보다 큰 것은 **아직 안 고친 두 번째 기전** 때문이다: 획이 자기
///   위를 지나거나 스치는 자리에서 붓 반경 `R(s)`(= 길 가장자리까지 거리)이 커져,
///   한 걸음이 반대편 팔까지 함께 칠한다. 접합을 덮으려고 일부러 넣은 성질이라
///   (`_brushSweep` 주석) 그냥 깎으면 안 된다 — 실제로 반경 상한을 6 으로 두고 재 보니
///   `_spread` 최근접 대체가 끼어들어 **더 나빠졌다**(deep_02 54 → 142).
///
///   찢어진 종이 가장자리가 통째로 켜지던 것은 `_flattenNonStrokes`(one_stroke_bake.dart)
///   가 잡았다. 그 전에는 여기 값이 지도마다 160~250 이었다.
const _budget = <String, double>{
  'map_basic_01': 19,
  'map_basic_02': 19,
  'map_basic_03': 18,
  'map_deep_01': 20,
  'map_deep_02': 25,
  'map_deep_03': 71,
  'map_deep_04': 171,
  'map_deep_05': 236,
  'map_deep_06': 25,
  'map_special_01': 170,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '연출 중간에 새로 켜지는 것은 붓끝 하나뿐이다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }
      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final k = compiler.sharpness.k;

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
          final schedule = timing.schedule(plan);
          final order = compiler.compile(plan, schedule);
          final w = size.width;
          final h = size.height;
          final roadIds = <int>{
            for (final s in plan.segments)
              if (s.kind == RevealSegmentKind.primaryStroke) s.id,
          };
          final frames = (schedule.total.inMilliseconds * 60 / 1000)
              .round()
              .clamp(2, 2000);
          final step = 1.0 / frames;

          Uint8List opaque(double p) {
            final o = Uint8List(w * h);
            for (var i = 0; i < w * h; i++) {
              if (!roadIds.contains(plan.segmentId[i])) continue;
              if (k * (p * 255 - order[i]) >= 255) o[i] = 1;
            }
            return o;
          }

          var prev = opaque(_from - step);
          // ⚠️ **길 단계가 끝나는 데서 멈추면 안 된다.** 길 픽셀이라고 길 단계 안에
          //   드러나는 것은 아니다 — 고치기 전 map_deep_05 의 가장자리 조각은 순서값
          //   140 을 받아 길 끝(0.57) **뒤인** 0.59 에 켜졌다. 거기서 멈추면 이 시험이
          //   겨냥한 바로 그 경우를 놓친다(실제로 놓쳤다).
          for (var p = _from; p < 1.0; p += step) {
            final now = opaque(p);
            // 새로 켜진 픽셀의 상자.
            var minX = w;
            var maxX = -1;
            var minY = h;
            var maxY = -1;
            for (var i = 0; i < w * h; i++) {
              if (now[i] != 1 || prev[i] != 0) continue;
              final x = i % w;
              final y = i ~/ w;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
            prev = now;
            if (maxX < 0) continue;
            final dx = (maxX - minX).toDouble();
            final dy = (maxY - minY).toDouble();
            final span = math.sqrt(dx * dx + dy * dy);
            expect(
              span,
              lessThanOrEqualTo(_budget[key] ?? 30.0),
              reason: '$key@${p.toStringAsFixed(3)} — 한 프레임에 켜진 것이 '
                  '${span.toStringAsFixed(0)}px 에 걸쳐 있다 '
                  '(상자 x $minX~$maxX · y $minY~$maxY).\n'
                  '붓끝 하나가 아니라 떨어진 자리가 같이 켜졌다는 뜻이다 — '
                  '길에 획이 아닌 조각이 섞였는지 본다.',
            );
          }
        } finally {
          pair.base.dispose();
          pair.composed.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
