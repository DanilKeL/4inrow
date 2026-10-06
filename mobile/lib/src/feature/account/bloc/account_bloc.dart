import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/bloc/account_event.dart';
import 'package:four3/src/feature/account/bloc/account_state.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';

final class AccountBloc extends Bloc<AccountEvent, AccountState> {
  new({required this._repository}) : super(const AccountState$Initial()) {
    on<AccountEvent>(_onEvent, transformer: sequential());
  }

  final AccountRepository _repository;

  AccountProfile? get profile {
    final AccountState current = state;
    if (current is AccountState$Ready) return current.profile;
    if (current is AccountState$Loading) return current.profile;
    if (current is AccountState$Failure) return current.profile;
    if (current is AccountState$PasswordReset) return current.profile;
    return null;
  }

  Future<void> _onEvent(AccountEvent event, Emitter<AccountState> emit) async {
    switch (event) {
      case AccountEvent$Load():
        emit(AccountState$Loading(profile));
        emit(AccountState$Ready(await _repository.load()));
      case AccountEvent$Login(:final username, :final password):
        await _action(emit, () => _repository.login(username.trim(), password));
      case AccountEvent$Register(
        :final username,
        :final email,
        :final password,
      ):
        emit(AccountState$Loading(profile));
        try {
          final AccountRegistrationResult result = await _repository.register(
            username.trim(),
            email.trim(),
            password,
          );
          emit(
            AccountState$Ready(
              result.verificationRequired
                  ? profile ?? await _repository.load()
                  : await _repository.load(),
              notice: result.notice.remote,
              clientNotice: result.notice.client,
              registrationCompleted: true,
            ),
          );
        } on RestClientException catch (error) {
          emit(
            AccountState$Failure(
              profile,
              error.message,
              failure: error.failure,
            ),
          );
        }
      case AccountEvent$VerifyEmail(:final token):
        await _action(
          emit,
          () => _repository.verifyEmail(token),
          clientNotice: AccountNotice.emailVerified,
        );
      case AccountEvent$OpenPasswordReset(:final token):
        if (token.isNotEmpty) emit(AccountState$PasswordReset(profile, token));
      case AccountEvent$ResendVerification(:final identifier):
        await _noticeAction(
          emit,
          () => _repository.resendVerification(identifier.trim()),
        );
      case AccountEvent$RequestPasswordReset(:final email):
        await _noticeAction(
          emit,
          () => _repository.requestPasswordReset(email.trim()),
        );
      case AccountEvent$CompletePasswordReset(:final token, :final password):
        await _action(
          emit,
          () => _repository.completePasswordReset(token, password),
          clientNotice: AccountNotice.passwordChanged,
        );
      case AccountEvent$ChangePassword(
        :final currentPassword,
        :final newPassword,
      ):
        await _action(
          emit,
          () => _repository.changePassword(currentPassword, newPassword),
          clientNotice: AccountNotice.passwordChanged,
        );
      case AccountEvent$Logout():
        await _action(emit, _repository.logout);
      case AccountEvent$ClearMessage():
        final AccountProfile? current = profile;
        if (current != null) emit(AccountState$Ready(current));
    }
  }

  Future<void> _action(
    Emitter<AccountState> emit,
    Future<AccountProfile> Function() operation, {
    String notice = '',
    AccountNotice? clientNotice,
  }) async {
    emit(AccountState$Loading(profile));
    try {
      emit(
        AccountState$Ready(
          await operation(),
          notice: notice,
          clientNotice: clientNotice,
        ),
      );
    } on RestClientException catch (error) {
      emit(
        AccountState$Failure(profile, error.message, failure: error.failure),
      );
    } on Exception {
      emit(
        AccountState$Failure(profile, '', failure: RestClientFailure.network),
      );
    }
  }

  Future<void> _noticeAction(
    Emitter<AccountState> emit,
    Future<AccountActionNotice> Function() operation,
  ) async {
    emit(AccountState$Loading(profile));
    try {
      final AccountActionNotice notice = await operation();
      emit(
        AccountState$Ready(
          profile ?? await _repository.load(),
          notice: notice.remote,
          clientNotice: notice.client,
        ),
      );
    } on RestClientException catch (error) {
      emit(
        AccountState$Failure(profile, error.message, failure: error.failure),
      );
    } on Exception {
      emit(
        AccountState$Failure(profile, '', failure: RestClientFailure.network),
      );
    }
  }
}
