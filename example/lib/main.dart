import 'package:easy_mail/easy_mail.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'services/mail_service.dart';
import 'widgets/folder_sidebar.dart';
import 'widgets/login_form.dart';
import 'widgets/message_detail.dart';
import 'widgets/message_list.dart';

void main() {
  runApp(const EasyMailExampleApp());
}

class EasyMailExampleApp extends StatelessWidget {
  const EasyMailExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => MailService()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: MaterialApp(
        title: 'easy_mail Example',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.select<AppState, bool>((s) => s.account != null);

    return Scaffold(
      body: account
          ? const Row(
              children: [
                FolderSidebar(),
                MessageList(),
                Expanded(child: DetailPane()),
              ],
            )
          : const LoginForm(),
    );
  }
}

class DetailPane extends StatelessWidget {
  const DetailPane({super.key});

  @override
  Widget build(BuildContext context) {
    final message =
        context.select<AppState, MailMessage?>((s) => s.selectedMessage);

    if (message == null) {
      return const Center(child: Text('Select a message to read'));
    }

    return MessageDetail(message: message);
  }
}
