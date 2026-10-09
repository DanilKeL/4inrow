import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/common/services/analytics/analytics_service.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';
import 'package:four3/src/feature/audio/service/audio_service.dart';
import 'package:four3/src/feature/daily/domain/repository/daily_repository.dart';
import 'package:four3/src/feature/game/domain/repository/game_storage_repository.dart';
import 'package:four3/src/feature/initialization/model/app_config.dart';
import 'package:four3/src/feature/initialization/service/deep_link_service.dart';
import 'package:four3/src/feature/leaderboard/domain/repository/leaderboard_repository.dart';
import 'package:four3/src/feature/levels/domain/repository/level_repository.dart';
import 'package:four3/src/feature/localization/data/datasource/app_locale_datasource.dart';
import 'package:four3/src/feature/match_history/domain/repository/match_history_repository.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';
import 'package:four3/src/feature/settings/domain/repository/settings_repository.dart';

final class RootDependenciesContainer {
  new({
    required this.config,
    required this.preferencesDatasourceTool,
    required this.appLocaleDatasource,
    required this.secureStorage,
    required this.restClient,
    required this.cookieStorage,
    required this.settingsRepository,
    required this.gameStorageRepository,
    required this.dailyRepository,
    required this.levelRepository,
    required this.deepLinkService,
    required this.accountRepository,
    required this.onlineTransport,
    required this.matchHistoryRepository,
    required this.leaderboardRepository,
    required this.audioService,
    required this.analyticsService,
  });

  final AppConfig config;
  final PreferencesDatasourceTool preferencesDatasourceTool;
  final AppLocaleDatasource appLocaleDatasource;
  final FlutterSecureStorage secureStorage;
  final RestClient restClient;
  final SessionCookieStorage cookieStorage;
  final SettingsRepository settingsRepository;
  final GameStorageRepository gameStorageRepository;
  final DailyRepository dailyRepository;
  final LevelRepository levelRepository;
  final DeepLinkService deepLinkService;
  final AccountRepository accountRepository;
  final OnlineTransport onlineTransport;
  final MatchHistoryRepository matchHistoryRepository;
  final LeaderboardRepository leaderboardRepository;
  final AudioService audioService;
  final AnalyticsService analyticsService;

  Future<void> dispose() async {
    await deepLinkService.dispose();
    await onlineTransport.dispose();
    await audioService.dispose();
    await analyticsService.dispose();
    restClient.dispose();
  }
}
