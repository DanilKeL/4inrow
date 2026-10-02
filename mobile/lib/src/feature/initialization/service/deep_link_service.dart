import 'dart:async';

import 'package:app_links/app_links.dart';

final class DeepLinkService {
  final AppLinks _links = AppLinks();
  final StreamController<Uri> _controller = StreamController.broadcast();
  StreamSubscription<Uri>? _subscription;
  Uri? _initialLink;

  Stream<Uri> get links => _controller.stream;

  Uri? takeInitialLink() {
    final Uri? value = _initialLink;
    _initialLink = null;
    return value;
  }

  Future<void> start() async {
    _initialLink = await _links.getInitialLink();
    _subscription = _links.uriLinkStream.listen(_controller.add);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
