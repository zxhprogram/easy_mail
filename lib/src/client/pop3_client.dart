import 'dart:async';

import 'package:easy_mail/src/client/mail_socket.dart';
import 'package:easy_mail/src/security/tls_options.dart';

/// Lightweight POP3 client. Returns raw RFC 5322 messages that can be fed to
/// [MimeParser] for parsing.
class Pop3Client {
  final String host;
  final int port;
  final TlsOptions tlsOptions;
  final MailSocket? socketFactory;

  MailSocket? _socket;
  LineReader? _reader;

  Pop3Client({
    required this.host,
    required this.port,
    this.tlsOptions = TlsOptions.secureImplicit,
    this.socketFactory,
  });

  /// Connects and reads the greeting.
  Future<void> connect() async {
    final s =
        socketFactory ?? await IoMailSocket.connect(host, port, tlsOptions);
    _socket = s;
    _reader = LineReader(s)..start();
    final greeting = await _readLine();
    if (!greeting.startsWith('+OK')) {
      throw Pop3Exception('Bad greeting: $greeting');
    }
    if (tlsOptions.startTls && !tlsOptions.implicitTls) {
      await _stls();
    }
  }

  Future<void> _stls() async {
    await _socket!.writeLine('STLS');
    final res = await _readLine();
    if (!res.startsWith('+OK')) {
      throw Pop3Exception('STLS rejected: $res');
    }
    await _socket!.upgradeToTls(tlsOptions);
    _reader = LineReader(_socket!)..start();
  }

  /// Authenticates with plain USER / PASS.
  Future<void> login(String username, String password) async {
    await _socket!.writeLine('USER $username');
    var res = await _readLine();
    if (!res.startsWith('+OK')) {
      throw Pop3Exception('USER rejected: $res');
    }
    await _socket!.writeLine('PASS $password');
    res = await _readLine();
    if (!res.startsWith('+OK')) {
      throw Pop3Exception('PASS rejected: $res');
    }
  }

  /// Returns (messageCount, totalSizeInOctets).
  Future<({int count, int size})> stat() async {
    await _socket!.writeLine('STAT');
    final res = await _readLine();
    if (!res.startsWith('+OK')) {
      throw Pop3Exception('STAT rejected: $res');
    }
    final parts = res.substring(3).trim().split(RegExp(r'\s+'));
    return (
      count: int.parse(parts[0]),
      size: int.parse(parts[1]),
    );
  }

  /// Lists messages: map of message-number -> size in octets.
  Future<Map<int, int>> list({int? messageNumber}) async {
    await _socket!
        .writeLine(messageNumber == null ? 'LIST' : 'LIST $messageNumber');
    final first = await _readLine();
    if (!first.startsWith('+OK')) {
      throw Pop3Exception('LIST rejected: $first');
    }
    final result = <int, int>{};
    if (messageNumber != null) {
      final parts = first.substring(3).trim().split(RegExp(r'\s+'));
      result[int.parse(parts[0])] = int.parse(parts[1]);
      return result;
    }
    // Multi-line response, terminated by "."
    while (true) {
      final line = await _reader!.readLine();
      if (line == '.') break;
      if (line.isEmpty && _reader!.isDone) break;
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        result[int.parse(parts[0])] = int.parse(parts[1]);
      }
    }
    return result;
  }

  /// Retrieves the raw RFC 5322 message for [messageNumber].
  Future<String> retrieve(int messageNumber) async {
    await _socket!.writeLine('RETR $messageNumber');
    final first = await _readLine();
    if (!first.startsWith('+OK')) {
      throw Pop3Exception('RETR rejected: $first');
    }
    final lines = <String>[];
    while (true) {
      final line = await _reader!.readLine();
      if (line == '.') break;
      // End of stream without a terminator.
      if (line.isEmpty && _reader!.isDone) break;
      // Dot-destuffing: a leading ".." -> ".".
      final destuffed = line.startsWith('..') ? line.substring(1) : line;
      lines.add(destuffed);
    }
    return lines.join('\r\n');
  }

  /// Marks [messageNumber] for deletion. The server applies deletions on QUIT.
  Future<void> delete(int messageNumber) async {
    await _socket!.writeLine('DELE $messageNumber');
    final res = await _readLine();
    if (!res.startsWith('+OK')) {
      throw Pop3Exception('DELE rejected: $res');
    }
  }

  /// Sends QUIT and closes the transport.
  Future<void> quit() async {
    if (_socket != null && !_socket!.isClosed) {
      try {
        await _socket!.writeLine('QUIT');
        await _readLine();
      } catch (_) {
        // Best effort.
      }
      await _socket!.close();
    }
  }

  Future<String> _readLine() => _reader!.readLine();
}

/// Exception thrown for POP3 protocol errors.
class Pop3Exception implements Exception {
  final String message;
  Pop3Exception(this.message);
  @override
  String toString() => 'Pop3Exception: $message';
}
