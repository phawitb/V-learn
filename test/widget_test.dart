import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:v_learn/app.dart';
import 'package:v_learn/state/app_state.dart';

void main() {
  testWidgets('Login screen renders when signed out', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final appState = AppState(prefs);
    await appState.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: appState, child: const VLearnApp()),
    );
    await tester.pump();

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });
}
