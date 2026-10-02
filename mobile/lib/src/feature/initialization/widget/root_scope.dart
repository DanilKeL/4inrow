import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/common/utils/build_context_extension.dart';
import 'package:four3/src/feature/account/data/account_datasource.dart';
import 'package:four3/src/feature/account/data/account_repository.dart';
import 'package:four3/src/feature/audio/service/audio_service.dart';
import 'package:four3/src/feature/game/service/game_storage_repository.dart';
import 'package:four3/src/feature/initialization/model/app_config.dart';
import 'package:four3/src/feature/initialization/service/deep_link_service.dart';
import 'package:four3/src/feature/leaderboard/data/leaderboard_datasource.dart';
import 'package:four3/src/feature/leaderboard/data/leaderboard_repository.dart';
import 'package:four3/src/feature/levels/service/level_repository.dart';
import 'package:four3/src/feature/match_history/data/match_history_datasource.dart';
import 'package:four3/src/feature/match_history/data/match_history_repository.dart';
import 'package:four3/src/feature/matchmaking/service/online_transport.dart';
import 'package:four3/src/feature/settings/service/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class RootDependencies {
  new({
    required this.config,
    required this.preferences,
    required this.secureStorage,
    required this.restClient,
    required this.cookieStorage,
    required this.settingsRepository,
    required this.gameStorageRepository,
    required this.levelRepository,
    required this.deepLinkService,
    required this.accountRepository,
    required this.onlineTransport,
    required this.matchHistoryRepository,
    required this.leaderboardRepository,
    required this.audioService,
  });

  final AppConfig config;
  final SharedPreferences preferences;
  final FlutterSecureStorage secureStorage;
  final RestClient restClient;
  final SessionCookieStorage cookieStorage;
  final SettingsRepository settingsRepository;
  final GameStorageRepository gameStorageRepository;
  final LevelRepository levelRepository;
  final DeepLinkService deepLinkService;
  final AccountRepository accountRepository;
  final OnlineTransport onlineTransport;
  final MatchHistoryRepository matchHistoryRepository;
  final LeaderboardRepository leaderboardRepository;
  final AudioService audioService;

  static Future<RootDependencies> create() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    final config = AppConfig.fromEnvironment();
    const cookieStorage = SessionCookieStorage(secureStorage);
    final restClient = RestClient$Http(
      baseUrl: config.apiBaseUrl,
      cookieStorage: cookieStorage,
    );
    final deepLinkService = DeepLinkService();
    await deepLinkService.start();
    final accountRepository = AccountRepository(
      datasource: AccountDatasource$RestClient(restClient: restClient),
      preferences: preferences,
    );
    final onlineTransport = OnlineTransport(
      endpoint: Uri.parse(config.onlineUrl),
      preferences: preferences,
      cookieStorage: cookieStorage,
    );
    final audioService = AudioService();
    return RootDependencies(
      config: config,
      preferences: preferences,
      secureStorage: secureStorage,
      restClient: restClient,
      cookieStorage: cookieStorage,
      settingsRepository: SettingsRepository(preferences),
      gameStorageRepository: GameStorageRepository(preferences),
      levelRepository: LevelRepository(preferences),
      deepLinkService: deepLinkService,
      accountRepository: accountRepository,
      onlineTransport: onlineTransport,
      matchHistoryRepository: MatchHistoryRepository(
        datasource: MatchHistoryDatasource$RestClient(restClient: restClient),
      ),
      leaderboardRepository: LeaderboardRepository(
        datasource: LeaderboardDatasource$RestClient(restClient: restClient),
      ),
      audioService: audioService,
    );
  }

  Future<void> dispose() async {
    await deepLinkService.dispose();
    await onlineTransport.dispose();
    await audioService.dispose();
    restClient.dispose();
  }
}

class RootScope extends StatefulWidget {
  const new({required this.child, super.key});
  final Widget child;

  static RootDependencies of(BuildContext context) =>
      context.inheritedOf<_InheritedRootScope>().dependencies;

  @override
  State<RootScope> createState() => _RootScopeState();
}

class _RootScopeState extends State<RootScope> {
  late final Future<RootDependencies> _future = RootDependencies.create();
  RootDependencies? _dependencies;

  @override
  void dispose() {
    _dependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RootDependencies>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Не удалось запустить приложение: ${snapshot.error}'),
            ),
          ),
        );
      }
      final RootDependencies? dependencies = snapshot.data;
      if (dependencies == null) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      _dependencies ??= dependencies;
      return _InheritedRootScope(
        dependencies: dependencies,
        child: widget.child,
      );
    },
  );
}

class _InheritedRootScope extends InheritedWidget {
  const new({required this.dependencies, required super.child});
  final RootDependencies dependencies;

  @override
  bool updateShouldNotify(covariant _InheritedRootScope oldWidget) => false;
}
