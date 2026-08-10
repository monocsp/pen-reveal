// PNG → RGBA 가 **여전히 그 바이트인가** — 리샘플러 골든.
//
//   왜 필요한가: 코퍼스 상수(최단 124.5 · 최장 905.7)는 `FilterQuality.medium` 리샘플러가
//   낸 픽셀을 잰 값이다(`src/image_bytes.dart` 의 `rgbaAt`). 엔진이 커널을 바꾸면 같은
//   PNG 에서 다른 길이가 나오고, 그때 `pen_reveal/test/corpus/length_corpus_test.dart` 가
//   빨개진다 — 그런데 **알고리즘이 바뀐 건지 엔진이 바뀐 건지 구분할 방법이 없다.**
//   이 파일이 그 둘을 가른다. **알고리즘 드리프트와 엔진 드리프트를 가르는 유일한 장치다.**
//
//     · 여기도 같이 빨갛다          → 엔진이다. 프로필을 다시 재고 manifest 의
//                                    `resampler`·Flutter 버전을 고친다.
//     · 여기는 초록인데 저기만 빨갛다 → 알고리즘이다. 굽기·탐지 쪽 변경을 의심한다.
//
//   (`src/image_bytes.dart` 주석이 가리키는 그 테스트다. 코퍼스 규약을 따르느라
//   `test/corpus/` 아래에 산다.)
//
//   ⚠️ **픽셀을 소스에 박지 않는다.** RGBA 원본을 상수로 적으면 그게 곧 디자인 자산이다.
//   대신 **다이제스트**만 커밋한다 — 스칼라라 그림이 새지 않는다. `package:crypto` 는
//   의존성에 없으니 FNV-1a 64bit 를 이 파일 안에 손으로 둔다. `Object.hashAll` 은 쓰지
//   않는다 — 표준 라이브러리의 해시는 릴리스마다 값이 바뀌어도 되는 값이라, 커밋해 두고
//   몇 년 뒤에 대조할 골든의 근거로는 약하다.
//
//   ## 기대 다이제스트 표를 채우는 법 (자산을 갖춘 기계에서 한 번)
//
//     1. `corpus/maps/<key>/{base,composed}.png` 10종을 채운다(인계 메모 §B).
//     2. `flutter test test/corpus/resampler_golden_test.dart` 를 돌린다.
//        표가 비어 있으면 이 테스트는 **일부러 실패한다.**
//     3. 실패 메시지에 찍힌 블록을 아래 [kExpectedRgbaDigest] 에 그대로 붙여 넣는다.
//        그 블록 자체가 Dart 문법이라 손으로 고칠 것이 없다.
//     4. 다시 돌려 초록인지 보고, 잰 Flutter 버전을 `corpus/manifest.json` 에 적은 뒤
//        **표만** 커밋한다(PNG 는 `.gitignore` 대상이다).
//
//   ⚠️ 표가 빨개졌을 때 새 값을 찍어 덮는 것은 "엔진이 바뀌었다"는 **판단을 내린 뒤**의
//   일이다. 먼저 Flutter 버전이 움직였는지 본다. 조용히 덮으면 이 파일은 아무것도 안 잰다.
//
//   ⚠️ 정본 지도 10종은 디자인 자산이라 이 레포에 없다 — 자산이 없으면 `corpusSkip` 으로
//   **스스로** 빠진다. 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
@Tags(['corpus'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'corpus_maps.dart';

/// 굽기 해상도 — 코퍼스 상수(최단 124.5 · 최장 905.7)를 잰 그 해상도다.
///
///   210·840 은 여기서 재지 않는다. 이 파일이 묻는 것은 "해상도를 바꿔도 순서가 같은가"가
///   아니라 "**그 해상도에서** 엔진이 같은 바이트를 내는가" 하나다.
const int kGoldenLongSide = 420;

/// 지도 한 벌의 다이제스트 — 바닥·최종본 각각 16자리 16진수.
typedef RgbaDigestPair = ({String base, String composed});

/// 기대 다이제스트 — `<key>` → 바닥·최종본의 FNV-1a 64bit.
///
///   ⚠️ **이 표는 "그 엔진에서 나온 바이트"라는 뜻이지 "옳은 바이트"라는 뜻이 아니다.**
///   Flutter 를 올리면 리샘플러가 바뀌어 여기가 통째로 빨개질 수 있다. 그때 할 일은
///   알고리즘을 의심하는 게 아니라 **표를 다시 뜨고 아래 버전을 고쳐 적는 것**이다.
///   코퍼스 길이(`length_profile.dart`)가 같이 빨개졌는지 보면 둘을 가를 수 있다 —
///   같이 움직였으면 엔진이고, 여기만 움직였으면 로더다.
///
///     잰 엔진 · Flutter 3.41.9 (stable, 00b0c91f06, 2026-04-29)
///     잰 해상도 · 긴 변 420
///     잰 자산 · corpus/maps/<key>/{base,composed}.png (879x1065)
///
///   ⚠️ 비어 있으면 아래 첫 테스트가 붙여 넣을 블록을 찍고 **일부러 실패한다** — 표 없이
///   조용히 초록이 되면 골든이 아니라 그냥 통과다. 자산이 없는 기계에서는 `corpusSkip`
///   이 먼저 걸려 여기까지 오지 않는다.
const Map<String, RgbaDigestPair> kExpectedRgbaDigest =
    <String, RgbaDigestPair>{
  'map_basic_01': (base: '93a1f4daf628da1f', composed: '5c4335de0b9c6a8f'),
  'map_basic_02': (base: '27fc9c48a7e097b8', composed: '82bd392e92647bc9'),
  'map_basic_03': (base: '557f62c70f7e7144', composed: 'b751d326ffaa387e'),
  'map_deep_01': (base: 'd5ee2940b4fb2019', composed: '9457933bea7baba2'),
  'map_deep_02': (base: '8126d08871563612', composed: '3948e1cf1de4fbcb'),
  'map_deep_03': (base: '8686fb1bd166f3a5', composed: 'aaa49239877c607a'),
  'map_deep_04': (base: '2730afcee7598648', composed: 'b16a177dc5b8597f'),
  'map_deep_05': (base: '88e024ebee3fc4c6', composed: 'e63eab7a20fe39bd'),
  'map_deep_06': (base: 'd81c3ba334e974cb', composed: 'f591d28a07a12330'),
  'map_special_01': (base: '5f0bd40cb5b2272f', composed: '4ffa3b3602bd84d1'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    '리샘플러 골든 — 굽기 해상도 $kGoldenLongSide 에서 PNG → RGBA',
    () {
      test(
        '10종의 RGBA 가 바이트 단위로 그대로다 — 움직였으면 엔진이 바뀐 것이다',
        () async {
          final digests = <String, RgbaDigestPair>{};
          for (final key in kCorpusKeys) {
            final rgba = await loadCorpusRgba(key, kGoldenLongSide);
            digests[key] = (
              base: _rgbaDigest(rgba.baseRgba, rgba.width, rgba.height),
              composed: _rgbaDigest(rgba.composedRgba, rgba.width, rgba.height),
            );
          }

          // 사람이 붙여 넣을 표 — 실패했을 때만 찍힌다.
          final block = _pasteBlock(digests);
          printOnFailure(block);

          if (kExpectedRgbaDigest.isEmpty) {
            fail(
              '기대 다이제스트 표가 비어 있다 — 자산이 있는 이 기계에서 한 번 재야 한다.\n'
              '아래 블록을 그대로 kExpectedRgbaDigest 에 붙여 넣으면 된다 '
              '(블록 자체가 Dart 문법이다).\n'
              '붙여 넣기 전에 잰 Flutter 버전을 corpus/manifest.json 에 적어 둔다 — '
              '이 표는 "그 엔진에서 나온 바이트"라는 뜻이지 "옳은 바이트"라는 뜻이 아니다.'
              '\n\n$block',
            );
          }

          expect(
            kExpectedRgbaDigest.keys.toSet().difference(kCorpusKeys.toSet()),
            isEmpty,
            reason: '표에 코퍼스에 없는 키가 있다 — 지도가 빠졌거나 이름이 갈라졌다',
          );

          for (final entry in digests.entries) {
            final key = entry.key;
            final actual = entry.value;
            final expected = kExpectedRgbaDigest[key];
            if (expected == null) {
              fail('$key: 기대 다이제스트가 표에 없다 — 표는 10종을 다 덮어야 한다');
            }
            expect(
              actual.base,
              expected.base,
              reason: '$key(base): 리샘플 결과가 움직였다 — 코퍼스 길이가 같이 빨개졌다면 '
                  '알고리즘이 아니라 엔진이다',
            );
            expect(
              actual.composed,
              expected.composed,
              reason: '$key(composed): 리샘플 결과가 움직였다 — 위와 같다',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: corpusSkip,
      );

      // 다이제스트 표가 비어 있어도 **뜻이 있는** 단언들 — 골든이 잠그는 것이 "그 바이트"
      //   라면, 이쪽은 "애초에 뜰 수 있는 모양인가"를 잠근다. 표를 채우기 전에도, 표를
      //   새로 뜬 직후에도 여기가 먼저 초록이어야 한다.
      test(
        '리샘플 결과의 모양 — 긴 변 $kGoldenLongSide, 두 장이 같은 격자, 투명 분포가 그대로',
        () async {
          for (final key in kCorpusKeys) {
            final rgba = await loadCorpusRgba(key, kGoldenLongSide);
            final longSide =
                rgba.width > rgba.height ? rgba.width : rgba.height;
            expect(
              longSide,
              kGoldenLongSide,
              reason: '$key: 긴 변이 굽기 해상도가 아니다 — 코퍼스와 다른 격자에서 잰 값은 '
                  '코퍼스와 비교할 수 없다',
            );
            expect(rgba.width, greaterThan(0), reason: '$key: 폭이 0 이다');
            expect(rgba.height, greaterThan(0), reason: '$key: 높이가 0 이다');

            final plane = rgba.width * rgba.height * 4;
            expect(
              rgba.baseRgba.length,
              plane,
              reason: '$key(base): 바이트 수가 ${rgba.width}x${rgba.height} 와 안 맞는다',
            );
            expect(
              rgba.composedRgba.length,
              plane,
              reason: '$key(composed): 최종본이 바닥과 다른 격자다 — 탐지는 두 장을 같은 '
                  '격자에서 뺀다',
            );

            // ⚠️ **전부 불투명을 요구하지 않는다.** 정본은 투명 배경 위에 뜬 폴라로이드
            //   카드라 카드 밖이 원래 비어 있다. 그 값을 **정확히** 못 박아, 자산이나
            //   리샘플러가 움직이면 걸리게 한다(예산이 아니라 등호다 — 실측이 10종·두
            //   층에서 한 값으로 같아서 느슨하게 잡을 이유가 없다).
            expect(
              _alphaShape(rgba.baseRgba, rgba.width, rgba.height),
              _kTranslucent,
              reason: '$key(base): 투명 픽셀 분포가 움직였다 — 자산이 바뀌었거나 '
                  '리샘플러가 가장자리를 다르게 문다',
            );
            expect(
              _alphaShape(rgba.composedRgba, rgba.width, rgba.height),
              _kTranslucent,
              reason: '$key(composed): 위와 같다',
            );

            // 바이트를 직접 비교하지 않는다 — 실패 메시지에 픽셀이 통째로 찍히면 그게
            //   로그로 새는 디자인 자산이다. 다이제스트끼리 비교한다.
            expect(
              _rgbaDigest(rgba.baseRgba, rgba.width, rgba.height),
              isNot(_rgbaDigest(rgba.composedRgba, rgba.width, rgba.height)),
              reason: '$key: 바닥과 최종본이 같은 바이트다 — 뺄 것이 없으면 획도 없다. '
                  '자산이 겹쳐 들어갔거나 로더가 같은 장을 두 번 읽었다',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: corpusSkip,
      );
    },
    skip: corpusSkip,
  );
}

/// 실패 메시지에 찍는, **그대로 붙여 넣는** 표.
///
///   한 줄 한 지도로 유지한다 — 사람이 diff 에서 "어느 지도가 움직였나"를 한 눈에 봐야
///   한다. 순서는 [kCorpusKeys] 순서다([digests] 가 그 순서로 채워져 온다).
String _pasteBlock(Map<String, RgbaDigestPair> digests) {
  final lines = <String>[
    'const Map<String, RgbaDigestPair> kExpectedRgbaDigest =',
    '    <String, RgbaDigestPair>{',
    for (final entry in digests.entries) _pasteLine(entry.key, entry.value),
    '};',
  ];
  return lines.join('\n');
}

/// 표의 한 줄 — 이대로 Dart 소스에 들어간다.
String _pasteLine(String key, RgbaDigestPair digest) =>
    "  '$key': (base: '${digest.base}', composed: '${digest.composed}'),";

/// 정본 10종이 공유하는 투명 픽셀 분포 — 안쪽 / 테두리.
///
///   폴라로이드 카드가 투명 배경 위에 떠 있어서 카드 밖이 비어 있다. 10종이 같은 카드
///   틀을 쓰므로 **열 장 · 두 층이 전부 같은 값**이다(실측). 지도마다 다른 예산을 둘
///   이유가 없어 상수 하나로 잠근다.
///
///   ⚠️ 이 값이 0 이 아닌 것이 정상이다. 엔진은 `composedAlphaThreshold`(기본 200)로
///   반투명 픽셀을 잉크에서 빼므로 연출에는 영향이 없다 — 카드 밖은 애초에 그릴 것이 없다.
///
///   ⚠️ 그래도 **잠그는 이유**: 여기가 움직이면 둘 중 하나다. 자산이 갈렸거나(디자인 쪽),
///   리샘플러가 그림 밖을 다르게 물기 시작했거나(엔진 쪽). 둘 다 조용히 지나가면 안 된다.
const _kTranslucent = (interior: 34314, border: 1530);

/// 알파가 255 가 아닌 픽셀의 분포 — 안쪽과 테두리를 갈라 센다.
///
///   왜 가르나: 리샘플러가 그림 밖을 물어 오면 **테두리만** 늘어나고(=엔진 쪽 이야기),
///   자산이 갈리면 안쪽이 움직인다(=자산 쪽 이야기). 합쳐 세면 다음 수를 못 정한다.
({int interior, int border}) _alphaShape(
  Uint8List rgba,
  int width,
  int height,
) {
  var interior = 0;
  var border = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rgba[(y * width + x) * 4 + 3] == 255) continue;
      if (x > 0 && y > 0 && x < width - 1 && y < height - 1) {
        interior++;
      } else {
        border++;
      }
    }
  }
  return (interior: interior, border: border);
}

// ── FNV-1a 64bit ──────────────────────────────────────────────────────────
//   손으로 둔 이유는 파일 머리에 적었다. 표준 라이브러리 산술만 쓰고, 곱셈·시프트가
//   64bit 에서 넘치면 잘리는 것에 기댄다(VM 의 int 는 고정 64bit 다).

/// 오프셋 기저 `0xcbf29ce484222325` 를 32bit 두 조각으로.
///
///   ⚠️ 한 리터럴로 적지 않는다 — 부호 있는 64bit 범위를 넘는 값이라 웹 타깃과 const
///   평가에서 처리가 갈린다. 조립해 쓰면 어디서도 같은 비트가 나온다. 값은 그대로다.
const int _fnvOffsetHi = 0xcbf29ce4;
const int _fnvOffsetLo = 0x84222325;

/// FNV-1a 64bit 의 소수 `0x100000001b3`.
const int _fnvPrime = 0x100000001b3;

int _fnvSeed() => (_fnvOffsetHi << 32) | _fnvOffsetLo;

int _fnvByte(int hash, int byte) => (hash ^ (byte & 0xff)) * _fnvPrime;

int _fnvInt32(int hash, int value) {
  var h = hash;
  for (var shift = 0; shift < 32; shift += 8) {
    h = _fnvByte(h, value >> shift);
  }
  return h;
}

/// RGBA 한 장의 다이제스트 — 16자리 16진수.
///
///   크기를 **먼저** 섞는다. 픽셀만 덮으면 같은 바이트를 다른 격자로 읽는 드리프트
///   (420x236 ↔ 236x420)를 못 잡는다.
String _rgbaDigest(Uint8List rgba, int width, int height) {
  var hash = _fnvSeed();
  hash = _fnvInt32(hash, width);
  hash = _fnvInt32(hash, height);
  for (final byte in rgba) {
    hash = _fnvByte(hash, byte);
  }
  return _hex64(hash);
}

/// 부호 없는 64bit 를 16자리 16진수로.
///
///   `toRadixString` 은 음수 앞에 `-` 를 붙여 버린다 — 다이제스트는 수가 아니라 **비트
///   패턴**이라 부호가 끼면 안 된다. 그래서 32bit 두 조각으로 나눠 찍는다.
String _hex64(int value) {
  final hi = ((value >>> 32) & 0xffffffff).toRadixString(16);
  final lo = (value & 0xffffffff).toRadixString(16);
  return '${hi.padLeft(8, '0')}${lo.padLeft(8, '0')}';
}
