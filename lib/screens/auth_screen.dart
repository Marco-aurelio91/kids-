import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login e cadastro dos responsáveis.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _loading = false;
  bool _hide = true;

  void _msg(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(email: _email.text.trim(), password: _password.text);
        if (res.session == null) _msg('Conta criada! Confirme seu e-mail para entrar.');
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      _msg(e.message);
    } catch (_) {
      _msg('Sem conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return _msg('Digite seu e-mail primeiro.');
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _msg('Enviamos um link para redefinir sua senha.');
    } on AuthException catch (e) {
      _msg(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primaryContainer, cs.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🏠', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 8),
                        Text('App Kids', style: Theme.of(context).textTheme.headlineMedium),
                        Text(
                          _signUp ? 'Crie a conta da família' : 'Área dos responsáveis',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder()),
                          validator: (v) =>
                              (v ?? '').contains('@') ? null : 'Informe um e-mail válido',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _hide,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                          validator: (v) =>
                              (v ?? '').length >= 6 ? null : 'Mínimo de 6 caracteres',
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_signUp ? 'Criar conta' : 'Entrar'),
                          ),
                        ),
                        if (!_signUp)
                          TextButton(onPressed: _forgot, child: const Text('Esqueci minha senha')),
                        TextButton(
                          onPressed: () => setState(() => _signUp = !_signUp),
                          child: Text(_signUp
                              ? 'Já tenho conta'
                              : 'Sou responsável e quero criar uma conta'),
                        ),
                        if (_signUp)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'O cadastro é feito apenas por pais ou responsáveis. '
                              'Os dados das crianças ficam protegidos e visíveis só para a sua família.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
