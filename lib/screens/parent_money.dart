import 'package:flutter/material.dart';

import '../util.dart';
import 'wallet_panel.dart';

/// Lista os filhos com saldo; ao tocar, abre a carteira completa.
class MoneyTab extends StatefulWidget {
  const MoneyTab({super.key});

  @override
  State<MoneyTab> createState() => _MoneyTabState();
}

class _MoneyTabState extends State<MoneyTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final kids = await db.from('children').select().order('created_at');
    final wal = await db.from('child_wallet').select();
    final w = {for (final x in wal) x['child_id']: x['total_cents']};
    return [for (final k in kids) {...k, 'cents': w[k['id']] ?? 0}];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final kids = snap.data!;
        if (kids.isEmpty) return const Center(child: Text('Cadastre um filho primeiro.'));
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aqui você controla mesada, ganhos e metas em R\$. '
                'O dinheiro de verdade é entregue por você (PIX ou espécie) — '
                'registre o pagamento para baixar do saldo.',
              ),
            ),
            for (final k in kids)
              ListTile(
                leading: Text(k['avatar'], style: const TextStyle(fontSize: 32)),
                title: Text(k['name']),
                subtitle: const Text('Toque para ver a carteira'),
                trailing: Text(brl(k['cents']),
                    style: Theme.of(context).textTheme.titleMedium),
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                                appBar: AppBar(title: Text('Carteira de ${k['name']}')),
                                body: WalletPanel(child: k, parentMode: true),
                              )));
                  setState(() => _future = _load());
                },
              ),
          ]),
        );
      },
    );
  }
}

/// Resumo dos últimos 7 dias por filho.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final since = DateTime.now().subtract(const Duration(days: 6));
    final sinceDay = since.toIso8601String().substring(0, 10);
    final sinceTs = DateTime(since.year, since.month, since.day).toUtc().toIso8601String();
    final kids = await db.from('children').select().order('created_at');
    final comps = await db
        .from('task_completions')
        .select('child_id, status')
        .gte('day', sinceDay);
    final earned = await db
        .from('wallet_transactions')
        .select('child_id, amount_cents')
        .inFilter('kind', ['task', 'allowance', 'bonus'])
        .gte('created_at', sinceTs);
    final lessons = await db
        .from('lesson_progress')
        .select('child_id')
        .gte('completed_at', sinceTs);
    return [
      for (final k in kids)
        {
          ...k,
          'approved': comps.where((c) => c['child_id'] == k['id'] && c['status'] == 'approved').length,
          'pending': comps.where((c) => c['child_id'] == k['id'] && c['status'] == 'pending').length,
          'rejected': comps.where((c) => c['child_id'] == k['id'] && c['status'] == 'rejected').length,
          'earned': earned
              .where((e) => e['child_id'] == k['id'])
              .fold<int>(0, (s, e) => s + (e['amount_cents'] as int)),
          'lessons': lessons.where((l) => l['child_id'] == k['id']).length,
        }
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final kids = snap.data!;
        if (kids.isEmpty) return const Center(child: Text('Cadastre um filho primeiro.'));
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Últimos 7 dias', style: Theme.of(context).textTheme.titleLarge),
            for (final k in kids)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${k['avatar']} ${k['name']}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('✅ ${k['approved']} tarefas aprovadas'),
                    Text('⏳ ${k['pending']} aguardando você · 🔁 ${k['rejected']} para refazer'),
                    Text('💰 ${brl(k['earned'])} recebidos (mesada, tarefas, bônus)'),
                    Text('📘 ${k['lessons']} aulas concluídas'),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}
