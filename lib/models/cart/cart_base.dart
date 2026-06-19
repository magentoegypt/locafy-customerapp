import 'package:flutter/material.dart';

import '../entities/product.dart';
import '../entities/product_variation.dart';
import '../entities/tax.dart';
import 'mixin/index.dart';

abstract class CartModel
    with
        CartMixin,
        AddressMixin,
        LocalMixin,
        CouponMixin,
        CurrencyMixin,
        MagentoMixin,
        OpencartMixin,
        VendorMixin,
        OrderDeliveryMixin,
        ChangeNotifier {
  @override
  double? getSubTotal();

  double getItemTotal(
      {ProductVariation? productVariation, Product? product, int quantity = 1});

  double? getTotal();

  Future<String> updateQuantity(Product product, String key, int quantity);

  void removeItemFromCart(String key);

  // @override
  // Product? getProductById1(String id);

  @override
  ProductVariation? getProductVariationById(String key);

  void clearCart(bool isFromCartScreen);

  void setOrderNotes(String note);

  void initData();

  @override
  Future<String> addProductToCart({
    context,
    Product? product,
    int? quantity = 1,
    ProductVariation? variation,
    Function? notify,
    isSaveLocal = true,
    isFromApi = false,
    Map? options,
  });

  void setRewardTotal(double total);

  @override
  void loadSavedCoupon();

  @override
  void setWalletAmount(double total);

  @override
  bool isWalletCart();

  @override
  void setTaxInfo(List<Tax> taxes, double taxesTotal);
}
