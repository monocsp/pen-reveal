// bake_golden_test.dart — **최적화가 결과를 바꾸지 않았음을 잠근다.**
//
//   굽기를 빠르게 만드는 변경(ROI 크롭·비트팩·자료구조 교체 …)은 전부 "출력이 그대로"가
//   전제다. 그런데 `measure`·세그먼트 픽셀 수 같은 **요약값**만 비교하면 순서 텍스처가
//   국소적으로 달라져도 통과한다 — 요약이 같은 서로 다른 그림은 얼마든지 있다.
//   그래서 여기서는 **컴파일된 8비트 텍스처 전체**의 다이제스트를 잠근다.
//
//   ⚠️ **이 다이제스트가 바뀌면 연출이 바뀐 것이다.** 의도한 변경이면 아래 표를 갱신하고
//   커밋 메시지에 무엇이 왜 바뀌었는지 적는다. 최적화라면 **버그다.**
//
//   ⚠️ 다이제스트는 정본 픽셀에서 나왔지만 **되돌릴 수 없는 스칼라**라 커밋한다
//   (레포 규칙: "PNG 에서 픽셀 단위로 나온 것은 ignore, 재서 얻은 스칼라만 커밋").
//   `resampler_golden_test.dart` 가 같은 방식을 쓴다.
//
//   자산이 없으면 스스로 skip 한다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 잠글 해상도. 210 은 ROI 가 상대적으로 크고, 840 은 세선화 패스가 늘어난다 —
///   최적화가 해상도에 따라 다르게 깨지는 것을 잡으려고 셋을 다 본다.
const _sides = <int>[210, 420, 840];

/// `<key>@<longSide>` → (`segmentId` 다이제스트, `within` 다이제스트, 텍스처 다이제스트,
///   세그먼트 요약 다이제스트, 재생 시간 ms).
///
///   ⚠️ **세 층을 다 잠근다.** 최종 텍스처만 보면 "계획이 다른데 8비트로 양자화되면서 같아진"
///   경우를 놓치고, 계획만 보면 컴파일러·정책이 바뀐 것을 놓친다(codex 지적).
///     · `segmentId` — 어느 픽셀이 어느 덩어리인가
///     · `within`    — 그 덩어리 안 진행도
///     · `order`     — 렌더러가 실제로 읽는 것
///     · 세그먼트 요약 — id·종류·픽셀수·bbox·measure·relativeLength
///     · 재생 시간   — 정책이 낸 총 길이
const _golden = <String, (String, String, String, String, int)>{
  'map_basic_01@210': ('e8dfaa69', '37c78b64', 'a0a7b2fd', '31e7640f', 1789),
  'map_basic_01@420': ('a48e4e48', 'baee7250', '01d222d3', '0cc52aa6', 2223),
  'map_basic_01@840': ('db24add6', '500016fd', '20687acd', 'b4f78c32', 2896),
  'map_basic_02@210': ('8aa3f33e', '8a9c5d25', 'cdc13d30', 'b89cbd50', 2328),
  'map_basic_02@420': ('a016d48c', 'b8b51eaa', '29c6c934', '3f9e0b84', 2656),
  'map_basic_02@840': ('6bdecee7', '64e93ca5', '0441a063', '4a70301a', 3424),
  'map_basic_03@210': ('698e5713', '5aad6143', 'ab729bd3', '689396c0', 1748),
  'map_basic_03@420': ('4ae19951', 'f53b296a', '3a295607', '3821788c', 2323),
  'map_basic_03@840': ('5b25ca07', '80c2ba00', 'ae8a1e6b', '1b73a78b', 3295),
  'map_deep_01@210': ('5cfbc022', '8bb4f8e2', '01d33465', '01bc7c57', 2414),
  'map_deep_01@420': ('a6712a00', '501e7e74', '92c862ff', '7e787803', 2882),
  'map_deep_01@840': ('2bc5d9e6', '354cd1ce', '146b0ee7', '809a2e93', 3452),
  'map_deep_02@210': ('e921f051', '1786d748', '5265d7bf', '8caac84b', 3137),
  'map_deep_02@420': ('5d4fafd0', '4a7c893a', '552f8800', '194cc93d', 3529),
  'map_deep_02@840': ('d70c2e42', 'ee6f1495', 'd218abaf', '6132797d', 4125),
  'map_deep_03@210': ('25d600c8', '19a3f1a9', 'e24d9110', '05f33e7b', 2880),
  'map_deep_03@420': ('7211cb47', '4fc6bb2c', 'ca6f47b5', '7ddfbd0d', 3198),
  'map_deep_03@840': ('813bae83', '96e84dbc', 'c7800b52', '31680b95', 3655),
  'map_deep_04@210': ('6273fb88', '166a44b4', '4c39283e', 'ca8438ec', 3032),
  'map_deep_04@420': ('9b8b6965', 'd25f9a7f', '3b068e50', 'e3deca0d', 3149),
  'map_deep_04@840': ('490449da', 'c72741da', 'f8b2b6fe', '312aebb7', 3384),
  'map_deep_05@210': ('4b657c93', 'a8d9a33a', '9dd375ce', '69ab2aa1', 3170),
  'map_deep_05@420': ('2c263f34', 'd4a8414c', 'a762ae01', '2752a62e', 3468),
  'map_deep_05@840': ('5da836de', '6f6c5aba', 'c2d2ea73', '23d091df', 3643),
  'map_deep_06@210': ('a2f819ed', '0cbc47b4', '65d0e7b8', '25ab1d1e', 3137),
  'map_deep_06@420': ('5d4fafd0', '4a7c893a', '552f8800', '194cc93d', 3529),
  'map_deep_06@840': ('e1ee5ef9', 'db4416d5', '2ddd7ae2', 'b5355e11', 4125),
  'map_special_01@210': ('56a4f40e', 'e9a05dfd', '721a4899', '739fabf0', 3097),
  'map_special_01@420': ('b9f8d307', 'ab3e2234', 'd8fed11f', '43b608a5', 3460),
  'map_special_01@840': ('702b0c04', 'ee8c985e', 'b6c4cf4a', '19532a80', 3911),
};

/// FNV-1a **32비트** — 짧고 의존성이 없다. 암호학적 용도가 아니라 회귀 감지용이라
///   30 케이스 × 4 다이제스트에서 충돌 확률은 무시할 수 있다.
///
///   ⚠️ 64비트를 쓰면 상수가 JS 정수 범위를 넘어 `avoid_js_rounded_ints` 에 걸린다.
String _digest(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '굽기 산출물이 골든과 바이트 단위로 같다',
    () async {
      final keys = await availableCorpusKeys();
      if (keys.isEmpty) {
        markTestSkipped(
          '정본 지도가 번들에 없다 — example/assets/maps/<key>_{base,composed}.png 를 채운다',
        );
        return;
      }

      const timing = HandwritingRevealTiming();
      const compiler = RevealTextureCompiler();
      final fresh = <String, (String, String, String, String, int)>{};
      final drift = <String>[];

      for (final key in keys) {
        final pair = await loadCorpusMap(key);
        for (final side in _sides) {
          final size = fitImageLongSide(pair.composed, side);
          final w = size.width;
          final h = size.height;
          final plan = detectReveal(
            RevealDetectInput(
              baseRgba: await rgbaAt(pair.base, w, h),
              composedRgba: await rgbaAt(pair.composed, w, h),
              width: w,
              height: h,
            ),
          );
          final schedule = timing.schedule(plan);
          final order = compiler.compile(plan, schedule);
          // 세그먼트 요약 — 값이 하나라도 흔들리면 다이제스트가 바뀐다.
          final summary = StringBuffer();
          for (final seg in plan.segments) {
            summary.write(
              '${seg.id}|${seg.kind.name}|${seg.pixelCount}|'
              '${seg.left},${seg.top},${seg.right},${seg.bottom}|'
              '${(seg.measure * 1000).round()}|'
              '${seg.relativeLength == null ? '-' : (seg.relativeLength! * 1e6).round()};',
            );
          }
          final now = (
            _digest(plan.segmentId),
            _digest(
              Uint8List.view(
                plan.within.buffer,
                plan.within.offsetInBytes,
                plan.within.lengthInBytes,
              ),
            ),
            _digest(order),
            _digest(Uint8List.fromList(summary.toString().codeUnits)),
            schedule.total.inMilliseconds,
          );
          final at = '$key@$side';
          fresh[at] = now;
          final want = _golden[at];
          if (want != null && want != now) {
            drift.add('$at  기대 $want  실제 $now');
          }
        }
        pair.base.dispose();
        pair.composed.dispose();
      }

      if (_golden.isEmpty) {
        final table = StringBuffer('\n아래를 _golden 에 붙여넣는다:\n\n');
        for (final e in fresh.entries) {
          final v = e.value;
          table.writeln(
            "  '${e.key}': ('${v.$1}', '${v.$2}', '${v.$3}', '${v.$4}', ${v.$5}),",
          );
        }
        fail('골든이 비어 있다.$table');
      }

      expect(
        drift,
        isEmpty,
        reason: '\n굽기 산출물이 골든과 다르다 — 최적화라면 버그이고, 의도한 변경이면 표를 갱신하라.\n'
            '${drift.join('\n')}\n',
      );
      expect(
        fresh.keys.toSet(),
        _golden.keys.toSet(),
        reason: '잠긴 케이스와 실제로 돈 케이스가 다르다',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
