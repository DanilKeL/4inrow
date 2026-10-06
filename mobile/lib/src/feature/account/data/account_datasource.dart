import 'package:four3/src/common/rest_client/rest_client.dart';

abstract interface class AccountDatasource {
  Future<Map<String, dynamic>> profile();

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  });

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  });

  Future<Map<String, dynamic>> verifyEmail({required String token});

  Future<Map<String, dynamic>> resendVerification({required String identifier});

  Future<Map<String, dynamic>> requestPasswordReset({required String email});

  Future<Map<String, dynamic>> completePasswordReset({
    required String token,
    required String password,
  });

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<Map<String, dynamic>> logout();
}

final class AccountDatasource$RestClient implements AccountDatasource {
  const new({required this._restClient});

  final RestClient _restClient;

  @override
  Future<Map<String, dynamic>> profile() => _restClient.get('/auth/me');

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) => _restClient.post(
    '/auth/login',
    data: <String, Object?>{'username': username, 'password': password},
  );

  @override
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) => _restClient.post(
    '/auth/register',
    data: <String, Object?>{
      'username': username,
      'email': email,
      'password': password,
    },
  );

  @override
  Future<Map<String, dynamic>> verifyEmail({required String token}) =>
      _restClient.post('/auth/verify', data: <String, Object?>{'token': token});

  @override
  Future<Map<String, dynamic>> resendVerification({
    required String identifier,
  }) => _restClient.post(
    '/auth/resend-verification',
    data: <String, Object?>{'identifier': identifier},
  );

  @override
  Future<Map<String, dynamic>> requestPasswordReset({required String email}) =>
      _restClient.post(
        '/auth/password-reset/request',
        data: <String, Object?>{'email': email},
      );

  @override
  Future<Map<String, dynamic>> completePasswordReset({
    required String token,
    required String password,
  }) => _restClient.post(
    '/auth/password-reset/complete',
    data: <String, Object?>{'token': token, 'password': password},
  );

  @override
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _restClient.post(
    '/auth/password/change',
    data: <String, Object?>{
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    },
  );

  @override
  Future<Map<String, dynamic>> logout() => _restClient.post('/auth/logout');
}
