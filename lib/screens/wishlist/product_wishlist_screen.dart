import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';

import '../../common/constants.dart';
import '../../common/tools.dart';
import '../../generated/l10n.dart';
import '../../menu/maintab_delegate.dart';
import '../../models/index.dart' show CartModel, ProductWishListModel;
import '../../modules/dynamic_layout/tabbar/tabbar_icon.dart';
import '../cart/cart_screen.dart';
import '../common/app_bar_mixin.dart';
import 'empty_wishlist.dart';

class ProductWishListScreen extends StatefulWidget {
  const ProductWishListScreen({super.key});

  @override
  State<StatefulWidget> createState() => _WishListState();
}

class _WishListState extends State<ProductWishListScreen> with AppBarMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    screenScrollController = _scrollController;
  }

  @override
  Widget build(BuildContext context) {

    return renderScaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      routeName: RouteList.wishlist,
      secondAppBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        // Always show the back arrow. The previous canPop() guard hid it when
        // the wishlist was opened as the bottom-nav tab root (nothing to pop),
        // which is how QA reaches it — so no arrow ever appeared there
        // (86d3pngec #1). Pop when there's a route to pop, otherwise return to
        // the Home tab (the "main page").
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).colorScheme.secondary,
            size: 24,
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // Switch the bottom-nav controller to the Home tab (index 0 —
              // the main screen). NavigateTools.navigateHome() can't be used
              // here: it routes by name, and since the home tab isn't
              // registered under RouteList.home it falls through to pushing a
              // standalone home route with no bottom bar.
              MainTabControlDelegate.getInstance().tabAnimateTo(0);
            }
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.background,
        // title: Text(
        //   S.of(context).myWishList,
        //   style: Theme.of(context)
        //       .textTheme
        //       .headlineSmall
        //       ?.copyWith(fontWeight: FontWeight.w500, fontSize: 18),
        // ),
        actions: [
          Selector<CartModel, int>(
            selector: (_, model) => model.totalCartQuantity,
            builder: (context, totalCart, child) {
              return IconButton(
                icon: IconCart(icon: Icon(
                  CupertinoIcons.bag,
                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.6),
                ), totalCart: totalCart),
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    RouteList.cart,
                    arguments: CartScreenArgument(isBuyNow: true, isModal: false),
                  );
                },
              );
            },
          ),
        ],
      ),
      child: ListenableProvider.value(
        value: Provider.of<ProductWishListModel>(context, listen: true),
        child: Consumer<ProductWishListModel>(
          builder: (context, model, child) {
            if (model.products.isEmpty) {
              return EmptyWishlist(
                onShowHome: () => NavigateTools.navigateHome(context),
                onSearchForItem: () => MainTabControlDelegate.getInstance().tabAnimateTo(1),
                //     NavigateTools.navigateToRootTab(
                //   context,
                //   RouteList.search,
                // ),
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 15,
                    ),
                    child: Text(
                      '${S.of(context).myWishList} (${model.products.length})',
                      style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w500, fontSize: 18),
                    ),
                  ),
                 // const Divider(height: 1, color: kGrey200),
                  const SizedBox(height: 15),
                  Expanded(
                    child: GridView.builder(
                      controller: _scrollController,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: model.products.length,
                      itemBuilder: (context, index) {

                        return WishlistItem(
                          product: model.products[index],
                          onRemove: () {
                            Provider.of<ProductWishListModel>(context,
                                listen: false)
                                .removeToWishlist(model.products[index]);
                          },
                          onAddToCart: () async {
                            final product = model.products[index];
                            if (product.isPurchased &&
                                product.isDownloadable!) {
                              Tools.launchURL(product.files![0]!);
                              return;
                            }
                            // Configurable/variable products need option
                            // selection: open the detail page instead of adding
                            // directly to the cart.
                            if (product.type == 'configurable' ||
                                product.isVariableProduct) {
                              Navigator.pushNamed(
                                context,
                                RouteList.productDetail,
                                arguments: product,
                              );
                              return;
                            }
                            var msg =
                            await Provider.of<CartModel>(context, listen: false)
                                .addProductToCart(
                              context: context,
                              product: product,
                              quantity: 1,
                            );
                            if (msg.isEmpty) {
                              msg =
                              '${product.name} ${S.of(context).addToCartSucessfully}';
                            }
                            Tools.showSnackBar(
                                ScaffoldMessenger.of(context), msg);
                          },
                        );
                      },
                    ),
                  )
                ],
              );
            }
          },
        ),
      ),
    );
  }
}
