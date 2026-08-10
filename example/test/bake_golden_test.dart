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
  'map_basic_01@210': ('e8dfaa69', '183bff83', 'df11aa2c', '23ab278a', 1828),
  'map_basic_01@420': ('a48e4e48', '05efb104', '0175c88f', '0aadefe4', 2251),
  'map_basic_01@840': ('db24add6', '7dc40de0', '3a5c5ce5', '5bcc39e5', 2915),
  'map_basic_02@210': ('8aa3f33e', 'b3f239c7', '481e4b4f', '2fc09b8d', 2382),
  'map_basic_02@420': ('a016d48c', '29c3eab7', '9305d8df', 'ef125bb0', 2689),
  'map_basic_02@840': ('6bdecee7', '16873272', 'c993c5eb', '4e4b3fa9', 3470),
  'map_basic_03@210': ('698e5713', '88a848b5', 'ed16e0a6', '1a4f052d', 1778),
  'map_basic_03@420': ('4ae19951', 'cdf4790d', '72deea30', '62cb0d4b', 2250),
  'map_basic_03@840': ('5b25ca07', '0d0d94bc', 'ef053af6', '32c6984a', 3255),
  'map_deep_01@210': ('5cfbc022', 'e9306fb4', '6f36b16b', 'b1a1e08d', 2443),
  'map_deep_01@420': ('a6712a00', '5bf4911f', 'a3183c78', 'fe342f26', 2885),
  'map_deep_01@840': ('2bc5d9e6', '9eecda3f', '938d8863', 'abb9af54', 3492),
  'map_deep_02@210': ('e921f051', 'ba0e5b2d', '8d314d06', '6b227305', 3143),
  'map_deep_02@420': ('5d4fafd0', '2065ae51', '0c98b03c', '970981ab', 3535),
  'map_deep_02@840': ('d70c2e42', 'd71763f9', '3e4dfc48', 'b5b23d7f', 4148),
  'map_deep_03@210': ('25d600c8', '78e69c85', '19956a17', '0bbf1b78', 2885),
  'map_deep_03@420': ('7211cb47', 'a40baef5', '0e70cfab', '05ada0ed', 3213),
  'map_deep_03@840': ('813bae83', '6d7f7041', 'ef9ee9b6', '08bd8551', 3681),
  'map_deep_04@210': ('6273fb88', 'b20ebb5f', '0357ab3c', '1e732d0f', 2984),
  'map_deep_04@420': ('9b8b6965', 'f0c7ce75', '21b9ae15', '69e349c8', 3121),
  'map_deep_04@840': ('490449da', '986cc2cd', '22ef4fb2', '90873441', 3359),
  'map_deep_05@210': ('4b657c93', '526eac0f', 'a187dc89', '3b0ba9fe', 3160),
  'map_deep_05@420': ('2c263f34', 'bcdf1046', 'b2e5d90f', '814c310d', 3490),
  'map_deep_05@840': ('5da836de', '827e055a', '98858199', 'e84bda8b', 3646),
  'map_deep_06@210': ('a2f819ed', 'c25017b3', '1f9e93ec', 'b6b84b98', 3143),
  'map_deep_06@420': ('5d4fafd0', '2065ae51', '0c98b03c', '970981ab', 3535),
  'map_deep_06@840': ('e1ee5ef9', '0239b64f', 'be4981ce', '3c9a40cb', 4148),
  'map_special_01@210': ('56a4f40e', '8203367a', '311ca86f', 'e06825aa', 3111),
  'map_special_01@420': ('b9f8d307', '9c0433b7', 'dc90e176', 'edc5063e', 3472),
  'map_special_01@840': ('702b0c04', '6347eb5c', '4de93163', 'cc599880', 3917),
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
