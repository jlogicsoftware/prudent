import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';

/// Prudent's own widget — the framework has no equivalent, it is product UI, not framework UI.
///
/// `zenIsDesktop` is the compile-time platform answer (see docs/DECISIONS.md / CLAUDE.md "the
/// two platform mechanisms"), not `Theme.of(context).platform`: the runtime value is wrong for a
/// browser on a phone and can be overridden by a `Theme`.
class Popup extends StatelessWidget {
  const Popup({super.key, required this.popupLeading, required this.popupBody});

  final Widget popupLeading;
  final Widget popupBody;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: popupLeading,
      onPressed:
          () =>
              zenIsDesktop
                  ? showDialog(
                    context: context,
                    builder:
                        (ctx) => Dialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: SizedBox(
                            width: 400,
                            height: 300,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: popupBody,
                            ),
                          ),
                        ),
                  )
                  : showModalBottomSheet(
                    isScrollControlled: true,
                    useSafeArea: true,
                    context: context,
                    builder: (ctx) => popupBody,
                    constraints: const BoxConstraints.expand(),
                  ),
    );
  }
}
