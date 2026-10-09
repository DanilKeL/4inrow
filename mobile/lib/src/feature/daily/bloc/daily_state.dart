import 'package:equatable/equatable.dart';
import 'package:four3/src/feature/daily/domain/model/daily_models.dart';
import 'package:four3/src/feature/daily/domain/repository/daily_repository.dart';

final class DailyState extends Equatable {
  const new({
    this.snapshot,
    this.loading = false,
    this.error = '',
    this.submission,
  });

  final DailySnapshot? snapshot;
  final bool loading;
  final String error;
  final DailySubmission? submission;

  DailyState copyWith({
    DailySnapshot? snapshot,
    bool? loading,
    String? error,
    DailySubmission? submission,
    bool clearSubmission = false,
  }) => DailyState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    submission: clearSubmission ? null : submission ?? this.submission,
  );

  @override
  List<Object?> get props => <Object?>[
    snapshot,
    loading,
    error,
    submission?.status,
    submission?.id,
    submission?.snapshot,
    submission?.message,
    submission?.retryable,
  ];
}
