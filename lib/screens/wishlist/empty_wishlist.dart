import 'package:flutter/material.dart';
import 'package:magentoegypt/ajstoreui/core/app_export.dart';

import '../../common/constants.dart';
import '../../common/tools.dart';
import '../../generated/l10n.dart';
import '../../models/index.dart' show Product;
import '../../services/service_config.dart';
import '../../services/services.dart';
import '../../widgets/product/dialog_add_to_cart.dart';
import '../../widgets/product/widgets/pricing.dart';

class EmptyWishlist extends StatelessWidget {
  final VoidCallback onShowHome;
  final VoidCallback onSearchForItem;

  const EmptyWishlist({
    required this.onShowHome,
    required this.onSearchForItem,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 80),
          Image.asset(
            'assets/images/empty_wishlist.png',
            width: 120,
            height: 120,
            color: Theme.of(context).primaryColor.withOpacity(0.8),
          ),
          const SizedBox(height: 20),
          Text(
            S.of(context).noFavoritesYet,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          Text(S.of(context).emptyWishlistSubtitle,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center),
          // const SizedBox(height: 30),
          // Row(
          //   children: [
          //     Expanded(
          //       child: ButtonTheme(
          //         height: 45,
          //         child: ElevatedButton(
          //           style: ElevatedButton.styleFrom(
          //             foregroundColor: Colors.white,
          //             backgroundColor: Theme.of(context).primaryColor,
          //           ),
          //           onPressed: onShowHome,
          //           child: Text(
          //             S.of(context).startShopping.toUpperCase(),
          //           ),
          //         ),
          //       ),
          //     )
          //   ],
          // ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ButtonTheme(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      backgroundColor: kGrey200,
                    ),
                    onPressed: onSearchForItem,
                    child: Text(S.of(context).searchForItems.toUpperCase()),
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}

class WishlistItem extends StatelessWidget {
  const WishlistItem({required this.product, this.onAddToCart, this.onRemove});

  final Product product;
  final VoidCallback? onAddToCart;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final localTheme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
          decoration: AppDecoration.outlineBluegray50019.copyWith(
            borderRadius: BorderRadiusStyle.roundedBorder4,
          ),
          child: InkWell(
            onTap: (){
              Navigator.of(context).pushNamed(
                RouteList.productDetail,
                arguments: product,
              );
            },
            child: Column(
              key: ValueKey(product.id),
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none, // ensures icon can overflow if needed
                            children: [
                              SizedBox(
                                 width: constraints.maxWidth * 0.95,
                                height: constraints.maxWidth * 0.6,
                                child: ImageResize(
                                    url: product.imageFeature,
                                    size: kSize.medium),
                              ),
                             Positioned(
                               top: -10,   // small padding from top
                               left: -10,  // small padding from left
                               child:  IconButton(
                               icon: const Icon(Icons.close),
                               onPressed: onRemove,
                             ),)
                            ],
                          ),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name ?? '',
                                  style: localTheme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 7),
                                ProductPricing(
                                  product: product,
                                  hide: false,
                                ),
                                const SizedBox(height: 5),
                                Spacer(),
                                if (Services()
                                    .widget
                                    .enableShoppingCart(product) &&
                                    !ServerConfig().isListingType)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor:
                                      localTheme.primaryColor,
                                      minimumSize: const Size.fromHeight(40), // height fixed
                                      maximumSize: const Size(double.infinity, 40), // full width
                                    ),
                                    onPressed: () => DialogAddToCart.show(
                                        context,
                                        product: product),
                                    child: (product.isPurchased &&
                                        product.isDownloadable!)
                                        ? Text(S
                                        .of(context)
                                        .download
                                        .toUpperCase())
                                        : Text(S
                                        .of(context)
                                        .addToCart
                                        .toUpperCase()),
                                  ),
                                const SizedBox(height: 5),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
