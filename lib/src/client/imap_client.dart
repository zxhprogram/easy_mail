import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_mail/src/client/mail_socket.dart';
import 'package:easy_mail/src/models/connection_state.dart';
import 'package:easy_mail/src/models/mail_envelope.dart';
import 'package:easy_mail/src/models/mail_event.dart';
import 'package:easy_mail/src/models/mail_message.dart';
import 'package:easy_mail/src/parser/mime_parser.dart';
import 'package:easy_mail/src/security/authenticator.dart';
import 'package:easy_mail/src/security/tls_options.dart';

/// Summary of a selected mailbox.
class MailboxInfo {
  final String name;
  final int exists;
  final int recent;
  final int uidValidity;
  final int uidNext;
  final List<String> flags;

  const MailboxInfo({
    required this.name,
    required this.exists,
    required this.recent,
    required this.uidValidity,
    required this.uidNext,
    required this.flags,
  });

  @override
  String toString() =>
      'MailboxInfo($name, exists=$exists, uidValidity=$uidValidity, uidNext=$uidNext)';
}

/// Result of a single tagged IMAP command.
class ImapResponse {
  final String tag;
  final String status; // OK / NO / BAD
  final String message;
  final List<ImapLine> untagged;

  const ImapResponse({
    required this.tag,
    required this.status,
    required this.message,
    required this.untagged,
  });

  bool get isOk => status.toUpperCase() == 'OK';
}

/// A logical response line, possibly carrying one or more string literals.
class ImapLine {
  final String text;
  final List<List<int>> literals;

  const ImapLine(this.text, [this.literals = const []]);

  @override
  String toString() => text;
}

/// IMAP4rev1 client. Uses an injectable [MailSocket] so the protocol logic can
/// be unit-tested with scripted responses.
class ImapClient {
  final String host;
  final int port;
  final TlsOptions tlsOptions;

  /// When provided, this socket is used instead of opening a real connection.
  /// Test code injects a fake here.
  final MailSocket? socketFactory;

  MailSocket? _socket;
  _ByteQueue? _bytes;
  final _stateController =
      StreamController<ImapConnectionState>.broadcast(sync: true);
  int _tagSeq = 0;
  bool _idleActive = false;
  Completer<void>? _idleStop;

  ImapClient({
    required this.host,
    required this.port,
    this.tlsOptions = TlsOptions.secureImplicit,
    this.socketFactory,
  });

  /// Connection lifecycle events.
  Stream<ImapConnectionState> get connectionState => _stateController.stream;

  bool get isConnected => _socket != null && !_socket!.isClosed;

  /// Connects (and optionally upgrades to TLS) and reads the server greeting.
  Future<void> connect() async {
    _stateController.add(ImapConnectionState.connecting);
    final s =
        socketFactory ?? await IoMailSocket.connect(host, port, tlsOptions);
    _socket = s;
    _bytes = _ByteQueue(s);
    if (tlsOptions.startTls && !tlsOptions.implicitTls) {
      await _startTlsUpgrade(s);
    }
    // Read greeting.
    final greeting = await _readLine();
    if (!greeting.text.contains('OK')) {
      throw ImapException('Bad greeting: ${greeting.text}');
    }
    _stateController.add(ImapConnectionState.connected);
  }

  Future<void> _startTlsUpgrade(MailSocket s) async {
    final res = await _sendCommand('STARTTLS');
    if (!res.isOk) {
      throw ImapException('STARTTLS failed: ${res.message}');
    }
    await s.upgradeToTls(tlsOptions);
  }

  /// Authenticates using [authenticator] (SASL) or plain LOGIN when
  /// [password] is given.
  Future<void> login(String username, String password) async {
    final res = await _sendCommand('LOGIN "$username" "$password"');
    if (!res.isOk) {
      throw ImapException('Login failed: ${res.message}');
    }
    _stateController.add(ImapConnectionState.authenticated);
  }

  /// Authenticates via a SASL [authenticator].
  Future<void> authenticate(Authenticator authenticator) async {
    if (authenticator.hasInitialResponse) {
      final res = await _sendCommand(
          'AUTHENTICATE ${authenticator.mechanismName} ${authenticator.initialResponse()}');
      if (!res.isOk) {
        throw ImapException('Auth failed: ${res.message}');
      }
    } else {
      // Two-step: send AUTHENTICATE MECH, then respond to challenge(s).
      final tag = _nextTag();
      await _socket!
          .writeLine('$tag AUTHENTICATE ${authenticator.mechanismName}');
      // First challenge.
      var line = await _readLine();
      while (line.text.startsWith('+')) {
        final decoded = _decodeChallenge(line.text);
        final response = authenticator.respondToChallenge(decoded);
        await _socket!.writeLine(response);
        line = await _readLine();
        if (line.text.startsWith('$tag ')) break;
      }
      if (!line.text.contains('OK')) {
        throw ImapException('Auth failed: ${line.text}');
      }
    }
    _stateController.add(ImapConnectionState.authenticated);
  }

  static String _decodeChallenge(String continuation) {
    // Continuation: "+ <base64>" or "+".
    final payload = continuation.substring(1).trim();
    if (payload.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(payload));
    } on FormatException {
      return payload;
    }
  }

  /// SELECTs [mailbox] and returns its status.
  Future<MailboxInfo> selectMailbox(String mailbox) async {
    final res = await _sendCommand('SELECT "$mailbox"');
    if (!res.isOk) {
      throw ImapException('SELECT failed: ${res.message}');
    }
    var exists = 0;
    var recent = 0;
    var uidValidity = 0;
    var uidNext = 0;
    final flags = <String>[];
    for (final line in res.untagged) {
      final text = line.text;
      final existsMatch = RegExp(r'^\* (\d+) EXISTS').firstMatch(text);
      if (existsMatch != null) {
        exists = int.parse(existsMatch.group(1)!);
        continue;
      }
      final recentMatch = RegExp(r'^\* (\d+) RECENT').firstMatch(text);
      if (recentMatch != null) {
        recent = int.parse(recentMatch.group(1)!);
        continue;
      }
      final uidvalMatch =
          RegExp(r'UIDVALIDITY (\d+)', caseSensitive: false).firstMatch(text);
      if (uidvalMatch != null) {
        uidValidity = int.parse(uidvalMatch.group(1)!);
        continue;
      }
      final uidnextMatch =
          RegExp(r'UIDNEXT (\d+)', caseSensitive: false).firstMatch(text);
      if (uidnextMatch != null) {
        uidNext = int.parse(uidnextMatch.group(1)!);
        continue;
      }
      final flagsMatch = RegExp(r'\* FLAGS \((.*)\)').firstMatch(text);
      if (flagsMatch != null) {
        flags.addAll(flagsMatch
            .group(1)!
            .split(RegExp(r'\s+'))
            .where((s) => s.trim().isNotEmpty));
      }
    }
    _stateController.add(ImapConnectionState.ready);
    return MailboxInfo(
      name: mailbox,
      exists: exists,
      recent: recent,
      uidValidity: uidValidity,
      uidNext: uidNext,
      flags: flags,
    );
  }

  /// LISTs mailboxes under [reference] matching [pattern].
  Future<List<String>> listMailboxes(
      {String reference = '', String pattern = '*'}) async {
    final res = await _sendCommand('LIST "$reference" "$pattern"');
    if (!res.isOk) {
      throw ImapException('LIST failed: ${res.message}');
    }
    final names = <String>[];
    for (final line in res.untagged) {
      final m =
          RegExp(r'\* LIST \([^)]*\) "[^"]*" (.+)$').firstMatch(line.text);
      if (m != null) {
        var name = m.group(1)!.trim();
        if (name.startsWith('"') && name.endsWith('"') && name.length >= 2) {
          name = name.substring(1, name.length - 1);
        }
        names.add(name);
      }
    }
    return names;
  }

  /// SEARCHes with a raw [filter] (e.g. `UNSEEN`). Returns UIDs when
  /// [byUid] is true (default), otherwise sequence numbers.
  Future<List<int>> search({String filter = 'ALL', bool byUid = true}) async {
    final prefix = byUid ? 'UID ' : '';
    final res = await _sendCommand('${prefix}SEARCH $filter');
    if (!res.isOk) {
      throw ImapException('SEARCH failed: ${res.message}');
    }
    for (final line in res.untagged) {
      final m = RegExp(r'\* SEARCH (.*)$').firstMatch(line.text);
      if (m != null) {
        final body = m.group(1)!.trim();
        if (body.isEmpty) return const [];
        return body
            .split(RegExp(r'\s+'))
            .map((s) => int.tryParse(s))
            .whereType<int>()
            .toList();
      }
    }
    return const [];
  }

  /// FETCHes the headers of [uid] and returns the parsed envelope.
  Future<MailEnvelope> fetchEnvelope(int uid) async {
    final res = await _sendCommand('UID FETCH $uid BODY.PEEK[HEADER]');
    if (!res.isOk) {
      throw ImapException('FETCH failed: ${res.message}');
    }
    final headerBytes = _extractLiteral(res);
    if (headerBytes == null) {
      throw ImapException('No header literal in FETCH response');
    }
    final headers = MimeParser.parseHeaders(headerBytes);
    return MailEnvelope.fromHeaders(headers);
  }

  /// FETCHes a body section (e.g. `1`, `1.2`, `TEXT`, `1.MIME`) as bytes.
  Future<List<int>> fetchBodySection(int uid, String section) async {
    final res = await _sendCommand('UID FETCH $uid BODY.PEEK[$section]');
    if (!res.isOk) {
      throw ImapException('FETCH failed: ${res.message}');
    }
    final body = _extractLiteral(res);
    return body ?? const <int>[];
  }

  /// Streams a large attachment body section in chunks so it can be piped to
  /// an [IOSink] without buffering it all in memory.
  Stream<List<int>> fetchAttachmentPayloadStream(
      int uid, String partId) async* {
    final bytes = await fetchBodySection(uid, partId);
    const chunkSize = 8 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end =
          offset + chunkSize > bytes.length ? bytes.length : offset + chunkSize;
      yield bytes.sublist(offset, end);
    }
  }

  /// FETCHes the full RFC822 message and parses it via [MimeParser].
  Future<MailMessage> fetchMessage(int uid) async {
    final res = await _sendCommand('UID FETCH $uid RFC822');
    if (!res.isOk) {
      throw ImapException('FETCH failed: ${res.message}');
    }
    final raw = _extractLiteral(res);
    if (raw == null) {
      throw ImapException('No message literal in FETCH response');
    }
    return MimeParser.parseBytes(raw);
  }

  /// Marks [uid] as seen by storing the `\Seen` flag.
  Future<void> markSeen(int uid) async {
    final res = await _sendCommand('UID STORE $uid +FLAGS.SILENT (\\Seen)');
    if (!res.isOk) {
      throw ImapException('STORE failed: ${res.message}');
    }
  }

  /// Starts IMAP IDLE and emits [MailEvent]s. Cancel the stream subscription
  /// (or call [stopIdle]) to send DONE and stop listening.
  Stream<MailEvent> idle() {
    final controller = StreamController<MailEvent>();
    _idleActive = true;
    _idleStop = Completer<void>();
    Future<void> run() async {
      final tag = _nextTag();
      await _socket!.writeLine('$tag IDLE');
      // Continuation response.
      await _readLine();
      while (_idleActive) {
        // Race the next server line against the stop signal so that
        // [stopIdle] can interrupt an otherwise-blocking read.
        final line = await Future.any<ImapLine>([
          _readLine(),
          _idleStop!.future.then((_) => const ImapLine('')),
        ]);
        if (!_idleActive) break;
        final event = _parseIdleEvent(line.text);
        if (event != null && !controller.isClosed) {
          controller.add(event);
        }
      }
      await _socket!.writeLine('DONE');
      if (!controller.isClosed) await controller.close();
    }

    run();
    return controller.stream;
  }

  /// Stops an active IDLE session.
  Future<void> stopIdle() async {
    _idleActive = false;
    final s = _idleStop;
    if (s != null && !s.isCompleted) {
      s.complete();
    }
  }

  /// LOGOUTs and closes the transport.
  Future<void> disconnect() async {
    _idleActive = false;
    if (_socket != null) {
      try {
        await _sendCommand('LOGOUT');
      } catch (_) {
        // Best effort.
      }
      await _socket!.close();
    }
    _stateController.add(ImapConnectionState.disconnected);
  }

  // --- protocol plumbing -------------------------------------------------

  MailEvent? _parseIdleEvent(String text) {
    final exists = RegExp(r'^\* (\d+) EXISTS').firstMatch(text);
    if (exists != null) {
      return MailEvent(
          type: MailEventType.newMail, sequence: int.parse(exists.group(1)!));
    }
    final expunged = RegExp(r'^\* (\d+) EXPUNGE').firstMatch(text);
    if (expunged != null) {
      return MailEvent(
          type: MailEventType.expunged,
          sequence: int.parse(expunged.group(1)!));
    }
    return null;
  }

  List<int>? _extractLiteral(ImapResponse res) {
    for (final line in res.untagged) {
      if (line.literals.isNotEmpty) return line.literals.first;
    }
    return null;
  }

  String _nextTag() {
    _tagSeq++;
    return 'A$_tagSeq';
  }

  Future<ImapResponse> _sendCommand(String command) async {
    final tag = _nextTag();
    await _socket!.writeLine('$tag $command');
    final untagged = <ImapLine>[];
    while (true) {
      final line = await _readLine();
      if (line.text.startsWith('$tag ') || line.text == tag) {
        final parts = line.text.split(RegExp(r'\s+'));
        final status = parts.length > 1 ? parts[1].toUpperCase() : '';
        final message = parts.length > 2 ? parts.sublist(2).join(' ') : '';
        return ImapResponse(
            tag: tag, status: status, message: message, untagged: untagged);
      }
      untagged.add(line);
    }
  }

  Future<ImapLine> _readLine() async {
    final text = StringBuffer();
    final literals = <List<int>>[];
    while (true) {
      final chunk = await _bytes!.readUntil(const [0x0D, 0x0A]);
      text.write(latin1.decode(chunk, allowInvalid: true));
      final literalMatch = RegExp(r'\{(\d+)\}$').firstMatch(text.toString());
      if (literalMatch == null) {
        return ImapLine(text.toString(), literals);
      }
      final n = int.parse(literalMatch.group(1)!);
      // Strip the `{N}` marker from the text.
      final marker = literalMatch.group(0)!;
      final stripped =
          text.toString().substring(0, text.length - marker.length);
      text.clear();
      text.write(stripped);
      final literal = await _bytes!.read(n);
      literals.add(literal);
      // Loop continues: read the remainder of the line after the literal.
    }
  }
}

/// Exception thrown for IMAP protocol errors.
class ImapException implements Exception {
  final String message;
  ImapException(this.message);
  @override
  String toString() => 'ImapException: $message';
}

/// Awaitable byte queue over a [MailSocket]. Supports reading until a marker
/// sequence or reading a fixed number of bytes — used to parse IMAP responses
/// including string literals.
class _ByteQueue {
  final MailSocket _socket;
  final List<int> _buf = [];
  final _waiters = <Completer<void>>[];
  bool _done = false;

  _ByteQueue(this._socket) {
    _socket.inputStream.listen((chunk) {
      _buf.addAll(chunk);
      _notify();
    }, onDone: () {
      _done = true;
      _notify();
    });
  }

  void _notify() {
    while (_waiters.isNotEmpty) {
      final w = _waiters.removeAt(0);
      if (!w.isCompleted) w.complete();
    }
  }

  Future<void> _waitForData() {
    if (_done) return Future.value();
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  Future<List<int>> read(int n) async {
    while (_buf.length < n && !_done) {
      await _waitForData();
    }
    final take = _buf.length < n ? _buf.length : n;
    final out = _buf.sublist(0, take);
    _buf.removeRange(0, take);
    return out;
  }

  Future<List<int>> readUntil(List<int> marker) async {
    while (true) {
      final idx = _indexOf(_buf, marker);
      if (idx != -1) {
        final out = _buf.sublist(0, idx);
        _buf.removeRange(0, idx + marker.length);
        return out;
      }
      if (_done) {
        final out = List<int>.from(_buf);
        _buf.clear();
        return out;
      }
      await _waitForData();
    }
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    if (needle.isEmpty) return 0;
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
