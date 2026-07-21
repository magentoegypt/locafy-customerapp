// Regression tests for the wishlist showing EGP0.00 / the undiscounted price
// (follow-up to the 86d3rtbnp layout fix).
//
// The wishlist is re-fetched from POST mobiconnect/wishlist/getwishlist on every
// app launch — ProductWishListModel.getLocalWishlist does not read the local box
// — and that endpoint returns prices as PREFORMATTED DISPLAY STRINGS rather than
// numbers. A real response body for this store:
//
//   {"product_name":"Modern Edge Tracksuit","product_type":"configurable",
//    "regular_price":"EGP 950.00","special_price":"EGP 760.00",
//    "min_price":null,"max_price":null,"final_price":null,"price":null}
//
// Note the U+00A0 non-breaking space between the currency and the amount, and
// the thousands separator on larger values ("EGP 1,100.00"). Every price
// field on Product holds a plain numeric string that PriceTools parses with
// double.tryParse, so the raw string parsed as 0 and the tile rendered EGP0.00.
//
// The strings below are copied verbatim from the live staging response.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magentoegypt/models/entities/product.dart';

void main() {
  // Only the price-bearing keys matter here; the constructor tolerates the rest
  // being absent.
  Product wishlistProduct({
    required String regular,
    required String special,
  }) {
    final json = jsonDecode('''
      {"product_id": "35366", "wishlist_item_id": "2661", "product_name": "Test",
       "product_type": "configurable",
       "regular_price": "$regular", "special_price": "$special"}
    ''') as Map<String, dynamic>;
    return Product.fromWislitJson(json, 'https://example.com');
  }

  group('Product.fromWislitJson pricing', () {
    test('parses a discounted product from the display strings', () {
      //   is the non-breaking space the API actually sends.
      final product =
          wishlistProduct(regular: 'EGP 950.00', special: 'EGP 760.00');

      expect(product.price, '760.0', reason: 'shopper pays the special price');
      expect(product.salePrice, '760.0');
      expect(product.original_price, '950.0',
          reason: 'drives the struck-through original in ProductPricing');
      expect(product.regularPrice, '950.0');
    });

    test('strips thousands separators', () {
      final product = wishlistProduct(
          regular: 'EGP 1,100.00', special: 'EGP 880.00');

      expect(product.regularPrice, '1100.0');
      expect(product.price, '880.0');
    });

    test('a product with no discount falls back to the regular price', () {
      // "no_special" is Magento's sentinel for "no special price set".
      final product =
          wishlistProduct(regular: 'EGP 700.00', special: 'no_special');

      expect(product.price, '700.0');
      expect(product.salePrice, isNull);
      expect(product.minimalPrice, isNull);
      // original_price still set, but equal to price — ProductPricing's
      // strike-through branch compares the two numerically and stays hidden.
      expect(product.original_price, '700.0');
    });

    test('leaves prices null rather than zero when the amount is unusable', () {
      // Null/blank must not become "0.0": that would render a real EGP0.00
      // instead of simply omitting the price, which is the bug being fixed.
      final json = jsonDecode(
              '{"product_id": "1", "product_name": "T", "regular_price": null,'
              ' "special_price": ""}')
          as Map<String, dynamic>;
      final product = Product.fromWislitJson(json, 'https://example.com');

      expect(product.price, isNull);
      expect(product.regularPrice, isNull);
      expect(product.original_price, isNull);
      expect(product.salePrice, isNull);
    });

    test('does not set onSale, so the original price renders only once', () {
      // ProductPricing has two strike-through routes: one above the price keyed
      // on original_price, one inline keyed on onSale. Enabling both would show
      // the original price twice in the same tile.
      final product =
          wishlistProduct(regular: 'EGP 950.00', special: 'EGP 760.00');

      expect(product.onSale ?? false, isFalse);
    });
  });
}
