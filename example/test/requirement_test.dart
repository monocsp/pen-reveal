// requirement_test.dart — **요구사항을 픽셀로 잠근다.**
//
//   요구사항(원문):
//     "갈색 베이스이미지에서 하얀색길이 생성되듯이 천천히 길이 파지고, 다 파지면 도착지점에
//      X가 \ 다음 / 가 생성되고 이후에 빨간색 글씨가 생성"
//
//   눈으로 보는 것으로는 "다 파지면" 이 정말 다 파진 뒤인지, `\` 가 정말 `/` 보다 먼저인지
//   못 잡는다. 그래서 진행도별로 실제 합성 결과를 그려 픽셀을 센다.
//
//   세는 방법: 같은 진행도에서 그린 화면과 **base** 를 비교해 "달라진 픽셀"을 영역별로 센다.
//   드러난 것만 base 와 달라지므로, 영역별 변화량이 곧 그 부분이 드러난 정도다.
@Tags(['regression'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_reveal_example/fixtures/synthetic_map.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 합성 지도의 길 끝(= X 중심). `synthetic_map.dart` 의 `_roadEnd(serpentine)`.
const Offset kEnd = Offset(202, 338);

/// 진행도 [p] 에서의 화면을 원본 해상도로 그려 RGBA 를 뜬다.
Future<Uint8List> _frame(
  ui.Image base,
  ui.Image composed,
  PreparedReveal prepared,
  double p,
) async {
  final recorder = ui.PictureRecorder();
  SequentialRevealPainter(
    base: base,
    composed: composed,
    prepared: prepared,
    progress: p,
  ).paint(ui.Canvas(recorder), const Size(kMapSide, kMapSide));
  final picture = recorder.endRecording();
  final image = await picture.toImage(kMapSide.toInt(), kMapSide.toInt());
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// [rect] 안에서 [frame] 이 [baseline] 과 눈에 띄게 다른 픽셀 수.
int _changed(Uint8List frame, Uint8List baseline, Rect rect) {
  var n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
      final i = (y * kMapSide.toInt() + x) * 4;
      final d = (frame[i] - baseline[i]).abs() +
          (frame[i + 1] - baseline[i + 1]).abs() +
          (frame[i + 2] - baseline[i + 2]).abs();
      if (d > 40) n++;
    }
  }
  return n;
}

Rect get _all => const Rect.fromLTWH(0, 0, kMapSide, kMapSide);

/// X 를 감싸는 상자. 길 끝 ±32px.
Rect get _crossBox => Rect.fromCenter(center: kEnd, width: 64, height: 64);

/// `\` 획만 지나는 자리(왼쪽 위 / 오른쪽 아래 귀퉁이).
Rect get _backslashA => Rect.fromCenter(
      center: kEnd + const Offset(-17, -17),
      width: 14,
      height: 14,
    );
Rect get _backslashB =>
    Rect.fromCenter(center: kEnd + const Offset(17, 17), width: 14, height: 14);

/// `/` 획만 지나는 자리(오른쪽 위 / 왼쪽 아래 귀퉁이).
Rect get _slashA => Rect.fromCenter(
      center: kEnd + const Offset(17, -17),
      width: 14,
      height: 14,
    );
Rect get _slashB => Rect.fromCenter(
      center: kEnd + const Offset(-17, 17),
      width: 14,
      height: 14,
    );

/// 빨간 글씨가 있는 자리 — 길 끝에서 오른쪽 아래로 떨어뜨려 그렸다.
Rect get _noteBox => Rect.fromLTWH(
      kEnd.dx + 50,
      kEnd.dy + 28,
      kMapSide - (kEnd.dx + 50) - 4,
      kMapSide - (kEnd.dy + 28) - 4,
    );

/// 길만 지나는 자리 — X·글씨에서 멀리 떨어진 길 위 한 점(뱀꼴의 위쪽 굽이).
Rect get _roadBox => const Rect.fromLTWH(150, 46, 120, 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image base;
  late ui.Image composed;
  late PreparedReveal prepared;
  late Uint8List zero;

  setUpAll(() async {
    final pair = await buildSyntheticMap();
    base = pair.base;
    composed = pair.composed;
    prepared =
        await const RevealPreparer().prepare(base: base, composed: composed);
    zero = await _frame(base, composed, prepared, 0);
  });

  tearDownAll(() {
    prepared.dispose();
    base.dispose();
    composed.dispose();
  });

  group('요구사항 — 갈색 땅에서 흰 길이 파이고 X 다음 글씨', () {
    test('합성 지도가 엔진의 네 관문을 통과한다 — X 가 실제로 잡혔다', () {
      expect(
        prepared.stages.hasCross,
        isTrue,
        reason: r'X 가 안 잡히면 붉은 표시가 전부 덩어리로 가서 `\`→`/` 순서가 사라진다',
      );
      expect(prepared.stages.hasAnnotation, isTrue, reason: '글씨 덩어리가 있어야 한다');
      expect(prepared.revealDuration.inMilliseconds, greaterThan(0));
    });

    test('진행도 0 이면 갈색 바닥만 — 길·X·글씨 어느 것도 없다', () async {
      expect(_changed(zero, zero, _all), 0);
    });

    test('길이 다 파지기 전에는 X 도 글씨도 안 나온다', () async {
      final mid = await _frame(
        base,
        composed,
        prepared,
        prepared.stages.primaryEnd * 0.5,
      );
      expect(_changed(mid, zero, _roadBox), greaterThan(0), reason: '길은 파이는 중');
      expect(_changed(mid, zero, _crossBox), 0, reason: 'X 가 미리 나오면 안 된다');
      expect(_changed(mid, zero, _noteBox), 0, reason: '글씨가 미리 나오면 안 된다');
    });

    test('길 끝(primaryEnd)에서 길은 다 파였고 X 는 아직이다', () async {
      final atRoad =
          await _frame(base, composed, prepared, prepared.stages.primaryEnd);
      final full = await _frame(base, composed, prepared, 1);

      final roadNow = _changed(atRoad, zero, _roadBox);
      final roadFull = _changed(full, zero, _roadBox);
      expect(
        roadNow,
        greaterThanOrEqualTo((roadFull * 0.98).floor()),
        reason: '"다 파지면" 이므로 길은 이 시점에 사실상 전부 드러나 있어야 한다',
      );
      expect(_changed(atRoad, zero, _noteBox), 0, reason: '글씨는 아직');
    });

    test(r'X 는 `\` 가 `/` 보다 먼저 나온다', () async {
      // `\` 창의 한복판 — 두 획 사이 어딘가에서 재 본다.
      final s = prepared.stages;
      final early = s.primaryEnd + (s.crossEnd - s.primaryEnd) * 0.42;
      final frame = await _frame(base, composed, prepared, early);

      final back = _changed(frame, zero, _backslashA) +
          _changed(frame, zero, _backslashB);
      final fwd =
          _changed(frame, zero, _slashA) + _changed(frame, zero, _slashB);

      expect(back, greaterThan(0), reason: r'`\` 는 이미 나와 있어야 한다');
      expect(
        fwd,
        lessThan(back),
        reason: r'`/` 가 `\` 보다 먼저·같이 나오면 순서 계약이 깨진 것이다',
      );
    });

    test('X 끝(crossEnd)에서 X 는 다 나왔고 글씨는 아직이다', () async {
      final atCross =
          await _frame(base, composed, prepared, prepared.stages.crossEnd);
      final full = await _frame(base, composed, prepared, 1);

      final crossNow = _changed(atCross, zero, _crossBox);
      final crossFull = _changed(full, zero, _crossBox);
      expect(crossNow, greaterThanOrEqualTo((crossFull * 0.95).floor()));
      expect(
        _changed(atCross, zero, _noteBox),
        0,
        reason: 'X 를 다 그은 순간에도 글씨는 아직이어야 한다',
      );
    });

    test('마지막에 빨간 글씨가 나온다', () async {
      final full = await _frame(base, composed, prepared, 1);
      expect(_changed(full, zero, _noteBox), greaterThan(200));
    });

    test('진행도 1 에서 완성본과 픽셀이 같다 — 반투명 잔상이 없다', () async {
      final full = await _frame(base, composed, prepared, 1);

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        composed,
        const Rect.fromLTWH(0, 0, kMapSide, kMapSide),
        const Rect.fromLTWH(0, 0, kMapSide, kMapSide),
        Paint(),
      );
      final pic = recorder.endRecording();
      final img = await pic.toImage(kMapSide.toInt(), kMapSide.toInt());
      final truth = (await img.toByteData())!.buffer.asUint8List();
      pic.dispose();
      img.dispose();

      // 임계 합성이라 경계 픽셀에 1~2 오차는 난다. 눈에 보이는 잔상(>40)이 없으면 된다.
      expect(
        _changed(full, truth, _all),
        0,
        reason: '연출이 끝났는데 원본과 다르면 마지막 획이 반투명하게 남은 것이다',
      );
    });

    test('단계 경계가 순서대로 벌어져 있다', () {
      final s = prepared.stages;
      expect(s.primaryEnd, greaterThan(0));
      expect(s.crossEnd, greaterThan(s.primaryEnd));
      expect(s.annotationEnd, greaterThan(s.crossEnd));
      expect(s.annotationEnd, closeTo(1, 1e-9));
    });
  });
}
