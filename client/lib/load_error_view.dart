import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'l10n/generated/prudent_localizations.dart';

/// What a screen shows in place of its data when loading it failed: a sentence in the user's
/// language saying what could not be loaded, what to try, and a button that tries again.
///
/// The exception is deliberately NOT part of what is shown. Its text is an implementation detail
/// (`ZenTransportError(code: internal_error, …)`), English whatever the user's language, and it
/// reads as a defect in the product rather than as something to act on. It goes to the log
/// instead, where whoever is debugging can find it.
class LoadErrorView extends StatefulWidget {
  const LoadErrorView({
    super.key,
    required this.message,
    required this.error,
    required this.onRetry,
    this.stackTrace,
    this.compact = false,
  });

  /// The localized "Could not load X." sentence.
  final String message;

  /// Logged, never displayed.
  final Object error;
  final StackTrace? stackTrace;

  /// Asks the data source again, typically `ref.invalidate(provider)`.
  final VoidCallback onRetry;

  /// A line inside a section of a screen, rather than the whole body: no icon, left aligned.
  final bool compact;

  @override
  State<LoadErrorView> createState() => _LoadErrorViewState();
}

class _LoadErrorViewState extends State<LoadErrorView> {
  @override
  void initState() {
    super.initState();
    // Once per failure, not once per build: a rebuild must not repeat the line.
    developer.log(
      'Could not load: ${widget.message}',
      name: 'prudent',
      level: 1000,
      error: widget.error,
      stackTrace: widget.stackTrace,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final retry = ZenButton(
      label: t.loadErrorRetry,
      onPressed: widget.onRetry,
      variant: widget.compact ? ZenButtonVariant.text : ZenButtonVariant.secondary,
    );

    if (widget.compact) {
      return Semantics(
        liveRegion: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [Text(widget.message), retry],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(widget.message, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                t.loadErrorHint,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              retry,
            ],
          ),
        ),
      ),
    );
  }
}
