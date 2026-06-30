import 'dart:async';
import 'dart:convert';

import 'package:dart_mail_kit/dart_mail_kit.dart';

/// A scriptable [MailSocket] for unit-testing the protocol clients without a
/// live server. The test feeds server responses via [feed] / [feedBytes] and
/// inspects what the client wrote via [writtenText] / [writtenLines].
///
/// Uses a single-subscription controller so that responses fed before the
/// client subscribes are buffered and delivered in order.
class FakeMailSocket extends MailSocket {
  final _controller = StreamController<List<int>>();
  final List<List<int>> written = [];
  bool _closed = false;
  int _upgradeCalls = 0;

  /// Feeds a UTF-8 string response (use `\r\n` line endings).
  void feed(String data) => _controller.add(utf8.encode(data));

  /// Feeds raw bytes.
  void feedBytes(List<int> data) => _controller.add(data);

  /// Closes the server side of the stream.
  void done() => _controller.close();

  /// Number of times [upgradeToTls] was called.
  int get upgradeCalls => _upgradeCalls;

  @override
  Stream<List<int>> get inputStream => _controller.stream;

  @override
  Future<void> write(List<int> data) async {
    written.add(List<int>.from(data));
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> upgradeToTls(TlsOptions options) async {
    _upgradeCalls++;
  }

  /// All bytes written by the client, decoded as Latin-1 (lossless for the
  /// ASCII protocol commands).
  String get writtenText => written.map(utf8.decode).join();

  /// The written bytes split into logical lines (CRLF stripped).
  List<String> get writtenLines =>
      writtenText.split(RegExp(r'\r\n')).where((l) => l.isNotEmpty).toList();
}
