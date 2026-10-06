import 'package:equatable/equatable.dart';

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
