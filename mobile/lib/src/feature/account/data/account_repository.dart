import 'dart:math';

import 'package:four3/src/feature/account/data/account_datasource.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AccountRepository {
  new({required this._datasource, required this._preferences});

  static const _guestKey = 'four-cubed-guest-name';
  final AccountDatasource _datasource;
  final SharedPreferences _preferences;

  String get guestName {
    final String? stored = _preferences.getString(_guestKey);
    if (stored != null && RegExp(r'^Гость_\d{6}$').hasMatch(stored)) {
      return stored;
    }
    final String value = 'Гость_${Random.secure().nextInt(900000) + 100000}';
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

  Future<String> register(
    String username,
    String email,
    String password,
  ) async {
    final Map<String, dynamic> json = await _datasource.register(
      username: username,
      email: email,
      password: password,
    );
    return json['message']?.toString() ??
        'Аккаунт создан. Подтвердите email, затем выполните вход.';
  }

  Future<AccountProfile> verifyEmail(String token) async {
    await _datasource.verifyEmail(token: token);
    return _profileFromJson(await _datasource.profile());
  }

  Future<String> resendVerification(String identifier) async {
    final Map<String, dynamic> json = await _datasource.resendVerification(
      identifier: identifier,
    );
    return json['message']?.toString() ?? 'Письмо отправлено.';
  }

  Future<String> requestPasswordReset(String email) async {
    final Map<String, dynamic> json = await _datasource.requestPasswordReset(
      email: email,
    );
    return json['message']?.toString() ??
        'Если аккаунт существует, письмо отправлено.';
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
