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
    'Нажмите на лунку — фишка займёт нижнее свободное место. Ходы чередуются. В одном столбце помещается до пяти фишек.',
  ),
  _Lesson(
    'horizontal',
    'Горизонталь',
    'Четыре на одном уровне',
    'Четыре фишки одного цвета стоят подряд в соседних столбцах. Такая линия может идти вдоль любой стороны доски и на любой высоте.',
  ),
  _Lesson(
    'vertical',
    'Вертикаль',
    'Четыре в одном столбце',
    'Соберите четыре фишки своего цвета друг над другом. Фишка соперника внутри столбца разрывает линию.',
  ),
  _Lesson(
    'diagonal-flat',
    'Диагональ слоя',
    'По диагонали одного слоя',
    'Каждая следующая фишка смещена на одну лунку в двух направлениях. Высота остаётся одинаковой.',
  ),
  _Lesson(
    'diagonal-third-layer',
    'Диагональ на высоте',
    'Победа на любом слое',
    'Соберите четыре фишки по диагонали на одной высоте. Такая линия побеждает на любом слое, а цвет опор снизу не важен.',
  ),
  _Lesson(
    'diagonal-space',
    'Объёмная диагональ',
    'Четыре через пространство',
    'Каждая следующая фишка смещена на одну лунку в обоих направлениях и на один уровень вверх. Это тоже прямая линия и победа.',
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
  bool _ended = false;

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
      await controller.setLooping(false);
      await controller.play();
      if (mounted) {
        setState(() {
          _video = controller;
          _failed = false;
          _ended = false;
        });
        controller.addListener(_syncPlayback);
      }
    } on Exception {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  void _syncPlayback() {
    final VideoPlayerController? video = _video;
    if (!mounted || video == null || !video.value.isInitialized) return;
    final bool ended =
        video.value.duration > Duration.zero &&
        video.value.position >= video.value.duration;
    if (ended != _ended) setState(() => _ended = ended);
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
      style: TextStyle(color: Color(0xFF626860), fontSize: 12, height: 1.5),
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
            side: BorderSide(
              color: index == _selected
                  ? const Color(0xFFCAD5FB)
                  : const Color(0xFFE0E3D9),
            ),
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
      color: const Color(0xFFEEEEE8),
      child: Stack(
        children: [
          Positioned.fill(
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
                            tooltip: _video!.value.isPlaying
                                ? 'Остановить пример'
                                : 'Воспроизвести пример',
                            onPressed: () async {
                              if (_video!.value.isPlaying) {
                                await _video!.pause();
                              } else {
                                if (_ended) {
                                  await _video!.seekTo(Duration.zero);
                                  _ended = false;
                                }
                                await _video!.play();
                              }
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
                            child: Semantics(
                              label: 'Позиция ролика',
                              child: VideoProgressIndicator(
                                _video!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Повторить пример',
                            onPressed: () async {
                              await _video!.seekTo(Duration.zero);
                              _ended = false;
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
          if (_ended && lesson.id != 'stacking')
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE8FAFBF7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '4 в ряд — победа',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (_failed)
            const Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Text(
                'Видео недоступно. Показан итоговый пример.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        lesson.title,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: compact ? 16 : 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        lesson.description,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: const Color(0xFF687062),
          fontSize: compact ? 11 : 12,
          height: compact ? 1.45 : 1.5,
        ),
      ),
    ],
  );

  Widget _footer() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      TextButton.icon(
        onPressed: () {
          setState(() => _selected = (_selected + 1) % _lessons.length);
          if (widget.loadVideos) _load();
        },
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 16),
        label: Text(
          _selected == _lessons.length - 1
              ? 'К первому примеру'
              : 'Следующий пример',
          style: const TextStyle(fontSize: 11),
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
