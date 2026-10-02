import 'package:equatable/equatable.dart';

import 'package:four3/src/feature/game/model/game_models.dart';

final class GameLevel extends Equatable {
  const new({required this.id, required this.chapter, required this.preset});
  final int id;
  final String chapter;
  final List<MoveCandidate> preset;

  factory fromJson(Map<String, dynamic> json) => GameLevel(
    id: (json['id'] as num).toInt(),
    chapter: json['chapter'] as String,
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
