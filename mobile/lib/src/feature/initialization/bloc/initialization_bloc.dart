import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_event.dart';
import 'package:four3/src/feature/initialization/bloc/initialization_state.dart';

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
