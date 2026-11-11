import 'package:flutter/material.dart';

import '../util.dart';
import 'child_mode.dart' show periodLabels;

const _dayNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// Gestão das rotinas e tarefas de um filho.
class ChildDetail extends StatefulWidget {
  final Map<String, dynamic> child;
  const ChildDetail({super.key, required this.child});

  @override
  State<ChildDetail> createState() => _ChildDetailState();
}

class _ChildDetailState extends State<ChildDetail> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => db
      .from('routines')
      .select('*, tasks(*)')
      .eq('child_id', widget.child['id'])
      .order('created_at');

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<void> Function() f) async {
    if (await guard(context, f)) _reload();
  }

  Future<void> _addRoutine() async {
    final title = await askText(context, 'Nova rotina', label: 'Ex.: Antes da escola');
    if (title == null || title.isEmpty || !mounted) return;
    final period = await pick<String>(context, 'Período', periodLabels);
    if (period == null) return;
    await _run(() => db.from('routines').insert(
        {'child_id': widget.child['id'], 'title': title, 'period': period}));
  }

  Future<void> _addTask(String routineId) async {
    final title = TextEditingController();
    final points = TextEditingController(text: '1');
    final money = TextEditingController();
    var category = 'routine';
    var needsApproval = true;
    final days = {1, 2, 3, 4, 5, 6, 7};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nova tarefa'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Tarefa (ex.: Escovar os dentes)')),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final e in categories.entries)
                    DropdownMenuItem(value: e.key, child: Text('${e.value.$1} ${e.value.$2}')),
                ],
                onChanged: (v) => setS(() => category = v!),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: points,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Pontos')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: money,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'R\$ (opcional)')),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preciso aprovar'),
                subtitle: const Text('Tarefas com R\$ sempre exigem aprovação'),
                value: needsApproval,
                onChanged: (v) => setS(() => needsApproval = v),
              ),
              Wrap(spacing: 4, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(_dayNames[i]),
                    selected: days.contains(i + 1),
                    onSelected: (s) => setS(() => s ? days.add(i + 1) : days.remove(i + 1)),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || days.isEmpty) return;
    await _run(() => db.from('tasks').insert({
          'routine_id': routineId,
          'title': title.text.trim(),
          'icon': categories[category]!.$1,
          'category': category,
          'points': int.tryParse(points.text) ?? 1,
          'reward_cents': parseBrl(money.text) ?? 0,
          'needs_approval': needsApproval,
          'weekdays': (days.toList()..sort()),
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.child['avatar']} ${widget.child['name']}')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final routines = snap.data!;
          if (routines.isEmpty) return const Center(child: Text('Crie a primeira rotina no +'));
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            for (final r in routines)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('${r['title']}  ·  ${periodLabels[r['period']]}',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      IconButton(
                          tooltip: 'Adicionar tarefa',
                          icon: const Icon(Icons.add_task),
                          onPressed: () => _addTask(r['id'])),
                      IconButton(
                          tooltip: 'Excluir rotina',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _run(() => db.from('routines').delete().eq('id', r['id']))),
                    ]),
                    for (final t in (r['tasks'] as List))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(t['icon'], style: const TextStyle(fontSize: 22)),
                        title: Text(t['title']),
                        subtitle: Text(categories[t['category']]!.$2),
                        trailing: Text(
                            '⭐ ${t['points']}${(t['reward_cents'] as int) > 0 ? ' · ${brl(t['reward_cents'])}' : ''}'),
                        onLongPress: () =>
                            _run(() => db.from('tasks').delete().eq('id', t['id'])),
                      ),
                    if ((r['tasks'] as List).isEmpty) const Text('Sem tarefas ainda.'),
                  ]),
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRoutine,
        icon: const Icon(Icons.add),
        label: const Text('Rotina'),
      ),
    );
  }
}
