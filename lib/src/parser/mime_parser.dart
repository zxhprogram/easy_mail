import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:easy_mail/src/models/attachment.dart';
import 'package:easy_mail/src/models/mail_envelope.dart';
import 'package:easy_mail/src/models/mail_message.dart';
import 'package:easy_mail/src/models/mime_part.dart';

/// Streaming + Isolate-friendly MIME (RFC 2045/5322) parser.
///
/// The parser works on raw bytes so that binary attachments survive intact.
/// Heavy parsing can be offloaded to a background isolate via
/// [parseInBackground], keeping the Flutter UI isolate free.
class MimeParser {
  MimeParser._();

  /// Parses a raw RFC 5322 message given as a [String]. The string should be
  /// the original 8-bit text; for messages with binary attachments prefer
  /// [parseBytes] or [parseStream].
  static MailMessage parse(String raw) => parseBytes(raw.codeUnits);

  /// Parses a raw RFC 5322 message given as a byte list.
  static MailMessage parseBytes(List<int> bytes) {
    final root = _parsePart(bytes, '');
    return _buildMessage(root);
  }

  /// Consumes a chunked byte stream and parses the assembled message. Useful
  /// when mail raw data is fetched incrementally; the heavy work can be moved
  /// to a background isolate by awaiting [parseInBackground] instead.
  static Future<MailMessage> parseStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder();
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return parseBytes(builder.toBytes());
  }

  /// Parses a raw message in a background isolate so the UI isolate is not
  /// blocked. Returns an immutable [MailMessage].
  static Future<MailMessage> parseInBackground(String raw) {
    return Isolate.run(() => MimeParser.parse(raw));
  }

  // --- internal ----------------------------------------------------------

  /// Parses a raw RFC 5322 header block (bytes) into a lower-cased header
  /// map, unfolding continuation lines. Exposed for client code that fetches
  /// only message headers.
  static Map<String, String> parseHeaders(List<int> headerBytes) =>
      _parseHeaders(headerBytes);

  static MimePart _parsePart(List<int> bytes, String partId) {
    final sep = _findHeaderBodySeparator(bytes);
    final headerBytes = sep == -1 ? bytes : bytes.sublist(0, sep);
    final bodyBytes = sep == -1
        ? const <int>[]
        : bytes.sublist(sep + _separatorLength(bytes, sep));

    final headers = _parseHeaders(headerBytes);
    final contentType = (headers['content-type'] ?? 'text/plain').toLowerCase();
    final boundary = _extractBoundary(headers['content-type']);
    final isMultipart =
        contentType.startsWith('multipart/') && boundary != null;

    if (isMultipart) {
      final rawChildren = _splitMultipart(bodyBytes, boundary);
      final children = <MimePart>[];
      for (var i = 0; i < rawChildren.length; i++) {
        children.add(_parsePart(rawChildren[i], _childId(partId, i)));
      }
      return MimePart(
        headers: headers,
        children: List.unmodifiable(children),
        body: null,
        partId: partId,
      );
    }

    final cte = (headers['content-transfer-encoding'] ?? '7bit').toLowerCase();
    final decoded = _decodeTransfer(bodyBytes, cte);
    return MimePart(
      headers: headers,
      children: const [],
      body: decoded,
      partId: partId,
    );
  }

  static String _childId(String parentId, int index) {
    final n = index + 1;
    return parentId.isEmpty ? '$n' : '$parentId.$n';
  }

  /// Finds the first blank line separating headers from the body. Returns the
  /// index of the first byte of the separator, or -1 if none.
  static int _findHeaderBodySeparator(List<int> bytes) {
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 0x0A) {
        if (i > 0 && bytes[i - 1] == 0x0D) {
          // \r\n
          if (i + 1 < bytes.length &&
              bytes[i + 1] == 0x0D &&
              i + 2 < bytes.length &&
              bytes[i + 2] == 0x0A) {
            return i - 1; // start of \r\n\r\n
          }
        } else {
          // \n
          if (i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
            return i; // start of \n\n
          }
        }
      }
    }
    return -1;
  }

  static int _separatorLength(List<int> bytes, int sep) {
    if (sep + 3 < bytes.length &&
        bytes[sep] == 0x0D &&
        bytes[sep + 1] == 0x0A &&
        bytes[sep + 2] == 0x0D &&
        bytes[sep + 3] == 0x0A) {
      return 4;
    }
    return 2;
  }

  static Map<String, String> _parseHeaders(List<int> headerBytes) {
    // Headers are 7-bit; latin1 preserves any raw bytes reversibly.
    final text = latin1.decode(headerBytes, allowInvalid: true);
    final lines = text.split(RegExp(r'\r?\n'));
    final headers = <String, String>{};
    final order = <String>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        // Folded continuation: append to the previous header.
        if (order.isEmpty) continue;
        final key = order.last;
        headers[key] = '${headers[key]} ${line.trim()}';
        continue;
      }
      final colon = line.indexOf(':');
      if (colon == -1) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (headers.containsKey(name)) {
        headers[name] = '${headers[name]}, $value';
      } else {
        headers[name] = value;
        order.add(name);
      }
    }
    return headers;
  }

  static String? _extractBoundary(String? contentType) {
    if (contentType == null) return null;
    final m = RegExp(
      r'boundary\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(contentType);
    return m?.group(1)?.trim();
  }

  static List<List<int>> _splitMultipart(List<int> body, String boundary) {
    final dash = '--'.codeUnits;
    final marker = [...dash, ...boundary.codeUnits];
    final closeMarker = [...marker, ...dash];

    final indices = <int>[];
    for (var i = 0; i <= body.length - marker.length; i++) {
      if (_matchesAt(body, i, marker)) {
        indices.add(i);
      }
    }

    final parts = <List<int>>[];
    for (var k = 0; k < indices.length; k++) {
      final start = indices[k];
      final contentStart = start + marker.length;
      // Skip the trailing CRLF after the boundary marker.
      var bodyStart = contentStart;
      while (bodyStart < body.length &&
          (body[bodyStart] == 0x0D || body[bodyStart] == 0x0A)) {
        bodyStart++;
      }
      // Is this the closing marker `--boundary--`?
      if (_matchesAt(body, start, closeMarker)) break;

      final nextStart = k + 1 < indices.length ? indices[k + 1] : body.length;
      var bodyEnd = nextStart;
      // Trim trailing CRLF before the next boundary.
      while (bodyEnd > bodyStart &&
          (body[bodyEnd - 1] == 0x0A || body[bodyEnd - 1] == 0x0D)) {
        bodyEnd--;
      }
      if (bodyEnd > bodyStart) {
        parts.add(body.sublist(bodyStart, bodyEnd));
      } else {
        parts.add(<int>[]);
      }
    }
    return parts;
  }

  static bool _matchesAt(List<int> data, int index, List<int> pattern) {
    if (index + pattern.length > data.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (data[index + i] != pattern[i]) return false;
    }
    return true;
  }

  static List<int> _decodeTransfer(List<int> bytes, String cte) {
    switch (cte.trim()) {
      case 'base64':
        return _decodeBase64Bytes(bytes);
      case 'quoted-printable':
        return _decodeQuotedPrintable(bytes);
      default:
        // 7bit, 8bit, binary, identity
        return List<int>.unmodifiable(bytes);
    }
  }

  static List<int> _decodeBase64Bytes(List<int> bytes) {
    final filtered = <int>[];
    for (final b in bytes) {
      // Keep only base64 alphabet characters.
      if ((b >= 0x41 && b <= 0x5A) ||
          (b >= 0x61 && b <= 0x7A) ||
          (b >= 0x30 && b <= 0x39) ||
          b == 0x2B ||
          b == 0x2F ||
          b == 0x3D) {
        filtered.add(b);
      }
    }
    final s = latin1.decode(filtered, allowInvalid: true);
    try {
      return base64.decode(s);
    } on FormatException {
      // Try padding fix-up.
      final padded = s.padRight((s.length + 3) ~/ 4 * 4, '=');
      try {
        return base64.decode(padded);
      } on FormatException {
        return const <int>[];
      }
    }
  }

  static List<int> _decodeQuotedPrintable(List<int> bytes) {
    final out = <int>[];
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x3D) {
        // '='
        if (i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
          i += 2; // soft line break (\n)
          continue;
        }
        if (i + 2 < bytes.length &&
            bytes[i + 1] == 0x0D &&
            bytes[i + 2] == 0x0A) {
          i += 3; // soft line break (\r\n)
          continue;
        }
        if (i + 2 < bytes.length) {
          final hex = String.fromCharCodes(bytes.sublist(i + 1, i + 3));
          final v = int.tryParse(hex, radix: 16);
          if (v != null) {
            out.add(v);
            i += 3;
            continue;
          }
        }
        out.add(b);
        i++;
      } else {
        out.add(b);
        i++;
      }
    }
    return out;
  }

  // --- message assembly --------------------------------------------------

  static MailMessage _buildMessage(MimePart root) {
    final envelope = MailEnvelope.fromHeaders(root.headers);
    final plain = StringBuffer();
    final html = StringBuffer();
    final attachments = <Attachment>[];
    final inlineImages = <Attachment>[];

    _walk(root, plain, html, attachments, inlineImages);

    return MailMessage(
      envelope: envelope,
      root: root,
      plainTextBody: plain.toString(),
      htmlBody: html.toString(),
      attachments: List.unmodifiable(attachments),
      inlineImages: List.unmodifiable(inlineImages),
      rawHeaders: Map.unmodifiable(root.headers),
      messageId: envelope.messageId,
    );
  }

  static void _walk(
    MimePart part,
    StringBuffer plain,
    StringBuffer html,
    List<Attachment> attachments,
    List<Attachment> inlineImages,
  ) {
    if (part.children.isNotEmpty) {
      for (final child in part.children) {
        _walk(child, plain, html, attachments, inlineImages);
      }
      return;
    }

    // Leaf part.
    if (part.isAttachment) {
      final attachment = part.toAttachment();
      if (part.disposition == ContentDisposition.inline &&
          part.mainType == 'image') {
        inlineImages.add(attachment);
      } else {
        attachments.add(attachment);
      }
      return;
    }

    if (part.mainType == 'text') {
      if (part.subType == 'html' && html.isEmpty) {
        html.write(part.decodedText);
      } else if (part.subType == 'plain' && plain.isEmpty) {
        plain.write(part.decodedText);
      }
    }
  }
}
