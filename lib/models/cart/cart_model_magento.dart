import 'package:flutter/material.dart';

import '../../common/config.dart';
import '../../common/tools.dart';
import '../../generated/l10n.dart';
import '../../services/services.dart';
import '../entities/product.dart';
import '../entities/product_variation.dart';
import 'cart_base.dart';
import 'mixin/index.dart';

class CartModelMagento
    with
        ChangeNotifier,
        CartMixin,
        CouponMixin,
        CurrencyMixin,
        AddressMixin,
        LocalMixin,
        OpencartMixin,
        VendorMixin,
        MagentoMixin,
        OrderDeliveryMixin
    implements CartModel {
  static final CartModelMagento _instance = CartModelMagento._internal();

  factory CartModelMagento() => _instance;

  CartModelMagento._internal();

  @override
  Future<void> initData() async {
    await getShippingAddress();
   // getCartInLocal();
    getCurrency();
  }

  @override
  double getSubTotal() {
    return productsInCart.keys.fold(0.0, (sum, key) {
      if (productVariationInCart[key] != null &&
          productVariationInCart[key]!.price != null &&
          productVariationInCart[key]!.price!.isNotEmpty) {
        return sum +
            double.parse(productVariationInCart[key]!.price!) *
                productsInCart[key]!;
      } else {
       // var productId = Product.cleanProductID(key);

        var price =
            PriceTools.getPriceProductValue(item[key], onSale: true)!;
        if (price.isNotEmpty) {
          return sum + double.parse(price) * productsInCart[key]!;
        }
        return sum;
      }
    });
  }

  /// Magento: get item total
  @override
  double getItemTotal({
    ProductVariation? productVariation,
    Product? product,
    int quantity = 1,
  }) {
    var subtotal = double.parse(product!.price!) * quantity;
    if (discountAmount > 0) {
      return subtotal - discountAmount;
    } else {
      if (couponObj != null) {
        if (couponObj!.discountType == 'percent') {
          return subtotal - subtotal * couponObj!.amount! / 100;
        } else {
          return subtotal - (couponObj!.amount! * quantity);
        }
      } else {
        return subtotal;
      }
    }
  }

  /// Magento: get coupon
  @override
  String getCoupon() {
    if (discountAmount > 0) {
      return '-${PriceTools.getCurrencyFormatted(discountAmount, currencyRates, currency: currencyCode)!}';
    } else {
      if (couponObj != null) {
        if (couponObj!.discountType == 'percent') {
          return '-${couponObj!.amount}%';
        } else {
          return '-${PriceTools.getCurrencyFormatted(couponObj!.amount! * totalCartQuantity, currencyRates, currency: currencyCode)!}';
        }
      } else {
        return '';
      }
    }
  }

  /// Magento: get total
  @override
  double getTotal() {
    var subtotal = getSubTotal();

    if (discountAmount > 0) {
      subtotal -= discountAmount;
    } else {
      if (couponObj != null) {
        if (couponObj!.discountType == 'percent') {
          subtotal -= subtotal * couponObj!.amount! / 100;
        } else {
          subtotal -= (couponObj!.amount! * totalCartQuantity);
        }
      }
    }
    if (kPaymentConfig.enableShipping) {
      subtotal += getShippingCost()!;
    }
    if (taxes.isNotEmpty) {
      subtotal += taxesTotal;
    }
    subtotal += getCODExtraFee();
    return subtotal;
  }

  /// Magento: get coupon cost
  @override
  double getCouponCost() {
    if (discountAmount > 0) {
      return discountAmount;
    } else {
      var subtotal = getSubTotal();
      if (couponObj != null) {
        if (couponObj!.discountType == 'percent') {
          return subtotal * couponObj!.amount! / 100;
        } else {
          return couponObj!.amount! * totalCartQuantity;
        }
      } else {
        return 0.0;
      }
    }
  }

  @override
  Future<String> updateQuantity(Product product, String key, int quantity, {context}) async {
    var message = '';
    var total = quantity;
    ProductVariation? variation;

    if (key.contains('-')) {
      variation = getProductVariationById(key);
    }
    var stockQuantity =
        variation == null ? product.stockQuantity : variation.stockQuantity;

    if (!product.manageStock) {
      productsInCart[key] = total;
    } else if (total <= stockQuantity!) {
      if (product.minQuantity == null && product.maxQuantity == null) {
        productsInCart[key] = total;
      } else if (product.minQuantity != null && product.maxQuantity == null) {
        total < product.minQuantity!
            ? message = 'Minimum quantity is ${product.minQuantity}'
            : productsInCart[key] = total;
      } else if (product.minQuantity == null && product.maxQuantity != null) {
        total > product.maxQuantity!
            ? message =
                'You can only purchase ${product.maxQuantity} for this product'
            : productsInCart[key] = total;
      } else if (product.minQuantity != null && product.maxQuantity != null) {
        if (total >= product.minQuantity! && total <= product.maxQuantity!) {
          productsInCart[key] = total;
        } else {
          if (total < product.minQuantity!) {
            message = 'Minimum quantity is ${product.minQuantity}';
          }
          if (total > product.maxQuantity!) {
            message =
                'You can only purchase ${product.maxQuantity} for this product';
          }
        }
      }
    } else {
      message = 'Currently we only have $stockQuantity of this product';
    }
    String? skuString = variation != null ? variation.sku : product.sku;
    final messageBody = await Services().api.addUpdateItemsToCart(product,skuString ?? "", quantity, true);
    if((messageBody ?? "").isNotEmpty){
      return (messageBody ?? "");
    }
    if (message.isEmpty) {
      updateQuantityCartLocal(key: key, quantity: quantity);
      notifyListeners();
    }
    return message;
  }

  @override
  // Removes an item from the cart.
  void removeItemFromCart(String key) {
    if (productsInCart.containsKey(key)) {
      shoppingList.forEach((element){
        if(element.id == key || element.sku == key){
          Services().api.deleteItemInCart(element.itemID ?? "");
        }
      });
      productsInCart.remove(key);
      productVariationInCart.remove(key);
      productSkuInCart.remove(key);
      removeProductLocal(key);
    }
    notifyListeners();
  }

  @override
  // Removes everything from the cart.
  void clearCart(bool isFromCartScreen) {
    if(isFromCartScreen){
      shoppingList.forEach((element){
        Services().api.deleteItemInCart(element.itemID ?? "");
      });
    }
    clearCartLocal();
    productsInCart.clear();
    item.clear();
    productVariationInCart.clear();
    productSkuInCart.clear();
    shippingMethod = null;
    paymentMethod = null;
    resetCoupon();
    notes = null;
    discountAmount = 0.0;
    notifyListeners();
  }

  @override
  void setOrderNotes(String note) {
    notes = note;
    notifyListeners();
  }

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
  }) async {
    if (product!.type == 'configurable' && variation == null) {
      return S.of(context).loading;
    }
    String? skuString = variation != null ? variation.sku : product.sku;
    if(!isFromApi) {
      final messagebody = await Services().api.addUpdateItemsToCart(product,skuString ?? "", quantity!, false);
      if (!(messagebody ?? "").isEmpty) {
        return messagebody ?? "";
      }
    }
    var message = super.addProductToCart(
        product: product,
        quantity: quantity,
        variation: variation,
        isSaveLocal: isSaveLocal,
        notify: notifyListeners);

    var key = product.id.toString();
    if (variation != null) {
      if (variation.id != null) {
        key += '-${variation.id}';
      }
      for (var attribute in variation.attributes) {
        if (attribute.id == null) {
          key += '-${attribute.name!}${attribute.option!}';
        }
      }
    }
    productSkuInCart[skuString ?? key] = variation != null ? variation.sku : product.sku;
    return message;
  }

  @override
  void setRewardTotal(double total) {
    rewardTotal = total;
    notifyListeners();
  }
}
