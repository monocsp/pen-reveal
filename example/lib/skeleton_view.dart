// skeleton_view.dart — **길을 얇은 선 하나로 단순화한 결과를 눈으로 보는 화면.**
//
//   연출을 보는 화면이 아니다. 시간도 순서도 안 그린다 — 굽기의 **중간 산물**인 뼈대가
//   어떤 모양으로 나오는지만 본다. 성능을 손보기 전에 "무엇을 줄이고 있는지" 를 먼저
//   눈으로 확인하려고 만든 것이다.
//
//   ⚠️ **`compute` 를 쓰지 않고 본 isolate 에서 동기로 부른다.** 뼈대는
//   `debugSkeletonSink` 라는 **전역**으로 흘러나오는데, `compute` 로 보내면 그 전역은
//   다른 isolate 의 것이라 아무것도 안 잡힌다. 진단 화면이라 20ms 정도는 받아들인다 —
//   연출 경로(`RevealPreparer`)는 그대로 isolate 를 쓴다.
//
//   색:
//     · 옅은 회색 = 길(굵은 그대로)
//     · 파랑      = 지나가는 자리(갈래 2)
//     · 초록      = 끝점(갈래 1)
//     · 빨강      = 갈래 3 이상
//
//   ⚠️ **갈래 수는 8-이웃으로 센 값이라 부풀어 있다.** 대각 계단마다 이웃이 3~4개가 되기
//   때문에, 눈으로는 갈림길이 없는 단순한 S 자에도 빨간 점이 수십 개 찍힌다. 진짜
//   갈림길과 계단을 가르려면 대각선 정리가 먼저다 — 그 전까지 이 숫자는 **상한**으로만 읽는다.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 얇은 선을 보는 화면.
class SkeletonView extends StatefulWidget {
  const SkeletonView({super.key});

  @override
  State<SkeletonView> createState() => _SkeletonViewState();
}

/// 한 지도를 단순화한 결과 — 그림과 숫자.
class _Simplified {
  const _Simplified({
    required this.image,
    required this.roadPixels,
    required this.linePixels,
    required this.ends,
    required this.forks,
    required this.through,
    required this.millis,
  });

  final ui.Image image;
  final int roadPixels;
  final int linePixels;
  final int ends;
  final int forks;
  final int through;
  final double millis;

  double get ratio => linePixels == 0 ? 0 : roadPixels / linePixels;
}

class _SkeletonViewState extends State<SkeletonView> {
  List<String>? _keys;
  String? _selected;
  _Simplified? _result;
  Object? _error;
  var _showRoad = true;

  /// 늦게 끝난 계산이 최신 결과를 덮지 못하게 하는 토큰.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    availableCorpusKeys().then((keys) {
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _selected = keys.isEmpty ? null : keys.first;
      });
      if (keys.isNotEmpty) unawaited(_build(keys.first));
    });
  }

  @override
  void dispose() {
    _result?.image.dispose();
    super.dispose();
  }

  Future<void> _build(String key) async {
    final generation = ++_generation;
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final pair = await loadCorpusMap(key);
      final size = fitImageLongSide(pair.composed, kBakeLongSide);
      final w = size.width;
      final h = size.height;
      final base = await rgbaAt(pair.base, w, h);
      final composed = await rgbaAt(pair.composed, w, h);
      pair.base.dispose();
      pair.composed.dispose();

      // 세그먼트마다 한 번씩 흘러나온다 — **가장 큰 것**이 길이다.
      DebugSkeleton? road;
      debugSkeletonSink = (s) {
        if (road == null || s.pixels.length > road!.pixels.length) road = s;
      };
      final clock = Stopwatch()..start();
      final plan = detectReveal(
        RevealDetectInput(
          baseRgba: base,
          composedRgba: composed,
          width: w,
          height: h,
        ),
      );
      clock.stop();
      // ⚠️ 전역이라 반드시 되돌린다 — 안 그러면 다음 지도가 이걸 물고 간다.
      debugSkeletonSink = null;

      final skel = road;
      if (skel == null) throw StateError('얇은 선이 안 나왔다');

      final roadPx = <int>[];
      for (var i = 0; i < w * h; i++) {
        final id = plan.segmentId[i];
        if (id < plan.segments.length &&
            plan.segments[id].kind == RevealSegmentKind.primaryStroke) {
          roadPx.add(i);
        }
      }
      var ends = 0;
      var forks = 0;
      var through = 0;
      for (final d in skel.degrees) {
        if (d <= 1) {
          ends++;
        } else if (d == 2) {
          through++;
        } else {
          forks++;
        }
      }

      final image = await _paint(w, h, roadPx, skel, showRoad: _showRoad);
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      final old = _result;
      setState(() {
        _result = _Simplified(
          image: image,
          roadPixels: roadPx.length,
          linePixels: skel.pixels.length,
          ends: ends,
          forks: forks,
          through: through,
          millis: clock.elapsedMicroseconds / 1000,
        );
      });
      old?.image.dispose();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;
    final selected = _selected;
    final result = _result;
    final error = _error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('얇은 선 (단순화)'),
        actions: [
          IconButton(
            tooltip: _showRoad ? '길 숨기기' : '길 보이기',
            icon: Icon(_showRoad ? Icons.layers : Icons.layers_clear),
            onPressed: () {
              setState(() => _showRoad = !_showRoad);
              final key = _selected;
              if (key != null) unawaited(_build(key));
            },
          ),
        ],
      ),
      body: switch ((keys, selected)) {
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<String> k, _) when k.isEmpty => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('정본 지도가 번들에 없다 — example/assets/maps 를 채운다'),
            ),
          ),
        (final List<String> _, null) =>
          const Center(child: CircularProgressIndicator()),
        (final List<String> all, final String key) => Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: all.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: Text(all[i].replaceFirst('map_', '')),
                    selected: all[i] == key,
                    onSelected: (_) {
                      setState(() => _selected = all[i]);
                      unawaited(_build(all[i]));
                    },
                  ),
                ),
              ),
              Expanded(
                child: switch ((error, result)) {
                  (final Object e, _) => Center(
                      child:
                          Text('$e', style: const TextStyle(color: Colors.red)),
                    ),
                  (_, null) => const Center(child: CircularProgressIndicator()),
                  (_, final _Simplified r) => InteractiveViewer(
                      maxScale: 12,
                      child: Center(
                        child: RawImage(image: r.image, fit: BoxFit.contain),
                      ),
                    ),
                },
              ),
              if (result != null) _Stats(result: result),
            ],
          ),
      },
    );
  }
}

/// 숫자 한 줄 — 압축이 얼마나 됐고 무엇이 남았나.
class _Stats extends StatelessWidget {
  const _Stats({required this.result});

  final _Simplified result;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('길 ${result.roadPixels}px  →  얇은 선 ${result.linePixels}px  '
                  '(${result.ratio.toStringAsFixed(1)}배 줄었다)  '
                  '· 세선화 포함 탐지 ${result.millis.toStringAsFixed(1)}ms'),
              Row(
                children: [
                  const _Dot(Color(0xFF16A34A)),
                  Text(' 끝점 ${result.ends}   '),
                  const _Dot(Color(0xFF2563EB)),
                  Text(' 지나감 ${result.through}   '),
                  const _Dot(Color(0xFFDC2626)),
                  Text(' 갈래 3+ ${result.forks}'),
                ],
              ),
              const Text(
                '⚠️ 갈래 수는 8-이웃으로 센 값이라 대각 계단까지 세어 부풀어 있다 — 상한으로만 읽을 것',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// 길 위에 얇은 선을 겹쳐 그림 한 장으로 만든다.
///
///   확대해서 픽셀을 세어 볼 수 있어야 하므로 굽기 해상도 그대로 만들고, 화면에서 늘린다.
Future<ui.Image> _paint(
  int w,
  int h,
  List<int> roadPx,
  DebugSkeleton skel, {
  required bool showRoad,
}) async {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = 255;
    px[i * 4 + 1] = 255;
    px[i * 4 + 2] = 255;
    px[i * 4 + 3] = 255;
  }
  void put(int x, int y, int r, int g, int b) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final j = (y * w + x) * 4;
    px[j] = r;
    px[j + 1] = g;
    px[j + 2] = b;
  }

  if (showRoad) {
    for (final i in roadPx) {
      put(i % w, i ~/ w, 222, 222, 226);
    }
  }
  for (var n = 0; n < skel.pixels.length; n++) {
    final p = skel.pixels[n];
    // 창(ROI) 좌표 → 원본 좌표.
    final x = p % skel.width + skel.left;
    final y = p ~/ skel.width + skel.top;
    final d = skel.degrees[n];
    if (d <= 1) {
      put(x, y, 22, 163, 74);
    } else if (d == 2) {
      put(x, y, 37, 99, 235);
    } else {
      put(x, y, 220, 38, 38);
    }
  }

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}
