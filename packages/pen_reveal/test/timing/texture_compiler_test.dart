// 구조 + 시간 → 순서 텍스처 한 장. 여기서 두 관심사가 처음이자 마지막으로 만난다.
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:pen_reveal/timing.dart';
import 'package:test/test.dart';

/// 가로 [width] 짜리 띠가 [segments] 줄, 각 줄이 세그먼트 하나로 왼→오 진행하는 계획.
RevealPlan stripePlan({int width = 8, int segments = 2}) {
  final segmentId = Uint8List(width * segments)
    ..fillRange(0, width * segments, kRevealHiddenSegment);
  final within = Uint16List(width * segments);
  final list = <RevealSegment>[];
  for (var s = 0; s < segments; s++) {
    for (var x = 0; x < width; x++) {
      final i = s * width + x;
      segmentId[i] = s;
      within[i] = (x / (width - 1) * kRevealWithinScale).round();
    }
    list.add(
      RevealSegment(
        id: s,
        kind: RevealSegmentKind.annotation,
        pixelCount: width,
        left: 0,
        top: s,
        right: width - 1,
        bottom: s,
        measure: width.toDouble(),
      ),
    );
  }
  return RevealPlan(
    width: width,
    height: segments,
    segmentId: segmentId,
    within: within,
    segments: list,
  );
}

void main() {
  _sharpnessEquality();
  const policy = HandwritingRevealTiming();
  const compiler = RevealTextureCompiler();

  test('세그먼트 밖은 hidden 그대로', () {
    final plan = stripePlan();
    final order = compiler.compile(plan, policy.schedule(plan));

    final blank = RevealPlan(
      width: 2,
      height: 1,
      segmentId: Uint8List(2)..fillRange(0, 2, kRevealHiddenSegment),
      within: Uint16List(2),
      segments: const [],
    );
    expect(
      compiler.compile(blank, policy.schedule(blank)),
      everyElement(kRevealHiddenSegment),
    );
    expect(order, isNot(everyElement(kRevealHiddenSegment)));
  });

  test('한 세그먼트 안에서 왼→오로 값이 커진다', () {
    final plan = stripePlan(segments: 1);
    final order = compiler.compile(plan, policy.schedule(plan));

    for (var x = 1; x < plan.width; x++) {
      expect(order[x], greaterThanOrEqualTo(order[x - 1]));
    }
    expect(order.first, 0);
  });

  test('뒤 세그먼트가 앞 세그먼트보다 늦다', () {
    final plan = stripePlan();
    final order = compiler.compile(plan, policy.schedule(plan));

    final firstMax =
        order.sublist(0, plan.width).reduce((a, b) => a > b ? a : b);
    final secondMin = order.sublist(plan.width).reduce((a, b) => a < b ? a : b);
    expect(secondMin, greaterThanOrEqualTo(firstMax));
  });

  group('렌더 임계와의 계약', () {
    test('최대 순서값이 hidden 과 안 부딪힌다', () {
      final plan = stripePlan();
      final order = compiler.compile(plan, policy.schedule(plan));

      expect(
        order.every(
          (v) => v <= compiler.maxOrderValue || v == kRevealHiddenSegment,
        ),
        isTrue,
      );
      expect(compiler.maxOrderValue, lessThan(kRevealHiddenSegment));
    });

    test('⚠️ 임계가 무딜수록 최대값을 낮춰야 마지막 획이 불투명해진다', () {
      // 원본은 여기서 `alpha = k·(progress·255 − reveal)` 를 손으로 풀어
      //   `k·(255 − maxOrderValue) ≥ 255` 인지 직접 확인했다. 그 수식은 이제 컴파일러의
      //   것이 아니라 `RevealSharpness` 의 것이고, `sharpness_binding_test.dart` 가
      //   k 열 종으로 더 촘촘히 잠근다 — 여기서 같은 식을 다시 쓰면 굽는 쪽과 그리는
      //   쪽을 갈라 놓았던 그 상수 복제를 **테스트에서** 되풀이하는 셈이다.
      //
      //   그래서 컴파일러 몫만 남긴다: 자기 상한을 따로 만들지 않고 `RevealSharpness` 가
      //   정한 값을 그대로 쓰며, 구워 낸 바이트가 실제로 그 선을 안 넘는가.
      for (final k in const [12.0, 24.0, 128.0, 255.0]) {
        final sharpness = RevealSharpness(k);
        final compiler = RevealTextureCompiler(sharpness: sharpness);
        expect(
          compiler.maxOrderValue,
          sharpness.maxOrderValue,
          reason: 'k=$k 에서 컴파일러가 제 상한을 따로 들고 있다',
        );

        final plan = stripePlan();
        final order = compiler.compile(plan, policy.schedule(plan));
        expect(
          order.every(
            (v) => v <= compiler.maxOrderValue || v == kRevealHiddenSegment,
          ),
          isTrue,
          reason: 'k=$k 에서 마지막 획이 반투명하게 남는다',
        );
      }
    });

    test('임계가 날카로울수록 시간축을 더 쓸 수 있다', () {
      const sharp = RevealTextureCompiler(sharpness: RevealSharpness(128));
      expect(
        sharp.maxOrderValue,
        greaterThan(const RevealTextureCompiler().maxOrderValue),
      );
      // ⚠️ 244 = 255 − ⌈255/24⌉. 기본 k=24 에서 쓸 수 있는 시간축의 위끝이고,
      //   이 숫자가 바뀌면 굽는 쪽과 그리는 쪽 중 한쪽이 혼자 움직인 것이다.
      expect(const RevealTextureCompiler().maxOrderValue, 244);
      expect(sharp.maxOrderValue, 253);
    });
  });

  test('RGBA 로 부풀리면 회색 + 불투명', () {
    final rgba = revealOrderToRgba(Uint8List.fromList(const [0, 128, 255]));

    expect(rgba, hasLength(12));
    expect(rgba.sublist(0, 4), [0, 0, 0, 255]);
    expect(rgba.sublist(4, 8), [128, 128, 128, 255]);
    expect(rgba.sublist(8, 12), [255, 255, 255, 255]);
  });

  group('진짜 그림 한 장으로 끝까지', () {
    late RevealPlan plan;

    setUp(() {
      const w = 90;
      const h = 90;
      Uint8List page() {
        final rgba = Uint8List(w * h * 4);
        for (var i = 0; i < w * h; i++) {
          rgba[i * 4] = 240;
          rgba[i * 4 + 1] = 238;
          rgba[i * 4 + 2] = 230;
          rgba[i * 4 + 3] = 255;
        }
        return rgba;
      }

      final composed = page();
      void paint(int x, int y, int r, int g, int b) {
        if (x < 0 || x >= w || y < 0 || y >= h) return;
        final j = (y * w + x) * 4;
        rgba(composed, j, r, g, b);
      }

      // ⚠️ 길이 있어야 X 를 X 로 알아본다 — X 를 고르는 가장 센 신호가 **길과의 거리**다.
      for (var y = 8; y <= 58; y++) {
        for (var x = 43; x <= 47; x++) {
          paint(x, y, 40, 38, 36);
        }
      }
      // 길 끝에 찍힌 X(실지도와 같은 면적비).
      for (var t = -6; t <= 6; t++) {
        for (var thick = -1; thick <= 1; thick++) {
          paint(45 + t + thick, 61 + t, 210, 40, 40);
          paint(45 - t + thick, 61 + t, 210, 40, 40);
        }
      }
      for (var y = 74; y < 83; y++) {
        for (var x = 12; x < 24; x++) {
          paint(x, y, 205, 45, 50);
        }
        for (var x = 40; x < 52; x++) {
          paint(x, y, 205, 45, 50);
        }
      }
      plan = detectReveal(
        RevealDetectInput(
          baseRgba: page(),
          composedRgba: composed,
          width: w,
          height: h,
        ),
      );
    });

    test('진행도를 올리면 세그먼트가 차례로 다 드러난다', () {
      final schedule = policy.schedule(plan);
      final order = compiler.compile(plan, schedule);

      int revealedAt(double progress) {
        final threshold = progress * compiler.maxOrderValue;
        var count = 0;
        for (final value in order) {
          if (value != kRevealHiddenSegment && value <= threshold) count++;
        }
        return count;
      }

      final total = plan.segments.fold<int>(0, (a, s) => a + s.pixelCount);
      expect(
        revealedAt(0),
        lessThan(total ~/ 4),
        reason: '시작하자마자 다 뜨면 연출이 아니다',
      );
      expect(revealedAt(1), total, reason: '끝나면 하나도 안 남고 다 드러나야 한다');

      var previous = 0;
      for (var i = 0; i <= 20; i++) {
        final now = revealedAt(i / 20);
        expect(now, greaterThanOrEqualTo(previous), reason: '드러난 것이 되돌아갔다');
        previous = now;
      }
    });

    test(r'X `\` 획이 다 드러난 뒤에야 `/` 획이 시작된다', () {
      final schedule = policy.schedule(plan);
      final order = compiler.compile(plan, schedule);
      final backslash = plan.segments.firstWhere(
        (s) => s.kind == RevealSegmentKind.crossBackslash,
      );
      final slash = plan.segments.firstWhere(
        (s) => s.kind == RevealSegmentKind.crossSlash,
      );

      var backslashMax = 0;
      var slashMin = 255;
      for (var i = 0; i < order.length; i++) {
        if (plan.segmentId[i] == backslash.id && order[i] > backslashMax) {
          backslashMax = order[i];
        }
        if (plan.segmentId[i] == slash.id && order[i] < slashMin) {
          slashMin = order[i];
        }
      }
      expect(slashMin, greaterThan(backslashMax));
    });
  });
}

void rgba(Uint8List target, int at, int r, int g, int b) {
  target[at] = r;
  target[at + 1] = g;
  target[at + 2] = b;
  target[at + 3] = 255;
}

// 값 동등성 — 계측대가 가파르기 손잡이를 돌릴 때 **값이 같으면 다시 안 굽게** 하려고 넣었다.
//   참조 동등성이면 매 build 가 "바뀌었다" 가 되어 열 때마다 두 번 굽는다.
//
//   ⚠️ 인스턴스를 **런타임에** 만든다. `const RevealSharpness(32)` 두 개는 컴파일러가
//   같은 객체로 접어 버려서 `identical` 가지에서 통과한다 — 그러면 `==` 를 지워도 초록이라
//   시험이 아무것도 안 잰다. 그래서 값을 함수로 감싸 접힘을 막는다.
RevealSharpness _sharp(double k) => RevealSharpness(k);

RevealTextureCompiler _comp(double k) =>
    RevealTextureCompiler(sharpness: _sharp(k));

void _sharpnessEquality() {
  group('값 동등성 — 같은 k 면 같은 컴파일러다', () {
    test('RevealSharpness 는 k 로 비교한다', () {
      expect(_sharp(32), _sharp(32));
      expect(_sharp(32).hashCode, _sharp(32).hashCode);
      expect(_sharp(32), isNot(_sharp(24)));
      // 손잡이가 기본값으로 돌아왔을 때도 "같다" 여야 다시 안 굽는다.
      expect(_sharp(24), RevealSharpness.standard);
    });

    test('RevealTextureCompiler 는 sharpness 로 비교한다', () {
      expect(_comp(32), _comp(32));
      expect(_comp(32).hashCode, _comp(32).hashCode);
      expect(_comp(32), isNot(_comp(24)));
      expect(_comp(24), const RevealTextureCompiler());
    });

    test('k 가 다르면 순서값 상한도 다르다 — 다시 구워야 하는 이유', () {
      expect(_comp(24).maxOrderValue, 244);
      expect(_comp(32).maxOrderValue, 247);
      expect(
        _comp(24).maxOrderValue,
        isNot(_comp(32).maxOrderValue),
        reason: 'k 를 바꾸면 텍스처가 달라진다 — 값 동등성이 굽기 재실행을 정한다',
      );
    });
  });
}
