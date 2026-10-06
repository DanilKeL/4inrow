import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/feature/settings/bloc/settings_event.dart';
import 'package:four3/src/feature/settings/bloc/settings_state.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/domain/repository/settings_repository.dart';

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
