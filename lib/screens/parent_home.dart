import 'package:flutter/material.dart';

import '../pin.dart';
import '../util.dart';
import 'child_detail.dart';
import 'child_mode.dart';
import 'parent_money.dart';

class ParentHome extends StatefulWidget {
  const ParentHome({super.key});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Credita mesadas vencidas ao abrir o app.
    db.rpc('apply_allowances').then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _ChildrenTab(),
      const _ApprovalsTab(),
      const MoneyTab(),
      const ReportsTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Kids'),
        actions: [
          IconButton(
            tooltip: 'Prêmios',
            icon: const Icon(Icons.card_giftcard),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RewardsScreen())),
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.child_care), label: 'Filhos'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'Aprovações'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Dinheiro'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Relatório'),
        ],
      ),
    );
  }
}

// ---------- Filhos ----------

class _ChildrenTab extends StatefulWidget {
  const _ChildrenTab();

  @override
  State<_ChildrenTab> createState() => _ChildrenTabState();
}

class _ChildrenTabState extends State<_ChildrenTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final kids = await db.from('children').select().order('created_at');
    final pts = await db.from('child_points').select();
    final wal = await db.from('child_wallet').select();
    final p = {for (final x in pts) x['child_id']: x['points']};
    final w = {for (final x in wal) x['child_id']: x['total_cents']};
    return [
      for (final k in kids) {...k, 'points': p[k['id']] ?? 0, 'cents': w[k['id']] ?? 0}
    ];
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _add() async {
    final name = await askText(context, 'Novo filho(a)');
    if (name == null || name.isEmpty || !mounted) return;
    final avatar = await pick<String>(context, 'Escolha um avatar', {for (final a in avatars) a: a});
    if (!mounted) return;
    final ok = await guard(context, () async {
      await db.from('children').insert({'name': name, 'avatar': avatar ?? '🙂'});
    });
    if (ok) _reload();
  }

  Future<void> _openChildMode(Map<String, dynamic> child) async {
    if (!await Pin.ensureSet(context) || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChildMode(child: child)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final kids = snap.data!;
          if (kids.isEmpty) {
            return const Center(child: Text('Adicione o primeiro filho(a) no botão +'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(children: [
              for (final k in kids)
                ListTile(
                  leading: Text(k['avatar'], style: const TextStyle(fontSize: 32)),
                  title: Text(k['name']),
                  subtitle: Text('⭐ ${k['points']} pontos · ${brl(k['cents'])}'),
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ChildDetail(child: k)));
                    _reload();
                  },
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => _openChildMode(k),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Modo filho'),
                  ),
                ),
            ]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}

// ---------- Aprovações ----------

class _ApprovalsTab extends StatefulWidget {
  const _ApprovalsTab();

  @override
  State<_ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<_ApprovalsTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => db
      .from('task_completions')
      .select('id, day, children(name, avatar), tasks(title, icon, points, reward_cents)')
      .eq('status', 'pending')
      .order('completed_at');

  Future<void> _decide(String id, String status) async {
    final ok = await guard(context, () async {
      await db.from('task_completions').update({'status': status}).eq('id', id);
    });
    if (ok) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('Nada para aprovar 🎉'));
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(children: [
            for (final i in items)
              ListTile(
                leading: Text(i['tasks']['icon'], style: const TextStyle(fontSize: 28)),
                title: Text(i['tasks']['title']),
                subtitle: Text('${i['children']['avatar']} ${i['children']['name']} · '
                    '+${i['tasks']['points']} pts'
                    '${(i['tasks']['reward_cents'] as int) > 0 ? ' · +${brl(i['tasks']['reward_cents'])}' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Reprovar',
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _decide(i['id'], 'rejected')),
                  IconButton(
                      tooltip: 'Aprovar',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _decide(i['id'], 'approved')),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

// ---------- Prêmios (resgatados com pontos) ----------

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => db.from('rewards').select().order('cost');

  Future<void> _add() async {
    final title = await askText(context, 'Novo prêmio', label: 'Ex.: 30 min de videogame');
    if (title == null || title.isEmpty || !mounted) return;
    final cost = await askText(context, 'Custo em pontos',
        label: 'Pontos', keyboard: TextInputType.number);
    final n = int.tryParse(cost ?? '');
    if (n == null || n <= 0 || !mounted) return;
    final ok = await guard(context, () async {
      await db.from('rewards').insert({'title': title, 'cost': n});
    });
    if (ok) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prêmios')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('Crie o primeiro prêmio no +'));
          return ListView(children: [
            for (final r in items)
              ListTile(
                leading: Text(r['icon'], style: const TextStyle(fontSize: 28)),
                title: Text(r['title']),
                subtitle: Text('⭐ ${r['cost']} pontos'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await guard(context, () async {
                      await db.from('rewards').delete().eq('id', r['id']);
                    });
                    setState(() => _future = _load());
                  },
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
