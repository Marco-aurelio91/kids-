import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

const avatars = ['🙂', '😎', '🦁', '🐼', '🦊', '🐯', '🐸', '🦄', '🚀', '⚽', '🎨', '🤖'];

const pots = {'spend': '💸 Gastar', 'save': '🐷 Guardar', 'give': '❤️ Doar'};

const categories = {
  'routine': ('🔁', 'Rotina'),
  'chore': ('🧹', 'Tarefa de casa'),
  'study': ('📚', 'Estudo'),
  'activity': ('⚽', 'Atividade'),
};

/// Centavos -> "R$ 1.234,50".
String brl(num cents) {
  final v = cents.abs().round();
  final reais = (v ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final c = (v % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '-' : ''}R\$ $reais,$c';
}

/// "12,50" / "1.200,5" / "12.50" -> centavos.
int? parseBrl(String input) {
  var s = input.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  s = s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s;
  final d = double.tryParse(s);
  if (d == null || d < 0) return null;
  return (d * 100).round();
}

String shortDate(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

String today() => DateTime.now().toIso8601String().substring(0, 10);

Future<String?> askText(BuildContext context, String title,
    {String label = 'Nome', TextInputType? keyboard}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Salvar')),
      ],
    ),
  );
}

/// Pergunta um valor em R$ e devolve centavos (ou null se cancelado/inválido).
Future<int?> askMoney(BuildContext context, String title) async {
  final s = await askText(context, title,
      label: 'Valor em R\$ (ex.: 12,50)',
      keyboard: const TextInputType.numberWithOptions(decimal: true));
  final cents = parseBrl(s ?? '');
  return (cents == null || cents <= 0) ? null : cents;
}

Future<T?> pick<T>(BuildContext context, String title, Map<T, String> options) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(title: Text(title), children: [
      for (final e in options.entries)
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
    ]),
  );
}

/// Executa uma ação e mostra o erro do banco (ex.: "Saldo insuficiente") em vez de falhar calado.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Algo deu errado: $e')));
    }
  }
  return false;
}
