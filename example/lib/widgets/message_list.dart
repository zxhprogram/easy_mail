import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/mail_service.dart';

class MessageList extends StatelessWidget {
  const MessageList({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Container(
      width: 340,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(appState.selectedFolder,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: appState.isLoading && appState.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: appState.messages.length,
                    itemBuilder: (context, index) {
                      final item = appState.messages[index];
                      final envelope = item.envelope;
                      final selected =
                          appState.selectedMessage?.messageId ==
                          envelope.messageId;
                      final from = envelope.from.isEmpty
                          ? 'Unknown'
                          : envelope.from.first.address;
                      final date = envelope.date != null
                          ? dateFormat.format(envelope.date!.toLocal())
                          : '';
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(
                          envelope.subject.isEmpty
                              ? '(No subject)'
                              : envelope.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$from\n$date',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          appState.setLoading(true);
                          try {
                            final service = context.read<MailService>();
                            final message =
                                await service.fetchFullMessage(item);
                            appState.selectMessage(message);
                          } catch (e) {
                            appState.setError(e.toString());
                          } finally {
                            appState.setLoading(false);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
