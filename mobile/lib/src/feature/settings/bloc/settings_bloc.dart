import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/feature/settings/model/app_settings.dart';
import 'package:four3/src/feature/settings/service/settings_repository.dart';

sealed class SettingsEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class SettingsEvent$Load extends SettingsEvent {
  const new();
}

final class SettingsEvent$Update extends SettingsEvent {
  const new(this.settings);
  final AppSettings settings;
  @override
  List<Object> get props => [settings];
}

sealed class SettingsState extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class SettingsState$Initial extends SettingsState {
  const new();
}

final class SettingsState$Ready extends SettingsState {
  const new(this.settings);
  final AppSettings settings;
  @override
  List<Object> get props => [settings];
}

final class SettingsState$Failure extends SettingsState {
  const new();
}

final class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  new({required this._repository}) : super(const SettingsState$Initial()) {
    on<SettingsEvent>(_onEvent, transformer: sequential());
  }

  final SettingsRepository _repository;

  AppSettings get settings => switch (state) {
    SettingsState$Ready(:final AppSettings settings) => settings,
    _ => const AppSettings(),
  };

  Future<void> _onEvent(
    SettingsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    switch (event) {
      case SettingsEvent$Load():
        emit(SettingsState$Ready(_repository.load()));
      case SettingsEvent$Update(:final settings):
        emit(SettingsState$Ready(settings));
        try {
          await _repository.save(settings);
        } on Exception {
          emit(const SettingsState$Failure());
          emit(SettingsState$Ready(settings));
        }
    }
  }
}
