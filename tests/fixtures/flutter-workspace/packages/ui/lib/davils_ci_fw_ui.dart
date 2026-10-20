/// The Flutter member of the Flutter workspace fixture.
library;

import 'package:davils_ci_fw_core/davils_ci_fw_core.dart';
import 'package:flutter/widgets.dart';

/// Shows the label of the core package.
class LabelView extends StatelessWidget {
  /// Creates the view.
  const LabelView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Text(label, textDirection: TextDirection.ltr);
}
