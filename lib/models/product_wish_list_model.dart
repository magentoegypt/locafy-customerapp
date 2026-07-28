import 'package:flutter/material.dart';
import 'package:inspireui/inspireui.dart';
import '../app.dart';
import '../common/tools/flash.dart';
import '../data/boxes.dart';
import '../generated/l10n.dart';
import '../services/index.dart';
import 'entities/product.dart';

class ProductWishListModel extends ChangeNotifier {
  ProductWishListModel() {
    getLocalWishlist();
  }

  List<Product> products = [];

  List<Product> getWishList() => products;

  int get wishlistCount => products.length;

  Future<void> addToWishlist(Product product) async {
    if (!UserBox().isLoggedIn) {
      _failMessage(S.current.mustLoginToWishlist);
      return;
    }
    final isExist = products.indexWhere((item) => item.id == product.id) != -1;
    if (!isExist) {

      final message =  await Services().api.addProductToWishList(product);
      if((message ?? "").isEmpty) {
        products.add(product);
        saveWishlist(products);
        notifyListeners();
      }else{
        _failMessage(message!);
      }
    }
  }

  Future<void> removeToWishlist(Product product) async {
    final isExist = products.indexWhere((item) => item.id == product.id) != -1;
    if (isExist) {
      products = products.where((item) => item.id != product.id).toList();
      final message = await Services().api.removeProductToWishList(product.itemID ?? "");
      if((message ?? "").isEmpty){
        saveWishlist(products);
        notifyListeners();
      }else{
        _failMessage(message!);
      }
    }
  }

  Future<void> saveWishlist(List<Product> products) async {
    try {
      UserBox().wishList = products;
    } catch (err, trace) {
      printError(err, trace, '[ProductWishListModel] saveWishlist error');
    }
  }

  /// Pull the wishlist from the server. Safe to call on every wishlist open:
  /// the current list is replaced only after a successful fetch.
  ///
  /// It used to clear first, which also wiped the saved copy — so a failed
  /// request (a flaky network, or the backend 401 that the integration token
  /// currently gets) emptied the wishlist and nothing refilled it until the
  /// next login.
  Future<void> getLocalWishlist() async {
    try {
      // Nothing to fetch for a signed-out customer, and whatever is in memory
      // belongs to whoever was signed in before — drop it.
      if (!UserBox().isLoggedIn) {
        await clearWishList();
        return;
      }
      final wishList = await Services().api.getWishList();//UserBox().wishList;
      if (wishList != null) {
        products = wishList;
        await saveWishlist(products);
        notifyListeners();
      }
    } catch (err, trace) {
      printError(err, trace, '[ProductWishListModel] getLocalWishlist error');
    }
  }

  Future<void> clearWishList() async {
    products = [];
    await saveWishlist(products);
    notifyListeners();
  }

  void _failMessage(String message) {

    if (message.isEmpty) return;
    FlashHelper.errorMessage(
      App.fluxStoreNavigatorKey.currentContext!,
      message: message,
    );
  }
}
