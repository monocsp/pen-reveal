// 굽는 쪽(순서값 상한)과 그리는 쪽(알파 임계)이 **같은 k 를 본다**는 것을 잠근다.
//
//   왜 이 테스트가 있나: 추출 전 원본은 이 값을 두 곳에 따로 선언했다 —
//   `dolo_reveal_texture_compiler.dart` 의 `painterSharpness = 24` 와
//   `dolo_sequential_reveal.dart` 의 `_edgeSharpness = 24`. 둘을 묶는 테스트가 없어서
//   한쪽만 바꾸면 **연출이 끝나도 마지막 획이 반투명하게 남았다.** 아무 테스트도 안
//   빨개지고, 실기에서 눈으로 봐야 알 수 있는 종류의 버그다.
//
//   `RevealSharpness` 가 둘 다 소유하게 바꿨으니 구조적으로는 어긋날 수 없지만,
//   "상한 공식과 임계 공식이 서로의 역이다" 라는 **수학적 관계**는 여전히 깨질 수 있다
//   (누가 headroom 계산의 ceil 을 floor 로 바꾸는 식으로). 그걸 여기서 잡는다.
@Tags(['regression'])
library;

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

void main() {
  group('RevealSharpness — 상한과 임계는 서로의 역', () {
    // k=1 은 headroom 이 255 라 여유가 없는 퇴화 구간이다(아래에서 따로 다룬다).
    const realistic = <double>[2, 3, 4, 8, 16, 24, 48, 64, 128, 255];

    test('maxOrderValue 픽셀은 progress=1 에서 완전히 불투명해진다', () {
      for (final k in realistic) {
        final s = RevealSharpness(k);
        expect(
          s.alphaAt(order: s.maxOrderValue, progress: 1),
          255,
          reason: 'k=$k · maxOrderValue=${s.maxOrderValue} — 마지막 획이 반투명하게 남는다. '
              'maxOrderValue 공식과 thresholdMatrix 의 k 가 어긋났다.',
        );
      }
    });

    test('maxOrderValue 보다 한 칸 큰 순서값은 불투명해지지 못한다 — 상한이 최소여야 한다', () {
      // 상한이 필요 이상으로 낮으면 시간축 해상도를 낭비한다. "딱 그 값" 임을 잠근다.
      for (final k in realistic) {
        final s = RevealSharpness(k);
        expect(
          s.alphaAt(order: s.maxOrderValue + 1, progress: 1),
          lessThan(255),
          reason: 'k=$k — 상한을 한 칸 더 올릴 수 있는데 안 올리고 있다(해상도 낭비)',
        );
      }
    });

    test('thresholdMatrix 의 알파 행이 alphaAt 과 같은 값을 낸다', () {
      // alphaAt 은 테스트용 복제다. 그게 실제 렌더가 쓰는 행렬과 갈라지면
      //   이 파일의 다른 단언들이 전부 무의미해진다.
      for (final k in <double>[8, 24, 128]) {
        final s = RevealSharpness(k);
        for (final progress in <double>[0, 0.25, 0.5, 0.75, 1]) {
          final m = s.thresholdMatrix(progress);
          // 알파 행 = 마지막 5개: [-k, 0, 0, 0, k*t*255]
          final slope = m[15];
          final offset = m[19];
          for (final order in <int>[0, 60, 120, 200, 244]) {
            final fromMatrix = (slope * order + offset).clamp(0.0, 255.0);
            expect(
              fromMatrix,
              closeTo(s.alphaAt(order: order, progress: progress), 1e-9),
              reason: 'k=$k progress=$progress order=$order',
            );
          }
        }
      }
    });

    test('hidden 픽셀은 progress=1 에서도 영영 안 드러난다', () {
      for (final k in realistic) {
        expect(
          RevealSharpness(k).alphaAt(order: kRevealHiddenSegment, progress: 1),
          0,
          reason: 'k=$k — 드러나면 안 되는 픽셀이 드러난다',
        );
      }
    });

    test('k=1 은 여유가 없는 퇴화 구간 — 상한이 1 로 잘리고 알파는 254 에 멈춘다', () {
      // 기록용이다. 원본의 `top < 1 ? 1 : top` 클램프가 남긴 구간이라 일부러 단언해
      //   둔다 — 나중에 누가 이 동작을 바꾸면 의도된 변경인지 여기서 마주치게 된다.
      const s = RevealSharpness(1);
      expect(s.maxOrderValue, 1);
      expect(s.alphaAt(order: 1, progress: 1), 254);
      expect(s.alphaAt(order: 0, progress: 1), 255);
    });

    test('가파르기는 양수여야 한다', () {
      expect(() => RevealSharpness(0), throwsA(isA<AssertionError>()));
      expect(() => RevealSharpness(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('RevealSharpness — 선단 번짐', () {
    test('k 가 클수록 선단이 좁다', () {
      expect(
        const RevealSharpness(128).leadingEdgeCodes,
        lessThan(RevealSharpness.standard.leadingEdgeCodes),
      );
    });

    test('기본 k=24 의 선단은 약 10.6 코드', () {
      // 시간축의 4.2% — 덩어리를 촘촘히 놓으면 다음 글자가 미리 비치는 그 값이다.
      expect(RevealSharpness.standard.leadingEdgeCodes, closeTo(10.625, 0.001));
    });
  });
}
