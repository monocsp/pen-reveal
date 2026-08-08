// 구조 층이 **시간을 모른다**는 것을 소스 수준에서 잠근다.
//
//   이건 관례로만 두면 반드시 샌다 — 나중에 누가 `Duration` 하나만 슬쩍 들이면 구조 층이
//   다시 시간 정책을 알게 되고, 그 순간 같은 계획을 화면마다 다른 리듬으로 그릴 수 없어진다.
//   그래서 **파일을 읽어서** 확인한다. 관례가 아니라 계약이다.
//
//   원본(앱)에서는 이 경계가 `lib/core/image/` vs `lib/design_system/` 폴더였다.
//   여기서는 `lib/src/plan/` vs `lib/src/timing/` 이다 — 강도는 같다.
@Tags(['regression'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// 구조 층에서 절대 나오면 안 되는 것들 — 시간·애니메이션·Flutter.
const _forbidden = <String, String>{
  'Duration': '시간 단위가 구조 층에 들어왔다',
  'Curve': '가감속이 구조 층에 들어왔다',
  'milliseconds': '시간 단위가 구조 층에 들어왔다',
  'Tween': '애니메이션이 구조 층에 들어왔다',
  'AnimationController': '애니메이션이 구조 층에 들어왔다',
};

/// 시간 이름을 **에둘러** 들이는 것도 막는다 — `relativeMs`·`primaryDurationHint` 처럼
///   금칙 타입은 피하면서 뜻만 시간인 필드가 생기면 분리가 이름부터 무너진다.
final _timeishName = RegExp(r'duration|millis|_ms\b', caseSensitive: false);

const _planDir = 'lib/src/plan';
const _timingDir = 'lib/src/timing';

/// 주석·doc 을 걷어낸 알맹이. 금칙어가 주석에 나오는 것은 막지 않는다 —
///   "여기엔 Duration 이 없다" 라고 설명하는 주석이 스스로를 빨갛게 만들면 안 된다.
String _code(String source) => source
    .replaceAll(RegExp('///.*'), '')
    .replaceAll(RegExp('//.*'), '')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    fail('$dir 가 없다 — 테스트를 패키지 루트에서 돌리고 있는지 확인하라');
  }
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('구조 층(plan)은 시간을 모른다', () {
    test('감시 대상이 비어 있지 않다', () {
      // 경로가 바뀌어 0개를 훑고 "통과"하는 것이 이 테스트의 최악 실패다.
      expect(_dartFiles(_planDir).length, greaterThanOrEqualTo(7));
    });

    test('금칙 타입이 없다', () {
      for (final file in _dartFiles(_planDir)) {
        final code = _code(file.readAsStringSync());
        for (final entry in _forbidden.entries) {
          expect(
            RegExp('\\b${entry.key}\\b').hasMatch(code),
            isFalse,
            reason: '${file.path}: ${entry.value} (`${entry.key}`)',
          );
        }
      }
    });

    test('시간을 에둘러 뜻하는 이름도 없다', () {
      for (final file in _dartFiles(_planDir)) {
        final match = _timeishName.firstMatch(_code(file.readAsStringSync()));
        expect(
          match,
          isNull,
          reason: '${file.path}: 이름만 시간인 식별자(`${match?.group(0)}`)가 구조 층에 생겼다',
        );
      }
    });

    test('표현 층을 import 하지 않는다 — 의존 방향은 timing → plan 한쪽뿐', () {
      for (final file in _dartFiles(_planDir)) {
        final code = _code(file.readAsStringSync());
        expect(
          code.contains('src/timing'),
          isFalse,
          reason: '${file.path}: 구조 층이 표현 층을 import 했다(방향이 뒤집혔다)',
        );
        expect(
          code.contains("import 'package:pen_reveal/timing.dart'"),
          isFalse,
          reason: '${file.path}: 구조 층이 표현 층 배럴을 import 했다',
        );
      }
    });

    test('Flutter 를 import 하지 않는다 — 순수 Dart 여야 isolate 로 넘길 수 있다', () {
      for (final file in [..._dartFiles(_planDir), ..._dartFiles(_timingDir)]) {
        final code = _code(file.readAsStringSync());
        for (final banned in const ['package:flutter/', 'dart:ui']) {
          expect(
            code.contains(banned),
            isFalse,
            reason: '${file.path}: `$banned` — 이 패키지는 Flutter 무의존이다',
          );
        }
      }
    });
  });

  group('표현 층(timing)이 시간의 유일한 소유자', () {
    test('plan.dart 배럴은 timing 을 export 하지 않는다', () {
      final barrel = File('lib/plan.dart').readAsStringSync();
      expect(
        _code(barrel).contains('timing'),
        isFalse,
        reason: 'plan.dart 가 timing 을 새어 보내면 import 로 층을 고를 수 없다',
      );
    });

    test('임계 가파르기를 아는 파일은 sharpness.dart 하나뿐', () {
      // 원본의 실수(상수 복제)를 구조적으로 재발 못 하게 하는 단언이다.
      final owners = <String>[];
      for (final file in _dartFiles(_timingDir)) {
        if (_code(file.readAsStringSync()).contains('thresholdMatrix') &&
            file.path.contains('sharpness.dart') == false) {
          owners.add(file.path);
        }
      }
      expect(
        owners,
        isEmpty,
        reason: '임계 행렬을 sharpness.dart 밖에서 만들고 있다: $owners',
      );
    });
  });
}
