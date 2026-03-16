import 'dart:async';
import 'dart:io';
import 'package:graphlink_cache_example/generated/client/GraphLinkClient.dart';

class SimpleWebSocketAdapter extends GraphLinkWebSocketAdapter {
  final String url;

  WebSocket? _socket;
  final _controller = StreamController<String>.broadcast();

  SimpleWebSocketAdapter(this.url);

  @override
  Future<void> onConnectionReady() async {
    _socket = await WebSocket.connect(url);
    _socket!.listen(
      (data) => _controller.add(data as String),
      onError: (e) => _controller.addError(e),
      onDone: () => _controller.close(),
    );
  }

  @override
  Stream<String> get onMessageStream => _controller.stream;

  @override
  void sendMessage(String message) {
    _socket?.add(message);
  }

  @override
  void close() {
    _socket?.close();
  }
}
