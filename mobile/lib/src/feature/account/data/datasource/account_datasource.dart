abstract interface class AccountDatasource {
  const new();

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
