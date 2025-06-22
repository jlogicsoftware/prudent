import 'package:flutter/material.dart';
import 'package:prudent/utils.dart';

class Popup extends StatelessWidget {
  const Popup({super.key, required this.icon, required this.popupContent});

  final Icon icon;
  final Widget popupContent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed:
          () =>
              isMobile(context)
                  ? showModalBottomSheet(
                    isScrollControlled: true,
                    useSafeArea: true,
                    context: context,
                    builder: (ctx) => popupContent,
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
                              child: popupContent,
                            ),
                          ),
                        ),
                  ),
    );
  }
}
