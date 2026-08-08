// 정본 지도 10종을 **PNG 디코더 없이** 읽는 통로.
//
//   이 패키지는 순수 Dart 라 PNG 를 못 푼다. 그래서 코퍼스 대조는 미리 구워 둔 RGBA
//   (`fixtures/rgba/<key>.bin`)를 읽는다 — 굽는 것은 Flutter 쪽 도구
//   (`tool/bake_rgba_fixtures.dart`, 인계 메모 §C)의 몫이다. **리샘플러가 캘리브레이션의
//   일부**라 순수 Dart 로 다시 뜨면 안 된다(코퍼스 상수 124.5·905.7 이 그 리샘플러가 낸
//   픽셀을 잰 값이다).
//
//   ⚠️ 이 파일이 **파일 형식의 계약**이다. 굽는 쪽은 여기 적힌 대로 써야 한다:
//
//     [0..8)   ASCII 매직 `PRRGBA1\n`
//     [8..12)  uint32 LE  width
//     [12..16) uint32 LE  height
//     [16..)   base RGBA (width*height*4) 그리고 이어서 composed RGBA (같은 길이)
//
//   크기를 헤더에 박는 이유: 긴 변만 420 이라 세로 길이는 지도마다 다르고, 파일 크기에서
//   역산하면 종횡비가 애매한 지도에서 조용히 틀린 값이 나온다.
//
//   ⚠️ 자산은 **레포에 없다**(`.gitignore` §디자인 자산 — 420px 픽셀은 원본과 동급이다).
//   그래서 이 통로를 쓰는 테스트는 전부 `@Tags(['corpus'])` 이고 [corpusSkip] 으로 스스로
//   빠진다. 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
import 'dart:io';
import 'dart:typed_data';

/// 정본 지도 10종의 키 — `fixtures/rgba/<key>.bin` 과 `corpus/maps/<key>/` 가 이 이름을 쓴다.
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

/// 프리베이크 RGBA 가 사는 곳 — 테스트는 패키지 루트에서 도니 레포 루트는 두 칸 위다.
const String kRgbaFixtureDir = '../../fixtures/rgba';

/// 파일 형식의 매직 — 굽는 쪽이 바뀌면 여기서 먼저 걸린다.
const List<int> _magic = <int>[0x50, 0x52, 0x52, 0x47, 0x42, 0x41, 0x31, 0x0a];

/// 굽기 해상도로 프리베이크된 지도 한 벌.
class CorpusPair {
  const CorpusPair({
    required this.key,
    required this.width,
    required this.height,
    required this.baseRgba,
    required this.composedRgba,
  });

  final String key;
  final int width;
  final int height;

  /// 바닥·최종본 RGBA — 둘 다 `width*height*4` 바이트.
  final Uint8List baseRgba;
  final Uint8List composedRgba;
}

String _pathOf(String key) => '$kRgbaFixtureDir/$key.bin';

/// 10종이 **전부** 있나. 반쪽만 있으면 없는 것으로 친다 — 여섯 장으로 잰 최단·최장은
///   코퍼스가 아니라 그냥 여섯 장이다.
bool get hasCorpusFixtures =>
    kCorpusKeys.every((key) => File(_pathOf(key)).existsSync());

/// 자산이 없을 때 테스트에 넘길 `skip` 사유 — 있으면 `null`(=안 건너뛴다).
///
///   `test(..., skip: corpusSkip)` 처럼 그대로 넘기면 된다.
String? get corpusSkip => hasCorpusFixtures
    ? null
    : '코퍼스 프리베이크가 없다 — `dart run tool/bake_rgba_fixtures.dart` 로 '
        '$kRgbaFixtureDir/ 를 채운 뒤 다시 돌린다(인계 메모 §C)';

/// [key] 한 벌을 읽는다. 형식이 안 맞으면 **조용히 넘어가지 않고** 던진다 —
///   굽는 쪽이 갈라진 것을 여기서 알아야 한다.
CorpusPair loadCorpusPair(String key) {
  final bytes = File(_pathOf(key)).readAsBytesSync();
  if (bytes.length < 16) {
    throw StateError('$key: 프리베이크가 헤더보다 짧다(${bytes.length}B)');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw StateError('$key: 매직이 안 맞는다 — 굽는 쪽 형식이 바뀌었다');
    }
  }
  final header = ByteData.sublistView(bytes, 8, 16);
  final width = header.getUint32(0, Endian.little);
  final height = header.getUint32(4, Endian.little);
  final plane = width * height * 4;
  if (bytes.length != 16 + plane * 2) {
    throw StateError(
      '$key: 길이가 크기와 안 맞는다 — ${width}x$height 면 ${16 + plane * 2}B '
      '여야 하는데 ${bytes.length}B 다',
    );
  }
  return CorpusPair(
    key: key,
    width: width,
    height: height,
    baseRgba: Uint8List.sublistView(bytes, 16, 16 + plane),
    composedRgba: Uint8List.sublistView(bytes, 16 + plane),
  );
}
