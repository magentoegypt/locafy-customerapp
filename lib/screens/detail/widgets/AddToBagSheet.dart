import 'package:flutter/material.dart';
import 'package:magentoegypt/screens/detail/widgets/product_title.dart';
import 'package:provider/provider.dart';
import 'package:quiver/strings.dart';

import '../../../common/config.dart';
import '../../../common/constants.dart';
import '../../../common/tools/image_resize.dart';
import '../../../generated/l10n.dart';
import '../../../models/entities/product.dart';
import '../../../models/entities/product_variation.dart';
import '../../../models/product_model.dart';
import '../../../services/services.dart';
import '../../../widgets/product/widgets/pricing.dart';
import '../../cart/cart_screen.dart';

class AddToBagSheet extends StatelessWidget {
  final Product? product;
   AddToBagSheet({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    int sale = 100;
    String? price;
    bool onSale = false;

    ProductVariation? productVariation = Provider.of<ProductModel>(context).selectedVariation;
   String? getProductPrice() {
      try {
        onSale = productVariation != null
            ? productVariation!.onSale ?? false
            : product!.onSale ?? false;
        price = productVariation != null &&
            (productVariation?.price?.isNotEmpty ?? false)
            ? productVariation!.price
            : isNotBlank(product!.price)
            ? product!.price
            : product!.regularPrice;

        /// update the Sale price
        if (onSale) {
          price = productVariation != null
              ? productVariation!.salePrice
              : isNotBlank(product!.salePrice)
              ? product!.salePrice
              : product!.price;
        }
      } catch (e, trace) {

      }
      return price;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24), // to balance the X icon space
               Text(
                S.of(context).addToCart,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Discount tag
          // Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          //   decoration: BoxDecoration(
          //     color: Colors.grey.shade200,
          //     borderRadius: BorderRadius.circular(8),
          //   ),
          //   child: const Text(
          //     'خصم 15% أقل',
          //     style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          //   ),
          // ),

          const SizedBox(height: 16),

          // Product info row
          Row(
            children: [
              // Product image
              SizedBox(
                height: 100,
                width: 60,
                child: ImageResize(
                  url: product?.imageFeature,
                  fit: BoxFit.contain,
                  isResize: true,
                  size: kSize.medium,
                  width: 60,
                  hidePlaceHolder: true,
                  forceWhiteBackground: kProductDetail.forceWhiteBackground,
                ),
              ),
              const SizedBox(width: 16),
              // Product details
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product?.name ?? "",
                    softWrap: true,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // const Text(
                  //   'بنطال محروط كلاسيكي',
                  //   style: TextStyle(
                  //     fontSize: 14,
                  //     color: Colors.grey,
                  //   ),
                  // ),
                  // const SizedBox(height: 4),
                  // const Text(
                  //   'مقاس 50',
                  //   style: TextStyle(fontSize: 14),
                  // ),
                  // const SizedBox(height: 4),
                //  ProductTitle(product),
                  Services().widget.renderDetailPrice(context, product!, getProductPrice()),
                ],
              ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Add to bag button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  RouteList.cart,
                  arguments: CartScreenArgument(isBuyNow: true, isModal: false),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                S.of(context).goToShoppingCart,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

}