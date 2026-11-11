import 'package:flutter/material.dart';

import '../util.dart';

const _lessonCategories = {
  'financas': '💰 Educação financeira',
  'habitos': '🌱 Bons hábitos',
  'conhecimentos': '🌍 Conhecimentos',
};

/// Lista de aulas com progresso do filho.
class LearnTab extends StatefulWidget {
  final Map<String, dynamic> child;
  const LearnTab({super.key, required this.child});

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  late Future<(List<Map<String, dynamic>>, Map<String, int>)> _future = _load();

  Future<(List<Map<String, dynamic>>, Map<String, int>)> _load() async {
    final lessons = await db.from('lessons').select().order('min_age').order('title');
    final prog = await db
        .from('lesson_progress')
        .select('lesson_id, score_pct')
        .eq('child_id', widget.child['id']);
    return (
      List<Map<String, dynamic>>.from(lessons),
      {for (final p in prog) p['lesson_id'] as String: p['score_pct'] as int},
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (lessons, done) = snap.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final cat in _lessonCategories.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(cat.value, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final l in lessons.where((l) => l['category'] == cat.key))
              Card(
                child: ListTile(
                  leading: Text(l['icon'], style: const TextStyle(fontSize: 30)),
                  title: Text(l['title']),
                  subtitle: Text('A partir de ${l['min_age']} anos · até ${l['points']} pts'),
                  trailing: done.containsKey(l['id'])
                      ? Chip(label: Text('${done[l['id']]}% ✅'))
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => LessonScreen(
                                lesson: l,
                                childId: widget.child['id'],
                                bestScore: done[l['id']])));
                    setState(() => _future = _load());
                  },
                ),
              ),
          ],
        ]);
      },
    );
  }
}

class LessonScreen extends StatefulWidget {
  final Map<String, dynamic> lesson;
  final String childId;
  final int? bestScore;
  const LessonScreen(
      {super.key, required this.lesson, required this.childId, this.bestScore});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late final List quiz = widget.lesson['quiz'] as List;
  late final List<int?> answers = List.filled(quiz.length, null);
  int? _score;

  Future<void> _submit() async {
    var right = 0;
    for (var i = 0; i < quiz.length; i++) {
      if (answers[i] == quiz[i]['answer']) right++;
    }
    final pct = quiz.isEmpty ? 100 : (right * 100 / quiz.length).round();
    setState(() => _score = pct);
    // Mantém a melhor nota.
    if (pct > (widget.bestScore ?? -1)) {
      await guard(context, () async {
        await db.from('lesson_progress').upsert(
          {'child_id': widget.childId, 'lesson_id': widget.lesson['id'], 'score_pct': pct},
          onConflict: 'child_id,lesson_id',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    return Scaffold(
      appBar: AppBar(title: Text('${l['icon']} ${l['title']}')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(l['content'], style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (quiz.isNotEmpty) Text('Vamos testar?', style: Theme.of(context).textTheme.titleLarge),
        for (var i = 0; i < quiz.length; i++) ...[
          const SizedBox(height: 12),
          Text('${i + 1}. ${quiz[i]['q']}', style: Theme.of(context).textTheme.titleMedium),
          RadioGroup<int>(
            groupValue: answers[i],
            onChanged: (v) {
              if (_score == null) setState(() => answers[i] = v);
            },
            child: Column(children: [
              for (var o = 0; o < (quiz[i]['options'] as List).length; o++)
                RadioListTile<int>(
                  value: o,
                  title: Text(quiz[i]['options'][o]),
                  secondary: _score == null
                      ? null
                      : o == quiz[i]['answer']
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (answers[i] == o ? const Icon(Icons.cancel, color: Colors.red) : null),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        if (_score == null)
          FilledButton(
            onPressed: answers.contains(null) ? null : _submit,
            child: const Text('Enviar respostas'),
          )
        else ...[
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _score == 100 ? '🎉 Perfeito! Você acertou tudo!' : 'Você acertou $_score%. Dá para tentar de novo!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        ],
      ]),
    );
  }
}
