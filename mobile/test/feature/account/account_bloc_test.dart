import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/account/bloc/account_bloc.dart';
import 'package:four3/src/feature/account/bloc/account_event.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/data/datasource/account_datasource.dart';
import 'package:four3/src/feature/account/data/datasource/account_preferences_datasource.dart';
import 'package:four3/src/feature/account/data/repository/account_repository.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _AccountDatasource datasource;
  late AccountBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    datasource = _AccountDatasource();
    final accountPreferences = AccountPreferencesDatasource$Preferences(
      preferencesDatasourceTool: PreferencesDatasourceTool$Shared(
        sharedPreferences: await SharedPreferences.getInstance(),
      ),
    );
    await accountPreferences.saveGuestName('Guest_123456');
    bloc = AccountBloc(
      repository: AccountRepository$Api(
        datasource: datasource,
        preferencesDatasource: accountPreferences,
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
    expect(ready.clientNotice, AccountNotice.passwordChanged);
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

  test('marks email registration complete and keeps its notice', () async {
    datasource.registrationResponse = {
      'verificationRequired': true,
      'message': 'Verification sent. Check your inbox and spam folder.',
    };
    bloc.add(const AccountEvent$Load());
    await bloc.stream.firstWhere((state) => state is AccountState$Ready);

    bloc.add(
      const AccountEvent$Register('Alice', 'alice@example.com', 'password-123'),
    );
    final AccountState$Ready ready = (await bloc.stream.firstWhere(
      (state) => state is AccountState$Ready && state.registrationCompleted,
    )) as AccountState$Ready;

    expect(ready.profile.username, isNull);
    expect(ready.registrationCompleted, isTrue);
    expect(ready.notice, contains('spam folder'));
  });
}

final class _AccountDatasource implements AccountDatasource {
  String? completedToken;
  bool signedIn = false;
  Map<String, dynamic> registrationResponse = {'message': 'registered'};

  @override
  Future<Map<String, dynamic>> profile() async => signedIn
      ? {
          'username': 'Alice',
          'guestName': 'Guest_123456',
          'email': 'alice@example.com',
          'emailVerified': true,
        }
      : {'guestName': 'Guest_123456'};

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
  }) async {
    signedIn = true;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> logout() async => {'guestName': 'Guest_123456'};

  @override
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async => registrationResponse;

  @override
  Future<Map<String, dynamic>> verifyEmail({required String token}) async {
    signedIn = true;
    return {'ok': true};
  }
}
