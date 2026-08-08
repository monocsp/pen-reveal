// 정본 지도 10종의 **PNG 원본**을 읽는 통로 — 엔진이 있는 쪽이라 디코드·리샘플을 다 한다.
//
//   순수 코어 쪽 통로(`pen_reveal/test/corpus/corpus_fixtures.dart`)와 갈라 둔 이유:
//   저쪽은 PNG 를 못 풀어 프리베이크 RGBA 를 읽고, 이쪽은 원본을 직접 푼다. 그래서
//   **해상도를 바꿔 가며 재는 시험은 이쪽에만 있다**(210·420·840 — 프리베이크는 420 한 장뿐).
//
//   ⚠️ 여기서 쓰는 리샘플러는 `image_bytes.dart` 의 것 그대로다(`rgbaAt`). 테스트가 자기
//   리샘플을 따로 구현하면 "엔진이 바뀌었나"를 재는 자가 두 개가 되어 아무것도 못 잰다.
//
//   ⚠️ 자산은 **레포에 없다**(`.gitignore` §디자인 자산). 이 통로를 쓰는 테스트는 전부
//   `@Tags(['corpus'])` 이고 [corpusSkip] 으로 스스로 빠진다.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 정본 지도 10종의 키 — `corpus/maps/<key>/{base,composed}.png`.
const List<String> kCorpusKeys = <String>[
  'map_basic_01',
  'map_basic_02',
  'map_basic_03',
  'map_deep_01',
  'map_deep_02',
  'map_deep_03',
  'map_deep_04',
  'map_deep_05',
  'map_deep_06',
  'map_special_01',
];

/// 지도 원본이 사는 곳 — 테스트는 패키지 루트에서 도니 레포 루트는 두 칸 위다.
const String kCorpusMapDir = '../../corpus/maps';

String corpusMapPath(String key, {required bool composed}) =>
    '$kCorpusMapDir/$key/${composed ? 'composed' : 'base'}.png';

/// 10종이 **전부**(바닥·최종본 둘 다) 있나.
bool get hasCorpusMaps => kCorpusKeys.every(
      (key) =>
          File(corpusMapPath(key, composed: false)).existsSync() &&
          File(corpusMapPath(key, composed: true)).existsSync(),
    );

/// 자산이 없을 때 테스트에 넘길 `skip` 사유 — 있으면 `null`(=안 건너뛴다).
String? get corpusSkip => hasCorpusMaps
    ? null
    : '코퍼스 지도가 없다 — $kCorpusMapDir/<key>/{base,composed}.png 를 채운 뒤 '
        '다시 돌린다(인계 메모 §B)';

/// PNG 한 장을 디코드한다. **호출부 소유**라 다 쓰면 `dispose()` 해야 한다.
Future<ui.Image> loadCorpusImage(String key, {required bool composed}) async {
  final bytes =
      await File(corpusMapPath(key, composed: composed)).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// 지도 한 벌을 [longSide] 굽기 해상도로 리샘플해 RGBA 로.
///
///   ⚠️ 크기는 **최종본 기준**으로 잡는다 — 탐지기가 두 장을 같은 격자에서 비교해야 하고,
///   원본 앱의 굽기 경로(`RevealPreparer.prepare`)도 최종본을 기준으로 잡는다.
Future<({Uint8List baseRgba, Uint8List composedRgba, int width, int height})>
    loadCorpusRgba(String key, int longSide) async {
  final base = await loadCorpusImage(key, composed: false);
  final composed = await loadCorpusImage(key, composed: true);
  try {
    final size = fitImageLongSide(composed, longSide);
    return (
      baseRgba: await rgbaAt(base, size.width, size.height),
      composedRgba: await rgbaAt(composed, size.width, size.height),
      width: size.width,
      height: size.height,
    );
  } finally {
    base.dispose();
    composed.dispose();
  }
}
