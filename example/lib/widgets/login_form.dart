import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/mail_service.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  String _host = 'imap.qq.com';
  int _port = 993;
  bool _useSsl = true;
  String _protocol = 'imap';
  String _username = '';
  String _password = '';

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final appState = context.read<AppState>();
    final service = context.read<MailService>();
    appState.setLoading(true);
    appState.setError(null);

    try {
      final account = MailAccount(
        host: _host,
        port: _port,
        useSsl: _useSsl,
        protocol: _protocol,
        username: _username,
        password: _password,
      );
      await service.login(account);
      appState.setAccount(account);

      final folders = await service.loadFolders();
      appState.setFolders(folders.isEmpty ? ['INBOX'] : folders);

      final messages = await service.loadMessages(appState.selectedFolder);
      appState.setMessages(messages);
    } catch (e) {
      appState.setError(e.toString());
    } finally {
      appState.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mail Login',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: _host,
                    decoration: const InputDecoration(labelText: 'Server'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                    onSaved: (v) => _host = v!,
                  ),
                  TextFormField(
                    initialValue: _port.toString(),
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                    onSaved: (v) => _port = int.parse(v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _protocol,
                    decoration: const InputDecoration(labelText: 'Protocol'),
                    items: const [
                      DropdownMenuItem(value: 'imap', child: Text('IMAP')),
                      DropdownMenuItem(value: 'pop3', child: Text('POP3')),
                    ],
                    onChanged: (v) => setState(() => _protocol = v!),
                  ),
                  SwitchListTile(
                    title: const Text('Use SSL'),
                    value: _useSsl,
                    onChanged: (v) => setState(() => _useSsl = v),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                    onSaved: (v) => _username = v!,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                    onSaved: (v) => _password = v!,
                  ),
                  if (appState.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        appState.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: appState.isLoading ? null : _login,
                      child: appState.isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
