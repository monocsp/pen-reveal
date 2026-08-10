// reveal_bench.dart — 굽고 재생하는 계측대 위젯 하나.
//
//   위젯북 use case 도 이걸 쓰고, 단독 앱(`bench_main.dart`)도 이걸 쓴다. 위젯북에 묶이지
//   않은 평범한 위젯이라 어디에 얹어도 돈다.
//
//   지키는 규약 셋:
//     ① **build 에서 굽지 않는다.** `prepare()` 는 리샘플·RGBA·isolate 탐지·텍스처 생성을
//        전부 한다. 프레임마다 부르면 안 된다는 것이 preparer 주석의 경고다.
//     ② **세대 토큰으로 경합을 막는다.** knob A 로 굽는 중 knob B 가 바뀌면 A 가 나중에
//        끝나 최신 결과를 덮을 수 있다. `mounted` 검사만으로는 부족하다.
//     ③ **컨트롤러에 curve 를 걸지 않는다.** 가감속은 이미 텍스처에 구워져 있다. 속도
//        배율은 curve 가 아니라 **남은 시간을 다시 계산**해서 준다.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 계측대에 넣을 지도 한 벌을 만드는 방법. 위젯이 소유권을 받아 dispose 한다.
typedef MapSource = Future<({ui.Image base, ui.Image composed})> Function();

/// 되감아 세울 수 있는 지점.
enum RevealStage {
  start('처음'),
  road('길 끝'),
  cross('X 끝'),
  end('전체 끝');

  const RevealStage(this.label);
  final String label;
}

class RevealBench extends StatefulWidget {
  const RevealBench({
    required this.source,
    this.timing = const HandwritingRevealTiming(),
    this.compiler = const RevealTextureCompiler(),
    this.detectConfig = const RevealDetectConfig(),
    this.sourceLabel = '합성 지도',
    this.autoPlay = true,
    this.showGroundTruth = false,
    super.key,
  });

  /// 지도 두 장을 어디서 얻을지. 이 값이 바뀌면 다시 굽는다.
  final MapSource source;

  /// 리듬. 밴드를 바꾸면 다시 굽는다(시간이 텍스처에 구워지므로).
  final RevealTimingPolicy timing;

  /// 임계 가파르기를 들고 있는 컴파일러. **바뀌면 다시 굽는다** — `k` 가 순서값 상한
  ///   (`255 − ⌈255/k⌉`)을 정하므로 텍스처 자체가 달라진다.
  ///
  ///   왜 손잡이로 빼나: `k` 는 선단이 번지는 폭(`255/k` 코드)을 정하는데, 그게 얼마나
  ///   번져야 "펜"으로 보이는지는 **재서 정할 수 있는 값이 아니다.** 정본 실측으로는
  ///   면적과 계단이 정확히 맞바꿔진다(k 24→64 에서 면적 0.38배, 계단 219→1283).
  ///   어디가 좋은지는 눈으로 봐야 한다.
  final RevealTextureCompiler compiler;

  /// 탐지 설정 — 음절 힌트 같은 것.
  ///
  ///   ⚠️ `timing` 과 달리 `didUpdateWidget` 에서 비교하지 않는다. `RevealDetectConfig`
  ///   에는 값 동등성이 없어서 매 build 마다 "바뀌었다" 가 되기 때문이다(= 열 때마다
  ///   두 번 굽는 그 함정). 이 값이 바뀌는 것은 호출부가 **key** 로 표현한다.
  final RevealDetectConfig detectConfig;

  final String sourceLabel;
  final bool autoPlay;

  /// 켜면 완성본을 옆에 나란히 둔다 — 연출이 원본을 훼손하지 않는지 눈으로 대조.
  final bool showGroundTruth;

  @override
  State<RevealBench> createState() => _RevealBenchState();
}

class _RevealBenchState extends State<RevealBench>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  ui.Image? _base;
  ui.Image? _composed;
  PreparedReveal? _prepared;
  Object? _error;
  var _speed = 1.0;

  /// 자산을 읽고 PNG 를 디코딩하는 데 든 시간 — `prepare()` **밖**이다.
  ///   "지도를 주면 몇 ms 뒤에 시작하나" 는 이것과 `profile.total` 을 더해야 나온다.
  Duration? _sourceTime;

  /// 늦게 끝난 굽기가 최신 결과를 덮지 못하게 하는 토큰.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    unawaited(_bake());
  }

  /// ⚠️ **`source` 를 비교하지 않는다.** 함수 참조는 Dart 에서 같은 리터럴에서 나와도
  ///   절대 동등하지 않다. 위젯북은 use case 를 그린 다음 프레임에 `knobs.lock()` 으로
  ///   반드시 한 번 rebuild 하므로, 참조를 비교하면 **열 때마다 두 번 굽는다**.
  ///   입력이 바뀌는 것은 호출부가 `ValueKey` 로 표현한다 — 그러면 State 가 새로 만들어져
  ///   `initState` 가 한 번 굽는다.
  @override
  void didUpdateWidget(RevealBench old) {
    super.didUpdateWidget(old);
    // ⚠️ `compiler` 도 본다 — `k` 가 순서값 상한을 정하므로 텍스처 자체가 달라진다.
    //   둘 다 값 동등성이 있어서 손잡이가 제자리로 돌아오면 다시 굽지 않는다.
    if (old.timing != widget.timing || old.compiler != widget.compiler) {
      unawaited(_bake());
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    _prepared?.dispose();
    _base?.dispose();
    _composed?.dispose();
    super.dispose();
  }

  Future<void> _bake() async {
    final generation = ++_generation;
    setState(() => _error = null);
    try {
      final clock = Stopwatch()..start();
      final pair = await widget.source();
      final sourceTime = Duration(microseconds: clock.elapsedMicroseconds);
      final prepared = await RevealPreparer(
        timing: widget.timing,
        compiler: widget.compiler,
        detectConfig: widget.detectConfig,
      ).prepare(base: pair.base, composed: pair.composed);

      // 낡은 요청이면 만든 것을 전부 버린다 — 안 버리면 그대로 샌다.
      if (!mounted || generation != _generation) {
        prepared.dispose();
        pair.base.dispose();
        pair.composed.dispose();
        return;
      }

      final oldPrepared = _prepared;
      final oldBase = _base;
      final oldComposed = _composed;
      setState(() {
        _prepared = prepared;
        _base = pair.base;
        _composed = pair.composed;
        _sourceTime = sourceTime;
      });
      oldPrepared?.dispose();
      oldBase?.dispose();
      oldComposed?.dispose();

      // 빈 계획이면 0초짜리다 — 재생 로직에 넣지 않고 바로 끝으로 보낸다.
      if (prepared.revealDuration == Duration.zero) {
        _controller.value = 1;
        return;
      }
      _controller
        ..duration = prepared.revealDuration
        ..value = 0;
      if (widget.autoPlay) _playTo(1);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  /// [target] 까지 **선형으로** 간다. 속도는 curve 가 아니라 시간으로 준다.
  void _playTo(double target) {
    final prepared = _prepared;
    if (prepared == null) return;
    final distance = (target - _controller.value).abs();
    if (distance < 1e-6) return;
    final micros =
        (prepared.revealDuration.inMicroseconds * distance / _speed).round();
    unawaited(
      _controller.animateTo(
        target,
        duration: Duration(microseconds: micros),
        // ⚠️ curve 를 걸지 않는다(기본이 linear). 가감속은 텍스처에 이미 구워져 있다.
      ),
    );
  }

  double _markOf(RevealStage stage) {
    final s = _prepared?.stages;
    if (s == null) return stage == RevealStage.start ? 0 : 1;
    return switch (stage) {
      RevealStage.start => 0,
      RevealStage.road => s.primaryEnd,
      RevealStage.cross => s.crossEnd,
      RevealStage.end => 1,
    };
  }

  void _jumpTo(RevealStage stage) {
    _controller
      ..stop(canceled: false)
      ..value = _markOf(stage);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _Panel(
        child:
            Text('굽기 실패 — $error', style: const TextStyle(color: Colors.red)),
      );
    }
    final base = _base;
    final composed = _composed;
    final prepared = _prepared;
    if (base == null || composed == null || prepared == null) {
      return const _Panel(child: Center(child: CircularProgressIndicator()));
    }

    final aspect = composed.width / composed.height;
    final stage = _currentStage(prepared);

    return _Panel(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: LayoutBuilder(
                    builder: (context, box) => SequentialReveal(
                      base: base,
                      composed: composed,
                      prepared: prepared,
                      progress: _controller.value,
                      size: Size(box.maxWidth, box.maxHeight),
                    ),
                  ),
                ),
              ),
              if (widget.showGroundTruth) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: RawImage(image: composed, fit: BoxFit.fill),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // "지도를 주면 몇 ms 뒤에 시작하나" 를 화면에서 바로 읽게 한다.
          //   ⚠️ 자산 로드·디코딩은 `prepare()` **밖**이라 따로 재서 더한다.
          Text(
            _sourceTime == null
                ? ''
                : '준비 ${_msOf(_sourceTime! + prepared.profile.total)} '
                    '= 로드·디코딩 ${_msOf(_sourceTime!)} + ${prepared.profile}',
            style: const TextStyle(
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          _StageBar(
            stages: prepared.stages,
            progress: _controller.value,
            current: stage,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: _controller.isAnimating ? '멈춤' : '재생',
                icon: Icon(
                  _controller.isAnimating ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (_controller.isAnimating) {
                    _controller.stop(canceled: false);
                    setState(() {});
                  } else {
                    if (_controller.value >= 1) _controller.value = 0;
                    _playTo(1);
                  }
                },
              ),
              IconButton(
                tooltip: '처음으로',
                icon: const Icon(Icons.replay),
                onPressed: () {
                  _controller
                    ..stop(canceled: false)
                    ..value = 0;
                  _playTo(1);
                },
              ),
              Expanded(
                child: Slider(
                  value: _controller.value.clamp(0, 1),
                  onChanged: (v) {
                    _controller
                      ..stop(canceled: false)
                      ..value = v;
                  },
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  _controller.value.toStringAsFixed(3),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('단계 ', style: TextStyle(fontSize: 12)),
              for (final s in RevealStage.values)
                OutlinedButton(
                  onPressed: () => _jumpTo(s),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    '${s.label} ${_markOf(s).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('속도 ', style: TextStyle(fontSize: 12)),
              for (final s in <double>[0.25, 0.5, 1, 2, 4])
                ChoiceChip(
                  label: Text('${s}x', style: const TextStyle(fontSize: 11)),
                  selected: _speed == s,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _speed = s);
                    if (_controller.isAnimating) _playTo(1);
                  },
                ),
            ],
          ),
          const Divider(height: 22),
          _Readout(
            label: widget.sourceLabel,
            prepared: prepared,
            size: Size(
              composed.width.toDouble(),
              composed.height.toDouble(),
            ),
          ),
        ],
      ),
    );
  }

  RevealStage _currentStage(PreparedReveal prepared) {
    final p = _controller.value;
    if (p <= 0) return RevealStage.start;
    if (p < prepared.stages.primaryEnd) return RevealStage.road;
    if (p < prepared.stages.crossEnd) return RevealStage.cross;
    return RevealStage.end;
  }
}

/// 단계 경계를 눈금으로 보여 준다 — "길이 다 파진 순간"이 어디인지 보여야 판단이 된다.
class _StageBar extends StatelessWidget {
  const _StageBar({
    required this.stages,
    required this.progress,
    required this.current,
  });

  final RevealStageMarks stages;
  final double progress;
  final RevealStage current;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 18,
            child: CustomPaint(
              painter: _StageBarPainter(stages: stages, progress: progress),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '지금: ${current.label}'
            '${stages.hasCross ? '' : '   ⚠️ X 세그먼트 없음 — 붉은 표시가 전부 덩어리로 갔다'}',
            style: TextStyle(
              fontSize: 11,
              color: stages.hasCross ? Colors.black54 : Colors.orange.shade900,
            ),
          ),
        ],
      );
}

class _StageBarPainter extends CustomPainter {
  const _StageBarPainter({required this.stages, required this.progress});

  final RevealStageMarks stages;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final track = Paint()..color = const Color(0xFFE3DED4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      track,
    );

    void band(double from, double to, Color color) {
      if (to <= from) return;
      canvas.drawRect(
        Rect.fromLTRB(from * size.width, 0, to * size.width, h),
        Paint()..color = color,
      );
    }

    band(0, stages.primaryEnd, const Color(0xFFBFD8C2));
    band(stages.primaryEnd, stages.crossEnd, const Color(0xFFF3C0BC));
    band(stages.crossEnd, 1, const Color(0xFFF7DFA8));

    final x = progress.clamp(0.0, 1.0) * size.width;
    canvas.drawRect(
      Rect.fromLTRB(x - 1, -2, x + 1, h + 2),
      Paint()..color = const Color(0xFF2C2621),
    );
  }

  @override
  bool shouldRepaint(_StageBarPainter old) =>
      old.progress != progress || old.stages != stages;
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.prepared,
    required this.size,
  });

  final String label;
  final PreparedReveal prepared;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final s = prepared.stages;
    final rows = <(String, String)>[
      ('입력', '$label   ${size.width.toInt()}×${size.height.toInt()}'),
      ('재생 시간', '${prepared.revealDuration.inMilliseconds} ms'),
      ('가파르기 k', '${prepared.sharpness.k}'),
      (
        '단계 경계',
        '길 ${s.primaryEnd.toStringAsFixed(3)} · '
            'X ${s.crossEnd.toStringAsFixed(3)} · '
            '끝 ${s.annotationEnd.toStringAsFixed(3)}'
      ),
      (
        '구간 길이',
        '길 ${(prepared.revealDuration.inMilliseconds * s.primaryEnd).round()} ms · '
            'X ${(prepared.revealDuration.inMilliseconds * (s.crossEnd - s.primaryEnd)).round()} ms · '
            '글씨 ${(prepared.revealDuration.inMilliseconds * (1 - s.crossEnd)).round()} ms'
      ),
      ('텍스처', '${prepared.reveal.width}×${prepared.reveal.height}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    k,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                Expanded(
                  child: Text(
                    v,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFFAF7F1),
        child: SafeArea(child: child),
      );
}

String _msOf(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)}ms';
