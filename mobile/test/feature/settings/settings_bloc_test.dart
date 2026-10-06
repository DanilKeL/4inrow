import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/bloc/settings_event.dart';
import 'package:four3/src/feature/settings/bloc/settings_state.dart';
import 'package:four3/src/feature/settings/data/datasource/settings_datasource_preferences.dart';
import 'package:four3/src/feature/settings/data/model/app_settings_dto.dart';
import 'package:four3/src/feature/settings/data/repository/settings_repository.dart';
import 'package:four3/src/feature/settings/domain/model/app_settings.dart';
import 'package:four3/src/feature/settings/domain/repository/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final datasource = SettingsDatasource$Preferences(
      preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
        sharedPreferences: await SharedPreferences.getInstance(),
      ),
    );
    await datasource.save(
      const AppSettingsDto(
        sound: false,
        volume: 1,
        animations: true,
        hints: true,
        xrayDefault: false,
        tutorialSeen: false,
      ),
    );
    repository = SettingsRepository$Local(datasource: datasource);
  });

  blocTest<SettingsBloc, SettingsState>(
    'loads and serially persists updates',
    build: () => SettingsBloc(repository: repository),
    act: (bloc) {
      bloc
        ..add(const SettingsEvent$Load())
        ..add(const SettingsEvent$Update(AppSettings(volume: .4)));
    },
    expect: () => const [
      SettingsState$Ready(AppSettings(sound: false)),
      SettingsState$Ready(AppSettings(volume: .4)),
    ],
    verify: (_) {
      expect(repository.load().sound, isTrue);
      expect(repository.load().volume, .4);
    },
  );
}
