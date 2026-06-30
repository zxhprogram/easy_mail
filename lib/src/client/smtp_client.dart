import 'dart:async';
import 'dart:convert';

import 'package:dart_mail_kit/src/client/mail_socket.dart';
import 'package:dart_mail_kit/src/models/mail_address.dart';
import 'package:dart_mail_kit/src/security/authenticator.dart';
import 'package:dart_mail_kit/src/security/tls_options.dart';

/// Result of a successful SMTP delivery.
class SmtpResponse {
  final int code;
  final String message;
  const SmtpResponse(this.code, this.message);

  bool get isSuccess => code >= 200 && code < 400;

  @override
  String toString() => 'SmtpResponse($code $message)';
}

/// SMTP client with keep-alive support for batched delivery. Takes an
/// injectable [MailSocket] so protocol logic can be unit-tested.
class SmtpClient {
  final String host;
  final int port;
  final TlsOptions tlsOptions;
  final MailSocket? socketFactory;

  MailSocket? _socket;
  LineReader? _reader;
  final _extensions = <String>{};
  bool _greeted = false;

  SmtpClient({
    required this.host,
    required this.port,
    this.tlsOptions = TlsOptions.secureImplicit,
    this.socketFactory,
  });

  Set<String> get extensions => Set.unmodifiable(_extensions);

  /// Connects, reads the greeting and issues EHLO.
  Future<void> connect() async {
    final s =
        socketFactory ?? await IoMailSocket.connect(host, port, tlsOptions);
    _socket = s;
    _reader = LineReader(s)..start();
    final greeting = await _readResponse();
    if (!greeting.isSuccess) {
      throw SmtpException('Bad greeting: ${greeting.message}');
    }
    if (tlsOptions.startTls && !tlsOptions.implicitTls) {
      await _ehlo();
      await _startTls();
    }
    await _ehlo();
    _greeted = true;
  }

  Future<void> _ehlo() async {
    await _socket!.writeLine('EHLO $host');
    final res = await _readResponseMulti();
    if (!res.last.isSuccess) {
      // Fallback to HELO.
      await _socket!.writeLine('HELO $host');
      await _readResponseMulti();
      return;
    }
    for (final line in res) {
      // `message` is the text after the "NNN " or "NNN-" prefix, e.g.
      // "SIZE 35882577" or "AUTH LOGIN PLAIN". The first token is the
      // extension keyword.
      final keyword = line.message.split(RegExp(r'\s+')).first.toUpperCase();
      if (keyword.isNotEmpty) _extensions.add(keyword);
    }
  }

  Future<void> _startTls() async {
    await _socket!.writeLine('STARTTLS');
    final res = await _readResponse();
    if (!res.isSuccess) {
      throw SmtpException('STARTTLS rejected: ${res.message}');
    }
    await _socket!.upgradeToTls(tlsOptions);
    _reader = LineReader(_socket!)..start();
  }

  /// Authenticates with the given SASL [authenticator].
  Future<void> authenticate(Authenticator authenticator) async {
    await _socket!.writeLine('AUTH ${authenticator.mechanismName}'
        '${authenticator.hasInitialResponse ? ' ${authenticator.initialResponse()}' : ''}');
    var res = await _readResponse();
    if (res.code == 235) return; // accepted immediately
    while (res.code == 334) {
      final challenge = _decodeBase64(res.message);
      final answer = authenticator.respondToChallenge(challenge);
      await _socket!.writeLine(answer);
      res = await _readResponse();
    }
    if (res.code != 235) {
      throw SmtpException('Auth failed: ${res.message}');
    }
  }

  /// Sends a raw RFC 5322 message to [recipients] from [from]. Honors
  /// keep-alive: the socket stays open so subsequent sends reuse the same
  /// connection.
  Future<SmtpResponse> send({
    required MailAddress from,
    required List<MailAddress> recipients,
    required String rawMessage,
  }) async {
    if (!_greeted) {
      throw StateError('SmtpClient.connect() must be called first');
    }
    await _socket!.writeLine('MAIL FROM:<${from.address}>');
    var res = await _readResponse();
    if (!res.isSuccess) {
      throw SmtpException('MAIL FROM rejected: ${res.message}');
    }
    for (final rcpt in recipients) {
      await _socket!.writeLine('RCPT TO:<${rcpt.address}>');
      res = await _readResponse();
      if (!res.isSuccess) {
        throw SmtpException('RCPT TO ${rcpt.address} rejected: ${res.message}');
      }
    }
    await _socket!.writeLine('DATA');
    res = await _readResponse();
    if (res.code != 354) {
      throw SmtpException('DATA rejected: ${res.message}');
    }
    await _socket!.write(utf8.encode(_dotStuff(rawMessage)));
    await _socket!.write(const [0x2E, 0x0D, 0x0A]); // terminating ".\r\n"
    final finalRes = await _readResponse();
    if (!finalRes.isSuccess) {
      throw SmtpException('Delivery failed: ${finalRes.message}');
    }
    return finalRes;
  }

  /// Sends QUIT and closes the transport.
  Future<void> quit() async {
    if (_socket != null && !_socket!.isClosed) {
      try {
        await _socket!.writeLine('QUIT');
        await _readResponse();
      } catch (_) {
        // Best effort.
      }
      await _socket!.close();
    }
    _greeted = false;
  }

  // --- helpers -----------------------------------------------------------

  static String _dotStuff(String message) {
    final normalized =
        message.replaceAll(RegExp(r'\r\n'), '\n').replaceAll('\n', '\r\n');
    // Dot-stuffing: any line starting with '.' gets an extra leading '.'.
    return normalized.replaceAllMapped(
      RegExp(r'^(\.)', multiLine: true),
      (m) => '.${m.group(1)}',
    );
  }

  static String _decodeBase64(String text) {
    try {
      return utf8.decode(base64.decode(text.trim()));
    } on FormatException {
      return text;
    }
  }

  Future<SmtpResponse> _readResponse() async {
    final lines = await _readResponseMulti();
    return lines.last;
  }

  Future<List<SmtpResponse>> _readResponseMulti() async {
    final lines = <SmtpResponse>[];
    while (true) {
      final line = await _reader!.readLine();
      if (line.isEmpty) break;
      final res = _parse(line);
      lines.add(res);
      // A multi-line response ends with a space after the code; continuation
      // uses a dash.
      if (line.length >= 4 && line[3] == ' ') break;
      if (line.length < 4) break;
    }
    return lines;
  }

  SmtpResponse _parse(String line) {
    final code = int.tryParse(line.substring(0, 3)) ?? 0;
    final message = line.length > 4 ? line.substring(4) : '';
    return SmtpResponse(code, message);
  }
}

/// Exception thrown for SMTP protocol errors.
class SmtpException implements Exception {
  final String message;
  SmtpException(this.message);
  @override
  String toString() => 'SmtpException: $message';
}
