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

    test('표현 층은 구조 층을 안다 — 화살표는 한 방향이고, 끊겨도 안 된다', () {
      final policy =
          _code(File('$_timingDir/timing_policy.dart').readAsStringSync());
      expect(
        policy.contains('reveal_plan.dart'),
        isTrue,
        reason: '정책이 계획을 안 본다 — 화살표가 끊겼다',
      );
      expect(policy.contains('Duration'), isTrue, reason: '시간은 여기 있어야 한다');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 반대 방향도 잠근다. 위 단언들은 "구조 층이 시간을 모른다" 만 보는데, 실제로 무너진 적이
  //   있는 쪽은 **그 반대**였다 — 표현 층이 픽셀 길이를 다시 읽고 코퍼스 기준·압축 곡선을
  //   자기 안에 복제하는 것. 그러면 밴드를 바꿀 때마다 곡선이 같이 흔들려 "t=0.5 = 밴드의
  //   절반" 이라는 약속이 깨지는데, 시간 시험은 전부 초록이다(양쪽이 같이 틀리니까).
  // ─────────────────────────────────────────────────────────────────────────
  group('반대쪽 — 표현 층은 픽셀 길이를 모른다', () {
    const policyPath = '$_timingDir/timing_policy.dart';
    const profilePath = '$_planDir/length_profile.dart';

    /// 코퍼스를 잰 숫자들 — 이 값이 사는 곳은 [profilePath] 하나뿐이어야 한다.
    const corpusLiterals = <String>['124.5', '905.7'];

    test('정책은 길 픽셀이 아니라 0~1 을 읽는다', () {
      final code = _code(File(policyPath).readAsStringSync());
      expect(
        code.contains('_primaryMillis(segment.relativeLength'),
        isTrue,
        reason: '주 획 시간이 다시 픽셀에서 나온다',
      );
      expect(
        code.contains('_primaryMillis(segment.measure'),
        isFalse,
        reason: 'measure(픽셀)는 문구·X 의 자다 — 주 획에 쓰면 정규화가 무의미해진다',
      );
    });

    test('정책에 코퍼스 기준·압축 곡선이 다시 생기지 않았다', () {
      final code = _code(File(policyPath).readAsStringSync());
      for (final gone in const [
        'math.pow',
        'referenceLongSide',
        'compression',
        ...corpusLiterals,
      ]) {
        expect(
          code.contains(gone),
          isFalse,
          reason: '길이의 자가 표현 층으로 되돌아왔다(`$gone`) — 기준은 구조 층이 소유한다',
        );
      }
    });

    test('코퍼스 상수는 length_profile.dart 안에서도 한 번씩만 나온다', () {
      // 같은 파일 안에서 두 번 적히면 한쪽만 고치는 사고가 다시 가능해진다.
      final source = _code(File(profilePath).readAsStringSync());
      for (final literal in const ['124.5', '905.7', '0.35']) {
        expect(
          RegExp(RegExp.escape(literal)).allMatches(source).length,
          1,
          reason: '$literal 이 정규화 파일 안에서 여러 번 나온다 — 출처가 갈렸다',
        );
      }
    });

    test('표현 층 어느 파일에도 코퍼스 숫자가 한 톨도 없다', () {
      for (final file in _dartFiles(_timingDir)) {
        final code = _code(file.readAsStringSync());
        for (final literal in corpusLiterals) {
          expect(
            code.contains(literal),
            isFalse,
            reason: '${file.path}: 길이의 자($literal)가 표현 층에 새어 나왔다',
          );
        }
      }
    });

    test('시간 시험의 기대값은 리터럴이다 — 공식을 다시 쓰면 아무것도 안 잡는다', () {
      // 지수 함수를 못 부르면 기대값을 공식으로 다시 쓸 수가 없다. (이 검사를 그 파일 안에
      //   두면 검사 문자열 자체가 걸려 영영 빨갛다 — 그래서 여기 있다.)
      const path = 'test/timing/timing_policy_test.dart';
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path 가 없다 — 시간 정책 시험이 사라졌다',
      );
      expect(
        file.readAsStringSync().contains("import 'dart:math'"),
        isFalse,
        reason: '$path 가 지수 함수를 부른다 — 구현이 곧 기대값이 됐을 수 있다',
      );
    });
  });
}
