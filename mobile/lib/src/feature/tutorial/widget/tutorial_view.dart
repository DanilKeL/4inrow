import 'package:flutter/material.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/app_theme/utils/app_theme.dart';
import 'package:four3/src/feature/app_theme/utils/theme_context_extension.dart';
import 'package:four3/src/feature/components/progress/app_circular_progress_indicator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

final class _Lesson {
  const new(this.id, this.tab, this.title, this.description);
  final String id;
  final String tab;
  final String title;
  final String description;
}

const _lessonIds = [
  'stacking',
  'horizontal',
  'vertical',
  'diagonal-flat',
  'diagonal-third-layer',
  'diagonal-space',
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
    final String lessonId = _lessonIds[_selected];
    final controller = VideoPlayerController.asset(
      'assets/tutorial/$lessonId.mp4',
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
    final List<_Lesson> lessons = _localizedLessons(context);
    final _Lesson lesson = lessons[_selected];
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.sizeOf(context).height <= 700;
    final Widget goal = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: context.l10n.tutorialGoalBefore),
          TextSpan(
            text: context.l10n.tutorialGoalStrong,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: context.l10n.tutorialGoalAfter),
        ],
      ),
      style: const TextStyle(
        color: Color(0xFF626860),
        fontSize: 12,
        height: 1.5,
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
                  child: _LessonButtons(
                    lessons: lessons,
                    selected: _selected,
                    vertical: true,
                    onSelected: _selectLesson,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _TutorialMedia(
                          lesson: lesson,
                          video: _video,
                          failed: _failed,
                          ended: _ended,
                          onTogglePlayback: _togglePlayback,
                          onReplay: _replay,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _TutorialCaption(lesson: lesson, compact: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _TutorialFooter(
            selected: _selected,
            starting: widget.starting,
            onNext: _nextLesson,
            onDone: widget.onDone,
          ),
        ],
      );
    }
    return Column(
      children: [
        goal,
        const SizedBox(height: 10),
        _LessonButtons(
          key: const ValueKey('tutorial-selector'),
          lessons: lessons,
          selected: _selected,
          vertical: false,
          onSelected: _selectLesson,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _TutorialMedia(
            lesson: lesson,
            video: _video,
            failed: _failed,
            ended: _ended,
            onTogglePlayback: _togglePlayback,
            onReplay: _replay,
          ),
        ),
        const SizedBox(height: 10),
        _TutorialCaption(lesson: lesson),
        const SizedBox(height: 8),
        _TutorialFooter(
          selected: _selected,
          starting: widget.starting,
          onNext: _nextLesson,
          onDone: widget.onDone,
        ),
      ],
    );
  }

  void _selectLesson(int index) {
    setState(() => _selected = index);
    if (widget.loadVideos) _load();
  }

  void _nextLesson() => _selectLesson((_selected + 1) % _lessonIds.length);

  Future<void> _togglePlayback() async {
    final VideoPlayerController? video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      if (_ended) {
        await video.seekTo(Duration.zero);
        _ended = false;
      }
      await video.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _replay() async {
    final VideoPlayerController? video = _video;
    if (video == null) return;
    await video.seekTo(Duration.zero);
    _ended = false;
    await video.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }
}

class _LessonButtons extends StatelessWidget {
  const new({
    required this.lessons,
    required this.selected,
    required this.vertical,
    required this.onSelected,
    super.key,
  });

  final List<_Lesson> lessons;
  final int selected;
  final bool vertical;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<Widget> buttons = [
      for (var index = 0; index < lessons.length; index++)
        OutlinedButton(
          onPressed: () => onSelected(index),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, vertical ? 31 : 36),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            backgroundColor: index == selected
                ? const Color(0xFFEDF1FF)
                : Colors.transparent,
            foregroundColor: index == selected
                ? AppColors.accent
                : AppColors.ink,
            side: BorderSide(
              color: index == selected
                  ? const Color(0xFFCAD5FB)
                  : const Color(0xFFE0E3D9),
            ),
            textStyle: context.textStyle.buttonSmall.copyWith(fontSize: 9),
          ),
          child: Text(
            vertical
                ? '${(index + 1).toString().padLeft(2, '0')}  ${lessons[index].tab}'
                : lessons[index].tab,
            maxLines: 1,
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 2.7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: buttons,
    );
  }
}

class _TutorialMedia extends StatelessWidget {
  const new({
    required this.lesson,
    required this.video,
    required this.failed,
    required this.ended,
    required this.onTogglePlayback,
    required this.onReplay,
  });

  final _Lesson lesson;
  final VideoPlayerController? video;
  final bool failed;
  final bool ended;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function() onReplay;

  @override
  Widget build(BuildContext context) => ClipRRect(
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
                      child: failed
                          ? Image.asset(
                              'assets/tutorial/${lesson.id}.webp',
                              fit: BoxFit.contain,
                            )
                          : video?.value.isInitialized == true
                          ? AspectRatio(
                              aspectRatio: video!.value.aspectRatio,
                              child: VideoPlayer(video!),
                            )
                          : const AppCircularProgressIndicator(),
                    ),
                  ),
                ),
                if (video?.value.isInitialized == true)
                  SizedBox(
                    height: 36,
                    child: ColoredBox(
                      color: const Color(0xF2EEEEE8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: video!.value.isPlaying
                                ? context.l10n.pauseExample
                                : context.l10n.playExample,
                            onPressed: onTogglePlayback,
                            icon: Icon(
                              video!.value.isPlaying
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                              size: 16,
                            ),
                          ),
                          Expanded(
                            child: Semantics(
                              label: context.l10n.videoPosition,
                              child: VideoProgressIndicator(
                                video!,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.replayExample,
                            onPressed: onReplay,
                            icon: const Icon(LucideIcons.rotateCcw, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (ended && lesson.id != 'stacking')
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
                child: Text(
                  context.l10n.fourInRowWin,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (failed)
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Text(
                context.l10n.videoUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TutorialCaption extends StatelessWidget {
  const new({required this.lesson, this.compact = false});

  final _Lesson lesson;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
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
}

class _TutorialFooter extends StatelessWidget {
  const new({
    required this.selected,
    required this.starting,
    required this.onNext,
    required this.onDone,
  });

  final int selected;
  final bool starting;
  final VoidCallback onNext;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      TextButton.icon(
        onPressed: onNext,
        style: TextButton.styleFrom(textStyle: context.textStyle.buttonSmall),
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 16),
        label: Text(
          selected == _lessonIds.length - 1
              ? context.l10n.firstExample
              : context.l10n.nextExample,
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: onDone ?? () => Navigator.maybePop(context),
        child: Text(starting ? context.l10n.start : context.l10n.gotIt),
      ),
    ],
  );
}

List<_Lesson> _localizedLessons(BuildContext context) {
  final AppLocalizations l10n = context.l10n;
  return [
    _Lesson(
      _lessonIds[0],
      l10n.tutorialMoveTab,
      l10n.tutorialMoveTitle,
      l10n.tutorialMoveBody,
    ),
    _Lesson(
      _lessonIds[1],
      l10n.tutorialHorizontalTab,
      l10n.tutorialHorizontalTitle,
      l10n.tutorialHorizontalBody,
    ),
    _Lesson(
      _lessonIds[2],
      l10n.tutorialVerticalTab,
      l10n.tutorialVerticalTitle,
      l10n.tutorialVerticalBody,
    ),
    _Lesson(
      _lessonIds[3],
      l10n.tutorialLayerDiagonalTab,
      l10n.tutorialLayerDiagonalTitle,
      l10n.tutorialLayerDiagonalBody,
    ),
    _Lesson(
      _lessonIds[4],
      l10n.tutorialRaisedDiagonalTab,
      l10n.tutorialRaisedDiagonalTitle,
      l10n.tutorialRaisedDiagonalBody,
    ),
    _Lesson(
      _lessonIds[5],
      l10n.tutorialSpaceDiagonalTab,
      l10n.tutorialSpaceDiagonalTitle,
      l10n.tutorialSpaceDiagonalBody,
    ),
  ];
}
