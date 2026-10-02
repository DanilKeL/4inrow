import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/settings/bloc/settings_bloc.dart';
import 'package:four3/src/feature/settings/model/app_settings.dart';
import 'package:four3/src/feature/settings/service/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'settings.sound': false});
    repository = SettingsRepository(await SharedPreferences.getInstance());
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
