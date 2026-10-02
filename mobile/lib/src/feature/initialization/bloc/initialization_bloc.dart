import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

final class InitializationBloc
    extends Bloc<InitializationEvent, InitializationState> {
  new() : super(const InitializationState$Initial()) {
    on<InitializationEvent>(_onEvent, transformer: sequential());
  }
  void _onEvent(InitializationEvent event, Emitter<InitializationState> emit) {
    switch (event) {
      case InitializationEvent$Start():
        emit(const InitializationState$Ready(foreground: true, resumeCount: 0));
      case InitializationEvent$Foreground():
        final int count = state is InitializationState$Ready
            ? (state as InitializationState$Ready).resumeCount + 1
            : 1;
        emit(InitializationState$Ready(foreground: true, resumeCount: count));
      case InitializationEvent$Background():
        final int count = state is InitializationState$Ready
            ? (state as InitializationState$Ready).resumeCount
            : 0;
        emit(InitializationState$Ready(foreground: false, resumeCount: count));
    }
  }
}
