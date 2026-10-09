import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/data/datasource/account_datasource.dart';
import 'package:four3/src/feature/account/data/datasource/account_datasource_rest_client.dart';
import 'package:four3/src/feature/account/data/datasource/account_preferences_datasource.dart';
import 'package:four3/src/feature/account/data/repository/account_repository.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';
import 'package:four3/src/feature/leaderboard/data/datasource/leaderboard_datasource_rest_client.dart';
import 'package:four3/src/feature/leaderboard/data/repository/leaderboard_repository.dart';
import 'package:four3/src/feature/leaderboard/domain/model/leaderboard_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account datasource only forwards raw REST maps', () async {
    final client = _FakeRestClient(<String, Map<String, dynamic>>{
      'POST /auth/login': <String, dynamic>{'ok': true, 'raw': 7},
    });
    final datasource = AccountDatasource$RestClient(restClient: client);

    final Map<String, dynamic> result = await datasource.login(
      username: 'cube',
      password: 'secret',
    );

    expect(result, <String, dynamic>{'ok': true, 'raw': 7});
    expect(client.lastPath, '/auth/login');
    expect(client.lastData, <String, Object?>{
      'username': 'cube',
      'password': 'secret',
    });
  });

  test('account repository owns profile deserialization', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final datasource = _FakeAccountDatasource()
      ..profileResponse = <String, dynamic>{
        'username': 'cube',
        'guestName': 'Guest_123456',
        'email': 'cube@example.com',
        'emailVerified': true,
        'createdAt': 42.0,
      };
    final repository = AccountRepository$Api(
      datasource: datasource,
      preferencesDatasource: AccountPreferencesDatasource$Preferences(
        preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
          sharedPreferences: preferences,
        ),
      ),
    );

    final AccountProfile profile = await repository.load();

    expect(profile.username, 'cube');
    expect(profile.guestName, 'Guest_123456');
    expect(profile.email, 'cube@example.com');
    expect(profile.emailVerified, isTrue);
    expect(profile.createdAt, 42);
  });

  test('account repository keeps the owner hint for offline launch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final AccountPreferencesDatasource$Preferences accountPreferences =
        AccountPreferencesDatasource$Preferences(
          preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
            sharedPreferences: preferences,
          ),
        );
    final _FakeAccountDatasource datasource = _FakeAccountDatasource()
      ..profileResponse = <String, dynamic>{
        'username': 'cube',
        'guestName': 'Guest_123456',
      };
    final AccountRepository$Api repository = AccountRepository$Api(
      datasource: datasource,
      preferencesDatasource: accountPreferences,
    );

    await repository.load();
    datasource.profileError = const RestClientException(
      '',
      failure: RestClientFailure.network,
    );
    final AccountProfile offline = await repository.load();

    expect(offline.username, 'cube');
    expect(offline.guestName, 'Guest_123456');
  });

  test(
    'account repository preserves registration feedback from web API',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final datasource = _FakeAccountDatasource()
        ..registerResponse = <String, dynamic>{
          'verificationRequired': true,
          'message': 'Verification sent. Check your inbox and spam folder.',
        };
      final repository = AccountRepository$Api(
        datasource: datasource,
        preferencesDatasource: AccountPreferencesDatasource$Preferences(
          preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
            sharedPreferences: preferences,
          ),
        ),
      );

      final AccountRegistrationResult result = await repository.register(
        'cube',
        'cube@example.com',
        'password-123',
      );

      expect(result.verificationRequired, isTrue);
      expect(result.notice.remote, contains('spam folder'));
    },
  );

  test('failed email delivery still completes registration like web', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final datasource = _FakeAccountDatasource()
      ..registerError = const RestClientException(
        'Account created, but email delivery failed. Try again later.',
        statusCode: 503,
        data: <String, dynamic>{'verificationRequired': true},
      );
    final repository = AccountRepository$Api(
      datasource: datasource,
      preferencesDatasource: AccountPreferencesDatasource$Preferences(
        preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
          sharedPreferences: preferences,
        ),
      ),
    );

    final AccountRegistrationResult result = await repository.register(
      'cube',
      'cube@example.com',
      'password-123',
    );

    expect(result.verificationRequired, isTrue);
    expect(result.notice.remote, startsWith('Account created'));
  });

  test('leaderboard repository converts raw rows into models', () async {
    final datasource = LeaderboardDatasource$RestClient(
      restClient: _FakeRestClient(<String, Map<String, dynamic>>{
        'GET /auth/leaderboard': <String, dynamic>{
          'players': <Map<String, Object?>>[
            <String, Object?>{
              'rank': 1.0,
              'username': 'winner',
              'elo': 1512.0,
              'games': 31.0,
            },
          ],
        },
      }),
    );
    final repository = LeaderboardRepository$Api(datasource: datasource);

    final List<LeaderboardPlayer> players = await repository.load();

    expect(players, hasLength(1));
    expect(players.single.rank, 1);
    expect(players.single.username, 'winner');
    expect(players.single.elo, 1512);
    expect(players.single.games, 31);
  });
}

final class _FakeRestClient implements RestClient {
  new(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  String? lastPath;
  Map<String, Object?>? lastData;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) async {
    lastPath = path;
    return responses['GET $path'] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? data,
    Map<String, String?>? queryParams,
    Map<String, String>? headers,
  }) async {
    lastPath = path;
    lastData = data;
    return responses['POST $path'] ?? <String, dynamic>{};
  }

  @override
  void dispose() {}
}

final class _FakeAccountDatasource implements AccountDatasource {
  Map<String, dynamic> profileResponse = <String, dynamic>{};
  Map<String, dynamic> registerResponse = <String, dynamic>{};
  RestClientException? registerError;
  RestClientException? profileError;

  @override
  Future<Map<String, dynamic>> profile() async {
    if (profileError case final error?) throw error;
    return profileResponse;
  }

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    if (registerError case final error?) throw error;
    return registerResponse;
  }

  @override
  Future<Map<String, dynamic>> verifyEmail({required String token}) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> resendVerification({
    required String identifier,
  }) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> completePasswordReset({
    required String token,
    required String password,
  }) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> logout() async => <String, dynamic>{};
}
