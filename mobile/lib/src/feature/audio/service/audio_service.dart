import 'package:just_audio/just_audio.dart';

enum SoundEffect { place, invalid, win, click, match }

final class AudioService {
  final Map<SoundEffect, AudioPlayer> _players = {
    for (final effect in SoundEffect.values) effect: AudioPlayer(),
  };
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await Future.wait([
      for (final entry in _players.entries)
        entry.value.setAsset('assets/audio/${entry.key.name}.wav'),
    ]);
  }

  Future<void> play(
    SoundEffect effect, {
    required bool enabled,
    required double volume,
  }) async {
    if (!enabled || volume <= 0) return;
    try {
      await load();
      final AudioPlayer player = _players[effect]!;
      await player.setVolume(volume.clamp(0, 1));
      await player.seek(Duration.zero);
      await player.play();
    } on Exception {
      // Sound must never interrupt gameplay.
    }
  }

  Future<void> dispose() =>
      Future.wait([for (final player in _players.values) player.dispose()]);
}
