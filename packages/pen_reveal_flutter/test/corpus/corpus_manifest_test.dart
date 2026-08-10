// `corpus/manifest.json` 이 **거짓말을 못 하게** 한다.
//
//   README 가 오래도록 이 파일을 가리키고 있었는데 **실물이 없었다.** 테스트 주석도
//   "잰 Flutter 버전을 manifest 에 적어라" 라고 지시했지만 적을 곳이 없었다. 그래서
//   이번에 만들었는데, 손으로 유지하는 문서를 그냥 두면 자산과 따로 놀다가 **다른 종류의
//   거짓말**이 된다 — 없는 것보다 나쁠 수 있다.
//
//   이 파일은 그 문서를 실제 환경과 대조한다:
//     · 코퍼스 키 목록이 로더가 아는 것과 같은가
//     · 굽기 해상도가 골든이 쓰는 값과 같은가
//     · 적어 둔 Flutter 버전이 지금 도는 버전과 같은가
//     · 계보가 가리키는 파일들이 실제로 있는가
//
//   ⚠️ **Flutter 를 올리면 여기가 빨개진다. 그게 의도다.** 리샘플러가 바뀌면 다이제스트와
//   코퍼스 길이를 다시 재야 하는데, 그 신호를 사람의 기억이 아니라 게이트가 준다.
//   그때 할 일은 값을 다시 재고 manifest 를 고치는 것이지 이 시험을 지우는 것이 아니다.
//
//   ⚠️ 자산이 없어도 도는 검사와 자산이 있어야 도는 검사를 갈라 둔다 — 문서의 앞뒤가
//   맞는지는 그림 없이도 볼 수 있다.
@Tags(['corpus'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'corpus_maps.dart';
import 'resampler_golden_test.dart' show kGoldenLongSide;

/// 레포 루트에서 본 manifest 자리. 테스트는 패키지 루트에서 돈다.
const _manifestPath = '../../corpus/manifest.json';

Map<String, dynamic> _load() {
  final file = File(_manifestPath);
  if (!file.existsSync()) {
    fail(
      '$_manifestPath 가 없다. README §코퍼스 가 이 파일을 가리키므로 '
      '없으면 README 가 거짓말을 한다 — 파일을 만들거나 README 에서 링크를 지운다.',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('코퍼스 계보 문서', () {
    test('키 목록이 로더가 아는 것과 같다', () {
      final m = _load();
      final keys = ((m['corpus'] as Map)['keys'] as List).cast<String>();
      expect(
        keys.toSet(),
        kCorpusKeys.toSet(),
        reason: 'manifest 의 키가 코드의 kCorpusKeys 와 갈렸다 — 지도가 늘거나 줄었는데 '
            '한쪽만 고쳤다',
      );
    });

    test('굽기 해상도가 골든이 쓰는 값과 같다', () {
      final m = _load();
      final side = (m['measuredWith'] as Map)['bakeLongSide'] as int;
      expect(
        side,
        kGoldenLongSide,
        reason: 'manifest 가 적은 해상도와 골든이 재는 해상도가 다르다 — 두 값을 다른 '
            '격자에서 재 놓고 비교하게 된다',
      );
    });

    test('계보가 가리키는 파일이 실제로 있다', () {
      final m = _load();
      final derived =
          (m['derivedConstants'] as List).cast<Map<String, dynamic>>();
      expect(derived, isNotEmpty, reason: '계보가 비었다 — 문서가 아무것도 안 말한다');
      for (final entry in derived) {
        final where = entry['where'] as String;
        expect(
          File('../../$where').existsSync(),
          isTrue,
          reason: 'manifest 가 가리키는 $where 가 없다 — 파일이 옮겨졌는데 문서만 남았다',
        );
        final guard = entry['guardedBy'] as String?;
        if (guard == null) continue;
        expect(
          File('../../$guard').existsSync(),
          isTrue,
          reason: '$where 를 지킨다는 $guard 가 없다',
        );
      }
    });

    // ⚠️ 이것만 자산이 필요하다 — 버전이 어긋났다는 말은 "다시 재야 한다" 는 뜻인데,
    //   잴 그림이 없는 기계에서는 할 수 있는 일이 없다.
    test(
      '적어 둔 Flutter 버전이 지금 도는 버전과 같다',
      () {
        final m = _load();
        final want = (m['measuredWith'] as Map)['flutter'] as String;
        final result = Process.runSync('flutter', ['--version', '--machine']);
        if (result.exitCode != 0) {
          markTestSkipped('flutter --version 을 못 돌렸다');
          return;
        }
        final info =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final now = info['frameworkVersion'] as String;
        expect(
          now,
          want,
          reason: 'manifest 는 Flutter $want 에서 쟀다고 적혀 있는데 지금은 $now 다.\n'
              '리샘플러가 바뀌었을 수 있다 — 다이제스트(resampler_golden_test)와 '
              '코퍼스 길이(length_corpus_test)가 같이 빨개졌는지 먼저 보고,\n'
              '엔진 드리프트가 맞으면 값을 다시 재고 manifest 의 flutter 를 고친다. '
              '이 시험을 지우지 않는다.',
        );
      },
      skip: corpusSkip,
    );
  });
}
