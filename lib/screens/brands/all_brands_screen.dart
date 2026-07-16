import 'package:flutter/material.dart';

import '../../common/config.dart';
import '../../common/constants.dart';
import '../../frameworks/magento/services/magento_service.dart';
import '../../generated/l10n.dart';
import '../../models/entities/back_drop_arguments.dart';
import '../../models/entities/category.dart' show ShopBrand;
import '../../routes/flux_navigate.dart';
import '../../services/index.dart';
import '../../widgets/common/webview.dart';
import '../../widgets/home/home_sections.dart' show BrandCard;

/// Native "All Brands" listing — the app's equivalent of the storefront's
/// `/shopbrand` page, opened from the Featured Brands block's "Shop All Brands"
/// CTA.
///
/// Tiles come from `GET mstore/shopbrands` (the same set the website lists).
/// Tapping one opens that brand's native product listing, filtered by the brand
/// attribute's `option_id` — mirroring the home block's brand cards — and falls
/// back to the storefront page when the id is missing.
class AllBrandsScreen extends StatefulWidget {
  const AllBrandsScreen({super.key});

  @override
  State<AllBrandsScreen> createState() => _AllBrandsScreenState();
}

class _AllBrandsScreenState extends State<AllBrandsScreen> {
  late final Future<List<ShopBrand>> _future;

  @override
  void initState() {
    super.initState();
    final api = Services().api;
    _future = api is MagentoService
        ? api.fetchShopBrands()
        : Future.value(const <ShopBrand>[]);
  }

  void _openBrand(ShopBrand brand) {
    final optionId = brand.optionId;
    if (optionId != null && optionId.isNotEmpty) {
      FluxNavigate.pushNamed(
        RouteList.backdrop,
        arguments: BackDropArguments(
          cateId: optionId,
          cateName: brand.name,
          brandImg: brand.image,
        ),
      );
      return;
    }
    // No brand option id (not every environment exposes one) — fall back to the
    // storefront brand page.
    final url = brand.url;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebView(url: url, title: brand.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: const Color(0xFF111111),
        title: Text(
          S.of(context).allBrands,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
      ),
      body: FutureBuilder<List<ShopBrand>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: kLoadingWidget(context));
          }
          final brands = snapshot.data ?? const <ShopBrand>[];
          if (brands.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  S.of(context).dataEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: brands.length,
            itemBuilder: (context, index) {
              final brand = brands[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: BrandCard(
                  name: brand.name,
                  logoUrl: brand.image,
                  onTap: () => _openBrand(brand),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
