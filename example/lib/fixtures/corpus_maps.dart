// fixtures/corpus_maps.dart — 정본 지도가 **있으면** 쓰고 없으면 조용히 빈손으로 돌아온다.
//
//   정본 10종은 디자인 자산이라 레포에 없다(README §코퍼스). 계측대가 그걸 요구하면 아무도
//   못 돌려 보므로, 여기서는 번들에 실제로 들어온 것만 물어보고 없으면 합성으로 간다 —
//   테스트 쪽의 자기-skip 규약과 같은 태도다.
//
//   채우는 법(자산을 가진 로컬에서만):
//
//     for k in map_basic_01 map_basic_02 map_basic_03 \
//              map_deep_01 map_deep_02 map_deep_03 map_deep_04 map_deep_05 map_deep_06 \
//              map_special_01; do
//       cp ../corpus/maps/$k/base.png     assets/maps/${k}_base.png
//       cp ../corpus/maps/$k/composed.png assets/maps/${k}_composed.png
//     done
//
//   `assets/maps/*.png` 는 gitignore 대상이다 — 픽셀은 커밋하지 않는다는 레포 규칙 그대로.
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 번들에 실린 정본 지도 키들 — 없으면 빈 목록.
Future<List<String>> availableCorpusKeys() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final keys = <String>{};
  for (final asset in manifest.listAssets()) {
    if (!asset.startsWith('assets/maps/')) continue;
    final name = asset.split('/').last;
    if (name.endsWith('_composed.png')) {
      keys.add(name.substring(0, name.length - '_composed.png'.length));
    }
  }
  // 짝이 맞는 것만 — base 가 없으면 굽지 못한다.
  final all = manifest.listAssets().toSet();
  final paired = keys
      .where((k) => all.contains('assets/maps/${k}_base.png'))
      .toList()
    ..sort();
  return paired;
}

/// 키 하나를 두 장으로 읽는다. 호출부가 소유한다(다 쓰면 dispose).
Future<({ui.Image base, ui.Image composed})> loadCorpusMap(String key) async {
  final base = await _decode('assets/maps/${key}_base.png');
  final composed = await _decode('assets/maps/${key}_composed.png');
  return (base: base, composed: composed);
}

Future<ui.Image> _decode(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
