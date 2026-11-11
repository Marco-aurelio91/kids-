import 'package:flutter_test/flutter_test.dart';

import 'package:app_kids/main.dart';

void main() {
  testWidgets('sem chave do Supabase mostra aviso', (tester) async {
    await tester.pumpWidget(const KidsApp());
    expect(find.textContaining('Falta a chave'), findsOneWidget);
  });
}
