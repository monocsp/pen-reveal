// 길이의 **자 자체**가 맞는지 — 길이를 아는 도형을 넣어 잰 값을 대조한다.
//
//   ⚠️ 이게 없으면 "자가 엉뚱해도 정본 10종에만 맞춘 정규화"가 통과한다. 코퍼스 표
//   (`test/corpus/` 의 실지도 대조)는 "지금 값이 그대로인가"만 보지 "그 값이 길이인가"는
//   못 본다. 여기서 보는 것은 잰 값이 **bbox 둘레도 픽셀 수도 아닌 경로 길이**라는 것이다.
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

const int _w = 400;
const int _h = 400;
const int _thick = 7;

Uint8List _blank() => Uint8List(_w * _h);

void _fill(Uint8List m, int left, int top, int right, int bottom) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      if (x < 0 || x >= _w || y < 0 || y >= _h) continue;
      m[y * _w + x] = 255;
    }
  }
}

double _lengthOf(Uint8List mask) =>
    bakeOneStrokeOrder(StrokeMask(mask, _w, _h)).length;

int _pixels(Uint8List mask) => mask.where((v) => v > 128).length;

void main() {
  test('곧은 선 — 잰 값이 길이(300)와 ±15%', () {
    final m = _blank();
    _fill(m, 100, 40, 100 + _thick - 1, 339); // 세로 300
    expect(_lengthOf(m), closeTo(300, 45));
  });

  test('ㄱ자 — 꺾여도 경로를 따라간다(400)', () {
    final m = _blank();
    _fill(m, 60, 40, 259, 40 + _thick - 1); // 가로 200
    _fill(m, 260 - _thick, 40, 259, 239); // 세로 200
    final measured = _lengthOf(m);

    expect(measured, closeTo(400, 60));
    // bbox 를 재는 것이었다면 둘레 800 이나 대각선 283 이 나왔을 것이다.
    expect(measured, lessThan(600), reason: 'bbox 둘레를 재고 있다');
  });

  test('U 자 — 되짚지 않고 한 바퀴만 센다(540)', () {
    final m = _blank();
    _fill(m, 60, 40, 60 + _thick - 1, 239); // 왼 세로 200
    _fill(m, 60, 240 - _thick, 199, 239); // 아래 가로 140
    _fill(m, 200 - _thick, 40, 199, 239); // 오른 세로 200
    final measured = _lengthOf(m);

    expect(measured, closeTo(540, 81));
    // 픽셀 수(≈3800)나 bbox 둘레(680)와 명백히 다르다 — 자가 바뀌면 여기서 갈린다.
    expect(_pixels(m), greaterThan(2000));
    expect(measured, lessThan(650), reason: 'bbox 둘레(680)를 재고 있다');
  });

  test('길수록 큰 값 — 자가 단조롭다', () {
    double bar(int height) {
      final m = _blank();
      _fill(m, 100, 30, 100 + _thick - 1, 30 + height - 1);
      return _lengthOf(m);
    }

    var previous = 0.0;
    for (final height in const [60, 120, 200, 300]) {
      final now = bar(height);
      expect(now, greaterThan(previous));
      previous = now;
    }
  });
}
