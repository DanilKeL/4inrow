import 'package:equatable/equatable.dart';
import 'package:four3/src/common/rest_client/rest_client.dart';
import 'package:four3/src/feature/account/domain/model/account_profile.dart';
import 'package:four3/src/feature/account/domain/repository/account_repository.dart';

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
