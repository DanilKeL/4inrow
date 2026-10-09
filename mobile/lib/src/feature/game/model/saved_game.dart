import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/model/game_view_data.dart';
import 'package:four3/src/feature/game/service/game_engine.dart';
import 'package:four3/src/feature/levels/domain/model/game_level.dart';

final class SavedGame extends Equatable {
  const new({
    required this.snapshot,
    required this.mode,
    required this.difficulty,
    required this.names,
    required this.accountAtStart,
    required this.recordId,
    required this.elapsed,
    required this.xray,
    required this.layers,
    required this.cameraView,
    required this.levelId,
    required this.levelChapter,
    required this.levelPresetLength,
    required this.levelBestBefore,
    required this.dailyChallenge,
    required this.dailyOwnerAtStart,
  });

  factory fromViewData(GameViewData data) => SavedGame(
    snapshot: data.snapshot,
    mode: data.mode,
    difficulty: data.difficulty,
    names: data.names,
    accountAtStart: data.accountAtStart,
    recordId: data.recordId,
    elapsed: data.elapsed,
    xray: data.xray,
    layers: data.layers,
    cameraView: data.cameraView,
    levelId: data.levelId,
    levelChapter: data.levelChapter,
    levelPresetLength: data.levelPresetLength,
    levelBestBefore: data.levelBestBefore,
    dailyChallenge: data.dailyChallenge,
    dailyOwnerAtStart: data.dailyOwnerAtStart,
  );

  factory fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['game'] is! String ||
        json['mode'] is! String ||
        json['difficulty'] is! String ||
        json['names'] is! List ||
        (json['names'] as List).length != 2 ||
        (json['names'] as List).any(
          (name) => name is! String || name.length > 100,
        ) ||
        json['recordId'] is! String ||
        (json['recordId'] as String).isEmpty ||
        (json['recordId'] as String).length > 160 ||
        (json['accountAtStart'] != null &&
            (json['accountAtStart'] is! String ||
                (json['accountAtStart'] as String).length > 24)) ||
        json['elapsed'] is! num ||
        !(json['elapsed'] as num).isFinite ||
        (json['elapsed'] as num) < 0 ||
        (json['elapsed'] as num) > 365 * 86400 ||
        json['xray'] is! bool ||
        json['layers'] is! List ||
        (json['layers'] as List).any(
          (layer) => layer is! int || layer < 0 || layer >= GameEngine.size,
        ) ||
        json['cameraView'] is! String) {
      throw const FormatException('Invalid saved game');
    }
    final GameMode mode = GameMode.values.byName(json['mode'] as String);
    if (mode == GameMode.online) {
      throw const FormatException('Online games cannot be restored');
    }
    final GameSnapshot snapshot = GameEngine.deserialize(
      json['game'] as String,
    );
    if (snapshot.status != GameStatus.playing) {
      throw const FormatException('Completed saved game');
    }
    final Object? rawDaily = json['dailyChallenge'];
    final DailyChallenge? daily = rawDaily == null
        ? null
        : DailyChallenge.fromJson(Map<String, dynamic>.from(rawDaily as Map));
    if ((mode == GameMode.daily) != (daily != null)) {
      throw const FormatException('Invalid daily save');
    }
    final Object? rawLevelId = json['levelId'];
    if (rawLevelId != null &&
        (rawLevelId is! int || rawLevelId < 1 || rawLevelId > 40)) {
      throw const FormatException('Invalid saved level');
    }
    final int? levelId = rawLevelId as int?;
    if ((mode == GameMode.level) != (levelId != null) ||
        (mode == GameMode.daily && levelId != null)) {
      throw const FormatException('Saved mode does not match level');
    }
    final Object? rawChapter = json['levelChapter'];
    if ((mode == GameMode.level) !=
        LevelChapter.values.any((chapter) => chapter.value == rawChapter)) {
      throw const FormatException('Invalid saved level chapter');
    }
    final Object? rawPresetLength = json['levelPresetLength'];
    if (rawPresetLength != null &&
        (rawPresetLength is! int ||
            rawPresetLength < 0 ||
            rawPresetLength > GameEngine.volume)) {
      throw const FormatException('Invalid saved preset length');
    }
    final int presetLength = rawPresetLength as int? ?? 0;
    if ((daily != null && presetLength != daily.preset.length) ||
        (mode != GameMode.daily &&
            mode != GameMode.level &&
            presetLength != 0)) {
      throw const FormatException('Saved preset length does not match mode');
    }
    final Object? rawBest = json['levelBestBefore'];
    if (rawBest != null && (rawBest is! int || rawBest <= 0 || rawBest > 63)) {
      throw const FormatException('Invalid saved level record');
    }
    final Object? rawDailyOwner = json['dailyOwnerAtStart'];
    if (rawDailyOwner != null &&
        (rawDailyOwner is! String || rawDailyOwner.length > 24)) {
      throw const FormatException('Invalid saved daily owner');
    }
    if (daily != null && rawDailyOwner != json['accountAtStart']) {
      throw const FormatException('Saved daily owner does not match account');
    }
    if (daily != null &&
        (snapshot.history.length < daily.preset.length ||
            daily.preset.indexed.any((entry) {
              final GameMove move = snapshot.history[entry.$1];
              return move.x != entry.$2.x || move.y != entry.$2.y;
            }))) {
      throw const FormatException('Daily preset does not match');
    }
    final List<int> layers =
        (json['layers'] as List).cast<int>().toSet().toList()..sort();
    return SavedGame(
      snapshot: snapshot,
      mode: mode,
      difficulty: Difficulty.values.byName(json['difficulty'] as String),
      names: (json['names'] as List).cast<String>(),
      accountAtStart: json['accountAtStart'] as String?,
      recordId: json['recordId'] as String,
      elapsed: (json['elapsed'] as num).toInt(),
      xray: json['xray'] as bool,
      layers: layers,
      cameraView: CameraView.values.byName(json['cameraView'] as String),
      levelId: levelId,
      levelChapter: rawChapter == null
          ? null
          : LevelChapter.fromValue(rawChapter),
      levelPresetLength: presetLength,
      levelBestBefore: rawBest as int?,
      dailyChallenge: daily,
      dailyOwnerAtStart: rawDailyOwner as String?,
    );
  }

  final GameSnapshot snapshot;
  final GameMode mode;
  final Difficulty difficulty;
  final List<String> names;
  final String? accountAtStart;
  final String recordId;
  final int elapsed;
  final bool xray;
  final List<int> layers;
  final CameraView cameraView;
  final int? levelId;
  final LevelChapter? levelChapter;
  final int levelPresetLength;
  final int? levelBestBefore;
  final DailyChallenge? dailyChallenge;
  final String? dailyOwnerAtStart;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'game': GameEngine.serialize(snapshot),
    'mode': mode.name,
    'difficulty': difficulty.name,
    'names': names,
    'accountAtStart': accountAtStart,
    'recordId': recordId,
    'elapsed': elapsed,
    'xray': xray,
    'layers': layers,
    'cameraView': cameraView.name,
    'levelId': levelId,
    'levelChapter': levelChapter?.value,
    'levelPresetLength': levelPresetLength,
    'levelBestBefore': levelBestBefore,
    'dailyChallenge': dailyChallenge?.toJson(),
    'dailyOwnerAtStart': dailyOwnerAtStart,
  };

  @override
  List<Object?> get props => <Object?>[
    snapshot,
    mode,
    difficulty,
    names,
    accountAtStart,
    recordId,
    elapsed,
    xray,
    layers,
    cameraView,
    levelId,
    levelChapter,
    levelPresetLength,
    levelBestBefore,
    dailyChallenge,
    dailyOwnerAtStart,
  ];
}
