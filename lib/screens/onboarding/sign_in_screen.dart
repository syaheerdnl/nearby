import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/app_mark.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _signUp = false;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthProvider>();
    setState(() => _info = null);
    if (_signUp) {
      final info = await auth.signUp(
        email: _email.text,
        password: _password.text,
        username: _username.text,
      );
      if (!mounted) return;
      if (info != null) {
        setState(() {
          _info = info;
          _signUp = false;
        });
      }
    } else {
      await auth.signIn(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                        alignment: Alignment.centerLeft, child: AppMark()),
                    const SizedBox(height: 20),
                    Text(_signUp ? 'Create your account' : 'Sign in to Nearby',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        'Reminders that go off when you reach a place, '
                        'not at a set time.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    if (_signUp) ...[
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          helperText: '3 to 20 lowercase letters, numbers or _',
                        ),
                        autocorrect: false,
                        validator: (v) => AuthProvider.usernamePattern
                                .hasMatch((v ?? '').trim().toLowerCase())
                            ? null
                            : 'Use 3 to 20 lowercase letters, numbers or _',
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (v) => (v ?? '').contains('@')
                          ? null
                          : 'Enter a valid email',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) => (v ?? '').length >= 8
                          ? null
                          : 'At least 8 characters',
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    if (auth.error != null)
                      Text(auth.error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    if (_info != null)
                      Text(_info!,
                          style: TextStyle(color: theme.colorScheme.primary)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () {
                              auth.clearError();
                              setState(() {
                                _signUp = !_signUp;
                                _info = null;
                              });
                            },
                      child: Text(_signUp
                          ? 'Have an account? Sign in'
                          : 'New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
