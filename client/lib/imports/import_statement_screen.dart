import 'package:flutter/material.dart';

import 'import_preview_screen.dart';
import 'import_upload_step.dart';

/// An import (M6, jlogicsoftware/prudent#74): choose a statement and upload it, review what was
/// found, confirm, and read the result.
///
/// It is ONE page whose two steps are state, not routes. Opened with `showZenDetail`, a wide host
/// makes this page the root route of a side pane, and a root route that is replaced or popped
/// closes the pane; stepping between pages with the navigator would make the pane vanish after
/// "Check statement" (ADR-093). So the upload step hands the new session's id up and this widget
/// swaps in the review, and the review hands "back to import" up to swap the upload step back in.
/// Leaving the page altogether (Back, the result's button, a pane's Close) pops this one route.
class ImportStatementScreen extends StatefulWidget {
  const ImportStatementScreen({super.key});

  @override
  State<ImportStatementScreen> createState() => _ImportStatementScreenState();
}

class _ImportStatementScreenState extends State<ImportStatementScreen> {
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final id = _sessionId;
    if (id == null) {
      return ImportUploadStep(onOpenReview: (sessionId) => setState(() => _sessionId = sessionId));
    }
    return ImportPreviewScreen(
      key: ValueKey(id),
      sessionId: id,
      onBackToImport: () => setState(() => _sessionId = null),
    );
  }
}
