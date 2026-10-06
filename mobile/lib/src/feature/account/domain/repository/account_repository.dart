import 'package:four3/src/feature/account/domain/model/account_profile.dart';

abstract interface class AccountRepository {
  const new();

  String get guestName;
  Future<AccountProfile> load();
  Future<AccountProfile> login(String username, String password);
  Future<AccountRegistrationResult> register(
    String username,
    String email,
    String password,
  );
  Future<AccountProfile> verifyEmail(String token);
  Future<AccountActionNotice> resendVerification(String identifier);
  Future<AccountActionNotice> requestPasswordReset(String email);
  Future<AccountProfile> completePasswordReset(String token, String password);
  Future<AccountProfile> changePassword(String current, String next);
  Future<AccountProfile> logout();
}

enum AccountNotice {
  emailVerified,
  passwordChanged,
  accountCreatedVerify,
  emailSent,
  passwordResetSent,
}

final class AccountActionNotice {
  const new({this.remote = '', this.client});

  final String remote;
  final AccountNotice? client;
}

final class AccountRegistrationResult {
  const new({required this.verificationRequired, required this.notice});

  final bool verificationRequired;
  final AccountActionNotice notice;
}
