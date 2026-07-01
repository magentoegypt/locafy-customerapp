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
    // Guests can't have a server-side wishlist — show the same message the
    // website shows instead of letting the API return a generic error.
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

  Future<void> getLocalWishlist() async {
    try {
      await clearWishList();
      final wishList = await Services().api.getWishList();//UserBox().wishList;
      if (wishList != null) {
        products = wishList;
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
