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
      levelRepository: LevelRepository(preferences, restClient),
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
  late Future<RootDependencies> _future = RootDependencies.create();
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
          home: _LaunchScreen(
            error: 'Проверьте соединение и попробуйте ещё раз.',
            onRetry: () => setState(() => _future = RootDependencies.create()),
          ),
        );
      }
      final RootDependencies? dependencies = snapshot.data;
      if (dependencies == null) {
        return const MaterialApp(home: _LaunchScreen());
      }
      _dependencies ??= dependencies;
      return _InheritedRootScope(
        dependencies: dependencies,
        child: widget.child,
      );
    },
  );
}

class _LaunchScreen extends StatelessWidget {
  const new({this.error, this.onRetry});
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F2EE),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text.rich(
              TextSpan(
                text: 'FOUR',
                children: [
                  TextSpan(
                    text: '3',
                    style: TextStyle(color: Color(0xFF2955E7), fontSize: 18),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 30),
            const _LoadingSculpture(),
            const SizedBox(height: 20),
            Text(
              error == null ? 'Загрузка игры' : 'Не удалось загрузить поле',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error ?? 'Доска и фишки…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF777A75), fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            if (error == null)
              const SizedBox(
                width: 128,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFF2955E7),
                  backgroundColor: Color(0xFFDDDFD7),
                ),
              )
            else
              FilledButton(
                onPressed: onRetry,
                child: const Text('Попробовать снова'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _LoadingSculpture extends StatefulWidget {
  const new();

  @override
  State<_LoadingSculpture> createState() => _LoadingSculptureState();
}

class _LoadingSculptureState extends State<_LoadingSculpture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  double _offset(double delay) {
    if (MediaQuery.disableAnimationsOf(context)) return 0;
    final double progress = (_controller.value - delay) % 1;
    if (progress <= .25) return -14 * (progress / .25);
    if (progress <= .45) return -14 * (1 - (progress - .25) / .2);
    return 0;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 170,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 15,
            bottom: 12,
            child: Stack(
              children: [
                Container(
                  width: 130,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF353A3D),
                    borderRadius: BorderRadius.circular(65),
                  ),
                ),
                Container(
                  width: 130,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E2DA),
                    border: Border.all(color: const Color(0xFFD0CEC6)),
                    borderRadius: BorderRadius.circular(65),
                  ),
                ),
              ],
            ),
          ),
          _LoadingCoin(
            bottom: 42,
            offset: _offset(0),
            color: const Color(0xFF30353C),
            edge: const Color(0xFF202429),
            hole: const Color(0xFF9B9D9E),
          ),
          _LoadingCoin(
            bottom: 68,
            offset: _offset(.064),
            color: const Color(0xFFF8F1E3),
            edge: const Color(0xFFD9D0BF),
            hole: const Color(0xFF9B9D9E),
          ),
          _LoadingCoin(
            bottom: 94,
            offset: _offset(.128),
            color: const Color(0xFF416BED),
            edge: const Color(0xFF2955CE),
            hole: const Color(0xFFC7D2FA),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _LoadingCoin extends StatelessWidget {
  const new({
    required this.bottom,
    required this.offset,
    required this.color,
    required this.edge,
    required this.hole,
  });

  final double bottom;
  final double offset;
  final Color color;
  final Color edge;
  final Color hole;

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: bottom,
    child: Transform.translate(
      offset: Offset(0, offset),
      child: SizedBox(
        width: 68,
        height: 35,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: edge,
                borderRadius: BorderRadius.circular(34),
              ),
            ),
            Container(
              height: 25,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(34),
              ),
            ),
            Positioned(
              top: 8,
              left: 30,
              child: Container(
                width: 7,
                height: 4,
                decoration: BoxDecoration(
                  border: Border.all(color: hole),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InheritedRootScope extends InheritedWidget {
  const new({required this.dependencies, required super.child});
  final RootDependencies dependencies;

  @override
  bool updateShouldNotify(covariant _InheritedRootScope oldWidget) => false;
}
