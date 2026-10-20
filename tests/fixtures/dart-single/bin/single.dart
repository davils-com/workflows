import 'package:davils_ci_single/davils_ci_single.dart';

void main(List<String> arguments) {
  if (arguments.contains('--version')) {
    print('1.2.3');
    return;
  }
  print(greet(arguments.isEmpty ? 'world' : arguments.first));
}
