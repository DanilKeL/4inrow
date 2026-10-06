import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/data/datasource/account_datasource_rest_client.dart';
import 'package:four3/src/feature/account/data/datasource/account_preferences_datasource.dart';
import 'package:four3/src/feature/account/data/repository/account_repository.dart';
import 'package:four3/src/feature/audio/service/audio_service.dart';
import 'package:four3/src/feature/game/data/datasource/game_storage_datasource_preferences.dart';
import 'package:four3/src/feature/game/data/repository/game_storage_repository.dart';
import 'package:four3/src/feature/initialization/domain/model/dependencies_container.dart';
import 'package:four3/src/feature/initialization/model/app_config.dart';
import 'package:four3/src/feature/initialization/service/deep_link_service.dart';
import 'package:four3/src/feature/leaderboard/data/datasource/leaderboard_datasource_rest_client.dart';
import 'package:four3/src/feature/leaderboard/data/repository/leaderboard_repository.dart';
import 'package:four3/src/feature/levels/data/datasource/level_asset_datasource.dart';
import 'package:four3/src/feature/levels/data/datasource/level_datasource_rest_client.dart';
import 'package:four3/src/feature/levels/data/datasource/level_preferences_datasource.dart';
import 'package:four3/src/feature/levels/data/repository/level_repository.dart';
import 'package:four3/src/feature/localization/data/datasource/app_locale_datasource.dart';
import 'package:four3/src/feature/match_history/data/datasource/match_history_datasource_rest_client.dart';
import 'package:four3/src/feature/match_history/data/repository/match_history_repository.dart';
import 'package:four3/src/feature/matchmaking/data/datasource/online_session_datasource.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';
import 'package:four3/src/feature/settings/data/datasource/settings_datasource_preferences.dart';
import 'package:four3/src/feature/settings/data/repository/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class CompositionRoot {
  const new();

  Future<RootDependenciesContainer> compose() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PreferencesDatasourceTool preferencesDatasourceTool =
        PreferencesDatasourceTool$Shared(sharedPreferences: preferences);
    const FlutterSecureStorage secureStorage = FlutterSecureStorage();
    final AppConfig config = AppConfig.fromEnvironment();
    const SessionCookieStorage cookieStorage = SessionCookieStorage(
      secureStorage,
    );
    final RestClient restClient = RestClient$Http(
      baseUrl: config.apiBaseUrl,
      cookieStorage: cookieStorage,
    );
    final DeepLinkService deepLinkService = DeepLinkService();
    await deepLinkService.start();
    final AccountRepository$Api accountRepository = AccountRepository$Api(
      datasource: AccountDatasource$RestClient(restClient: restClient),
      preferencesDatasource: AccountPreferencesDatasource$Preferences(
        preferencesDatasourceTool: preferencesDatasourceTool,
      ),
    );
    final OnlineTransport onlineTransport = OnlineTransport(
      endpoint: Uri.parse(config.onlineUrl),
      persistenceDatasource: OnlineSessionDatasource$Preferences(
        preferencesDatasourceTool: preferencesDatasourceTool,
      ),
      cookieStorage: cookieStorage,
    );
    final AudioService audioService = AudioService();
    return RootDependenciesContainer(
      config: config,
      preferencesDatasourceTool: preferencesDatasourceTool,
      appLocaleDatasource: AppLocaleDatasource$Preferences(
        preferencesDatasourceTool: preferencesDatasourceTool,
      ),
      secureStorage: secureStorage,
      restClient: restClient,
      cookieStorage: cookieStorage,
      settingsRepository: SettingsRepository$Local(
        datasource: SettingsDatasource$Preferences(
          preferencesDatasourceTool: preferencesDatasourceTool,
        ),
      ),
      gameStorageRepository: GameStorageRepository$Local(
        datasource: GameStorageDatasource$Preferences(
          preferencesDatasourceTool: preferencesDatasourceTool,
        ),
      ),
      levelRepository: LevelRepository$Local(
        assetDatasource: LevelAssetDatasource$Bundle(),
        preferencesDatasource: LevelPreferencesDatasource$Preferences(
          preferencesDatasourceTool: preferencesDatasourceTool,
        ),
        remoteDatasource: LevelRemoteDatasource$RestClient(
          restClient: restClient,
        ),
      ),
      deepLinkService: deepLinkService,
      accountRepository: accountRepository,
      onlineTransport: onlineTransport,
      matchHistoryRepository: MatchHistoryRepository$Api(
        datasource: MatchHistoryDatasource$RestClient(restClient: restClient),
      ),
      leaderboardRepository: LeaderboardRepository$Api(
        datasource: LeaderboardDatasource$RestClient(restClient: restClient),
      ),
      audioService: audioService,
    );
  }
}
