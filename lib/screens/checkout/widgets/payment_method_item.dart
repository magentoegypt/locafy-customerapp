import 'package:flutter/material.dart';

import '../../../common/config.dart';
import '../../../models/index.dart' show PaymentMethod;
import '../../../services/index.dart';
import '../../../widgets/common/flux_image.dart';

class PaymentMethodItem extends StatelessWidget {
  const PaymentMethodItem(
      {Key? key,
      required this.paymentMethod,
      this.onSelected,
      this.selectedId,
      this.descWidget})
      : super(key: key);
  final PaymentMethod paymentMethod;
  final Function(String?)? onSelected;
  final String? selectedId;
  final Widget? descWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        InkWell(
          onTap: () {
            if (onSelected != null) onSelected!(paymentMethod.id);
          },
          child: Container(
            decoration: BoxDecoration(
                color: paymentMethod.id == selectedId
                    ? Theme.of(context).primaryColorLight
                    : Colors.transparent),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
              child: Column(
                children: [
                  Row(
                    children: <Widget>[
                      Radio<String?>(
                          value: paymentMethod.id,
                          groupValue: selectedId,
                          onChanged: onSelected),
                      const SizedBox(width: 10),
                      Expanded(
                        child: kPayments[paymentMethod.id] != null
                            ? Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: FluxImage(
                                  imageUrl: kPayments[paymentMethod.id],
                                  height: 30,
                                ),
                              )
                            : Row(
                                children: <Widget>[
                                  // Leading brand mark so each option reads as
                                  // "logo + name" in checkout. Unmapped codes
                                  // fall back to name only.
                                  ..._buildBrandMark(context, paymentMethod.id),
                                  Expanded(
                                    // Never null-assert the title — a method
                                    // with a missing title degrades to a plain
                                    // name (its code) instead of throwing during
                                    // build and tripping the global ErrorWidget
                                    // (the red "Something went wrong" beside
                                    // COD/Visa in the QA build, 86d3g53f8 #7).
                                    child: Services()
                                        .widget
                                        .renderShippingPaymentTitle(
                                          context,
                                          paymentMethod.title ??
                                              paymentMethod.id ??
                                              '',
                                        ),
                                  ),
                                ],
                              ),
                      )
                    ],
                  ),
                  if (descWidget != null) descWidget!
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1)
      ],
    );
  }

  /// Leading brand mark(s) for a payment method, shown before its name so each
  /// checkout row reads as "logo + name". Keyed by the Magento payment code.
  /// Real card art (Visa/Mastercard) is bundled; COD/BNPL use a representative
  /// glyph until brand logos are supplied. Unknown codes get no mark (name
  /// only), so a new backend method can never break the row.
  List<Widget> _buildBrandMark(BuildContext context, String? id) {
    final color = Theme.of(context).colorScheme.secondary;
    const gap = SizedBox(width: 10);
    switch (id) {
      case 'online': // Secure online payment by Visa / MasterCard
        return [
          Image.asset('assets/icons/credit_cards/visa.png', height: 22),
          const SizedBox(width: 4),
          Image.asset('assets/icons/credit_cards/mastercard.png', height: 22),
          gap,
        ];
      case 'cashondelivery':
        return [Icon(Icons.payments_outlined, size: 24, color: color), gap];
      case 'sympl': // Pay later in installments
        return [
          Icon(Icons.calendar_month_outlined, size: 24, color: color),
          gap
        ];
      case 'aman':
        return [
          Icon(Icons.account_balance_wallet_outlined, size: 24, color: color),
          gap
        ];
      default:
        return const [];
    }
  }
}
