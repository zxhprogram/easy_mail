import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_mail/src/security/tls_options.dart';

/// Abstraction over the underlying TCP/TLS transport. Injecting a fake
/// implementation lets the protocol clients be unit-tested without a live
/// server, while [IoMailSocket] provides the production `dart:io` socket.
abstract class MailSocket {
  /// Byte stream arriving from the server.
  Stream<List<int>> get inputStream;

  /// Writes raw bytes to the transport.
  Future<void> write(List<int> data);

  /// Writes a line terminated with CRLF.
  Future<void> writeLine(String line) => write(utf8.encode('$line\r\n'));

  /// Closes both directions of the connection.
  Future<void> close();

  /// Whether the transport has been closed.
  bool get isClosed;

  /// Upgrades an already-connected plain socket to TLS via STARTTLS. Only
  /// [IoMailSocket] implements this; fakes throw.
  Future<void> upgradeToTls(TlsOptions options) =>
      throw UnsupportedError('upgradeToTls not supported');
}

/// Production socket backed by `dart:io` [Socket] / [SecureSocket].
///
/// The wrapped socket is held in a mutable field so that [upgradeToTls] can
/// swap the plain socket for a [SecureSocket] while keeping the same
/// [inputStream] for consumers.
class IoMailSocket extends MailSocket {
  Socket _socket;
  bool _closed = false;
  final String host;
  final int port;
  final TlsOptions options;

  IoMailSocket._(this._socket, this.host, this.port, this.options);

  /// Opens a connection to [host]:[port] using [options] for TLS decisions.
  static Future<IoMailSocket> connect(
    String host,
    int port,
    TlsOptions options,
  ) async {
    final Socket socket;
    if (options.implicitTls) {
      socket = await SecureSocket.connect(
        host,
        port,
        context: options.securityContext,
        onBadCertificate: options.allowBadCertificate ? (_) => true : null,
      );
    } else {
      socket = await Socket.connect(host, port);
    }
    return IoMailSocket._(socket, host, port, options);
  }

  @override
  Stream<List<int>> get inputStream => _socket;

  @override
  Future<void> write(List<int> data) => _socket.addStream(Stream.value(data));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> upgradeToTls(TlsOptions options) async {
    final secure = await SecureSocket.secure(
      _socket,
      host: host,
      context: options.securityContext ?? this.options.securityContext,
      onBadCertificate:
          (options.allowBadCertificate || this.options.allowBadCertificate)
              ? (_) => true
              : null,
    );
    _socket = secure;
  }
}

/// A line-buffered reader over a [MailSocket]. Maintains a persistent
/// subscription and an internal line queue so callers can interleave single
/// reads ([readLine]) with multi-line reads without losing lines emitted
/// between subscriptions.
class LineReader {
  final MailSocket socket;
  final List<int> _buf = [];
  final List<String> _lines = [];
  final _waiters = <Completer<String>>[];
  bool _done = false;
  StreamSubscription<List<int>>? _sub;

  LineReader(this.socket);

  /// Starts consuming the socket. Call once after construction.
  void start() {
    _sub = socket.inputStream.listen(
      _onData,
      onDone: () {
        _done = true;
        _flushWaiters();
      },
    );
  }

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    _drainLines();
    _flushWaiters();
  }

  void _drainLines() {
    while (true) {
      var nl = -1;
      for (var i = 0; i < _buf.length; i++) {
        if (_buf[i] == 0x0A) {
          nl = i;
          break;
        }
      }
      if (nl == -1) break;
      var end = nl;
      if (end > 0 && _buf[end - 1] == 0x0D) end--;
      _lines.add(latin1.decode(_buf.sublist(0, end), allowInvalid: true));
      _buf.removeRange(0, nl + 1);
    }
  }

  /// Returns the next logical line (CRLF stripped). Returns an empty string
  /// if the transport closes with no pending data.
  Future<String> readLine() async {
    if (_lines.isNotEmpty) {
      return _lines.removeAt(0);
    }
    if (_done) return '';
    final c = Completer<String>();
    _waiters.add(c);
    return c.future;
  }

  /// Whether the underlying transport has closed.
  bool get isDone => _done;

  void _flushWaiters() {
    while (_waiters.isNotEmpty && _lines.isNotEmpty) {
      final w = _waiters.removeAt(0);
      if (!w.isCompleted) w.complete(_lines.removeAt(0));
    }
    if (_done) {
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete('');
      }
      _waiters.clear();
    }
  }

  Future<void> cancel() async => await _sub?.cancel();
}
