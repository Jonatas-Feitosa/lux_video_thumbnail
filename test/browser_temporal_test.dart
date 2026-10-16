@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lux_video_thumbnail_web/lux_video_thumbnail_web.dart';
import 'temporal_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => LuxVideoThumbnailWeb.registerWith());
  for (final check in temporalChecks().entries) {
    test(check.key, check.value, timeout: const Timeout(Duration(seconds: 45)));
  }
}
