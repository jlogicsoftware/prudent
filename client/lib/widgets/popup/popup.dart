import 'package:flutter/material.dart';
import 'package:prudent/utils.dart';

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
              isMobile(context)
                  ? showModalBottomSheet(
                    isScrollControlled: true,
                    useSafeArea: true,
                    context: context,
                    builder: (ctx) => popupBody,
                    constraints: const BoxConstraints.expand(),
                  )
                  : showDialog(
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
                  ),
    );
  }
}
