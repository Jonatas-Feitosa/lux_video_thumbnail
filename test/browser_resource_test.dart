@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'resource_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final check in resourceChecks().entries) {
    test(check.key, check.value, timeout: const Timeout(Duration(seconds: 45)));
  }
}
