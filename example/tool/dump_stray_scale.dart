// 일회성 계측 — **붉은 잉크에 닿은 길 잡티가 굽기 해상도에 따라 얼마나 자라나.**
//
//   `detector.dart` 의 `strayInkMaxPixels` 는 절대 픽셀 수다. 같은 파일에서 기하를 재는
//   X 관문들은 전부 캔버스 대비 비율인데 이것만 다르다. 해상도를 올리면 관문의 뜻이
//   달라지는데, **얼마나** 달라지는지는 실제 리샘플러를 통과시켜 봐야 안다.
//
//   합성 픽스처를 최근접으로 확대하면 조각이 s² 로 자란다 — 하지만 그건 확대이지
//   재표본화가 아니다. 진짜 굽기는 원본 879×1065 을 새 격자로 다시 뽑으므로 안티에일리어싱
//   띠가 새로 생기고, 띠 두께는 대체로 출력 1픽셀이라 면적이 둘레(∝ s)만 따라갈 수도 있다.
//   지수를 찍어서 정하면 반대 방향으로 깨진다 — 그래서 잰다.
//
//   규칙을 **끄고**(strayInkMaxPixels: 0) 재야 "원래 몇 px 짜리가 몇 개 생기는지" 가 보인다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

const _sides = [210, 420, 840, 1260];

/// `_absorbStrayInk` 이 보는 것과 **똑같은** 모집단 — 붉은 것에 닿은 길 덩어리들의 크기.
///
///   그냥 "가장 큰 것 말고 나머지" 를 세면 안 된다. 길이 여러 조각으로 갈린 것까지 섞여
///   들어와 관문과 무관한 숫자가 나온다(실측: 420 에서 그렇게 세면 최대 203px 이 나오는데
///   그건 잡티가 아니라 길 조각이다).
List<int> _strayCandidates(RevealPlan p, int w, int h) {
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
    final st = <int>[start];
    seen[start] = 1;
    while (st.isNotEmpty) {
      final q = st.removeLast();
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
            st.add(j);
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
    '잡티 크기가 굽기 해상도를 어떻게 따라가나',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped('정본 지도가 번들에 없다');
        return;
      }

      // ignore: avoid_print
      print('\n지도            해상도  붉은것에닿은길덩어리  최대   합   12px이하  본체(최대)');
      final byside = <int, List<int>>{for (final s in _sides) s: <int>[]};

      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        for (final side in _sides) {
          final size = fitImageLongSide(pair.composed, side);
          final base = await rgbaAt(pair.base, size.width, size.height);
          final composed = await rgbaAt(pair.composed, size.width, size.height);
          final plan = detectReveal(
            RevealDetectInput(
              baseRgba: base,
              composedRgba: composed,
              width: size.width,
              height: size.height,
              // 규칙을 끄고 날것을 본다.
              config: const RevealDetectConfig(strayInkMaxPixels: 0),
            ),
          );
          final touching = _strayCandidates(plan, size.width, size.height);
          if (touching.isEmpty) continue;
          // 본체(길 전체)도 붉은 X 와 맞닿으므로 이 목록에 들어 있다 — 그게 정상이고,
          //   크기 상한이 그걸 지켜 준다. 그래서 최대값은 따로 떼어 본다.
          final body = touching.last;
          final small = touching.sublist(0, touching.length - 1);
          final maxSmall = small.isEmpty ? 0 : small.last;
          byside[side]!.add(maxSmall);
          // ignore: avoid_print
          print(
            '${key.padRight(15)} ${side.toString().padLeft(4)}  '
            '${touching.length.toString().padLeft(14)}  '
            '${maxSmall.toString().padLeft(6)}  '
            '${small.fold(0, (a, b) => a + b).toString().padLeft(5)}  '
            '${small.where((n) => n <= 12).length.toString().padLeft(6)}  '
            '${body.toString().padLeft(8)}',
          );
        }
        pair.base.dispose();
        pair.composed.dispose();
      }

      // ignore: avoid_print
      print('\n해상도별 「지도 하나의 최대 잡티」 — 이 값이 관문을 넘으면 샌다');
      // ignore: avoid_print
      print('해상도  배율   지도별 최대잡티의 최대   중앙값   420 대비');
      final ref = <int>[...byside[420]!]..sort();
      final refMax = ref.isEmpty ? 1 : ref.last;
      for (final side in _sides) {
        final v = <int>[...byside[side]!]..sort();
        if (v.isEmpty) continue;
        final med = v[v.length ~/ 2];
        // ignore: avoid_print
        print(
          '${side.toString().padLeft(5)}  '
          '${(side / 420).toStringAsFixed(2).padLeft(5)}  '
          '${v.last.toString().padLeft(20)}  '
          '${med.toString().padLeft(6)}  '
          '${(v.last / refMax).toStringAsFixed(2).padLeft(7)}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
