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
  const new(this.profile, {this.notice = ''});
  final AccountProfile profile;
  final String notice;
  @override
  List<Object> get props => [profile, notice];
}

final class AccountState$Failure extends AccountState {
  const new(this.profile, this.message);
  final AccountProfile? profile;
  final String message;
  @override
  List<Object?> get props => [profile, message];
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
          final String notice = await _repository.register(
            username.trim(),
            email.trim(),
            password,
          );
          emit(
            AccountState$Ready(
              profile ?? await _repository.load(),
              notice: notice,
            ),
          );
        } on RestClientException catch (error) {
          emit(AccountState$Failure(profile, error.message));
        }
      case AccountEvent$VerifyEmail(:final token):
        await _action(
          emit,
          () => _repository.verifyEmail(token),
          notice: 'Email подтверждён.',
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
  }) async {
    emit(AccountState$Loading(profile));
    try {
      emit(AccountState$Ready(await operation(), notice: notice));
    } on RestClientException catch (error) {
      emit(AccountState$Failure(profile, error.message));
    } on Exception {
      emit(AccountState$Failure(profile, 'Нет связи с сервером.'));
    }
  }
}
