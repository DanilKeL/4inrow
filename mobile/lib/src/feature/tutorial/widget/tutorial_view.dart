import 'package:flutter/material.dart';
import 'package:four3/src/common/theme/app_theme.dart';
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
  const new({
    this.starting = false,
    this.onDone,
    this.loadVideos = true,
    super.key,
  });

  final bool starting;
  final VoidCallback? onDone;
  final bool loadVideos;

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
    if (widget.loadVideos) {
      _load();
    } else {
      _failed = true;
    }
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
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.sizeOf(context).height <= 700;
    const Widget goal = Text.rich(
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
    );
    if (landscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          goal,
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  key: const ValueKey('tutorial-selector'),
                  width: 170,
                  child: _lessonButtons(vertical: true),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _media(lesson)),
                      const SizedBox(height: 6),
                      _caption(context, lesson, compact: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _footer(),
        ],
      );
    }
    return Column(
      children: [
        goal,
        const SizedBox(height: 10),
        SizedBox(
          key: const ValueKey('tutorial-selector'),
          height: 78,
          child: _lessonButtons(vertical: false),
        ),
        const SizedBox(height: 10),
        Expanded(child: _media(lesson)),
        const SizedBox(height: 10),
        _caption(context, lesson),
        const SizedBox(height: 8),
        _footer(),
      ],
    );
  }

  Widget _lessonButtons({required bool vertical}) {
    final List<Widget> buttons = [
      for (var index = 0; index < _lessons.length; index++)
        OutlinedButton(
          onPressed: () {
            setState(() => _selected = index);
            if (widget.loadVideos) _load();
          },
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, vertical ? 31 : 36),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            backgroundColor: index == _selected
                ? const Color(0xFFEDF1FF)
                : Colors.transparent,
            foregroundColor: index == _selected
                ? AppColors.accent
                : AppColors.ink,
          ),
          child: Text(
            vertical
                ? '${(index + 1).toString().padLeft(2, '0')}  ${_lessons[index].tab}'
                : _lessons[index].tab,
            maxLines: 1,
            style: const TextStyle(fontSize: 9),
          ),
        ),
    ];
    if (vertical) {
      return Column(
        children: [
          for (final button in buttons)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: button,
              ),
            ),
        ],
      );
    }
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 2.7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: buttons,
    );
  }

  Widget _media(_Lesson lesson) => ClipRRect(
    key: const ValueKey('tutorial-media'),
    borderRadius: BorderRadius.circular(12),
    child: ColoredBox(
      color: const Color(0xFFE7E4DE),
      child: Column(
        children: [
          Expanded(
            child: ClipRect(
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
          if (_video?.value.isInitialized == true)
            SizedBox(
              height: 36,
              child: ColoredBox(
                color: const Color(0xF2EEEEE8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        _video!.value.isPlaying
                            ? await _video!.pause()
                            : await _video!.play();
                        if (mounted) setState(() {});
                      },
                      icon: Icon(
                        _video!.value.isPlaying
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        size: 16,
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _video!,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: AppColors.accent,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _video!.seekTo(Duration.zero);
                        await _video!.play();
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(LucideIcons.rotateCcw, size: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _caption(
    BuildContext context,
    _Lesson lesson, {
    bool compact = false,
  }) => Column(
    children: [
      Text(
        lesson.title,
        style: TextStyle(
          fontSize: compact ? 16 : 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        lesson.description,
        textAlign: TextAlign.center,
        maxLines: compact ? 2 : 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: compact ? 10 : 11, color: AppColors.muted),
      ),
    ],
  );

  Widget _footer() => Row(
    children: [
      Expanded(
        child: TextButton.icon(
          onPressed: () {
            setState(() => _selected = (_selected + 1) % _lessons.length);
            if (widget.loadVideos) _load();
          },
          iconAlignment: IconAlignment.end,
          icon: const Icon(LucideIcons.arrowRight),
          label: Text(
            _selected == _lessons.length - 1
                ? 'К первому примеру'
                : 'Следующий пример',
          ),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: widget.onDone ?? () => Navigator.maybePop(context),
        child: Text(widget.starting ? 'Начать' : 'Понятно'),
      ),
    ],
  );

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }
}
