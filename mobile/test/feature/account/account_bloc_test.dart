import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/data/account_datasource.dart';
import 'package:four3/src/feature/account/data/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _AccountDatasource datasource;
  late AccountBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {
      'four-cubed-guest-name': 'Гость_123456',
    });
    datasource = _AccountDatasource();
    bloc = AccountBloc(
      repository: AccountRepository(
        datasource: datasource,
        preferences: await SharedPreferences.getInstance(),
      ),
    );
  });

  tearDown(() => bloc.close());

  test('opens a reset deep link and completes password reset', () async {
    bloc.add(const AccountEvent$Load());
    await bloc.stream.firstWhere((state) => state is AccountState$Ready);

    bloc.add(const AccountEvent$OpenPasswordReset('reset-token'));
    final AccountState$PasswordReset reset = (await bloc.stream.firstWhere(
      (state) => state is AccountState$PasswordReset,
    )) as AccountState$PasswordReset;
    expect(reset.token, 'reset-token');

    bloc.add(
      const AccountEvent$CompletePasswordReset('reset-token', 'new-pass'),
    );
    final AccountState$Ready ready = (await bloc.stream.firstWhere(
      (state) => state is AccountState$Ready,
    )) as AccountState$Ready;
    expect(ready.profile.username, 'Alice');
    expect(ready.notice, 'Пароль изменён.');
    expect(datasource.completedToken, 'reset-token');
  });

  test(
    'surfaces repository notices for reset and verification emails',
    () async {
      bloc.add(const AccountEvent$Load());
      await bloc.stream.firstWhere((state) => state is AccountState$Ready);

      bloc.add(const AccountEvent$RequestPasswordReset('alice@example.com'));
      AccountState$Ready ready = (await bloc.stream.firstWhere(
        (state) => state is AccountState$Ready,
      )) as AccountState$Ready;
      expect(ready.notice, 'reset sent');

      bloc.add(const AccountEvent$ResendVerification('Alice'));
      ready = (await bloc.stream.firstWhere(
        (state) => state is AccountState$Ready,
      )) as AccountState$Ready;
      expect(ready.notice, 'verification sent');
    },
  );
}

final class _AccountDatasource implements AccountDatasource {
  String? completedToken;
  bool signedIn = false;

  @override
  Future<Map<String, dynamic>> profile() async => signedIn
      ? {
          'username': 'Alice',
          'guestName': 'Гость_123456',
          'email': 'alice@example.com',
          'emailVerified': true,
        }
      : {'guestName': 'Гость_123456'};

  @override
  Future<Map<String, dynamic>> completePasswordReset({
    required String token,
    required String password,
  }) async {
    completedToken = token;
    signedIn = true;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async => {'message': 'reset sent'};

  @override
  Future<Map<String, dynamic>> resendVerification({
    required String identifier,
  }) async => {'message': 'verification sent'};

  @override
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> logout() async => {'guestName': 'Гость_123456'};

  @override
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async => {'message': 'registered'};

  @override
  Future<Map<String, dynamic>> verifyEmail({required String token}) async => {
    'ok': true,
  };
}
