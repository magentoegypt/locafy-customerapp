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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (kPayments[paymentMethod.id] != null)
                              FluxImage(
                                imageUrl: kPayments[paymentMethod.id],
                                height: 30,
                              ),
                            if (kPayments[paymentMethod.id] == null)
                              // Match the website: show just the payment
                              // method name. Never null-assert the title — a
                              // method with a missing title must degrade to a
                              // plain name (fall back to its code) rather than
                              // throw during build and trip the global
                              // ErrorWidget, which is what rendered the red
                              // "Something went wrong" beside COD/Visa in the
                              // QA build (ClickUp 86d3g53f8, item 7).
                              Services().widget.renderShippingPaymentTitle(
                                  context,
                                  paymentMethod.title ??
                                      paymentMethod.id ??
                                      ''),
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
}
