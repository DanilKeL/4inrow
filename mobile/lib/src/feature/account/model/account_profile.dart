import 'package:equatable/equatable.dart';

final class AccountProfile extends Equatable {
  const new({
    required this.username,
    required this.guestName,
    this.email,
    this.emailVerified = false,
    this.createdAt,
  });

  final String? username;
  final String guestName;
  final String? email;
  final bool emailVerified;
  final int? createdAt;

  String get displayName => username ?? guestName;

  @override
  List<Object?> get props => [
    username,
    guestName,
    email,
    emailVerified,
    createdAt,
  ];
}
