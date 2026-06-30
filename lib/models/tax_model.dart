import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cart/cart_model.dart';
import '../services/index.dart';
import 'entities/tax.dart';

class TaxModel extends ChangeNotifier {
  // The website does not apply any tax during checkout, so tax is disabled in
  // the mobile apps to keep the totals consistent with the web experience.
  // Flip this to true to restore backend-driven tax calculation.
  static const bool enableTax = false;

  final Services _service = Services();
  List<Tax>? taxes = [];
  double taxesTotal = 0;

  Future<void> getTaxes(CartModel cartModel, onSuccess,
      {Function? onError}) async {
    if (!enableTax) {
      taxes = [];
      taxesTotal = 0;
      onSuccess(taxesTotal, taxes);
      return;
    }
    try {
      var res = await _service.api.getTaxes(cartModel);
      if (res != null) {
        taxes = res['items'];
        taxesTotal = double.parse(res['total']);
      }
      onSuccess(taxesTotal, taxes);
    } catch (err) {
      if (onError != null) {
        onError(err);
      }
      notifyListeners();
    }
  }
}
