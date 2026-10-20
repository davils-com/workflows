import 'package:davils_ci_fw_ui/davils_ci_fw_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the label', (tester) async {
    await tester.pumpWidget(const LabelView());
    expect(find.text('davils-ci'), findsOneWidget);
  });
}
