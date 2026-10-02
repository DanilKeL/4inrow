import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

final class _Lesson {
  const new(this.id, this.tab, this.title, this.description);
  final String id;
  final String tab;
  final String title;
  final String description;
}

const _lessons = [
  _Lesson(
    'stacking',
    'Как ходить',
    'Фишки встают друг на друга',
    'Нажмите на лунку — фишка займёт нижнее свободное место. Вы выбираете столбец, а не высоту.',
  ),
  _Lesson(
    'horizontal',
    'Горизонталь',
    'Четыре на одном уровне',
    'Четыре фишки одного цвета стоят подряд в соседних столбцах на одной высоте.',
  ),
  _Lesson(
    'vertical',
    'Вертикаль',
    'Четыре в одном столбце',
    'Соберите четыре фишки своего цвета друг над другом.',
  ),
  _Lesson(
    'diagonal-flat',
    'Диагональ слоя',
    'По диагонали одного слоя',
    'Каждая следующая фишка смещена на одну лунку в двух направлениях.',
  ),
  _Lesson(
    'diagonal-third-layer',
    'На высоте',
    'Победа на любом слое',
    'Линия может находиться на любом из пяти уровней; цвет опор снизу не важен.',
  ),
  _Lesson(
    'diagonal-space',
    'В пространстве',
    'Четыре через пространство',
    'Одновременно меняются ряд, столбец и высота — это тоже прямая линия.',
  ),
];

class TutorialView extends StatefulWidget {
  const new({super.key});

  @override
  State<TutorialView> createState() => _TutorialViewState();
}

class _TutorialViewState extends State<TutorialView> {
  int _selected = 0;
  VideoPlayerController? _video;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final VideoPlayerController? previous = _video;
    _video = null;
    await previous?.dispose();
    final _Lesson lesson = _lessons[_selected];
    final controller = VideoPlayerController.asset(
      'assets/tutorial/${lesson.id}.mp4',
    );
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {
          _video = controller;
          _failed = false;
        });
      }
    } on Exception {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _Lesson lesson = _lessons[_selected];
    return Column(
      children: [
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Соберите '),
              TextSpan(
                text: '4 фишки своего цвета',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: ' по прямой, без пропусков.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _lessons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) => ChoiceChip(
              selected: index == _selected,
              label: Text(_lessons[index].tab),
              onSelected: (_) {
                setState(() => _selected = index);
                _load();
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: const Color(0xFFE7E4DE),
              child: Center(
                child: _failed
                    ? Image.asset(
                        'assets/tutorial/${lesson.id}.webp',
                        fit: BoxFit.contain,
                      )
                    : _video?.value.isInitialized == true
                    ? AspectRatio(
                        aspectRatio: _video!.value.aspectRatio,
                        child: VideoPlayer(_video!),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          lesson.title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(lesson.description, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            setState(() => _selected = (_selected + 1) % _lessons.length);
            _load();
          },
          icon: const Icon(LucideIcons.arrowRight),
          label: Text(
            _selected == _lessons.length - 1
                ? 'К первому примеру'
                : 'Следующий пример',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }
}
