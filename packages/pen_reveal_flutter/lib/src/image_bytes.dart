// src/image_bytes.dart — `ui.Image` ↔ raw RGBA. **엔진 경계는 이 파일에만 있다.**
//
//   ⚠️ 여기서 쓰는 리샘플러(`FilterQuality.medium`)는 사실상 **캘리브레이션의 일부**다.
//   `pen_reveal` 의 코퍼스 상수(최단 124.5 · 최장 905.7)는 이 리샘플러가 낸 픽셀을 잰
//   값이다. 엔진이 커널을 바꾸면 같은 PNG 에서 다른 길이가 나온다 — 그래서
//   `test/resampler_golden_test.dart` 가 "PNG → RGBA 가 여전히 그 바이트인가"를 따로 잠근다.
//   그 테스트가 빨개지면 알고리즘이 아니라 **엔진이** 바뀐 것이다.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// [src] 를 [width]×[height] 로 리샘플해 raw RGBA 를 뜬다.
///
///   임시 자원은 실패해도 반드시 놓는다. 반환 바이트는 이미 복사본이라 원본 수명과 무관하다.
Future<Uint8List> rgbaAt(ui.Image src, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    src,
    Offset.zero & Size(src.width.toDouble(), src.height.toDouble()),
    Offset.zero & Size(width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  try {
    final resized = await picture.toImage(width, height);
    try {
      final data = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('리샘플한 이미지에서 픽셀을 못 읽었다(${width}x$height)');
      }
      // `toByteData` 는 이미 복사본이라 이미지를 놓아도 살아 있다.
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      resized.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 원본 비율을 지키면서 **긴 변만** [longSide] 에 맞춘 크기.
///
///   ⚠️ 정사각(`longSide`×`longSide`)이 아니다 — 억지로 맞추면 그림이 찌그러지고,
///   찌그러진 그림에서 잰 길 길이는 코퍼스와 비교할 수 없게 된다.
({int width, int height}) fitLongSide(ui.Image image, int longSide) {
  final wide = image.width >= image.height;
  return (
    width: wide ? longSide : (longSide * image.width / image.height).round(),
    height: wide ? (longSide * image.height / image.width).round() : longSide,
  );
}

/// 회색 RGBA 바이트를 텍스처로.
Future<ui.Image> textureFromRgba(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// [ImageProvider] 를 디코드해 [ui.Image] 로 — 그리기 전에 **픽셀을 뜯어봐야** 할 때 쓴다.
///
///   반환값은 **호출부 소유**다(image cache 의 것과 별개인 clone). 다 쓰면 `dispose()` 해야
///   한다. clone 을 뜨는 이유: 그냥 참조만 들고 있으면 cache 가 원본을 비울 때 같이 죽어
///   "Cannot access a disposed image" 로 터진다.
Future<ui.Image> decodeImageProvider(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (completer.isCompleted) {
        info.dispose();
        return;
      }
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
