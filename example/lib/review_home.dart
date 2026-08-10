// review_home.dart — **켜자마자 볼 것이 나오는 화면.**
//
//   위젯북은 개발자 도구다. 켜면 남의 안내 카드가 먼저 뜨고, 볼 것까지 가려면
//   Navigation → 트리 펼치기 → use case 고르기 → Knobs 탭으로 네 번을 건너야 한다.
//   "이거 확인해 주세요" 하고 건네는 물건으로는 못 쓴다.
//
//   그래서 판단에 필요한 것만 한 화면에 둔다 — 지도 고르기 · 재생 · 진행도 · 그리고
//   **지금 판단해야 하는 값인 가파르기 k** 를 손에 닿는 자리에.
//
//   위젯북은 없애지 않는다. 합성 도형·경계 조건처럼 개발 중에만 보는 것들이 거기 있고,
//   그건 여기 있을 이유가 없다. 오른쪽 위 버튼으로 넘어간다.
import 'package:flutter/material.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_example/reveal_bench.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 정본 지도를 보며 가파르기를 정하는 화면.
class ReviewHome extends StatefulWidget {
  const ReviewHome({required this.onOpenWorkbench, super.key});

  /// 위젯북으로 넘어가기.
  final VoidCallback onOpenWorkbench;

  @override
  State<ReviewHome> createState() => _ReviewHomeState();
}

class _ReviewHomeState extends State<ReviewHome> {
  List<String>? _keys;
  String? _selected;
  double _k = 24;
  var _speed = RevealSpeed.normal;

  @override
  void initState() {
    super.initState();
    availableCorpusKeys().then((keys) {
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _selected = keys.isEmpty ? null : keys.first;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('연출 확인'),
        actions: [
          IconButton(
            onPressed: widget.onOpenWorkbench,
            icon: const Icon(Icons.science_outlined),
            tooltip: '개발용 위젯북 (합성 도형·경계 조건)',
          ),
        ],
      ),
      body: switch ((keys, selected)) {
        (null, _) => const Center(child: CircularProgressIndicator()),
        // 자산이 없으면 **왜 없는지와 어떻게 채우는지**를 화면에 적는다. 빈 화면을 주고
        //   사람이 코드를 뒤지게 하지 않는다.
        (final List<String> k, _) when k.isEmpty => const _NoAssets(),
        (_, null) => const Center(child: CircularProgressIndicator()),
        (final List<String> all, final String key) => Column(
            children: [
              _MapStrip(
                keys: all,
                selected: key,
                onSelected: (k) => setState(() => _selected = k),
              ),
              Expanded(
                child: RevealBench(
                  // 지도가 바뀌면 새로 굽는다. k 는 key 에 넣지 않는다 — 값 동등성이
                  //   있어서 `didUpdateWidget` 이 알아서 다시 굽고, State 를 버리면
                  //   보던 진행도가 날아간다.
                  key: ValueKey('review-$key'),
                  sourceLabel: '정본 · $key',
                  source: () => loadCorpusMap(key),
                  compiler: RevealTextureCompiler(
                    sharpness: RevealSharpness(_k),
                  ),
                  timing: HandwritingRevealTiming(speed: _speed),
                ),
              ),
              _SpeedBar(
                value: _speed,
                onChanged: (v) => setState(() => _speed = v),
              ),
              _SharpnessBar(
                value: _k,
                onChanged: (v) => setState(() => _k = v),
              ),
            ],
          ),
      },
    );
  }
}

/// 지도 고르기 — 가로로 훑는다.
class _MapStrip extends StatelessWidget {
  const _MapStrip({
    required this.keys,
    required this.selected,
    required this.onSelected,
  });

  final List<String> keys;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: keys.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final key = keys[i];
            return ChoiceChip(
              label: Text(key.replaceFirst('map_', '')),
              selected: key == selected,
              onSelected: (_) => onSelected(key),
            );
          },
        ),
      );
}

/// 단계별 배속 — 길·X·글씨를 따로 빠르게/느리게.
///
///   바깥에서 이 패키지를 쓸 때 쓰는 것이 그대로다 —
///   `HandwritingRevealTiming(speed: RevealSpeed(road: 2, ...))`.
class _SpeedBar extends StatelessWidget {
  const _SpeedBar({required this.value, required this.onChanged});

  final RevealSpeed value;
  final ValueChanged<RevealSpeed> onChanged;

  static const _steps = [0.5, 1.0, 2.0, 4.0];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, double now, RevealSpeed Function(double) set) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
              const SizedBox(width: 4),
              for (final s in _steps)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${s}x',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: now == s,
                    onSelected: (_) => onChanged(set(s)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('단계별 속도', style: theme.textTheme.titleSmall),
            row('길', value.road, (s) => value.copyWith(road: s)),
            row('X', value.cross, (s) => value.copyWith(cross: s)),
            row('글씨', value.annotation, (s) => value.copyWith(annotation: s)),
          ],
        ),
      ),
    );
  }
}

/// 가파르기 손잡이 — **이 화면의 본론이라 맨 아래 고정이다.**
class _SharpnessBar extends StatelessWidget {
  const _SharpnessBar({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  /// 정본 10종 실측 — 올리면 번짐은 줄고 선단은 딱딱해진다(맞바꿈이라 정답이 없다).
  static const _measured = <int, String>{
    12: '두 배로 번진다',
    24: '지금 기본값',
    32: '번짐 3/4 · 10종 중 6종은 계단 0',
    40: '번짐 2/3',
    48: '번짐 절반 · 계단이 세 배',
    64: '번짐 1/3 · 계단이 여섯 배',
  };

  String get _note {
    var best = 24;
    for (final k in _measured.keys) {
      if ((k - value).abs() < (best - value).abs()) best = k;
    }
    return _measured[best]!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('붓끝 번짐', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  'k ${value.toStringAsFixed(0)} · 선단 '
                  '${(255 / value).toStringAsFixed(1)}코드',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            Slider(
              value: value,
              min: 12,
              max: 64,
              divisions: 13,
              label: value.toStringAsFixed(0),
              onChanged: onChanged,
            ),
            Row(
              children: [
                Text('많이 번짐', style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(_note, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text('칼같이', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 자산이 없을 때 — 무엇이 없고 어떻게 채우는지 화면에 적는다.
class _NoAssets extends StatelessWidget {
  const _NoAssets();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                '정본 지도가 번들에 없다',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '디자인 자산이라 레포에 안 들어간다(README §코퍼스).\n'
                'example/assets/maps/ 에 <key>_base.png 와 <key>_composed.png 를 넣고\n'
                '다시 빌드하면 열 종이 여기 뜬다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
