import 'dart:convert';

import 'package:four3/src/common/preferences/preferences_datasource_tool.dart';
import 'package:four3/src/feature/match_history/domain/model/match_history_models.dart';

abstract interface class MatchHistoryPreferencesDatasource {
  const new();

  List<PendingMatch> loadPending();
  Future<void> savePending(List<PendingMatch> matches);
}

final class MatchHistoryPreferencesDatasource$Preferences
    implements MatchHistoryPreferencesDatasource {
  const new({required this.preferencesDatasourceTool});

  final PreferencesDatasourceTool preferencesDatasourceTool;
  static const String _key = 'four-cubed-match-outbox-v1';

  @override
  List<PendingMatch> loadPending() {
    final String? value = preferencesDatasourceTool.getString(_key);
    if (value == null) return <PendingMatch>[];
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! List) return <PendingMatch>[];
      final List<PendingMatch> result = <PendingMatch>[];
      for (final Object? item in decoded.skip(
        decoded.length > 100 ? decoded.length - 100 : 0,
      )) {
        if (item is! Map) continue;
        try {
          result.add(PendingMatch.fromJson(Map<String, dynamic>.from(item)));
        } on Object {
          // One damaged entry must not discard the rest of the outbox.
        }
      }
      return result;
    } on Object {
      return <PendingMatch>[];
    }
  }

  @override
  Future<void> savePending(List<PendingMatch> matches) {
    final List<PendingMatch> limited = matches.length <= 100
        ? matches
        : matches.sublist(matches.length - 100);
    return preferencesDatasourceTool.setString(
      _key,
      jsonEncode(<Map<String, Object>>[
        for (final PendingMatch match in limited) match.toJson(),
      ]),
    );
  }
}
