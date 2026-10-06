import 'package:equatable/equatable.dart';

sealed class InitializationState extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class InitializationState$Initial extends InitializationState {
  const new();
}

final class InitializationState$Ready extends InitializationState {
  const new({required this.foreground, required this.resumeCount});

  final bool foreground;
  final int resumeCount;

  @override
  List<Object> get props => [foreground, resumeCount];
}
