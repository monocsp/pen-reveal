// X 를 두 획으로 가르는 탐지를 잠근다 — 실지도 픽스처 갈래.
//
//   `tool/bake_cross_calibration.py` 가 정본 지도 10종에서 구운 **진짜 X** 다. 합성 마스크는
//   내가 정답을 알고 그린 그림이라 "그 각도가 나오나"까지만 묻지만, 여기서는 python 굽기와
//   Dart 구현이 **같은 답**을 내는지가 갈린다 — 알고리즘을 한쪽만 고치면 여기가 빨개진다.
//   (각도·굵기·잡음을 내가 정해 놓고 묻는 합성 갈래는 `test/plan/cross_stroke_detector_test.dart`.)
//
//   ⚠️ 원본 앱은 이 픽스처를 **생성 Dart** 로 import 했지만 이 레포에서는 그러면 안 된다.
//   RLE 은 PNG 픽셀을 그대로 뜬 것이라 디자인 원본과 동급이고(`.gitignore` §디자인 자산),
//   없는 파일을 import 하면 자산 없는 공개 CI 에서 **컴파일 자체가 깨진다** — 태그 skip 은
//   실행을 뺄 뿐 컴파일을 빼지 못한다. 그래서 런타임에 JSON 을 읽고, 파일이 없으면
//   [_fixtureSkip] 으로 스스로 빠진다. 공개 CI 가 초록인 것은 빠뜨려서가 아니라 설계다.
//
//   ⚠️ 아래 스키마가 굽기 도구와의 **계약**이다. 키 이름은 원본 픽스처 클래스의 필드를 그대로
//   옮긴 것이라 생성기는 이대로 써야 한다(설명용 `//` 는 진짜 JSON 에 넣지 않는다):
//
//     {
//       "measured_at": "2026-08-08",     // 언제 쟀나 — 사람용 메모
//       "long_side": 420,                // 굽기 해상도. 긴 변만 고정한다
//       "fixtures": [
//         {
//           "name": "map_basic_01",
//           "width": 47, "height": 41,   // X 의 bbox 를 잘라낸 비트맵 크기
//           "runs": [5, 2, 44, ...],     // 행 우선 교대 런 길이 — **0 런부터** 시작한다
//           "pixelCount": 1066,
//           "backslashAngle": 38, "slashAngle": 137,
//           "backslashCount": 567, "slashCount": 499,
//
//           // ↓ X 를 뺀 나머지 붉은 픽셀(문구·그림). 이 파일은 안 읽는다 — 같은 JSON 을
//           //   문구 세그먼터 코퍼스 테스트가 읽어 간다. 연결요소 수는 세그먼터가 잡티를
//           //   붙이기 **전** 값이다.
//           "annotationWidth": 106, "annotationHeight": 46,
//           "annotationRuns": [...],
//           "annotationPixelCount": 1801,
//           "annotationComponentCount": 6
//         }
//       ]
//     }
@Tags(['corpus'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

/// 실지도 RLE 픽스처가 사는 곳 — 테스트는 패키지 루트에서 도니 레포 루트는 두 칸 위다.
const String _fixturePath = '../../fixtures/cross_expected.json';

/// 픽스처가 없을 때 테스트에 넘길 `skip` 사유 — 있으면 `null`(=안 건너뛴다).
///
///   `corpus_fixtures.dart` 의 `corpusSkip` 과는 **별개**다. 저쪽은 프리베이크 RGBA 를
///   보고 이쪽은 이 JSON 을 본다 — 하나만 있고 하나는 없을 수 있다.
String? get _fixtureSkip => File(_fixturePath).existsSync()
    ? null
    : '실지도 X 픽스처가 없다 — `python3 tool/bake_cross_calibration.py` 로 '
        '$_fixturePath 를 구운 뒤 다시 돌린다';

/// JSON 이 없으면 **빈 목록**이라 지도마다 만드는 `test` 가 아예 안 생긴다. 개수를 세는
///   첫 시험만 사유와 함께 skip 으로 남아 "왜 안 돌았나"가 보인다.
final List<_CrossFixture> _fixtures =
    _fixtureSkip == null ? _readFixtures() : const <_CrossFixture>[];

/// 형식이 안 맞으면 **조용히 넘어가지 않고** 던진다 — 굽는 쪽이 갈라진 것을 여기서 알아야 한다.
List<_CrossFixture> _readFixtures() {
  final text = File(_fixturePath).readAsStringSync();
  final root = jsonDecode(text) as Map<String, dynamic>;
  final list = root['fixtures'] as List<dynamic>;
  final out = <_CrossFixture>[];
  for (final entry in list) {
    out.add(_CrossFixture.fromJson(entry as Map<String, dynamic>));
  }
  return out;
}

/// 지도 하나에서 잰 X 한 개.
class _CrossFixture {
  const _CrossFixture({
    required this.name,
    required this.width,
    required this.height,
    required this.runs,
    required this.pixelCount,
    required this.backslashAngle,
    required this.slashAngle,
    required this.backslashCount,
    required this.slashCount,
  });

  factory _CrossFixture.fromJson(Map<String, dynamic> json) {
    return _CrossFixture(
      name: json['name'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      runs: (json['runs'] as List<dynamic>).cast<int>(),
      pixelCount: json['pixelCount'] as int,
      backslashAngle: json['backslashAngle'] as int,
      slashAngle: json['slashAngle'] as int,
      backslashCount: json['backslashCount'] as int,
      slashCount: json['slashCount'] as int,
    );
  }

  final String name;
  final int width;
  final int height;

  /// 교대 런 길이(0 런부터). [toMask] 로 편다.
  final List<int> runs;

  final int pixelCount;
  final int backslashAngle;
  final int slashAngle;
  final int backslashCount;
  final int slashCount;

  /// 런을 펴서 픽셀당 0/1 바이트맵으로.
  Uint8List toMask() => _inflate(runs, width * height);
}

/// 교대 런(0 런부터)을 길이 [length] 짜리 0/1 바이트맵으로 편다.
Uint8List _inflate(List<int> runs, int length) {
  final out = Uint8List(length);
  var i = 0;
  var value = 0;
  for (final run in runs) {
    if (value == 1) {
      out.fillRange(i, i + run, 1);
    }
    i += run;
    value = 1 - value;
  }
  return out;
}

void main() {
  group(
    '실지도 픽스처 — python 굽기와 같은 답을 내는가',
    () {
      test(
        '지도 10종을 다 굽는다',
        () {
          expect(_fixtures, hasLength(10));
        },
        skip: _fixtureSkip,
      );

      for (final fixture in _fixtures) {
        test(
          fixture.name,
          () {
            final mask = fixture.toMask();
            final pixels = <int>[];
            for (var i = 0; i < mask.length; i++) {
              if (mask[i] == 1) pixels.add(i);
            }
            expect(
              pixels,
              hasLength(fixture.pixelCount),
              reason: 'RLE 복원이 틀렸다',
            );

            final split = splitCrossStrokes(
              pixels: Int32List.fromList(pixels),
              width: fixture.width,
            );
            expect(split, isNotNull, reason: '실지도 X 를 못 갈랐다');

            expect(
              split!.backslash.angleDegrees,
              fixture.backslashAngle,
              reason: r'python 이 잰 `\` 각도와 다르다 — 두 구현이 갈렸다',
            );
            expect(
              split.slash.angleDegrees,
              fixture.slashAngle,
              reason: 'python 이 잰 `/` 각도와 다르다 — 두 구현이 갈렸다',
            );
            expect(split.backslashCount, fixture.backslashCount);
            expect(split.slashCount, fixture.slashCount);
            expect(
              split.backslashCount + split.slashCount,
              fixture.pixelCount,
              reason: '모든 X 픽셀이 정확히 한 획에 들어가야 한다',
            );

            // `\` 가 `/` 보다 먼저 — 각도로도 확인한다(0~90 이 오른쪽 아래).
            expect(split.backslash.angleDegrees, greaterThan(0));
            expect(split.backslash.angleDegrees, lessThan(90));
            expect(split.slash.angleDegrees, greaterThan(90));
            expect(split.slash.angleDegrees, lessThan(180));

            for (final want in const [1, 0]) {
              var topY = 1 << 30;
              var bottomY = -1;
              var atTop = 2.0;
              var atBottom = -1.0;
              for (var i = 0; i < pixels.length; i++) {
                if (split.onBackslash[i] != want) continue;
                final y = pixels[i] ~/ fixture.width;
                if (y < topY) {
                  topY = y;
                  atTop = split.within[i];
                }
                if (y > bottomY) {
                  bottomY = y;
                  atBottom = split.within[i];
                }
              }
              expect(atTop, lessThan(atBottom), reason: '획은 위에서 아래로 그어져야 한다');
            }
          },
          skip: _fixtureSkip,
        );
      }
    },
    skip: _fixtureSkip,
  );
}
