import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/mail_service.dart';

class FolderSidebar extends StatelessWidget {
  const FolderSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Container(
      width: 200,
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
            child:
                Text('Folders', style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: appState.folders.length,
              itemBuilder: (context, index) {
                final folder = appState.folders[index];
                final selected = folder == appState.selectedFolder;
                return ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(folder),
                  onTap: selected
                      ? null
                      : () async {
                          appState.selectFolder(folder);
                          appState.setLoading(true);
                          try {
                            final service = context.read<MailService>();
                            final messages =
                                await service.loadMessages(folder);
                            appState.setMessages(messages);
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
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              final service = context.read<MailService>();
              service.disconnect();
              appState.clear();
            },
          ),
        ],
      ),
    );
  }
}
