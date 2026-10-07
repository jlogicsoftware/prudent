import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../money.dart';

/// One side of a transfer (jlogicsoftware/prudent#32): its amount, and its currency — chosen when
/// the account holds more than one, otherwise just shown. The amount is a magnitude; a transfer's
/// direction is its from/to accounts, never a sign.
class TransferLeg extends StatelessWidget {
  const TransferLeg({
    super.key,
    required this.amountLabel,
    required this.amountController,
    required this.currencyLabel,
    required this.currencies,
    required this.currency,
    required this.onCurrencyChanged,
  });

  final String amountLabel;
  final TextEditingController amountController;
  final String currencyLabel;
  final List<String> currencies;
  final String? currency;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ZenAmountField(
            label: amountLabel,
            controller: amountController,
            maxFractionDigits: minorUnitDigits,
            allowNegative: false,
          ),
        ),
        const SizedBox(width: 12),
        if (currencies.length > 1)
          SizedBox(
            width: 140,
            child: ZenSelect<String>(
              label: currencyLabel,
              items: currencies,
              itemLabel: (code) => code,
              value: currency,
              onChanged: onCurrencyChanged,
            ),
          )
        else
          Padding(padding: const EdgeInsets.only(top: 16), child: Text(currency ?? '')),
      ],
    );
  }
}
