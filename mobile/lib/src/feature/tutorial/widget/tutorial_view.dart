import 'package:flutter/material.dart';
import 'package:four3/l10n/generated/app_localizations.dart';
import 'package:four3/src/common/theme/app_theme.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
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
                  child: _lessonButtons(context, lessons, vertical: true),
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
          _footer(context),
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
          child: _lessonButtons(context, lessons, vertical: false),
        ),
        const SizedBox(height: 10),
        Expanded(child: _media(lesson)),
        const SizedBox(height: 10),
        _caption(context, lesson),
        const SizedBox(height: 8),
        _footer(context),
      ],
    );
  }

  Widget _lessonButtons(
    BuildContext context,
    List<_Lesson> lessons, {
    required bool vertical,
  }) {
    final List<Widget> buttons = [
      for (var index = 0; index < lessons.length; index++)
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
                ? '${(index + 1).toString().padLeft(2, '0')}  ${lessons[index].tab}'
                : lessons[index].tab,
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
                                ? context.l10n.pauseExample
                                : context.l10n.playExample,
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
                              label: context.l10n.videoPosition,
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
                            tooltip: context.l10n.replayExample,
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
          if (_failed)
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

  Widget _footer(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      TextButton.icon(
        onPressed: () {
          setState(() => _selected = (_selected + 1) % _lessonIds.length);
          if (widget.loadVideos) _load();
        },
        iconAlignment: IconAlignment.end,
        icon: const Icon(LucideIcons.arrowRight, size: 16),
        label: Text(
          _selected == _lessonIds.length - 1
              ? context.l10n.firstExample
              : context.l10n.nextExample,
          style: const TextStyle(fontSize: 11),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: widget.onDone ?? () => Navigator.maybePop(context),
        child: Text(widget.starting ? context.l10n.start : context.l10n.gotIt),
      ),
    ],
  );

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }
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
