import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN dos responsáveis, guardado no aparelho. Protege a saída do modo filho.
class Pin {
  static const _key = 'parent_pin';

  /// Garante que existe um PIN; se não, pede para criar. Retorna false se cancelado.
  static Future<bool> ensureSet(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key) != null) return true;
    if (!context.mounted) return false;
    final pin = await _ask(context, 'Crie um PIN de 4 dígitos para sair do modo filho');
    if (pin == null) return false;
    await prefs.setString(_key, pin);
    return true;
  }

  static Future<bool> verify(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (!context.mounted) return false;
    final pin = await _ask(context, 'PIN dos responsáveis');
    return pin != null && pin == saved;
  }

  static Future<String?> _ask(BuildContext context, String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.length == 4 ? c.text : null),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
