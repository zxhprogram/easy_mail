import 'dart:convert';

import 'package:easy_mail/easy_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';

import 'attachment_bar.dart';

class MessageDetail extends StatelessWidget {
  final MailMessage message;

  const MessageDetail({super.key, required this.message});

  String _buildHtml() {
    final html = message.htmlBody.isNotEmpty
        ? message.htmlBody
        : '<pre>${const HtmlEscape().convert(message.plainTextBody)}</pre>';

    // Replace cid: inline images with base64 data URIs.
    var body = html;
    for (final image in message.inlineImages) {
      final cid = image.partId;
      body = body.replaceAll(
        'cid:$cid',
        'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
      );
    }

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 16px; color: #333; }
  img { max-width: 100%; height: auto; }
  blockquote { border-left: 2px solid #ccc; margin-left: 0; padding-left: 12px; color: #666; }
  pre { white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final html = _buildHtml();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.subject.isEmpty ? '(No subject)' : message.subject,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('From: ${message.from.map((a) => a.toString()).join(', ')}'),
              Text('To: ${message.to.map((a) => a.toString()).join(', ')}'),
              if (message.envelope.date != null)
                Text(
                    'Date: ${dateFormat.format(message.envelope.date!.toLocal())}'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: InAppWebView(
            key: ValueKey(message.messageId),
            initialData: InAppWebViewInitialData(data: html),
          ),
        ),
        AttachmentBar(attachments: message.attachments),
      ],
    );
  }
}
