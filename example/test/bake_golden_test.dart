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
  // 다시 뽑는 법: 이 표를 비우고 `flutter test test/bake_golden_test.dart` 를 돌리면
  //   실패 메시지가 붙여넣을 표를 출력한다.
  //
  //   ⚠️ map_deep_02 와 map_deep_06 의 다이제스트가 **완전히 같다** — 두 정본이 같은
  //   그림이라는 뜻이다(굽기 결과가 네 층 모두 일치). "정본 10종"이 실제로는 9가지다.
  'map_basic_01@210': ('e8dfaa69', 'a0531043', '13c77d5d', '23ab278a', 1828),
  'map_basic_01@420': ('a48e4e48', '3894ebde', '09769ede', '0aadefe4', 2251),
  'map_basic_01@840': ('db24add6', '7f6186cd', '1d994a2a', '5bcc39e5', 2915),
  'map_basic_02@210': ('8aa3f33e', '3f6e67ff', '94474915', '2fc09b8d', 2382),
  'map_basic_02@420': ('a016d48c', 'dca7885b', '998fb151', 'ef125bb0', 2689),
  'map_basic_02@840': ('6bdecee7', '00bc8d05', 'c8fc66ac', '4e4b3fa9', 3470),
  'map_basic_03@210': ('698e5713', 'd6e26aa3', '476f8eef', '1a4f052d', 1778),
  'map_basic_03@420': ('4ae19951', 'c46a2e2e', '3bdc7548', '62cb0d4b', 2250),
  'map_basic_03@840': ('5b25ca07', '47699806', '9d6a5c25', '32c6984a', 3255),
  'map_deep_01@210': ('5cfbc022', '13402f26', '85180670', 'b1a1e08d', 2443),
  'map_deep_01@420': ('a6712a00', '2bfd40d9', 'a666872b', 'fe342f26', 2885),
  'map_deep_01@840': ('2bc5d9e6', '7f7c0ee5', '4e860c00', 'abb9af54', 3492),
  'map_deep_02@210': ('e921f051', '2fcc6528', '7900af76', '6b227305', 3143),
  'map_deep_02@420': ('5d4fafd0', 'de6650ad', 'df2615ea', '970981ab', 3535),
  'map_deep_02@840': ('d70c2e42', 'ccbc4f8f', '193ae468', 'b5b23d7f', 4148),
  'map_deep_03@210': ('25d600c8', '669fb086', '2e6ecd02', '0bbf1b78', 2885),
  'map_deep_03@420': ('7211cb47', '9c3a68c5', 'a54d3657', '05ada0ed', 3213),
  'map_deep_03@840': ('813bae83', '89cca3bf', '3a97a22f', '08bd8551', 3681),
  'map_deep_04@210': ('6273fb88', '7a2ecdc4', 'aae4f92e', '1e732d0f', 2984),
  'map_deep_04@420': ('9b8b6965', '0f335a25', '5a356ee3', '69e349c8', 3121),
  'map_deep_04@840': ('490449da', '52d464f8', 'bd483614', '90873441', 3359),
  'map_deep_05@210': ('4b657c93', 'e0358152', '18e18991', '3b0ba9fe', 3160),
  'map_deep_05@420': ('2c263f34', '218ff923', '4daab87b', '814c310d', 3490),
  'map_deep_05@840': ('5da836de', '5b61217f', 'f70c2e7b', 'e84bda8b', 3646),
  'map_deep_06@210': ('a2f819ed', 'a8c97dbe', '4bc6411c', 'b6b84b98', 3143),
  'map_deep_06@420': ('5d4fafd0', 'de6650ad', 'df2615ea', '970981ab', 3535),
  'map_deep_06@840': ('e1ee5ef9', 'aeedf98c', '848525e2', '3c9a40cb', 4148),
  'map_special_01@210': ('56a4f40e', '3812ee54', '4c140d30', 'e06825aa', 3111),
  'map_special_01@420': ('b9f8d307', '0c590839', '63c841d0', 'edc5063e', 3472),
  'map_special_01@840': ('702b0c04', 'f60206e4', '1d20a5e7', 'cc599880', 3917),
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
