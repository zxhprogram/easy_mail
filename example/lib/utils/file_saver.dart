import 'dart:io';

import 'package:easy_mail/easy_mail.dart';
import 'package:path_provider/path_provider.dart';

class FileSaver {
  static Future<String> saveAttachment(Attachment attachment) async {
    final directory = await getDownloadsDirectory();
    if (directory == null) {
      throw StateError('Could not locate downloads directory');
    }
    final path = '${directory.path}/${attachment.fileName}';
    final file = File(path);
    await file.writeAsBytes(attachment.bytes);
    return path;
  }
}
