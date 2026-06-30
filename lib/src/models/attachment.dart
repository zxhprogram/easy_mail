import 'dart:async';

import 'package:easy_mail/src/models/mime_part.dart';

/// An immutable description of a decoded attachment, plus a factory that
/// produces a chunked [Stream<List<int>>] so Flutter apps can pipe it straight
/// to an `IOSink` without holding the whole file in memory.
class Attachment {
  final String partId;
  final String fileName;
  final String mimeType;
  final int size;
  final String charset;
  final ContentDisposition disposition;

  /// Source bytes. Kept so callers can re-create the chunk stream or fully
  /// materialize the attachment when memory allows.
  final List<int> bytes;

  const Attachment({
    required this.partId,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.charset,
    required this.disposition,
    required this.bytes,
  });

  /// Chunked byte stream. [chunkSize] controls memory pressure for large
  /// attachments — each emitted event is at most [chunkSize] bytes.
  Stream<List<int>> openRead({int chunkSize = 8 * 1024}) async* {
    if (bytes.isEmpty) return;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end =
          offset + chunkSize > bytes.length ? bytes.length : offset + chunkSize;
      yield bytes.sublist(offset, end);
    }
  }

  Map<String, dynamic> toJson() => {
        'partId': partId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
        'charset': charset,
        'disposition': disposition.name,
        // Body bytes intentionally omitted: attachments may be large and are
        // usually persisted to disk rather than JSON.
      };

  factory Attachment.fromJson(Map<String, dynamic> json) {
    final dispName = json['disposition'] as String? ?? 'unknown';
    ContentDisposition disp;
    switch (dispName) {
      case 'attachment':
        disp = ContentDisposition.attachment;
        break;
      case 'inline':
        disp = ContentDisposition.inline;
        break;
      default:
        disp = ContentDisposition.unknown;
    }
    return Attachment(
      partId: json['partId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'untitled',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      size: json['size'] as int? ?? 0,
      charset: json['charset'] as String? ?? 'us-ascii',
      disposition: disp,
      bytes: const <int>[],
    );
  }

  @override
  String toString() => 'Attachment($fileName, $mimeType, $size bytes)';
}
