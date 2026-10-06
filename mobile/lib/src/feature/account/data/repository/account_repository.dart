import 'dart:math';

import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/data/datasource/account_datasource.dart';
import 'package:four3/src/feature/account/data/datasource/account_preferences_datasource.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';

final class AccountRepository$Api implements AccountRepository {
  const new({required this.datasource, required this.preferencesDatasource});

  final AccountDatasource datasource;
  final AccountPreferencesDatasource preferencesDatasource;

  @override
  String get guestName {
    final String? stored = preferencesDatasource.guestName;
    if (stored != null && stored.isNotEmpty) return stored;
    final String value = 'Guest_${Random.secure().nextInt(900000) + 100000}';
    preferencesDatasource.saveGuestName(value).ignore();
    return value;
  }

  @override
  Future<AccountProfile> load() async {
    try {
      return _profileFromJson(await datasource.profile());
    } on Object {
      return AccountProfile(username: null, guestName: guestName);
    }
  }

  @override
  Future<AccountProfile> login(String username, String password) async {
    await datasource.login(username: username, password: password);
    return _profileFromJson(await datasource.profile());
  }

  @override
  Future<AccountRegistrationResult> register(
    String username,
    String email,
    String password,
  ) async {
    late final Map<String, dynamic> json;
    try {
      json = await datasource.register(
        username: username,
        email: email,
        password: password,
      );
    } on RestClientException catch (error) {
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

  @override
  Future<AccountProfile> verifyEmail(String token) async {
    await datasource.verifyEmail(token: token);
    return _profileFromJson(await datasource.profile());
  }

  @override
  Future<AccountActionNotice> resendVerification(String identifier) async {
    final Map<String, dynamic> json = await datasource.resendVerification(
      identifier: identifier,
    );
    final String? message = json['message']?.toString();
    return message == null
        ? const AccountActionNotice(client: AccountNotice.emailSent)
        : AccountActionNotice(remote: message);
  }

  @override
  Future<AccountActionNotice> requestPasswordReset(String email) async {
    final Map<String, dynamic> json = await datasource.requestPasswordReset(
      email: email,
    );
    final String? message = json['message']?.toString();
    return message == null
        ? const AccountActionNotice(client: AccountNotice.passwordResetSent)
        : AccountActionNotice(remote: message);
  }

  @override
  Future<AccountProfile> completePasswordReset(
    String token,
    String password,
  ) async {
    await datasource.completePasswordReset(token: token, password: password);
    return _profileFromJson(await datasource.profile());
  }

  @override
  Future<AccountProfile> changePassword(String current, String next) async {
    await datasource.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    return _profileFromJson(await datasource.profile());
  }

  @override
  Future<AccountProfile> logout() async =>
      _profileFromJson(await datasource.logout());

  AccountProfile _profileFromJson(Map<String, dynamic> json) {
    final String? remoteGuest = json['guestName']?.toString();
    if (remoteGuest != null && remoteGuest.isNotEmpty) {
      preferencesDatasource.saveGuestName(remoteGuest).ignore();
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
