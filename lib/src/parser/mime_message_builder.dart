import 'dart:convert';

import 'package:dart_mail_kit/src/models/mail_address.dart';

/// Fluent builder that assembles an RFC 5322 compliant message as a [String]
/// or a chunked byte [Stream]. Supports plain text, HTML, inline images and
/// file attachments.
///
/// ```
/// final raw = MimeMessageBuilder()
///   .from(MailAddress(address: 'a@x.com'))
///   .to(MailAddress(address: 'b@y.com'))
///   .subject('Hello')
///   .text('Hi there')
///   .html('<p>Hi there</p>')
///   .attach(bytes: fileBytes, fileName: 'doc.pdf', mimeType: 'application/pdf')
///   .build();
/// ```
class MimeMessageBuilder {
  MailAddress? _from;
  final List<MailAddress> _to = [];
  final List<MailAddress> _cc = [];
  final List<MailAddress> _bcc = [];
  String _subject = '';
  String _textBody = '';
  String _htmlBody = '';
  String _messageId = '';
  final List<_AttachmentSpec> _attachments = [];
  final List<_AttachmentSpec> _inline = [];
  final Map<String, String> _extraHeaders = {};

  MimeMessageBuilder from(MailAddress address) {
    _from = address;
    return this;
  }

  MimeMessageBuilder to(MailAddress address) {
    _to.add(address);
    return this;
  }

  MimeMessageBuilder toMany(Iterable<MailAddress> addresses) {
    _to.addAll(addresses);
    return this;
  }

  MimeMessageBuilder cc(MailAddress address) {
    _cc.add(address);
    return this;
  }

  MimeMessageBuilder bcc(MailAddress address) {
    _bcc.add(address);
    return this;
  }

  MimeMessageBuilder subject(String subject) {
    _subject = subject;
    return this;
  }

  MimeMessageBuilder text(String body) {
    _textBody = body;
    return this;
  }

  MimeMessageBuilder html(String body) {
    _htmlBody = body;
    return this;
  }

  MimeMessageBuilder messageId(String id) {
    _messageId = id;
    return this;
  }

  /// Adds a file attachment. Returns the generated `Content-ID` so the caller
  /// can reference it from the HTML body via `cid:`.
  String addInlineImage({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) {
    final cid =
        '<${DateTime.now().microsecondsSinceEpoch}.$fileName@dart_mail_kit>';
    _inline.add(_AttachmentSpec(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      contentId: cid,
      inline: true,
    ));
    return cid;
  }

  MimeMessageBuilder attach({
    required List<int> bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) {
    _attachments.add(_AttachmentSpec(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      contentId: null,
      inline: false,
    ));
    return this;
  }

  /// Adds an arbitrary header (e.g. `In-Reply-To`, `X-Mailer`).
  MimeMessageBuilder header(String name, String value) {
    _extraHeaders[name] = value;
    return this;
  }

  /// Builds the message as a [String]. Binary attachment bytes are base64
  /// encoded, so the result is always valid UTF-8 text.
  String build() {
    final buffer = StringBuffer();
    _writeHeaders(buffer);
    buffer.write(_buildBody());
    return buffer.toString();
  }

  /// Builds the message as a chunked byte stream.
  Stream<List<int>> buildStream() async* {
    final text = build();
    yield utf8.encode(text);
  }

  void _writeHeaders(StringBuffer out) {
    final from = _from;
    if (from != null) {
      out.writeln('From: ${_formatAddress(from)}');
    }
    if (_to.isNotEmpty) {
      out.writeln('To: ${_to.map(_formatAddress).join(', ')}');
    }
    if (_cc.isNotEmpty) {
      out.writeln('Cc: ${_cc.map(_formatAddress).join(', ')}');
    }
    // Bcc is omitted from headers by design.
    out.writeln('Subject: ${_encodeHeader(_subject)}');
    out.writeln('Date: ${_formatDate(DateTime.now().toUtc())}');
    final mid = _messageId.isNotEmpty
        ? _messageId
        : '<${DateTime.now().microsecondsSinceEpoch}@dart_mail_kit>';
    out.writeln('Message-ID: $mid');
    out.writeln('MIME-Version: 1.0');
    _extraHeaders.forEach((name, value) => out.writeln('$name: $value'));
  }

  String _buildBody() {
    final hasText = _textBody.isNotEmpty;
    final hasHtml = _htmlBody.isNotEmpty;
    final hasAttachments = _attachments.isNotEmpty;
    final hasInline = _inline.isNotEmpty;

    if (!hasText && !hasHtml && !hasAttachments && !hasInline) {
      // Empty body.
      return 'Content-Type: text/plain; charset=utf-8\r\n'
          'Content-Transfer-Encoding: 7bit\r\n'
          '\r\n';
    }

    // No attachments: alternative or single part.
    if (!hasAttachments && !hasInline) {
      if (hasText && hasHtml) {
        final boundary = '_alt_${_token()}';
        final b = StringBuffer();
        b.writeln('Content-Type: multipart/alternative; boundary="$boundary"');
        b.writeln();
        b.writeln('--$boundary');
        b.writeln('Content-Type: text/plain; charset=utf-8');
        b.writeln('Content-Transfer-Encoding: base64');
        b.writeln();
        b.writeln(base64.encode(utf8.encode(_textBody)));
        b.writeln('--$boundary');
        b.writeln('Content-Type: text/html; charset=utf-8');
        b.writeln('Content-Transfer-Encoding: base64');
        b.writeln();
        b.writeln(base64.encode(utf8.encode(_htmlBody)));
        b.writeln('--$boundary--');
        return b.toString();
      }
      final body = hasHtml ? _htmlBody : _textBody;
      final subtype = hasHtml ? 'html' : 'plain';
      final b = StringBuffer();
      b.writeln('Content-Type: text/$subtype; charset=utf-8');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln();
      b.writeln(base64.encode(utf8.encode(body)));
      return b.toString();
    }

    // Mixed (with attachments and/or inline images).
    final boundary = '_mixed_${_token()}';
    final b = StringBuffer();
    b.writeln('Content-Type: multipart/mixed; boundary="$boundary"');
    b.writeln();
    b.writeln('--$boundary');

    if (hasText && hasHtml) {
      final altBoundary = '_alt_${_token()}';
      b.writeln('Content-Type: multipart/alternative; boundary="$altBoundary"');
      b.writeln();
      b.writeln('--$altBoundary');
      b.writeln('Content-Type: text/plain; charset=utf-8');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln();
      b.writeln(base64.encode(utf8.encode(_textBody)));
      b.writeln('--$altBoundary');
      b.writeln('Content-Type: text/html; charset=utf-8');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln();
      b.writeln(base64.encode(utf8.encode(_htmlBody)));
      b.writeln('--$altBoundary--');
      b.writeln();
    } else {
      final body = hasHtml ? _htmlBody : _textBody;
      final subtype = hasHtml ? 'html' : 'plain';
      b.writeln('Content-Type: text/$subtype; charset=utf-8');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln();
      b.writeln(base64.encode(utf8.encode(body)));
      b.writeln();
    }

    for (final spec in _inline) {
      b.writeln('--$boundary');
      b.writeln(
          'Content-Type: ${spec.mimeType}; name="${_encodeHeader(spec.fileName)}"');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln(
          'Content-Disposition: inline; filename="${_encodeHeader(spec.fileName)}"');
      b.writeln('Content-ID: ${spec.contentId}');
      b.writeln();
      b.writeln(base64.encode(spec.bytes));
      b.writeln();
    }

    for (final spec in _attachments) {
      b.writeln('--$boundary');
      b.writeln(
          'Content-Type: ${spec.mimeType}; name="${_encodeHeader(spec.fileName)}"');
      b.writeln('Content-Transfer-Encoding: base64');
      b.writeln(
          'Content-Disposition: attachment; filename="${_encodeHeader(spec.fileName)}"');
      b.writeln();
      b.writeln(base64.encode(spec.bytes));
      b.writeln();
    }

    b.writeln('--$boundary--');
    return b.toString();
  }

  static String _formatAddress(MailAddress a) {
    if (a.name.isEmpty) return a.address;
    return '${_encodeHeader(a.name)} <${a.address}>';
  }

  /// RFC 2047 encodes a header value when it contains non-ASCII characters.
  static String _encodeHeader(String value) {
    if (value.codeUnits.every((c) => c < 0x80)) return value;
    final encoded = base64.encode(utf8.encode(value));
    return '=?utf-8?B?$encoded?=';
  }

  static String _formatDate(DateTime utc) {
    // IMF-fixdate, e.g. "Mon, 02 Jan 2006 15:04:05 +0000".
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final local = utc;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[local.weekday - 1]}, ${two(local.day)} ${months[local.month - 1]} '
        '${local.year} ${two(local.hour)}:${two(local.minute)}:${two(local.second)} +0000';
  }

  static String _token() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

class _AttachmentSpec {
  final List<int> bytes;
  final String fileName;
  final String mimeType;
  final String? contentId;
  final bool inline;

  const _AttachmentSpec({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.contentId,
    required this.inline,
  });
}
