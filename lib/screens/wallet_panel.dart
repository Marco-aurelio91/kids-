import 'package:flutter/material.dart';

import '../util.dart';

/// Carteira em R$: potes, metas, mesada e extrato. Usada no modo pais e no modo filho.
/// O dinheiro real é entregue pelos responsáveis (PIX/espécie); o app mantém o controle.
class WalletPanel extends StatefulWidget {
  final Map<String, dynamic> child;
  final bool parentMode;
  const WalletPanel({super.key, required this.child, required this.parentMode});

  @override
  State<WalletPanel> createState() => _WalletPanelState();
}

class _W {
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> tx;
  final List<Map<String, dynamic>> goals;
  final Map<String, dynamic>? allowance;
  _W(this.wallet, this.tx, this.goals, this.allowance);

  int saved(String goalId) => tx
      .where((t) => t['goal_id'] == goalId && t['pot'] == 'save')
      .fold(0, (s, t) => s + (t['amount_cents'] as int));
}

class _WalletPanelState extends State<WalletPanel> {
  late Future<_W> _future = _load();
  String get _id => widget.child['id'];

  Future<_W> _load() async {
    final wallet = await db.from('child_wallet').select().eq('child_id', _id).single();
    final tx = await db
        .from('wallet_transactions')
        .select()
        .eq('child_id', _id)
        .order('created_at', ascending: false)
        .limit(200);
    final goals = await db.from('savings_goals').select().eq('child_id', _id).order('created_at');
    final al = await db.from('allowances').select().eq('child_id', _id).maybeSingle();
    return _W(wallet, tx, goals, al);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<void> Function() f) async {
    if (await guard(context, f)) _reload();
  }

  Future<void> _newGoal() async {
    final title = await askText(context, 'Qual é o seu sonho?', label: 'Ex.: Bicicleta nova');
    if (title == null || title.isEmpty || !mounted) return;
    final target = await askMoney(context, 'Quanto custa?');
    if (target == null) return;
    await _run(() => db
        .from('savings_goals')
        .insert({'child_id': _id, 'title': title, 'target_cents': target}));
  }

  Future<void> _transfer(_W w) async {
    final balances = {
      'spend': w.wallet['spend_cents'] as int,
      'save': w.wallet['save_cents'] as int,
      'give': w.wallet['give_cents'] as int,
    };
    var from = 'spend';
    var to = 'save';
    String? goalId;
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Mover dinheiro'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: from,
              decoration: const InputDecoration(labelText: 'De'),
              items: [
                for (final e in pots.entries)
                  DropdownMenuItem(
                      value: e.key, child: Text('${e.value} (${brl(balances[e.key]!)})')),
              ],
              onChanged: (v) => setS(() => from = v!),
            ),
            DropdownButtonFormField<String>(
              initialValue: 'save',
              decoration: const InputDecoration(labelText: 'Para'),
              items: [
                for (final e in pots.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
                for (final g in w.goals)
                  DropdownMenuItem(value: 'goal:${g['id']}', child: Text('🎯 Meta: ${g['title']}')),
              ],
              onChanged: (v) => setS(() {
                if (v!.startsWith('goal:')) {
                  to = 'save';
                  goalId = v.substring(5);
                } else {
                  to = v;
                  goalId = null;
                }
              }),
            ),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor em R\$'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mover')),
          ],
        ),
      ),
    );
    final cents = parseBrl(amount.text);
    if (ok != true || cents == null || cents <= 0) return;
    await _run(() => db.rpc('transfer_money', params: {
          'p_child': _id,
          'p_from': from,
          'p_to': to,
          'p_cents': cents,
          'p_goal': goalId,
        }));
  }

  Future<void> _bonus() async {
    final desc = await askText(context, 'Bônus', label: 'Motivo (ex.: Nota 10)');
    if (desc == null || !mounted) return;
    final cents = await askMoney(context, 'Valor do bônus');
    if (cents == null) return;
    await _run(() => db.from('wallet_transactions').insert({
          'child_id': _id,
          'pot': 'spend',
          'kind': 'bonus',
          'amount_cents': cents,
          'description': desc.isEmpty ? 'Bônus' : desc,
        }));
  }

  Future<void> _payout() async {
    final pot = await pick<String>(context, 'Pagar de qual pote?', pots);
    if (pot == null || !mounted) return;
    final cents = await askMoney(context, 'Valor entregue (PIX ou dinheiro)');
    if (cents == null) return;
    await _run(() => db.rpc('payout_money', params: {
          'p_child': _id,
          'p_pot': pot,
          'p_cents': cents,
          'p_desc': 'Pagamento',
        }));
  }

  Future<void> _allowance() async {
    final cents = await askMoney(context, 'Valor da mesada');
    if (cents == null || !mounted) return;
    final freq = await pick<String>(
        context, 'Frequência', {'weekly': 'Toda semana', 'monthly': 'Todo mês'});
    if (freq == null || !mounted) return;
    final first = await showDatePicker(
      context: context,
      helpText: 'Primeiro pagamento',
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (first == null) return;
    await _run(() async {
      await db.from('allowances').upsert({
        'child_id': _id,
        'amount_cents': cents,
        'frequency': freq,
        'next_due': first.toIso8601String().substring(0, 10),
        'active': true,
      }, onConflict: 'child_id');
      await db.rpc('apply_allowances');
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_W>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final w = snap.data!;
        final cs = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Text('Saldo total'),
                  Text(brl(w.wallet['total_cents']),
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    for (final e in pots.entries)
                      Column(children: [
                        Text(e.value),
                        Text(brl(w.wallet['${e.key}_cents']),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: () => _transfer(w),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Mover dinheiro')),
              OutlinedButton.icon(
                  onPressed: _newGoal,
                  icon: const Icon(Icons.flag),
                  label: const Text('Nova meta')),
              if (widget.parentMode) ...[
                OutlinedButton.icon(
                    onPressed: _bonus,
                    icon: const Icon(Icons.add),
                    label: const Text('Bônus')),
                OutlinedButton.icon(
                    onPressed: _payout,
                    icon: const Icon(Icons.payments),
                    label: const Text('Registrar pagamento')),
                OutlinedButton.icon(
                    onPressed: _allowance,
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Mesada')),
              ],
            ]),
            if (w.allowance != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '📅 Mesada: ${brl(w.allowance!['amount_cents'])} '
                  '${w.allowance!['frequency'] == 'weekly' ? 'por semana' : 'por mês'} '
                  '· próxima em ${shortDate(w.allowance!['next_due'])}',
                ),
              ),
            if (w.goals.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('🎯 Metas', style: Theme.of(context).textTheme.titleLarge),
              for (final g in w.goals) _goalTile(g, w),
            ],
            const SizedBox(height: 20),
            Text('Extrato', style: Theme.of(context).textTheme.titleLarge),
            if (w.tx.isEmpty) const Text('Nenhuma movimentação ainda.'),
            for (final t in w.tx)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(_kindIcon(t['kind']), style: const TextStyle(fontSize: 22)),
                title: Text(t['description'] == '' ? _kindName(t['kind']) : t['description']),
                subtitle: Text('${shortDate(t['created_at'])} · ${pots[t['pot']]}'),
                trailing: Text(
                  '${(t['amount_cents'] as int) > 0 ? '+' : ''}${brl(t['amount_cents'])}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (t['amount_cents'] as int) > 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _goalTile(Map<String, dynamic> g, _W w) {
    final saved = w.saved(g['id']);
    final target = g['target_cents'] as int;
    final done = saved >= target;
    return Card(
      child: ListTile(
        onLongPress: widget.parentMode
            ? () => _run(() => db.from('savings_goals').delete().eq('id', g['id']))
            : null,
        leading: Text(g['icon'], style: const TextStyle(fontSize: 28)),
        title: Text(g['title']),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 6),
          LinearProgressIndicator(value: (saved / target).clamp(0, 1).toDouble()),
          const SizedBox(height: 4),
          Text(done
              ? '🎉 Meta alcançada! ${brl(saved)}'
              : '${brl(saved)} de ${brl(target)}'),
        ]),
      ),
    );
  }

  String _kindIcon(String k) => switch (k) {
        'task' => '✅',
        'allowance' => '📅',
        'bonus' => '🎁',
        'transfer' => '🔄',
        _ => '💵',
      };

  String _kindName(String k) => switch (k) {
        'task' => 'Tarefa',
        'allowance' => 'Mesada',
        'bonus' => 'Bônus',
        'transfer' => 'Transferência',
        _ => 'Pagamento',
      };
}
