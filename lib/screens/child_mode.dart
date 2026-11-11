import 'package:flutter/material.dart';

import '../pin.dart';
import '../util.dart';
import 'learn.dart';
import 'wallet_panel.dart';

const periodLabels = {
  'morning': '🌅 Manhã',
  'afternoon': '☀️ Tarde',
  'night': '🌙 Noite',
};

/// Tela do filho. A saída para a área dos pais é protegida por PIN.
class ChildMode extends StatefulWidget {
  final Map<String, dynamic> child;
  const ChildMode({super.key, required this.child});

  @override
  State<ChildMode> createState() => _ChildModeState();
}

class _ChildModeState extends State<ChildMode> {
  int _tab = 0;

  Future<void> _exit() async {
    if (await Pin.verify(context) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    final pages = [
      _TodayTab(child: c),
      WalletPanel(child: c, parentMode: false),
      LearnTab(child: c),
      _RewardsTab(child: c),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Oi, ${c['name']}! ${c['avatar']}'),
          actions: [
            IconButton(
                tooltip: 'Área dos pais', icon: const Icon(Icons.lock), onPressed: _exit),
          ],
        ),
        body: pages[_tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today), label: 'Hoje'),
            NavigationDestination(icon: Icon(Icons.savings), label: 'Carteira'),
            NavigationDestination(icon: Icon(Icons.school), label: 'Aprender'),
            NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'Prêmios'),
          ],
        ),
      ),
    );
  }
}

// ---------- Hoje ----------

class _Today {
  final List<Map<String, dynamic>> routines;
  final Map<String, String> status;
  final int points;
  final int streak;
  _Today(this.routines, this.status, this.points, this.streak);
}

class _TodayTab extends StatefulWidget {
  final Map<String, dynamic> child;
  const _TodayTab({required this.child});

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  late Future<_Today> _future = _load();
  String get _id => widget.child['id'];

  Future<_Today> _load() async {
    final routines = await db.from('routines').select('*, tasks(*)').eq('child_id', _id);
    final since = DateTime.now().subtract(const Duration(days: 60)).toIso8601String().substring(0, 10);
    final recent = await db
        .from('task_completions')
        .select('task_id, status, day')
        .eq('child_id', _id)
        .gte('day', since);
    final t = today();
    final status = {
      for (final r in recent)
        if (r['day'] == t) r['task_id'] as String: r['status'] as String
    };
    final pts = await db.from('child_points').select().eq('child_id', _id).single();
    return _Today(routines, status, pts['points'] as int, _streak(recent));
  }

  /// Dias seguidos com ao menos uma tarefa aprovada (hoje ainda pode estar em aberto).
  int _streak(List<Map<String, dynamic>> recent) {
    final days = {
      for (final r in recent)
        if (r['status'] == 'approved') r['day'] as String
    };
    var d = DateTime.now();
    String f(DateTime x) => x.toIso8601String().substring(0, 10);
    if (!days.contains(f(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(f(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  Future<void> _complete(String taskId) async {
    final ok = await guard(context, () async {
      await db.from('task_completions').insert({'task_id': taskId, 'child_id': _id});
    });
    if (ok) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Today>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final weekday = DateTime.now().weekday;
        final cs = Theme.of(context).colorScheme;
        int total = 0, finished = 0;
        final sections = <Widget>[];
        for (final r in d.routines) {
          final tasks = [
            for (final t in (r['tasks'] as List))
              if (t['active'] == true && (t['weekdays'] as List).contains(weekday)) t
          ];
          if (tasks.isEmpty) continue;
          sections.add(Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text('${r['title']}  ${periodLabels[r['period']]}',
                style: Theme.of(context).textTheme.titleLarge),
          ));
          for (final t in tasks) {
            total++;
            final st = d.status[t['id']];
            if (st == 'approved') finished++;
            sections.add(_taskCard(t, st));
          }
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: _stat('⭐', '${d.points}', 'pontos', cs.primaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                  child: _stat('🔥', '${d.streak}', d.streak == 1 ? 'dia seguido' : 'dias seguidos',
                      cs.tertiaryContainer)),
            ]),
            if (total > 0) ...[
              const SizedBox(height: 16),
              Text('Hoje: $finished de $total concluídas'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  value: finished / total),
            ],
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Nenhuma tarefa para hoje 🎈')),
              ),
            ...sections,
          ]),
        );
      },
    );
  }

  Widget _stat(String icon, String value, String label, Color color) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ]),
        ),
      );

  Widget _taskCard(Map<String, dynamic> t, String? st) {
    final cents = t['reward_cents'] as int;
    final reward = [
      '+${t['points']} pts',
      if (cents > 0) '+${brl(cents)}',
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Text(t['icon'], style: const TextStyle(fontSize: 28)),
        title: Text(t['title']),
        subtitle: Text(switch (st) {
          'pending' => 'Aguardando os pais ⏳',
          'approved' => 'Feito! ✅',
          'rejected' => 'Vamos tentar de novo 🔁',
          _ => reward,
        }),
        trailing: st != null
            ? null
            : FilledButton(onPressed: () => _complete(t['id']), child: const Text('Fiz!')),
      ),
    );
  }
}

// ---------- Prêmios ----------

class _RewardsTab extends StatefulWidget {
  final Map<String, dynamic> child;
  const _RewardsTab({required this.child});

  @override
  State<_RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<_RewardsTab> {
  late Future<(int, List<Map<String, dynamic>>)> _future = _load();

  Future<(int, List<Map<String, dynamic>>)> _load() async {
    final pts = await db.from('child_points').select().eq('child_id', widget.child['id']).single();
    final rewards = await db.from('rewards').select().order('cost');
    return (pts['points'] as int, List<Map<String, dynamic>>.from(rewards));
  }

  Future<void> _redeem(Map<String, dynamic> r, int points) async {
    if (points < (r['cost'] as int)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ainda faltam pontos! Continue assim 💪')));
      return;
    }
    final ok = await guard(context, () async {
      await db.from('redemptions').insert(
          {'child_id': widget.child['id'], 'reward_id': r['id'], 'cost': r['cost']});
    });
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Você resgatou: ${r['title']} 🎉')));
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (points, rewards) = snap.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Você tem ⭐ $points pontos', style: Theme.of(context).textTheme.titleLarge),
          if (rewards.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: Text('Peça para os pais criarem prêmios 🎁')),
            ),
          for (final r in rewards)
            Card(
              child: ListTile(
                leading: Text(r['icon'], style: const TextStyle(fontSize: 28)),
                title: Text(r['title']),
                trailing: FilledButton(
                  onPressed: () => _redeem(r, points),
                  child: Text('⭐ ${r['cost']}'),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
