import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:four3/src/common/rest_client/rest_client.dart';

import 'package:four3/src/feature/account/data/account_repository.dart';
import 'package:four3/src/feature/account/model/account_profile.dart';

sealed class AccountEvent extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class AccountEvent$Load extends AccountEvent {
  const new();
}

final class AccountEvent$Login extends AccountEvent {
  const new(this.username, this.password);
  final String username;
  final String password;
  @override
  List<Object> get props => [username, password];
}

final class AccountEvent$Register extends AccountEvent {
  const new(this.username, this.email, this.password);
  final String username;
  final String email;
  final String password;
  @override
  List<Object> get props => [username, email, password];
}

final class AccountEvent$VerifyEmail extends AccountEvent {
  const new(this.token);
  final String token;
  @override
  List<Object> get props => [token];
}

final class AccountEvent$OpenPasswordReset extends AccountEvent {
  const new(this.token);
  final String token;
  @override
  List<Object> get props => [token];
}

final class AccountEvent$ResendVerification extends AccountEvent {
  const new(this.identifier);
  final String identifier;
  @override
  List<Object> get props => [identifier];
}

final class AccountEvent$RequestPasswordReset extends AccountEvent {
  const new(this.email);
  final String email;
  @override
  List<Object> get props => [email];
}

final class AccountEvent$CompletePasswordReset extends AccountEvent {
  const new(this.token, this.password);
  final String token;
  final String password;
  @override
  List<Object> get props => [token, password];
}

final class AccountEvent$ChangePassword extends AccountEvent {
  const new(this.currentPassword, this.newPassword);
  final String currentPassword;
  final String newPassword;
  @override
  List<Object> get props => [currentPassword, newPassword];
}

final class AccountEvent$Logout extends AccountEvent {
  const new();
}

final class AccountEvent$ClearMessage extends AccountEvent {
  const new();
}

sealed class AccountState extends Equatable {
  const new();
  @override
  List<Object?> get props => const [];
}

final class AccountState$Initial extends AccountState {
  const new();
}

final class AccountState$Loading extends AccountState {
  const new(this.profile);
  final AccountProfile? profile;
  @override
  List<Object?> get props => [profile];
}

final class AccountState$Ready extends AccountState {
  const new(
    this.profile, {
    this.notice = '',
    this.clientNotice,
    this.registrationCompleted = false,
  });
  final AccountProfile profile;
  final String notice;
  final AccountNotice? clientNotice;
  final bool registrationCompleted;
  @override
  List<Object?> get props => [
    profile,
    notice,
    clientNotice,
    registrationCompleted,
  ];
}

final class AccountState$Failure extends AccountState {
  const new(this.profile, this.message, {this.failure});
  final AccountProfile? profile;
  final String message;
  final RestClientFailure? failure;
  @override
  List<Object?> get props => [profile, message, failure];
}

final class AccountState$PasswordReset extends AccountState {
  const new(this.profile, this.token);
  final AccountProfile? profile;
  final String token;
  @override
  List<Object?> get props => [profile, token];
}

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
