import 'dart:async';

import 'package:app_links/app_links.dart';

final class DeepLinkService {
  final AppLinks _links = AppLinks();
  final StreamController<Uri> _controller = StreamController.broadcast();
  StreamSubscription<Uri>? _subscription;

  Stream<Uri> get links => _controller.stream;

  Future<void> start() async {
    final Uri? initial = await _links.getInitialLink();
    if (initial != null) _controller.add(initial);
    _subscription = _links.uriLinkStream.listen(_controller.add);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
