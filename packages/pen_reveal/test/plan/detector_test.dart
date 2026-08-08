// 그림 두 장 → 드러낼 순서 계획. 코어 진입점을 통째로 잠근다.
//
//   ⚠️ 인공 장면이지만 **실지도의 비율을 흉내 낸다** — X 를 고르는 관문이 전부 비율
//   (면적비·거리비)이라, 아무렇게나 그린 X 는 진짜 지도에서 통하는 규칙을 못 통과한다.
//   여기서 지키는 계약: X 는 **길 위에** 찍힌 **X 크기**의 **두 막대** 덩어리다.
import 'dart:typed_data';

import 'package:pen_reveal/plan.dart';
import 'package:test/test.dart';

const int _w = 90;
const int _h = 90;

/// 흰 종이 한 장.
Uint8List blankPage() {
  final rgba = Uint8List(_w * _h * 4);
  for (var i = 0; i < _w * _h; i++) {
    rgba[i * 4] = 240;
    rgba[i * 4 + 1] = 238;
    rgba[i * 4 + 2] = 230;
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}

void paint(Uint8List rgba, int x, int y, int r, int g, int b) {
  if (x < 0 || x >= _w || y < 0 || y >= _h) return;
  final j = (y * _w + x) * 4;
  rgba[j] = r;
  rgba[j + 1] = g;
  rgba[j + 2] = b;
  rgba[j + 3] = 255;
}

/// 위에서 아래로 내려긋는 검은 길. 끝점은 (45, 58).
void paintRoad(Uint8List rgba) {
  for (var y = 8; y <= 58; y++) {
    for (var x = 43; x <= 47; x++) {
      paint(rgba, x, y, 40, 38, 36);
    }
  }
}

/// 두 획으로 된 빨간 X. 기본값은 실지도와 같은 면적비(≈0.0096)다.
void paintCross(Uint8List rgba, int cx, int cy, {int reach = 6}) {
  for (var t = -reach; t <= reach; t++) {
    for (var thick = -1; thick <= 1; thick++) {
      paint(rgba, cx + t + thick, cy + t, 210, 40, 40);
      paint(rgba, cx - t + thick, cy + t, 210, 40, 40);
    }
  }
}

/// X 의 `\` 획 하나만(반쪽).
void paintHalfCross(Uint8List rgba, int cx, int cy, {int reach = 6}) {
  for (var t = -reach; t <= reach; t++) {
    for (var thick = -1; thick <= 1; thick++) {
      paint(rgba, cx + t + thick, cy + t, 210, 40, 40);
    }
  }
}

/// 빨간 글씨 덩어리(사각 블록).
void paintWord(Uint8List rgba, int left, int top, int width, int height) {
  for (var y = top; y < top + height; y++) {
    for (var x = left; x < left + width; x++) {
      paint(rgba, x, y, 205, 45, 50);
    }
  }
}

void main() {
  late Uint8List base;
  late Uint8List composed;

  setUp(() {
    base = blankPage();
    composed = blankPage();
    paintRoad(composed);
    // X 는 길 끝에 찍힌다 — 위치가 X 를 가르는 가장 센 신호다.
    paintCross(composed, 45, 61);
    paintWord(composed, 12, 74, 12, 9);
    paintWord(composed, 32, 74, 12, 9);
    paintWord(composed, 52, 74, 12, 9);
  });

  RevealPlan detect() => detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      );

  test(r'순서는 길 → X `\` → X `/` → 문구 덩어리들', () {
    final plan = detect();
    final kinds = plan.segments.map((s) => s.kind).toList();

    expect(kinds.first, RevealSegmentKind.primaryStroke);
    expect(kinds[1], RevealSegmentKind.crossBackslash);
    expect(kinds[2], RevealSegmentKind.crossSlash);
    expect(kinds.skip(3), everyElement(RevealSegmentKind.annotation));
    expect(kinds.skip(3), hasLength(3), reason: '글씨 덩어리 셋');
  });

  test('세그먼트 id 는 재생 순서와 같다', () {
    final plan = detect();
    for (var i = 0; i < plan.segments.length; i++) {
      expect(plan.segments[i].id, i);
    }
  });

  test('문구 덩어리는 왼쪽부터', () {
    final plan = detect();
    final annotations = plan.segments
        .where((s) => s.kind == RevealSegmentKind.annotation)
        .toList();

    for (var i = 1; i < annotations.length; i++) {
      expect(annotations[i].left, greaterThan(annotations[i - 1].left));
    }
  });

  test('덩어리 안의 진행도는 왼 → 오로 커진다', () {
    final plan = detect();
    final chunk = plan.segments.lastWhere(
      (s) => s.kind == RevealSegmentKind.annotation,
    );

    var leftmost = 1 << 30;
    var rightmost = -1;
    var atLeft = 1 << 30;
    var atRight = -1;
    for (var i = 0; i < plan.segmentId.length; i++) {
      if (plan.segmentId[i] != chunk.id) continue;
      final x = i % _w;
      if (x < leftmost) {
        leftmost = x;
        atLeft = plan.within[i];
      }
      if (x > rightmost) {
        rightmost = x;
        atRight = plan.within[i];
      }
    }
    expect(atLeft, 0);
    expect(atRight, kRevealWithinScale);
  });

  test('X 두 획은 픽셀을 나눠 갖고 겹치지 않는다', () {
    final plan = detect();
    final backslash = plan.segments.firstWhere(
      (s) => s.kind == RevealSegmentKind.crossBackslash,
    );
    final slash = plan.segments.firstWhere(
      (s) => s.kind == RevealSegmentKind.crossSlash,
    );

    expect(backslash.pixelCount, greaterThan(0));
    expect(slash.pixelCount, greaterThan(0));

    var red = 0;
    for (var i = 0; i < _w * _h; i++) {
      final j = i * 4;
      if (composed[j] - composed[j + 1] > 35 && composed[j] != base[j]) red++;
    }
    final annotationPixels = plan.segments
        .where((s) => s.kind == RevealSegmentKind.annotation)
        .fold<int>(0, (sum, s) => sum + s.pixelCount);
    expect(
      backslash.pixelCount + slash.pixelCount + annotationPixels,
      red,
      reason: '붉은 픽셀은 하나도 빠지지 않고 정확히 한 세그먼트에 들어가야 한다',
    );
  });

  test('X 획 안의 진행도는 위 → 아래로 커진다', () {
    final plan = detect();
    for (final kind in const [
      RevealSegmentKind.crossBackslash,
      RevealSegmentKind.crossSlash,
    ]) {
      final segment = plan.segments.firstWhere((s) => s.kind == kind);
      var topY = 1 << 30;
      var bottomY = -1;
      var atTop = 1 << 30;
      var atBottom = -1;
      for (var i = 0; i < plan.segmentId.length; i++) {
        if (plan.segmentId[i] != segment.id) continue;
        final y = i ~/ _w;
        if (y < topY) {
          topY = y;
          atTop = plan.within[i];
        }
        if (y > bottomY) {
          bottomY = y;
          atBottom = plan.within[i];
        }
      }
      expect(atTop, lessThan(atBottom), reason: '$kind 가 아래에서 위로 그어졌다');
    }
  });

  test('두 장이 같으면 계획이 비어 있다', () {
    composed = blankPage();
    expect(detect().isEmpty, isTrue);
  });

  test('세그먼트에 안 든 픽셀은 hidden 이다', () {
    final plan = detect();
    var hidden = 0;
    for (final id in plan.segmentId) {
      if (id == kRevealHiddenSegment) hidden++;
    }
    final covered = plan.segments.fold<int>(0, (a, s) => a + s.pixelCount);
    expect(hidden + covered, _w * _h);
  });

  test('크기가 안 맞으면 던진다', () {
    expect(
      () => detectReveal(
        RevealDetectInput(
          baseRgba: Uint8List(4),
          composedRgba: composed,
          width: _w,
          height: _h,
        ),
      ),
      throwsArgumentError,
    );
  });

  // ── X 를 고르는 관문 ────────────────────────────────────────────────────────
  //
  //   "최대 붉은 연결요소 = X" 는 위험하다(실측 면적 우세비 최악 1.21배). 형태 검사
  //   (`splitCrossStrokes`)도 정체 검사가 아니라 non-X 덩어리의 8/10 이 통과한다.
  //   그래서 **길과의 거리 + 면적비 + 형태** 를 다 본다. 하나라도 안 맞으면 X 가 아니라
  //   문구로 되돌린다 — 못 알아본 것을 억지로 X 로 쓰는 것보다 낫다.
  group('X 는 길 위에 찍힌 X 크기의 두 막대다', () {
    List<RevealSegmentKind> kindsOf(RevealPlan plan) =>
        plan.segments.map((s) => s.kind).toList();

    test('X 가 반쪽만 남으면 X 로 안 본다 — 문구를 X 로 오인하지도 않는다', () {
      composed = blankPage();
      paintRoad(composed);
      paintHalfCross(composed, 45, 61);
      paintWord(composed, 12, 74, 12, 9);
      paintWord(composed, 32, 74, 12, 9);

      final kinds = kindsOf(detect());
      expect(kinds, isNot(contains(RevealSegmentKind.crossBackslash)));
      expect(kinds, isNot(contains(RevealSegmentKind.crossSlash)));
      expect(kinds.first, RevealSegmentKind.primaryStroke);
      expect(kinds.skip(1), everyElement(RevealSegmentKind.annotation));
    });

    test('X 가 아예 없으면 문구만 남는다', () {
      composed = blankPage();
      paintRoad(composed);
      paintWord(composed, 12, 74, 12, 9);
      paintWord(composed, 32, 74, 12, 9);

      expect(kindsOf(detect()), [
        RevealSegmentKind.primaryStroke,
        RevealSegmentKind.annotation,
        RevealSegmentKind.annotation,
      ]);
    });

    test('X 모양이어도 길에서 멀면 X 가 아니다 — 위치가 가장 센 신호다', () {
      composed = blankPage();
      paintRoad(composed);
      // 크기·모양은 X 그대로인데 길에서 떨어져 있다. 후보가 이것 하나뿐이라
      //   **거리 관문만이** 이걸 막을 수 있다.
      paintCross(composed, 74, 79);

      final kinds = kindsOf(detect());
      expect(kinds, isNot(contains(RevealSegmentKind.crossBackslash)));
      expect(kinds, isNot(contains(RevealSegmentKind.crossSlash)));
    });

    test('관문에 걸린 덩어리는 읽기 순서대로 — 맨 처음이 아니다', () {
      // ⚠️ 여기서 잡는 결함: 관문에 걸린 후보를 문구 목록에 **되돌리지 않고** 곧장
      //   세그먼트로 박으면 id 가 제일 작아 읽기 순서를 무시하고 맨 처음 떠 버린다.
      //   그래서 **맨 오른쪽 덩어리가 제일 크게** 그려 둔다 — 되돌리지 않으면 오른쪽 끝
      //   글자가 왼쪽 글자보다 먼저 써진다.
      composed = blankPage();
      paintRoad(composed);
      paintWord(composed, 12, 74, 8, 9);
      paintWord(composed, 32, 74, 8, 9);
      paintWord(composed, 68, 72, 14, 13); // 제일 큰데 맨 오른쪽

      final plan = detect();
      final annotations = plan.segments
          .where((s) => s.kind == RevealSegmentKind.annotation)
          .toList();
      expect(annotations, hasLength(3));
      expect(annotations.first.left, 12, reason: '맨 왼쪽이 먼저 써져야 한다');
      expect(annotations.last.left, 68, reason: '맨 오른쪽이 마지막이어야 한다');
      for (var i = 1; i < annotations.length; i++) {
        expect(annotations[i].left, greaterThan(annotations[i - 1].left));
      }
    });

    test('길이 없으면 X 를 안 고른다 — 위치 신호가 없으면 문구로', () {
      composed = blankPage();
      paintCross(composed, 45, 61);
      paintWord(composed, 12, 74, 12, 9);

      final kinds = kindsOf(detect());
      expect(kinds, isNot(contains(RevealSegmentKind.crossBackslash)));
      expect(kinds, everyElement(RevealSegmentKind.annotation));
    });

    test('관문은 설정으로 열려 있다 — 다른 그림에도 맞출 수 있다', () {
      composed = blankPage();
      paintRoad(composed);
      // 길에서 12px 떨어졌다 — 기본 관문(0.05×90=4.5px)에는 걸린다.
      paintCross(composed, 45, 70);
      paintWord(composed, 12, 78, 12, 9);

      expect(
        detect().segments.map((s) => s.kind),
        isNot(contains(RevealSegmentKind.crossBackslash)),
      );
      final loose = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: _w,
          height: _h,
          config: const RevealDetectConfig(xMaxRoadDistanceRatio: 0.2),
        ),
      );
      expect(
        loose.segments.map((s) => s.kind),
        contains(RevealSegmentKind.crossBackslash),
      );
    });
  });
}
