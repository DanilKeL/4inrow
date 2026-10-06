import 'package:equatable/equatable.dart';

sealed class LeaderboardEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class LeaderboardEvent$Load extends LeaderboardEvent {
  const new();
}
