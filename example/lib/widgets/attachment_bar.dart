import 'package:easy_mail/easy_mail.dart';
import 'package:flutter/material.dart';

import '../utils/file_saver.dart';

class AttachmentBar extends StatelessWidget {
  final List<Attachment> attachments;

  const AttachmentBar({super.key, required this.attachments});

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.attach_file, size: 18),
              label: Text('${attachment.fileName} (${attachment.size})'),
              onPressed: () async {
                try {
                  final path = await FileSaver.saveAttachment(attachment);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved to $path')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Save failed: $e')),
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }
}
