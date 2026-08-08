// 손글씨·그림을 **읽는 순서** 덩어리로 가르는 것을 잠근다.
//
//   여기 있는 것은 전부 **합성 입력**이다 — 꽉 찬 사각형으로 "글자"를 만들어 줄 묶기와
//   줄 안 좌우 순서만 본다. 픽셀의 생김새가 아니라 순서 규칙을 재는 시험이라 실지도가
//   없어도 성립한다.
//
//   ⚠️ **옮기지 못한 단언**: 원본에는 실지도 10종의 붉은 픽셀(X 를 뺀 나머지)을 그대로
//   먹여 도는 `실지도 픽스처` 그룹이 있었다 — 줄 번호가 0 부터 끊기지 않고 커지는지,
//   같은 줄 안에서 left 가 단조증가하는지, 한 픽셀이 두 덩어리에 겹쳐 들어가지 않는지,
//   그리고 잡티 판정에 먹히는 양이 3% 미만인지를 잰다. 그 픽스처는 PNG 에서 **픽셀 단위로**
//   뜬 것이라 이 공개 레포에 없고(`.gitignore` §디자인 자산), `@Tags` 는 파일 단위라
//   여기 섞으면 합성 테스트까지 통째로 corpus 로 묶여 공개 CI 에서 빠진다.
//   그래서 그 그룹은 `test/corpus/` 몫이다 — 단언을 약하게 바꾼 게 아니라 자리를 옮겼다.
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

/// [boxes] 를 꽉 채운 사각형들로 마스크를 만든다 — (left, top, right, bottom).
Int32List blocks(int width, List<List<int>> boxes) {
  final pixels = <int>[];
  for (final box in boxes) {
    for (var y = box[1]; y <= box[3]; y++) {
      for (var x = box[0]; x <= box[2]; x++) {
        pixels.add(y * width + x);
      }
    }
  }
  return Int32List.fromList(pixels);
}

void main() {
  group('읽기 순서', () {
    test('한 줄이면 왼쪽부터', () {
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [100, 10, 118, 30],
          [10, 10, 28, 30],
          [55, 10, 73, 30],
        ]),
        width: 200,
        height: 60,
      );

      expect(chunks, hasLength(3));
      expect(chunks.map((c) => c.left), [10, 55, 100]);
      expect(chunks.map((c) => c.line), everyElement(0));
    });

    test('두 줄이면 윗줄을 다 쓰고 아랫줄로', () {
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [60, 60, 78, 80], // 아랫줄 오른쪽
          [60, 10, 78, 30], // 윗줄 오른쪽
          [10, 60, 28, 80], // 아랫줄 왼쪽
          [10, 10, 28, 30], // 윗줄 왼쪽
        ]),
        width: 200,
        height: 120,
      );

      expect(chunks, hasLength(4));
      expect(chunks.map((c) => c.line), [0, 0, 1, 1]);
      expect(chunks.map((c) => c.left), [10, 60, 10, 60]);
      expect(chunks.map((c) => c.top), [10, 10, 60, 60]);
    });

    test('⚠️ 받침이 떨어져 있어도 같은 줄로 본다 — 중심 y 로 묶으면 틀린다', () {
      // 한글 "발" 처럼 윗부분(초성+중성)과 받침이 별개 연결요소인 경우.
      // 중심 y 는 각각 20 과 46 이라 중심 기준 clustering 은 두 줄로 가른다.
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [10, 10, 30, 30], // 윗부분
          [10, 34, 30, 46], // 받침
          [45, 10, 65, 46], // 다음 글자(통짜)
        ]),
        width: 200,
        height: 80,
      );

      expect(
        chunks.map((c) => c.line).toSet(),
        {
          0,
        },
        reason: '세로로 겹치는 덩어리는 한 줄이어야 한다',
      );
    });
  });

  group('작은 조각', () {
    test('가까우면 버리지 않고 이웃에 붙인다 — 획에서 떨어져 나온 점', () {
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [10, 10, 30, 40], // 획 몸통
          [16, 45, 19, 48], // 그 아래 작은 점(16px < minChunkPixels)
        ]),
        width: 200,
        height: 80,
      );

      expect(chunks, hasLength(1), reason: '점이 몸통에 붙어야 한다');
      expect(chunks.single.bottom, 48);
      expect(
        chunks.single.pixels.length,
        21 * 31 + 4 * 4,
        reason: '붙일 때 픽셀을 잃으면 안 된다',
      );
    });

    test('아무 데도 안 붙을 만큼 멀면 제 덩어리로 선다 — 버리지는 않는다', () {
      // ⚠️ 예전엔 잡티로 버렸다. 그러면 그 픽셀이 **진행도 1 에서도 안 드러나** 최종본과
      //   달라진다(2026-08-07 회귀 — "진행도 1 에서 최종본과 100% 같아진다" 를 잠그는
      //   커버리지 테스트). 늦게라도 그리는 게 맞다.
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [10, 10, 30, 40],
          [180, 90, 183, 93], // 화면 반대편의 점
        ]),
        width: 200,
        height: 120,
      );

      expect(chunks, hasLength(2));
      expect(chunks.first.left, 10);
      expect(chunks.last.left, 180, reason: '아랫줄이라 뒤에 온다');
      expect(
        chunks.fold<int>(0, (a, c) => a + c.pixels.length),
        21 * 31 + 4 * 4,
        reason: '픽셀을 하나도 잃으면 안 된다',
      );
    });

    test('큰 덩어리가 하나도 없으면 있는 대로 쓴다', () {
      final chunks = segmentAnnotation(
        pixels: blocks(200, [
          [10, 10, 13, 13],
          [40, 10, 43, 13],
        ]),
        width: 200,
        height: 40,
      );

      expect(chunks, hasLength(2));
      expect(chunks.map((c) => c.left), [10, 40]);
    });
  });

  test('빈 입력은 빈 결과', () {
    expect(
      segmentAnnotation(pixels: Int32List(0), width: 10, height: 10),
      isEmpty,
    );
  });
}
