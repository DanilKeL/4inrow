import 'dart:math';

import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/data/account_datasource.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final class AccountRepository {
  new({required this._datasource, required this._preferences});

  static const _guestKey = 'four-cubed-guest-name';
  final AccountDatasource _datasource;
  final SharedPreferences _preferences;

  String get guestName {
    final String? stored = _preferences.getString(_guestKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final String value = 'Guest_${Random.secure().nextInt(900000) + 100000}';
    _preferences.setString(_guestKey, value);
    return value;
  }

  Future<AccountProfile> load() async {
    try {
      return _profileFromJson(await _datasource.profile());
    } on Object {
      return AccountProfile(username: null, guestName: guestName);
    }
  }

  Future<AccountProfile> login(String username, String password) async {
    await _datasource.login(username: username, password: password);
    return _profileFromJson(await _datasource.profile());
  }

  Future<AccountRegistrationResult> register(
    String username,
    String email,
    String password,
  ) async {
    late final Map<String, dynamic> json;
    try {
      json = await _datasource.register(
        username: username,
        email: email,
        password: password,
      );
    } on RestClientException catch (error) {
      // The account already exists when delivery of the verification email
      // fails. The web client treats that response as a completed registration
      // and offers the resend action instead of leaving the user on the form.
      if (error.data?['verificationRequired'] == true) {
        return AccountRegistrationResult(
          verificationRequired: true,
          notice: AccountActionNotice(remote: error.message),
        );
      }
      rethrow;
    }
    final bool verificationRequired = json['verificationRequired'] == true;
    final Object? remoteNotice = json['message'] ?? json['error'];
    return AccountRegistrationResult(
      verificationRequired: verificationRequired,
      notice: verificationRequired
          ? remoteNotice == null
                ? const AccountActionNotice(
                    client: AccountNotice.accountCreatedVerify,
                  )
                : AccountActionNotice(remote: remoteNotice.toString())
          : const AccountActionNotice(),
    );
  }

  Future<AccountProfile> verifyEmail(String token) async {
    await _datasource.verifyEmail(token: token);
    return _profileFromJson(await _datasource.profile());
  }

  Future<AccountActionNotice> resendVerification(String identifier) async {
    final Map<String, dynamic> json = await _datasource.resendVerification(
      identifier: identifier,
    );
    final String? message = json['message']?.toString();
    return message == null
        ? const AccountActionNotice(client: AccountNotice.emailSent)
        : AccountActionNotice(remote: message);
  }

  Future<AccountActionNotice> requestPasswordReset(String email) async {
    final Map<String, dynamic> json = await _datasource.requestPasswordReset(
      email: email,
    );
    final String? message = json['message']?.toString();
    return message == null
        ? const AccountActionNotice(client: AccountNotice.passwordResetSent)
        : AccountActionNotice(remote: message);
  }

  Future<AccountProfile> completePasswordReset(
    String token,
    String password,
  ) async {
    await _datasource.completePasswordReset(token: token, password: password);
    return _profileFromJson(await _datasource.profile());
  }

  Future<AccountProfile> changePassword(String current, String next) async {
    await _datasource.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    return _profileFromJson(await _datasource.profile());
  }

  Future<AccountProfile> logout() async =>
      _profileFromJson(await _datasource.logout());

  AccountProfile _profileFromJson(Map<String, dynamic> json) {
    final String? remoteGuest = json['guestName']?.toString();
    if (remoteGuest != null && remoteGuest.isNotEmpty) {
      _preferences.setString(_guestKey, remoteGuest);
    }
    return AccountProfile(
      username: json['username']?.toString(),
      guestName: remoteGuest ?? guestName,
      email: json['email']?.toString(),
      emailVerified: json['emailVerified'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}
