// review_home.dart — **켜자마자 볼 것이 나오는 화면.**
//
//   위젯북은 개발자 도구다. 켜면 남의 안내 카드가 먼저 뜨고, 볼 것까지 가려면
//   Navigation → 트리 펼치기 → use case 고르기 → Knobs 탭으로 네 번을 건너야 한다.
//   "이거 확인해 주세요" 하고 건네는 물건으로는 못 쓴다.
//
//   ⚠️ **아래에 고정하는 것은 재생 버튼 하나다.** 처음엔 조절 손잡이를 아래에 깔았는데,
//   그러면 정작 재생을 하려고 스크롤을 해야 한다 — 가장 자주 누르는 것이 가장 멀었다.
//   조절값은 시트로 뺀다.
//
//   위젯북은 없애지 않는다. 합성 도형·경계 조건처럼 개발 중에만 보는 것들이 거기 있고,
//   그건 여기 있을 이유가 없다. 오른쪽 위 버튼으로 넘어간다.
import 'package:flutter/material.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_example/reveal_bench.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';

/// 정본 지도를 보며 연출을 맞추는 화면.
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
  final _play = ValueNotifier<int>(0);

  double _k = 24;
  var _speed = RevealSpeed.normal;

  /// 정본 문구는 전부 "발견한곳" 4음절이다.
  ///
  ///   ⚠️ **힌트가 없으면 붙은 음절이 안 갈린다.** 자모가 이어져 한 연결요소로 남으면
  ///   ("견한" 은 굽기 420 에서 폭 50px — 이웃 덩어리의 두 배다) 연결요소만으로는 음절을
  ///   못 가르고, 그 덩어리가 통째로 드러나 **두 글자가 동시에 뜬다.**
  ///
  ///   래스터에서 음절 경계를 추정해 보려고 세로비를 재 봤지만 갈리지 않았다 — 붙은
  ///   음절이 1.19~1.42 인데 받침 조각이 1.67~2.83 이라 구간이 겹친다. 그리는 쪽은 자기가
  ///   쓴 글자 수를 아니까, 그 값을 받는 것이 맞다.
  int _syllables = 4;

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
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  Future<void> _openSettings() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => StatefulBuilder(
          builder: (context, setSheet) => _SettingsSheet(
            speed: _speed,
            sharpness: _k,
            syllables: _syllables,
            onSpeed: (v) {
              setSheet(() {});
              setState(() => _speed = v);
            },
            onSharpness: (v) {
              setSheet(() {});
              setState(() => _k = v);
            },
            onSyllables: (v) {
              setSheet(() {});
              setState(() => _syllables = v);
            },
          ),
        ),
      );

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
        // 자산이 없으면 **왜 없는지와 어떻게 채우는지**를 화면에 적는다.
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
                  // 지도나 탐지 설정이 바뀌면 새로 굽는다. 배속·가파르기는 key 에 넣지
                  //   않는다 — 값 동등성이 있어 `didUpdateWidget` 이 알아서 다시 굽고,
                  //   State 를 버리면 보던 진행도가 날아간다.
                  key: ValueKey('review-$key-$_syllables'),
                  sourceLabel: '정본 · $key',
                  source: () => loadCorpusMap(key),
                  playSignal: _play,
                  compiler: RevealTextureCompiler(
                    sharpness: RevealSharpness(_k),
                  ),
                  timing: HandwritingRevealTiming(speed: _speed),
                  detectConfig: RevealDetectConfig(
                    annotation: AnnotationSegmenterConfig(
                      expectedSyllableCount: _syllables < 2 ? null : _syllables,
                    ),
                  ),
                ),
              ),
            ],
          ),
      },
      bottomNavigationBar: (keys?.isEmpty ?? true)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _play.value++,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('처음부터 재생'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune),
                      tooltip: '속도 · 붓끝 · 음절',
                      padding: const EdgeInsets.all(14),
                    ),
                  ],
                ),
              ),
            ),
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

/// 조절값 시트 — 속도 · 붓끝 · 음절.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.speed,
    required this.sharpness,
    required this.syllables,
    required this.onSpeed,
    required this.onSharpness,
    required this.onSyllables,
  });

  final RevealSpeed speed;
  final double sharpness;
  final int syllables;
  final ValueChanged<RevealSpeed> onSpeed;
  final ValueChanged<double> onSharpness;
  final ValueChanged<int> onSyllables;

  static const _steps = [0.5, 1.0, 2.0, 4.0];

  /// 정본 실측 — 올리면 번짐은 줄고 선단은 딱딱해진다(맞바꿈이라 정답이 없다).
  static const _sharpNote = <int, String>{
    12: '두 배로 번진다',
    24: '기본값',
    48: '번짐 절반 · 계단이 세 배',
    96: '번짐 1/4',
    255: '거의 칼같이 — 선단 1코드',
  };

  String get _note {
    var best = 24;
    for (final k in _sharpNote.keys) {
      if ((k - sharpness).abs() < (best - sharpness).abs()) best = k;
    }
    return _sharpNote[best]!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget speedRow(
      String label,
      double now,
      RevealSpeed Function(double) set,
    ) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              for (final s in _steps)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('${s}x', style: const TextStyle(fontSize: 12)),
                    selected: now == s,
                    onSelected: (_) => onSpeed(set(s)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('단계별 속도', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            speedRow('길', speed.road, (s) => speed.copyWith(road: s)),
            speedRow('X', speed.cross, (s) => speed.copyWith(cross: s)),
            speedRow(
              '글씨',
              speed.annotation,
              (s) => speed.copyWith(annotation: s),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Text('붓끝 번짐', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  'k ${sharpness.toStringAsFixed(0)} · 선단 '
                  '${(255 / sharpness).toStringAsFixed(1)}코드',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            Slider(
              value: sharpness,
              min: 12,
              max: 255,
              divisions: 27,
              label: sharpness.toStringAsFixed(0),
              onChanged: onSharpness,
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
            const Divider(height: 28),
            Row(
              children: [
                Text('문구 음절 수', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  syllables < 2 ? '안 가름' : '$syllables 음절',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '자모가 이어져 두 글자가 한 덩어리로 남으면 동시에 뜬다. '
              '래스터만으로는 못 가르므로 글자 수를 알려 줘야 한다.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [0, 2, 3, 4, 5, 6])
                  ChoiceChip(
                    label: Text(n == 0 ? '안 가름' : '$n'),
                    selected: syllables == n,
                    onSelected: (_) => onSyllables(n),
                  ),
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
