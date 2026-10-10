import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/automation/automation_id.dart';

/// The [AutomationId] wrapper that carries [id].
Finder findAutomationId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);
