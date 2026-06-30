import 'dart:convert';

import 'package:dart_mail_kit/src/models/attachment.dart';
import 'package:dart_mail_kit/src/parser/charset_decoder.dart';

/// Disposition of a MIME part per RFC 2183.
enum ContentDisposition { inline, attachment, unknown }

/// A node in the MIME tree produced by [MimeParser].
///
/// Immutable in the sense that all fields are final; the [children] list is
/// unmodifiable. Raw body bytes are kept for leaf parts so that callers can
/// either decode text or stream them out as an attachment.
class MimePart {
  /// Lower-cased header name -> raw (still possibly RFC 2047 encoded) value.
  final Map<String, String> headers;

  /// Child parts for `multipart/*` parts. Empty for leaf parts.
  final List<MimePart> children;

  /// Raw decoded body bytes for leaf parts (Base64/Quoted-Printable already
  /// reversed). `null` for multipart parts.
  final List<int>? body;

  /// Dotted path identifying this part within the message, e.g. "1.2".
  final String partId;

  const MimePart({
    required this.headers,
    this.children = const [],
    this.body,
    this.partId = '',
  });

  /// Value of the `Content-Type` header, defaulting to `text/plain`.
  String get contentType => headers['content-type']?.toLowerCase() ?? 'text/plain';

  /// Primary type, e.g. `text`, `multipart`, `application`.
  String get mainType => _splitType(0);

  /// Subtype, e.g. `plain`, `mixed`, `pdf`.
  String get subType => _splitType(1);

  String _splitType(int index) {
    final ct = headers['content-type'] ?? 'text/plain';
    final semi = ct.indexOf(';');
    final head = (semi == -1 ? ct : ct.substring(0, semi)).trim().toLowerCase();
    final parts = head.split('/');
    return parts.length > index ? parts[index] : '';
  }

  /// Parsed parameters of the `Content-Type` header (charset, boundary, name).
  Map<String, String> get contentTypeParameters => _parseParams(headers['content-type']);

  /// Parsed parameters of the `Content-Disposition` header.
  Map<String, String> get contentDispositionParameters =>
      _parseParams(headers['content-disposition']);

  String get charset =>
      (contentTypeParameters['charset'] ?? 'us-ascii').toLowerCase();

  String? get boundary => contentTypeParameters['boundary'];

  ContentDisposition get disposition {
    final raw = (headers['content-disposition'] ?? '').toLowerCase();
    if (raw.startsWith('attachment')) return ContentDisposition.attachment;
    if (raw.startsWith('inline')) return ContentDisposition.inline;
    return ContentDisposition.unknown;
  }

  /// Decoded file name from either disposition `filename` or type `name`.
  String? get fileName {
    final raw = contentDispositionParameters['filename'] ??
        contentTypeParameters['name'];
    if (raw == null) return null;
    return CharsetDecoder.instance.decodeHeader(raw);
  }

  /// Decoded text body for `text/*` leaf parts.
  String get decodedText {
    final bytes = body ?? const <int>[];
    return CharsetDecoder.instance.decodeBytes(bytes, charset);
  }

  /// Whether this part should be treated as an attachment.
  bool get isAttachment {
    if (disposition == ContentDisposition.attachment) return true;
    // Parts with a filename or non-text content are attachments.
    if (fileName != null && fileName!.isNotEmpty) return true;
    if (mainType != 'text' && mainType != 'multipart') return true;
    return false;
  }

  /// Convenience view of this part as an [Attachment].
  Attachment toAttachment() => Attachment(
        partId: partId,
        fileName: fileName ?? 'untitled',
        mimeType: contentType.split(';').first.trim(),
        size: body?.length ?? 0,
        charset: charset,
        disposition: disposition,
        bytes: body ?? const <int>[],
      );

  Map<String, dynamic> toJson() => {
        'headers': Map<String, String>.from(headers),
        'children': children.map((e) => e.toJson()).toList(),
        'body': body == null ? null : base64Encode(body!),
        'partId': partId,
      };

  factory MimePart.fromJson(Map<String, dynamic> json) {
    final bodyRaw = json['body'] as String?;
    return MimePart(
      headers: Map<String, String>.from(json['headers'] as Map? ?? const {}),
      children: (json['children'] as List<dynamic>? ?? [])
          .map((e) => MimePart.fromJson(e as Map<String, dynamic>))
          .toList(),
      body: bodyRaw == null ? null : base64Decode(bodyRaw),
      partId: json['partId'] as String? ?? '',
    );
  }

  static Map<String, String> _parseParams(String? header) {
    final result = <String, String>{};
    if (header == null) return result;
    final semi = header.indexOf(';');
    if (semi == -1) return result;
    final params = header.substring(semi + 1);
    final regex = RegExp(r'([\w-]+)\s*=\s*"([^"]*)"|([\w-]+)\s*=\s*([^;]+)');
    for (final m in regex.allMatches(params)) {
      final key = (m.group(1) ?? m.group(3))!.toLowerCase();
      final value = m.group(2) ?? m.group(4) ?? '';
      result[key] = value.trim();
    }
    return result;
  }
}
