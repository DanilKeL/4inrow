import 'package:equatable/equatable.dart';

import 'package:four3/src/feature/game/model/game_models.dart';

enum LevelChapter {
  firstSteps('firstSteps'),
  tactics('tactics'),
  combinations('combinations'),
  counterattack('counterattack'),
  advanced('advanced');

  new(this.value);
  final String value;

  static LevelChapter fromValue(Object? value) => values.firstWhere(
    (chapter) => chapter.value == value,
    orElse: () => LevelChapter.firstSteps,
  );
}

final class GameLevel extends Equatable {
  const new({required this.id, required this.chapter, required this.preset});
  final int id;
  final LevelChapter chapter;
  final List<MoveCandidate> preset;

  factory fromJson(Map<String, dynamic> json) => GameLevel(
    id: (json['id'] as num).toInt(),
    chapter: LevelChapter.fromValue(json['chapter']),
    preset: [
      for (final value in json['preset'] as List)
        MoveCandidate(
          ((value as Map)['x'] as num).toInt(),
          (value['y'] as num).toInt(),
        ),
    ],
  );

  @override
  List<Object> get props => [id, chapter, preset];
}
