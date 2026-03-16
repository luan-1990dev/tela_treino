// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:tela_treino/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Adicionado o parâmetro obrigatório isFirebaseReady para o teste
    await tester.pumpWidget(const MyApp(isFirebaseReady: true));

    // O teste padrão do Flutter (contador) não se aplica mais ao seu app atual,
    // pois a interface mudou completamente para o sistema de treino.
    // Este arquivo pode ser atualizado futuramente para testar suas novas telas.
  });
}
