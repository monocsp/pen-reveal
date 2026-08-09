// main.dart — 위젯북 진입점.
//
//   코드젠(widgetbook_generator·build_runner)은 쓰지 않는다. 이 레포 정책이기도 하고,
//   use case 가 열 개도 안 되는데 생성기를 붙일 이유가 없다. 트리를 손으로 적는다.
//
//   실행:  cd example && flutter run -d <device>
import 'package:flutter/material.dart';
import 'package:pen_reveal_example/fixtures/corpus_maps.dart';
import 'package:pen_reveal_example/fixtures/synthetic_map.dart';
import 'package:pen_reveal_example/reveal_bench.dart';
import 'package:pen_reveal_flutter/pen_reveal_flutter.dart';
import 'package:widgetbook/widgetbook.dart';

void main() => runApp(const PenRevealBook());

class PenRevealBook extends StatelessWidget {
  const PenRevealBook({super.key});

  @override
  Widget build(BuildContext context) => Widgetbook.material(
        addons: [
          ViewportAddon([
            Viewports.none,
            IosViewports.iPhone13,
            IosViewports.iPadPro11Inches,
          ]),
          InspectorAddon(),
        ],
        directories: [
          WidgetbookCategory(
            name: 'pen_reveal',
            children: [
              WidgetbookComponent(
                name: '연출 (SequentialReveal)',
                useCases: [
                  // 정본 지도가 먼저다 — 합성은 자산이 없을 때의 대비책이지 판단 근거가
                  //   아니다. 절차적으로 그린 길은 가장자리가 매끈해서 실제 브러시 질감이
                  //   만드는 문제(세선화가 거친 테두리를 어떻게 먹는지)를 못 보여 준다.
                  WidgetbookUseCase(name: '정본 지도 10종', builder: _corpus),
                  WidgetbookUseCase(
                    name: '정본 — 원본과 나란히',
                    builder: _corpusSideBySide,
                  ),
                  WidgetbookUseCase(name: '정본 — 리듬 조절', builder: _corpusTiming),
                  WidgetbookUseCase(name: '합성 — 길 모양', builder: _shapes),
                  WidgetbookUseCase(name: '합성 — 경계 조건', builder: _edgeCases),
                  WidgetbookUseCase(name: '합성 — 길 두께', builder: _basic),
                ],
              ),
            ],
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────

Widget _basic(BuildContext context) {
  final width = context.knobs.double
      .slider(label: '길 두께', initialValue: 14, min: 8, max: 22, divisions: 14);
  return RevealBench(
    key: ValueKey('basic-$width'),
    sourceLabel: '합성 · 뱀꼴',
    source: () => buildSyntheticMap(roadWidth: width),
  );
}

Widget _shapes(BuildContext context) {
  final shape = context.knobs.object.dropdown(
    label: '길 모양',
    options: RoadShape.values,
    labelBuilder: (s) => switch (s) {
      RoadShape.gentle => '짧은 S — 재생 빠름',
      RoadShape.serpentine => '긴 뱀꼴 — 재생 느림',
      RoadShape.loop => '고리 — 되짚는 경로',
    },
  );
  return RevealBench(
    key: ValueKey('shape-$shape'),
    sourceLabel: '합성 · ${shape.name}',
    source: () => buildSyntheticMap(shape: shape),
  );
}

Widget _corpus(BuildContext context) {
  // 정본 문구는 전부 "발견한곳" 4음절이다. 힌트를 주면 음절로 갈리고 자모 순서가 붙는다.
  final syllables = context.knobs.int.slider(
    label: '음절 수 힌트 (0 = 안 줌)',
    initialValue: 4,
    max: 8,
    divisions: 8,
  );
  return _CorpusPicker(
    // 탐지 설정은 값 동등성이 없다 — key 로 바뀐 것을 알린다.
    key: ValueKey('syllables-$syllables'),
    detectConfig: RevealDetectConfig(
      annotation: AnnotationSegmenterConfig(
        expectedSyllableCount: syllables == 0 ? null : syllables,
      ),
    ),
  );
}

Widget _corpusSideBySide(BuildContext context) =>
    const _CorpusPicker(showGroundTruth: true);

Widget _corpusTiming(BuildContext context) {
  final min = context.knobs.double.slider(
    label: '길 최소 (ms)',
    initialValue: 500,
    min: 200,
    max: 3000,
    divisions: 28,
  );
  final max = context.knobs.double.slider(
    label: '길 최대 (ms)',
    initialValue: 2000,
    min: 200,
    max: 6000,
    divisions: 58,
  );
  final crossGap = context.knobs.double.slider(
    label: '길 → X 쉼 (ms)',
    initialValue: 120,
    max: 1200,
    divisions: 24,
  );
  final noteGap = context.knobs.double.slider(
    label: 'X → 글씨 쉼 (ms)',
    initialValue: 160,
    max: 1200,
    divisions: 24,
  );
  return _CorpusPicker(
    timing: HandwritingRevealTiming(
      primaryMinDuration: Duration(milliseconds: min.round()),
      primaryMaxDuration: Duration(milliseconds: max.round()),
      primaryToCrossGap: Duration(milliseconds: crossGap.round()),
      crossToAnnotationGap: Duration(milliseconds: noteGap.round()),
    ),
  );
}

Widget _edgeCases(BuildContext context) {
  final withCross = context.knobs.boolean(label: 'X 넣기', initialValue: true);
  final withNote = context.knobs.boolean(label: '글씨 넣기', initialValue: true);
  return RevealBench(
    key: ValueKey('edge-$withCross-$withNote'),
    sourceLabel: '합성 · X=$withCross 글씨=$withNote',
    source: () => buildSyntheticMap(
      withCross: withCross,
      withNote: withNote,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// 정본 지도는 번들에 있을 때만 고를 수 있다 — 없으면 채우는 법을 알려 준다.
class _CorpusPicker extends StatefulWidget {
  const _CorpusPicker({
    super.key,
    this.showGroundTruth = false,
    this.timing = const HandwritingRevealTiming(),
    this.detectConfig = const RevealDetectConfig(),
  });

  final bool showGroundTruth;
  final RevealTimingPolicy timing;
  final RevealDetectConfig detectConfig;

  @override
  State<_CorpusPicker> createState() => _CorpusPickerState();
}

class _CorpusPickerState extends State<_CorpusPicker> {
  List<String>? _keys;
  String? _selected;

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
    if (keys == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (keys.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            '정본 지도가 번들에 없다.\n\n'
            '디자인 자산이라 레포에 커밋하지 않는다(README §코퍼스).\n'
            'corpus/maps/<key>/{base,composed}.png 를 갖춘 로컬에서\n'
            'example/assets/maps/<key>_{base,composed}.png 로 복사한 뒤\n'
            '다시 빌드하면 여기에 10종이 뜬다.\n\n'
            '그때까지는 다른 use case 의 합성 지도로 본다.',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ),
      );
    }
    final selected = _selected ?? keys.first;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              for (final k in keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(k, style: const TextStyle(fontSize: 11)),
                    selected: k == selected,
                    onSelected: (_) => setState(() => _selected = k),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RevealBench(
            // timing 은 key 에 넣지 않는다 — 리듬만 바뀔 때 State 를 버리면 재생이
            //   끊긴다. 값 동등성이 생겼으니 `didUpdateWidget` 이 알아서 다시 굽는다.
            key: ValueKey('corpus-$selected'),
            sourceLabel: '정본 · $selected',
            showGroundTruth: widget.showGroundTruth,
            timing: widget.timing,
            detectConfig: widget.detectConfig,
            source: () => loadCorpusMap(selected),
          ),
        ),
      ],
    );
  }
}
