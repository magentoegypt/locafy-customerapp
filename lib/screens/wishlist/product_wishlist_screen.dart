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
        // leading: IconButton(
        //   icon: Icon(
        //     Icons.arrow_back_ios,
        //     color: Theme.of(context).colorScheme.secondary,
        //     size: 24,
        //   ),
        //   onPressed: () {
        //     Navigator.pop(context);
        //   },
        // ),
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
                            if (model.products[index].isPurchased &&
                                model.products[index].isDownloadable!) {
                              Tools.launchURL(model.products[index].files![0]!);
                              return;
                            }
                            var msg =
                            await Provider.of<CartModel>(context, listen: false)
                                .addProductToCart(
                              context: context,
                              product: model.products[index],
                              quantity: 1,
                            );
                            if (msg.isEmpty) {
                              msg =
                              '${model.products[index].name} ${S.of(context).addToCartSucessfully}';
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
