import 'dart:async';
import 'dart:isolate';

import 'package:four3/src/feature/game/model/game_models.dart';
import 'package:four3/src/feature/game/service/ai_engine.dart';

final class AiMoveRunner {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  Completer<MoveCandidate?>? _completer;

  Future<MoveCandidate?> run(
    GameSnapshot snapshot,
    Difficulty difficulty, {
    BotOptions options = const BotOptions(),
  }) async {
    cancel();
    final receivePort = ReceivePort();
    final completer = Completer<MoveCandidate?>();
    _receivePort = receivePort;
    _completer = completer;
    receivePort.listen((message) {
      if (!identical(_completer, completer) || completer.isCompleted) return;
      if (message is List<int> && message.length == 2) {
        completer.complete(MoveCandidate(message[0], message[1]));
      } else if (message == null) {
        completer.complete(null);
      } else {
        completer.completeError(StateError(message.toString()));
      }
      _release();
    });
    _isolate = await Isolate.spawn(
      _calculate,
      _AiRequest(receivePort.sendPort, snapshot, difficulty, options),
      onError: receivePort.sendPort,
    );
    return completer.future;
  }

  void cancel() {
    final Completer<MoveCandidate?>? completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const AiMoveCancelled());
    }
    _release();
  }

  void dispose() => cancel();

  void _release() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _completer = null;
  }

  static void _calculate(_AiRequest request) {
    try {
      final MoveCandidate? move = AiEngine.chooseMove(
        request.snapshot,
        request.difficulty,
        options: request.options,
      );
      request.reply.send(move == null ? null : [move.x, move.y]);
    } on Object catch (error) {
      request.reply.send(error.toString());
    }
  }
}

final class _AiRequest {
  const new(this.reply, this.snapshot, this.difficulty, this.options);
  final SendPort reply;
  final GameSnapshot snapshot;
  final Difficulty difficulty;
  final BotOptions options;
}

final class AiMoveCancelled implements Exception {
  const new();

  @override
  String toString() => 'AI move cancelled';
}
