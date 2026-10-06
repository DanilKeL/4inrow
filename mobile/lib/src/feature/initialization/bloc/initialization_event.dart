import 'package:equatable/equatable.dart';

sealed class InitializationEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

final class InitializationEvent$Start extends InitializationEvent {
  const new();
}

final class InitializationEvent$Foreground extends InitializationEvent {
  const new();
}

final class InitializationEvent$Background extends InitializationEvent {
  const new();
}
