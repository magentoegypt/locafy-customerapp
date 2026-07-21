// Regression tests for the order-details defects in ClickUp 86d3rrauf.
//
// Two of them were wrong-field bugs against the Magento REST shape, and one was
// a status the app had no name for. All three payload shapes below are copied
// from real responses on testing.locafy.market (customer PII replaced):
//
//   * billing_address carries `telephone` and `country_id`. The app was reading
//     'mobile' and 'country' / 'countryId', which do not exist in a Magento
//     address — so the phone rendered as the literal word "null" and the
//     country came out blank (#4).
//   * A merchant can define any `status` string in the Magento admin. This
//     store uses `Delivered_to_be_invioced` (its own typo), `order_confirmed_cod`
//     and `approved`, none of which the OrderStatus enum names — they all
//     rendered as "Unknown" (#5). `state` is a fixed Magento vocabulary, so it
//     resolves them without the app having to know each store's status list.
//
// Payloads are built with jsonDecode rather than Dart map literals so the values
// are `dynamic`, matching what the parsers actually receive from the API.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magentoegypt/models/entities/address.dart';
import 'package:magentoegypt/models/order/order.dart';

void main() {
  group('Address.fromMagentoJson', () {
    // Shape taken from GET /V1/orders -> items[0].billing_address.
    Map<String, dynamic> billing() => jsonDecode('''
      {"firstname": "QA", "lastname": "Tester", "street": ["1 Test Street"],
       "city": "Abou Al Matamer", "region": "Al Beheira", "country_id": "EG",
       "telephone": "201002007878", "postcode": null}
    ''');

    test('reads the phone from `telephone`, not `mobile`', () {
      final address = Address.fromMagentoJson(billing());
      expect(address.phoneNumber, '201002007878');
    });

    test('reads the country from `country_id`', () {
      final address = Address.fromMagentoJson(billing());
      // The ISO-2 code, not a display name: toMagentoJson sends it back as
      // country_id and getCountryName renders it as "Egypt".
      expect(address.country, 'EG');
      expect(address.countryId, 'EG');
    });

    test('still parses the non-Magento key shapes it used to accept', () {
      // The `?? ` fallbacks must keep working for any caller passing the old
      // shape, so fixing the Magento path cannot regress them.
      final legacy = Address.fromMagentoJson(jsonDecode(
          '{"mobile": "01000000000", "country": "EG", "countryId": "EG"}'));
      expect(legacy.phoneNumber, '01000000000');
      expect(legacy.country, 'EG');
    });
  });

  group('parseOrderStatus', () {
    final order = Order();

    test('resolves a merchant-defined status through its state', () {
      // The exact status on order 7000003366, which QA saw as "Unknown".
      expect(
        order.parseOrderStatus('Delivered_to_be_invioced', state: 'complete'),
        OrderStatus.completed,
      );
      expect(
        order.parseOrderStatus('order_confirmed_cod', state: 'new'),
        OrderStatus.pending,
      );
      expect(
        order.parseOrderStatus('approved', state: 'processing'),
        OrderStatus.processing,
      );
    });

    test('covers the rest of the fixed Magento state vocabulary', () {
      expect(order.parseOrderStatus('whatever', state: 'pending_payment'),
          OrderStatus.pending);
      expect(order.parseOrderStatus('whatever', state: 'payment_review'),
          OrderStatus.pending);
      expect(order.parseOrderStatus('whatever', state: 'closed'),
          OrderStatus.refunded);
      expect(order.parseOrderStatus('whatever', state: 'canceled'),
          OrderStatus.canceled);
      expect(order.parseOrderStatus('whatever', state: 'holded'),
          OrderStatus.onHold);
    });

    test('an explicitly known status still wins over the state fallback', () {
      // 'complete' is matched by the switch before the fallback is reached.
      expect(order.parseOrderStatus('complete', state: 'complete'),
          OrderStatus.completed);
      expect(order.parseOrderStatus('holded', state: 'holded'),
          OrderStatus.onHold);
      expect(order.parseOrderStatus('pending', state: 'new'),
          OrderStatus.pending);
    });

    test('other backends calling without a state are unaffected', () {
      expect(order.parseOrderStatus('on-hold'), OrderStatus.onHold);
      expect(order.parseOrderStatus('refunded'), OrderStatus.refunded);
      expect(order.parseOrderStatus('out-for-delivery'),
          OrderStatus.outForDelivery);
      // Still Unknown when there is nothing at all to go on — the fallback adds
      // a route out, it does not invent one.
      expect(order.parseOrderStatus('some_custom_status'), OrderStatus.unknown);
      expect(order.parseOrderStatus('some_custom_status', state: 'bogus'),
          OrderStatus.unknown);
    });
  });
}
