// 리샘플 크기 계산 — **정사각으로 찌그러뜨리지 않는다**는 것을 잠근다.
//
//   왜 중요한가: 코퍼스 상수(최단 124.5 · 최장 905.7)는 비율을 지킨 420px 리샘플에서 잰
//   값이다. 여기서 정사각으로 늘이면 같은 그림에서 다른 획 길이가 나오고, 연출 시간이
//   조용히 어긋난다. 엔진 없이 검증할 수 있게 정수를 받는 순수 함수로 뽑아 뒀다.
@Tags(['regression'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

void main() {
  group('fitLongSide — 비율을 지키고 긴 변만 맞춘다', () {
    test('가로가 긴 그림', () {
      final r = fitLongSide(width: 1600, height: 900, longSide: 420);
      expect(r.width, 420);
      expect(r.height, 236); // 420 * 900/1600 = 236.25 → 236
    });

    test('세로가 긴 그림', () {
      final r = fitLongSide(width: 900, height: 1600, longSide: 420);
      expect(r.height, 420);
      expect(r.width, 236);
    });

    test('정사각은 그대로 정사각', () {
      final r = fitLongSide(width: 500, height: 500, longSide: 420);
      expect(r.width, 420);
      expect(r.height, 420);
    });

    test('긴 변은 언제나 정확히 longSide 다', () {
      for (final (w, h) in const [
        (879, 500),
        (500, 879),
        (2, 1000),
        (1000, 2),
      ]) {
        final r = fitLongSide(width: w, height: h, longSide: 420);
        expect(
          r.width > r.height ? r.width : r.height,
          420,
          reason: '${w}x$h',
        );
      }
    });

    test('종횡비가 보존된다 — 찌그러지면 획 길이가 코퍼스와 안 맞는다', () {
      const w = 879;
      const h = 500;
      final r = fitLongSide(width: w, height: h, longSide: 420);
      expect(r.width / r.height, closeTo(w / h, 0.01));
    });
  });
}
