import 'dart:async';
import 'dart:convert' as convert;
import 'package:country_pickers/utils/utils.dart';
import 'package:http/http.dart' as http;
import 'package:inspireui/inspireui.dart';
import 'package:magentoegypt/common/logger.dart';
import 'package:magentoegypt/data/boxes.dart';
import 'package:magentoegypt/models/SearchResponse.dart';
import 'package:magentoegypt/models/banner_images_model.dart';
import 'package:magentoegypt/models/entities/index.dart';
import 'package:magentoegypt/models/entities/product_review.dart';
import 'package:quiver/strings.dart';
import '../../../common/config.dart';
import '../../../common/constants.dart';
import '../../../common/events.dart';
import '../../../common/extensions.dart';
import '../../../generated/l10n.dart';
import '../../../models/entities/ProdcutOptionAttribute.dart';
import '../../../models/entities/home_section.dart';
import '../../../models/index.dart'
    show
        CartModel,
        Category,
        Coupons,
        Order,
        OrderStatus,
        PaymentMethod,
        Product,
        ProductAttribute,
        ProductVariation,
        Review,
        ShippingMethod,
        Store,
        Tax,
        User,
        UserModel;
import '../../../services/base_services.dart';
import '../../../services/https.dart';
import '../../../services/services.dart';
import 'magento_helper.dart';

const bool kEnableProductThumbnail = false;

class MagentoService extends BaseServices {
  final String accessToken;
  String? guestQuoteId;
  Map<String, ProductAttribute>? attributes;
  List<String> brandIds = [];
  Map<String, String>? _brandLabelsCache;

  MagentoService({
    required String domain,
    String? blogDomain,
    required this.accessToken,
  })  : attributes = null,
        guestQuoteId = null,
        super(domain: domain, blogDomain: blogDomain);

  Product parseProductFromJson(productJson, {Map<String, String>? brandLabels}) {
    final dateSaleFrom = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'special_from_date');
    final dateSaleTo = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'special_to_date');
    var onSale = false;
    var price = productJson['price'];
    var salePrice = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'special_price');
    var minimalPrice = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'minimal_price');

    if (dateSaleFrom != null || dateSaleTo != null) {
      final now = DateTime.now();
      if (dateSaleFrom != null && dateSaleTo != null) {
        onSale = now.isAfter(DateTime.parse(dateSaleFrom)) &&
            now.isBefore(DateTime.parse(dateSaleTo));
      }
      if (dateSaleFrom != null && dateSaleTo == null) {
        onSale = now.isAfter(DateTime.parse(dateSaleFrom));
      }
      if (dateSaleFrom == null && dateSaleTo != null) {
        onSale = now.isBefore(DateTime.parse(dateSaleTo));
      }
      if (onSale && salePrice != null) {
        price = salePrice;
        minimalPrice = salePrice;
      }
    } else if (salePrice != null &&
        dateSaleFrom == null &&
        dateSaleTo == null) {
      onSale = double.parse("${productJson["price"]}") > double.parse(salePrice);
      price = salePrice;
      minimalPrice = salePrice;
    }


    final mediaGalleryEntries = productJson['media_gallery_entries'];
    var images = kEnableProductThumbnail
        ? [MagentoHelper.getProductImageUrl(domain, productJson, 'thumbnail')]
        : <String>[];
    if (mediaGalleryEntries != null &&
            (kEnableProductThumbnail && mediaGalleryEntries.length > 1) ||
        (!kEnableProductThumbnail && mediaGalleryEntries.length > 0)) {
      for (var item in mediaGalleryEntries) {
        print('========================item: $item');
        images
            .add(MagentoHelper.getProductImageUrlByName(domain, item['file']));
      }
    }
    var product = Product.fromMagentoJson(productJson);
    final description = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'description');
    final shortDescription = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'short_description');
    product.description = description ?? shortDescription;
    // Only surface the short-description block when it isn't already the
    // sole content of the Details section (description fallback above).
    if (description != null) {
      product.shortDescription = shortDescription;
    }
    product.size_chart = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'size_chart');

    /// Configurable swatches (color/size options with product images +
    /// child product_ids), exposed on both list and single payloads.
    final rawSwatches = productJson['extension_attributes']?['swatches'];
    if (rawSwatches is List) {
      product.swatches = rawSwatches
          .whereType<Map>()
          .map((a) => ConfigurableSwatch.fromJson(a))
          .toList();
    }

    /// Marketplace seller ("Sold by …"), exposed by the backend as
    /// extension_attributes.seller_name (+ seller_shop_url). id is left null so
    /// the same-store related-products block stays off (no vendor API here).
    final sellerName = productJson['extension_attributes']?['seller_name'];
    if (sellerName is String && sellerName.isNotEmpty) {
      product.store = Store.fromLocalJson({
        'name': sellerName,
        'website': productJson['extension_attributes']?['seller_shop_url'],
      });
    }
    if (productJson['type_id'] == 'configurable') {
      // `product.price` (the entity field) is always null at this point —
      // Product.fromMagentoJson() never sets it — so this used to always
      // take the special_price/minimal_price branch below, then throw away
      // the onSale/regularPrice/salePrice already computed above and hard
      // -code onSale=false. That silently dropped every discount badge and
      // "before" price for configurable products (the common case for
      // clothing with size/color options), even when special_price made
      // them genuinely on sale. Check the raw `price` value from the
      // response instead, and reuse the onSale/salePrice already derived
      // from special_price/date range above, same as simple products.
      if (price == null) {
        if((MagentoHelper.getCustomAttribute(productJson['custom_attributes'], 'special_price') ?? "").isNotEmpty){
          product.price = MagentoHelper.getCustomAttribute(
              productJson['custom_attributes'], 'special_price');
        }else{
          product.price = MagentoHelper.getCustomAttribute(
              productJson['custom_attributes'], 'minimal_price');
        }
      } else {
        product.price = '$price';
      }
    } else {
      product.price = '$price';
    }
    // The parent/base `price` attribute is frequently 0/unset for
    // configurable products in this store's data (real pricing lives on the
    // child SKUs), even when special_price/date-range detection above
    // correctly finds a discount. Only trust it as the "regular" (before
    // discount) price when it's actually greater than the current price —
    // otherwise claiming onSale=true with a bogus regularPrice of 0 shows a
    // broken "0.00" strikethrough/badge instead of just the plain price.
    final rawPriceValue = double.tryParse('${productJson["price"]}') ?? 0;
    final currentPriceValue = double.tryParse(product.price ?? '') ?? 0;
    final hasReliableRegularPrice = rawPriceValue > currentPriceValue;
    product.regularPrice =
        hasReliableRegularPrice ? "${productJson["price"]}" : product.price;
    product.salePrice = onSale ? salePrice : product.price;
    product.onSale = onSale && hasReliableRegularPrice;

    product.minimalPrice = minimalPrice;
    if (minimalPrice != null) {
      // Same reasoning as hasReliableRegularPrice above: only show
      // minimal_price's predecessor as the "before" price when it's an
      // actual, larger value.
      final minimalPriceValue = double.tryParse(minimalPrice) ?? 0;
      if (currentPriceValue > minimalPriceValue) {
        product.original_price = product.price;
      }
      product.price = minimalPrice;
      product.salePrice = minimalPrice;
    }
    product.images = images;
    product.imageFeature = images.isNotEmpty ? images[0] : null;

    final brandId =
        MagentoHelper.getCustomAttribute(productJson['custom_attributes'], 'brand');
    if (brandId != null) {
      product.vendor = brandLabels?[brandId];
    }

    List<dynamic>? categoryIds;
    if (productJson['custom_attributes'] != null &&
        productJson['custom_attributes'].length > 0) {
      for (var item in productJson['custom_attributes']) {
        if (item['attribute_code'] == 'category_ids') {
          categoryIds = item['value'];
          break;
        }
      }
    }
    product.categoryId = categoryIds!.isNotEmpty ? '${categoryIds[0]}' : '0';
    product.permalink = '';

    var attrs = <ProductAttribute>[];
    final options = productJson['extension_attributes'] != null &&
        productJson['extension_attributes']['configurable_product_options'] != null
        ? productJson['extension_attributes']['configurable_product_options']
        : [];
    final configurableProductLinks = productJson['extension_attributes'] != null &&
        productJson['extension_attributes']['configurable_product_links'] != null
        ? productJson['extension_attributes']['configurable_product_links']
        : [];
    product.configurable_product_links = configurableProductLinks;
    product.configurable_product_options = options;
    List? attrsList = kAdvanceConfig.enableAttributesConfigurableProduct;
    List? attrsLabelList =
        kAdvanceConfig.enableAttributesLabelConfigurableProduct;

    for (var i = 0; i < options.length; i++) {
      final option = options[i];

      for (var j = 0; j < attrsList.length; j++) {
        final item = attrsList[j];
        final itemLabel = attrsLabelList[j];
       // if (option['label'].toLowerCase() == itemLabel.toString().toLowerCase()) {
          List? values = option['values'];
          var optionAttr = [];
          if (attributes?[item] != null) {
            for (var f in attributes![item]!.options!) {
              final value = values!.firstWhere(
                  (o) => o['value_index'].toString() == f['value'],
                  orElse: () => null);
              if (value != null) {
                optionAttr.add(f);
              }
            }
            attrs.add(ProductAttribute.fromMagentoJson({
              'attribute_id': attributes![item]!.id,
              'attribute_code': attributes![item]!.name,
              'options': optionAttr
            }));
          }
      //  }
      }
    }
    product.attributes = attrs;
    product.type = productJson['type_id'];
    return product;
  }

  @override
  Future<Product?> getStockStatus(sku) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'stockStatuses/$sku')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      final body = convert.jsonDecode(response.body);

      if (response.statusCode == 200) {
        return Product.fromStockStatusJson(body, domain, sku);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> getStockStatusOld(sku) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'stockItems/$sku')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      final body = convert.jsonDecode(response.body);
      return body['is_in_stock'] ?? false;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<ProdcutOptionAttribute>> getProductAttributesWithOption(String attributeCode) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'products/attributes/$attributeCode/options')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      final body = convert.jsonDecode(response.body);
      final list = (body as List).map((i) => ProdcutOptionAttribute.fromJson(i)).toList();
      return list;
    } catch (e) {
      rethrow;
    }
  }

  /// Maps the `brand` attribute's numeric option ids (what
  /// `custom_attributes` gives us on a product) to their display label,
  /// fetched once and cached for the app session.
  Future<Map<String, String>> getBrandLabels() async {
    if (_brandLabelsCache != null) return _brandLabelsCache!;
    try {
      final options = await getProductAttributesWithOption('brand');
      _brandLabelsCache = {
        for (final o in options)
          if (o.value != null) o.value!: o.label ?? '',
      };
    } catch (e) {
      _brandLabelsCache = {};
    }
    return _brandLabelsCache!;
  }

  List? _storeViewsCache;
  Future<int?> _storeViewIdForCode(String code) async {
    try {
      if (_storeViewsCache == null) {
        final res = await httpGet(
            MagentoHelper.buildUrl(domain, 'store/storeViews')!,
            headers: {'Authorization': 'Bearer $accessToken'});
        if (res.statusCode == 200) {
          final body = convert.jsonDecode(res.body);
          if (body is List) {
            _storeViewsCache = body;
          }
        }
      }
      final match = _storeViewsCache?.firstWhere(
          (s) => s is Map && s['code'] == code,
          orElse: () => null);
      return match?['id'];
    } catch (_) {
      return null;
    }
  }

  Map<String, Map<String, dynamic>>? _visibleAttributesCache;
  String? _visibleAttributesCacheLang;

  /// attribute_code -> {'label': localized label, 'options': value->label}
  /// for every attribute flagged visible-on-front, fetched once per language.
  /// Used to build the PDP "Product Details" table like the website's
  /// "More Information" tab.
  Future<Map<String, Map<String, dynamic>>> getVisibleFrontAttributes(
      {String? lang}) async {
    final langCode = (lang ?? SettingsBox().languageCode ?? 'en').toLowerCase();
    if (_visibleAttributesCache != null &&
        _visibleAttributesCacheLang == langCode) {
      return _visibleAttributesCache!;
    }
    final result = <String, Map<String, dynamic>>{};
    var succeeded = false;
    try {
      // Store-scoped path so option labels come localized.
      final storePath = langCode == 'ar' ? 'eg-ar' : 'eg-en';
      final storeId =
          await _storeViewIdForCode(storePath.replaceAll('-', '_'));
      final url = '$domain/$storePath/rest/V1/products/attributes?'
          'searchCriteria[filter_groups][0][filters][0][field]=is_visible_on_front'
          '&searchCriteria[filter_groups][0][filters][0][value]=1'
          '&searchCriteria[pageSize]=200'
          '&fields=items[attribute_code,default_frontend_label,frontend_labels,options]';
      final res = await httpGet(url.toUri()!,
          headers: {'Authorization': 'Bearer $accessToken'});
      final body = convert.jsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['items'] is List) {
        succeeded = true;
        for (final item in body['items']) {
          final code = item['attribute_code'];
          if (code is! String || code.isEmpty) {
            continue;
          }
          String? label;
          final storeLabels = item['frontend_labels'];
          if (storeId != null && storeLabels is List) {
            final match = storeLabels.firstWhere(
                (l) => l is Map && l['store_id'] == storeId,
                orElse: () => null);
            if (match != null && match['label'] is String) {
              label = match['label'];
            }
          }
          if (label == null && item['default_frontend_label'] is String) {
            label = item['default_frontend_label'];
          }
          if (label == null || label.trim().isEmpty) {
            continue;
          }
          final optionsMap = <String, String>{};
          if (item['options'] is List) {
            for (final option in item['options']) {
              final value = '${option['value'] ?? ''}'.trim();
              final optionLabel = option['label'];
              if (value.isEmpty ||
                  optionLabel is! String ||
                  optionLabel.trim().isEmpty) {
                continue;
              }
              optionsMap[value] = optionLabel.trim();
            }
          }
          result[code] = {'label': label.trim(), 'options': optionsMap};
        }
      }
    } catch (e) {
      printLog('getVisibleFrontAttributes error: $e');
    }
    // Only cache a successful fetch — otherwise a transient failure would
    // suppress the Product Details table for the whole app session.
    if (succeeded) {
      _visibleAttributesCache = result;
      _visibleAttributesCacheLang = langCode;
    }
    return result;
  }

  /// Fetch just the configurable swatches for a SKU. Used to backfill
  /// product.swatches on PDPs whose product came from a source that doesn't
  /// carry them (e.g. live-search results), so color swatches render there too.
  Future<List<ConfigurableSwatch>> getProductSwatches(String? sku) async {
    if (sku == null || sku.isEmpty) {
      return [];
    }
    try {
      final res = await httpGet(
          MagentoHelper.buildUrl(domain,
              'products/${Uri.encodeComponent(sku)}?fields=extension_attributes[swatches]')!,
          headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode == 200) {
        final body = convert.jsonDecode(res.body);
        final ext = body is Map ? body['extension_attributes'] : null;
        final sw = ext is Map ? ext['swatches'] : null;
        if (sw is List) {
          return sw
              .whereType<Map>()
              .map((a) => ConfigurableSwatch.fromJson(a))
              .toList();
        }
      }
    } catch (e) {
      printLog('getProductSwatches error: $e');
    }
    return [];
  }

  /// Attributes shown elsewhere on the PDP — keep them out of the table.
  static const _kExcludedInforCodes = [
    'description',
    'short_description',
    'size_chart',
  ];

  /// Builds the localized "Product Details" rows (product.infors) from the
  /// product's visible-on-front custom attributes.
  Future<List<ProductAttribute>> getProductInfors(String? sku,
      {String? lang}) async {
    final infors = <ProductAttribute>[];
    if (sku == null || sku.isEmpty) {
      return infors;
    }
    try {
      final meta = await getVisibleFrontAttributes(lang: lang);
      if (meta.isEmpty) {
        return infors;
      }
      final res = await httpGet(
          MagentoHelper.buildUrl(domain,
              'products/${Uri.encodeComponent(sku)}?fields=custom_attributes')!,
          headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode != 200) {
        return infors;
      }
      final body = convert.jsonDecode(res.body);
      final customAttributes = body is Map ? body['custom_attributes'] : null;
      if (customAttributes is! List) {
        return infors;
      }
      for (final attr in customAttributes) {
        final code = attr['attribute_code'];
        final rawValue = attr['value'];
        final attrMeta = meta[code];
        if (attrMeta == null ||
            rawValue == null ||
            _kExcludedInforCodes.contains(code)) {
          continue;
        }
        final optionLabels = attrMeta['options'] as Map<String, String>;
        final values = <String>[];
        // Multiselect values arrive as comma-joined option ids.
        for (final part in '$rawValue'.split(',')) {
          final value = part.trim();
          if (value.isEmpty) {
            continue;
          }
          final resolved = optionLabels[value];
          if (resolved != null) {
            values.add(resolved);
          } else if (optionLabels.isEmpty) {
            // Text attribute — show the raw value.
            values.add(value);
          }
        }
        if (values.isEmpty) {
          continue;
        }
        infors.add(ProductAttribute(
          id: code,
          name: attrMeta['label'],
          label: attrMeta['label'],
          options: values,
        ));
      }
    } catch (e) {
      printLog('getProductInfors error: $e');
    }
    return infors;
  }

  Future getAllAttributes() async {
    try {
      attributes = <String, ProductAttribute>{};
      List attrs = kAdvanceConfig.enableAttributesConfigurableProduct;

      for (var item in attrs) {
        var attrsItem = await getProductAttributes(item);
        attributes![item] = attrsItem;
      }
    } catch (e) {
      rethrow;
    }
  }


  Future<List<ProductAttribute>> getConfigurableproductsAttributes(String sku) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'configurable-products/$sku/options/list')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      final body = convert.jsonDecode(response.body);
      if (body is List && body.isNotEmpty) {
        final attributes = body[0]['attributes'] as List;

        return attributes
            .map((attr) => ProductAttribute.fromConfigProductJson(attr))
            .toList();
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<ProductAttribute> getProductAttributes(String attributeCode) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'products/attributes/$attributeCode')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      final body = convert.jsonDecode(response.body);
      if (body['message'] != null) {
        throw Exception(MagentoHelper.getErrorMessage(body));
      } else {
        return ProductAttribute.fromMagentoJson(body);
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<Category>> getCategories({lang}) async {
    try {
      final brands = await fetchBrands();
      brandIds.clear();
      for (var element in brands) {
        brandIds.add(element.value);
      }
      print(MagentoHelper.buildUrl(domain, 'mstore/categories', lang)!);
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'mstore/categories', lang)!,
          headers: {'Authorization': 'Bearer $accessToken'});
      var list = <Category>[];
      if (response.statusCode == 200) {
        for (var item in convert.jsonDecode(response.body)['children_data']) {
          if (item['is_active'] == true && item['include_in_menu'] == true) {
            var category = Category.fromMagentoJson(item,domain);
            category.parent = '0';
            if (item['image'] != null) {
              category.image = item['image'].toString().contains('media/')
                  ? "$kMediaDomain/${item["image"]}"
                  : "$kMediaDomain/media/catalog/category/${item["image"]}";
            }
            list.add(category);
            if(category.brandIds.isNotEmpty){
              attachBrandsAtTopLevel(category,list, brands);
            }

            for (var item1 in item['children_data']) {
              if (item1['is_active'] == true && item1['include_in_menu'] == true) {
                list.add(Category.fromMagentoJson(item1,domain));

                for (var item2 in item1['children_data']) {
                  if (item2['is_active'] == true  && item2['include_in_menu'] == true) {
                    list.add(Category.fromMagentoJson(item2,domain));
                  }
                }
              }
            }
          }
        }
      }
      return list;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Brand>> fetchBrands() async {
    var response = await httpGet(
      MagentoHelper.buildUrl(domain, 'mstore/brands', null)!,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final data = convert.jsonDecode(response.body) as List;
      return data.map((e) => Brand.fromJson(e)).toList();
    }
    return [];
  }

  /// Backend-curated home / main-category sections
  /// (`GET mstore/homepage-sections`): a list of groups of typed sections
  /// (banner / category / brands). Rendered banner -> category -> brands; the
  /// brands section is shared by the home and main-category screens.
  Future<List<HomeSection>> fetchHomepageSections({String? lang}) async {
    try {
      final response = await httpGet(
        MagentoHelper.buildUrl(domain, 'mstore/homepage-sections', lang)!,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        return HomeSection.parseResponse(convert.jsonDecode(response.body));
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Backend-curated sections for a MAIN category's landing page
  /// (86d3g36q4). `GET mstore/sections/{categoryId}` returns
  /// `[ { "sections": [ { "label": "...", "sub_category": "id" | "id,id,..." }, ... ] } ]`.
  /// A `sub_category` with several comma-separated ids is a "shop collection"
  /// (hero subcategory banners); a single id is a product carousel whose
  /// products are that category's curated set. Labels are merchant-defined and
  /// vary per category, so callers render whatever comes back. Returns an empty
  /// list when the category has no curation configured.
  Future<List<Map<String, dynamic>>> fetchMainCategorySections(
      String categoryId, {String? lang}) async {
    try {
      final response = await httpGet(
        MagentoHelper.buildUrl(domain, 'mstore/sections/$categoryId', lang)!,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        final data = convert.jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data.first is Map) {
          final sections = (data.first as Map)['sections'];
          if (sections is List) {
            return sections
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
          }
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  void attachBrandsAtTopLevel(
      Category parentCategory,
      List<Category> categories,
      List<Brand> brands,
      ) {
    // 🔹 Collect all brand IDs from the full tree
    final brandIds = collectBrandIds(parentCategory);

    // 🔹 Match brands
    final matchedBrands = brands.where((brand) {
      final id = int.tryParse(brand.value);
      return id != null && brandIds.contains(id);
    }).toList();


    // 🔥 Create Brand Children
    final brandChildren = matchedBrands.map((b) {
      return Category(
        id: b.value,
        name: b.label,
        parent: "-${parentCategory.id}",
        subCategories: [],
        hasChildren: false,
      );
    }).toList();

    // 🔥 Create "Brands" node (5th item)
    final brandsNode = Category(
      id: "-${parentCategory.id}", // unique fake id
      name: "Brands",
      parent: parentCategory.id,
      subCategories: [],
      hasChildren: true,
    );
    categories.add(brandsNode);
    categories.addAll(brandChildren);
  }

  void attachBrandsAtTopLevel1(
      List<Category> categories,
      List<Brand> brands,
      ) {
    for (var topCategory in categories) {
      // 🔹 Collect all brand IDs from full tree
      final brandIds = collectBrandIds(topCategory);

      if (brandIds.isEmpty) continue;

      // 🔹 Match brands
      final matchedBrands = brands.where((brand) {
        final id = int.tryParse(brand.value);
        return id != null && brandIds.contains(id);
      }).toList();

      if (matchedBrands.isEmpty) continue;

      // 🔥 Create Brand Children
      final brandChildren = matchedBrands.map((b) {
        return Category(
          id: b.value,
          name: b.label,
          parent: topCategory.id,
          subCategories: [],
          hasChildren: false,
        );
      }).toList();

      // 🔥 Create "Brands" node (5th item)
      final brandsNode = Category(
        id: "-${topCategory.id}", // unique fake id
        name: "Brands",
        parent: topCategory.id,
        subCategories: brandChildren,
        hasChildren: true,
      );

      // ✅ Ensure it's always last (optional safe)
      topCategory.subCategories
          .removeWhere((c) => c.name == "Brands");

      topCategory.subCategories.add(brandsNode);
    }
  }

  Set<int> collectBrandIds(Category category) {
    final ids = <int>{};

    // 🔹 from current category
    if (category.brandIds != null) {
      ids.addAll(category.brandIds);
    }

    // 🔁 from children
    for (var child in category.subCategories) {
      ids.addAll(collectBrandIds(child));
    }

    return ids;
  }

  @override
  Future<SearchResponse?> searchProductsResult(String? search) async {
    try {
      final url =
          '$domain/eg-en/mageworx_searchsuiteautocomplete/ajax/index/?q=${Uri.encodeComponent(search ?? '')}';
      print(url);
      var response = await httpGet(Uri.parse(url),
          headers: {'Authorization': 'Bearer $accessToken'});
      if (response.statusCode == 200) {
        return SearchResponse.fromJson(convert.jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<Product>> getProducts({userId}) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildUrl(
              domain, 'mstore/products&searchCriteria[pageSize]=$apiPageSize')!,
          headers: {'Authorization': 'Bearer $accessToken'});
      var list = <Product>[];
      if (response.statusCode == 200) {
        for (var item in convert.jsonDecode(response.body)['items']) {
          var product = parseProductFromJson(item);
          list.add(product);
        }
      }
      return list;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<Product>> fetchProductsLayout({required config, lang, userId, bool refreshCache = false}) async {
    try {
      var list = <Product>[];
      if (config['layout'] == 'imageBanner' ||
          config['layout'] == 'circleCategory') {
        return list;
      }

      var endPoint = '?';
      if (config.containsKey('category')) {
        endPoint +=
            "searchCriteria[filter_groups][0][filters][0][field]=category_id&searchCriteria[filter_groups][0][filters][0][value]=${config["category"]}&searchCriteria[filter_groups][0][filters][0][condition_type]=eq&searchCriteria[pageSize]=${config['limit'] ?? apiPageSize}";
      }
      if (config.containsKey('page')) {
        endPoint += "&searchCriteria[currentPage]=${config["page"]}";
      }

      /// sort by
      if (config.containsKey('orderby') && config['orderby'] != null) {
        endPoint +=
            '&searchCriteria[sortOrders][1][field]=${getOrderByKey(config['orderBy'])}';
      }

      if (config.containsKey('order') && config['order'] != null) {
        endPoint +=
            '&searchCriteria[sortOrders][1][direction]=${getOrderDirection(config['order'])}';
      }

      endPoint +=
          '&searchCriteria[filter_groups][1][filters][0][field]=visibility&searchCriteria[filter_groups][1][filters][0][value]=4';

      'mstore/products$endPoint'.log();

      'URL:${MagentoHelper.buildUrl(domain, 'mstore/products$endPoint', lang)!}'
          .log();
      'Bearer Token:$accessToken'.log();

      var response = await httpCache(
        MagentoHelper.buildUrl(domain, 'mstore/products$endPoint', lang)!,
        headers: {'Authorization': 'Bearer $accessToken'},
        refreshCache: refreshCache,
      );

      if (response.statusCode == 200) {
        for (var item in convert.jsonDecode(response.body)['items']) {
          var product = parseProductFromJson(item);
          list.add(product);
        }
      }
      return list;
    } catch (e) {
      rethrow;
    }
  }

  @override
  String getOrderByKey(orderBy) {
    switch (orderBy) {
      case 'price':
        return 'price';
      case 'title':
        return 'name';
      // Matches the website's default "Sort by Position" option.
      case 'menu_order':
        return 'position';
      case 'popularity':
      case 'rating':
      case 'date':
      default:
        return 'created_at';
    }
  }

  @override
  String getOrderDirection(order) {
    switch (order) {
      case 'asc':
        return 'ASC';
      case 'desc':
      default:
        return 'DESC';
    }
  }

  // called on details products
  @override
  Future<List<Product>?> fetchProductsByCategory(
      {categoryId,
      tagId,
      page,
      minPrice,
      maxPrice,
      lang,
      orderBy,
      order,
      featured,
      onSale,
      attribute,
      attributeTerm,
      listingLocation,
      userId,
      String? include,
      String? search,
        String? searchText,
      Map<String, List<String>>? attributeFilters,
      nextCursor}) async {
    try {
      var endPoint = '?';
      if (categoryId != null) {
        if(brandIds.contains(categoryId)){
          endPoint +=
          'searchCriteria[filter_groups][0][filters][0][field]=brand&searchCriteria[filter_groups][0][filters][0][value]=$categoryId&searchCriteria[filter_groups][0][filters][0][condition_type]=eq';
        }else{
          endPoint +=
          'searchCriteria[filter_groups][0][filters][0][field]=category_id&searchCriteria[filter_groups][0][filters][0][value]=$categoryId&searchCriteria[filter_groups][0][filters][0][condition_type]=eq';
        }

      }
      if (minPrice != null) {
        // Was filter_groups[0].filters[1] — the SAME group as category_id
        // above. Filters within one group are OR'd in Magento's
        // searchCriteria, so that made the query
        // "(category_id = X OR price >= minPrice) AND price <= maxPrice",
        // which let any category item through regardless of price (proven
        // on-device: a category item priced below minPrice still appeared).
        // Needs its own group, isolated from category_id/maxPrice/onSale/
        // search (groups 0/2/3/4), so it's a genuine AND condition.
        endPoint +=
            '&searchCriteria[filter_groups][5][filters][0][field]=price&searchCriteria[filter_groups][5][filters][0][value]=$minPrice&searchCriteria[filter_groups][5][filters][0][condition_type]=gteq';
      }
      if (maxPrice != null) {
        endPoint +=
            '&searchCriteria[filter_groups][2][filters][1][field]=price&searchCriteria[filter_groups][2][filters][1][value]=$maxPrice&searchCriteria[filter_groups][2][filters][1][condition_type]=lteq';
      }
      //Search by SKU
      // Uses filter_groups[4] (not [0], which category_id/minPrice already
      // occupy) so a text search performed inside a category doesn't
      // silently overwrite the category filter via a duplicate query key.
      if (search != null) {
        // This block used to be missing its leading '&', so whenever a
        // category/price filter had already been appended above, this
        // segment ran straight into it with no separator — corrupting the
        // whole query string and causing the backend to 404 on searches
        // performed from within a category.
        if (endPoint != '?') endPoint += '&';
        if (kAdvanceConfig.enableSkuSearch) {
          endPoint +=
              'searchCriteria[filter_groups][4][filters][0][field]=name&searchCriteria[filter_groups][4][filters][0][value]=%$search%&searchCriteria[filter_groups][4][filters][0][condition_type]=like&searchCriteria[filter_groups][4][filters][1][field]=sku&searchCriteria[filter_groups][4][filters][1][value]=%$search%&searchCriteria[filter_groups][4][filters][1][condition_type]=like';
        } else {
          endPoint +=
              'searchCriteria[filter_groups][4][filters][0][field]=name&searchCriteria[filter_groups][4][filters][0][value]=%$search%&searchCriteria[filter_groups][4][filters][0][condition_type]=like';
        }
      }
      // Layered-navigation attribute filters (Brand, Colour, Size, Gender,
      // Material, …) selected from the filter panel. Each attribute gets its
      // OWN filter group (starting at index 6 — 0-5 are taken by
      // category/visibility/max-price/on-sale/search/min-price), so different
      // attributes are AND'd together. Multiple selected values for one
      // attribute go in a single `in` filter, so they are OR'd — exactly
      // Magento layered navigation and the website. The option ids are the
      // same EAV values `brand`/`category_id` already filter on above.
      if (attributeFilters != null && attributeFilters.isNotEmpty) {
        var groupIndex = 6;
        attributeFilters.forEach((field, values) {
          final clean =
              values.where((v) => v.trim().isNotEmpty).toList();
          if (field.trim().isEmpty || clean.isEmpty) return;
          if (endPoint != '?') endPoint += '&';
          final joined = clean.join(',');
          endPoint +=
              'searchCriteria[filter_groups][$groupIndex][filters][0][field]=$field'
              '&searchCriteria[filter_groups][$groupIndex][filters][0][value]=$joined'
              '&searchCriteria[filter_groups][$groupIndex][filters][0][condition_type]=in';
          groupIndex++;
        });
      }
      if (page != null) {
        endPoint += '&searchCriteria[currentPage]=$page';
      }

      endPoint +=
          '&searchCriteria[sortOrders][1][field]=${getOrderByKey(orderBy)}';

      endPoint +=
          '&searchCriteria[sortOrders][1][direction]=${getOrderDirection(order)}';

      if (onSale == true) {
        endPoint +=
            '&searchCriteria[filter_groups][3][filters][0][field]=special_price&searchCriteria[filter_groups][3][filters][0][condition_type]=notnull';
      }
      endPoint += '&searchCriteria[pageSize]=$apiPageSize';

      endPoint +=
          '&searchCriteria[filter_groups][1][filters][0][field]=visibility&searchCriteria[filter_groups][1][filters][0][value]=4';
      if (searchText != null && searchText.isNotEmpty) {
        final encodedSearch = Uri.encodeComponent(searchText);
        if (endPoint == '?') {
          endPoint += 'q=$encodedSearch';
        } else {
          endPoint += '&q=$encodedSearch';
        }
      }
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'mstore/products$endPoint', lang)!,
          headers: {'Authorization': 'Bearer $accessToken'});

      var list = <Product>[];
      if (response.statusCode == 200) {
        final brandLabels = await getBrandLabels();
        for (var item in convert.jsonDecode(response.body)['items']) {
          var product = parseProductFromJson(item, brandLabels: brandLabels);
          list.add(product);
        }
      }
      return list;
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch the web-parity filter attributes (Brand, Colour, Size, Gender,
  /// Material, Pattern, Sleeve length, Style, Product Type, …) for a category
  /// via the storefront GraphQL `aggregations` — the only surface on this
  /// install that exposes layered-navigation options/counts (the REST
  /// `mstore/products` endpoint has none). The *selected* values are then
  /// applied back through REST `fetchProductsByCategory` so the product list,
  /// prices and paging stay on the existing REST path. See docs/qa-followups.md
  /// item 3.
  Future<List<CategoryFilterAttribute>> fetchCategoryFilters({
    required String categoryId,
    String? lang,
  }) async {
    try {
      final langCode = (lang ?? SettingsBox().languageCode ?? 'en').toLowerCase();
      final store = langCode == 'ar' ? 'eg_ar' : 'eg_en';
      final query = '''
{
  products(filter: {category_id: {eq: "$categoryId"}}, pageSize: 1) {
    aggregations {
      attribute_code
      label
      options { label value count }
    }
  }
}''';
      final response = await httpPost(
        '$domain/graphql'.toUri()!,
        headers: {'content-type': 'application/json', 'Store': store},
        body: convert.jsonEncode({'query': query}),
      );
      if (response.statusCode != 200) return const [];
      final body = convert.jsonDecode(response.body);
      final aggs = body?['data']?['products']?['aggregations'];
      if (aggs is! List) return const [];

      // `category_id` and `price` are already covered by the category tree and
      // the price slider in the panel — don't duplicate them as chips.
      const skip = {'category_id', 'price'};

      // Merge attributes that share a display label into one group (e.g. the
      // several category-specific `*_producttype` codes all show as "Product
      // Type" on the web). Each option keeps its own attribute_code so it
      // still filters the right field.
      final byLabel = <String, List<CategoryFilterOption>>{};
      final order = <String>[];
      for (final agg in aggs) {
        final code = '${agg['attribute_code'] ?? ''}'.trim();
        if (code.isEmpty || skip.contains(code)) continue;
        final label = '${agg['label'] ?? code}'.trim();
        if (label.isEmpty) continue;
        final options = agg['options'];
        if (options is! List) continue;
        final parsed = <CategoryFilterOption>[];
        for (final o in options) {
          final value = '${o['value'] ?? ''}'.trim();
          final optLabel = '${o['label'] ?? ''}'.trim();
          if (value.isEmpty || optLabel.isEmpty) continue;
          final rawCount = o['count'];
          final count = rawCount is num
              ? rawCount.toInt()
              : int.tryParse('${rawCount ?? ''}') ?? 0;
          parsed.add(CategoryFilterOption(
            code: code,
            label: optLabel,
            value: value,
            count: count,
          ));
        }
        if (parsed.isEmpty) continue;
        if (!byLabel.containsKey(label)) order.add(label);
        byLabel.putIfAbsent(label, () => []).addAll(parsed);
      }

      return [
        for (final label in order)
          CategoryFilterAttribute(label: label, options: byLabel[label]!),
      ];
    } catch (e) {
      printLog('fetchCategoryFilters error: $e');
      return const [];
    }
  }


  @override
  Future<PagingResponse<Review>>? getReviews(productId, {int page = 1, int perPage = 10}) async {
    try {
      // This Magento build has no REST review routes — reviews are only
      // exposed via GraphQL. `productId` must be the product SKU.
      final langCode = (SettingsBox().languageCode ?? 'en').toLowerCase();
      final store = langCode == 'ar' ? 'eg_ar' : 'eg_en';
      final query = '''
{
  products(filter: {sku: {eq: "$productId"}}) {
    items {
      reviews(pageSize: $perPage, currentPage: $page) {
        items {
          nickname
          summary
          text
          average_rating
          created_at
        }
      }
    }
  }
}''';
      final response = await httpPost(
        '$domain/graphql'.toUri()!,
        headers: {'content-type': 'application/json', 'Store': store},
        body: convert.jsonEncode({'query': query}),
      );
      var list = <Review>[];
      if (response.statusCode == 200) {
        final body = convert.jsonDecode(response.body);
        final items = body?['data']?['products']?['items'];
        if (items is List && items.isNotEmpty) {
          final reviewItems = items.first?['reviews']?['items'];
          if (reviewItems is List) {
            for (final item in reviewItems) {
              final summary = '${item['summary'] ?? ''}'.trim();
              final text = '${item['text'] ?? ''}'.trim();
              final rating = item['average_rating'];
              list.add(Review.fromMagentoJson({
                'name': item['nickname'],
                'review': summary.isEmpty || summary == text
                    ? text
                    : '$summary\n$text',
                // GraphQL returns a 0-100 percentage; the UI expects 0-5.
                'rating': rating is num ? rating / 20.0 : null,
                'date_created': item['created_at'],
              }));
            }
          }
        }
      }
      return PagingResponse(data: list);
    } catch (e) {
      // Degrade to the widget's empty state rather than leaving the
      // Reviews section stuck on its loading spinner.
      printLog('getReviews error: $e');
      return PagingResponse(data: <Review>[]);
    }
  }

  @override
  Future<PagingResponse<ProductReview>>? getProductReviews(productSKU, {int page = 1, int perPage = 10}) async {
    try {
      // Same GraphQL source as getReviews — the REST route doesn't exist.
      final langCode = (SettingsBox().languageCode ?? 'en').toLowerCase();
      final store = langCode == 'ar' ? 'eg_ar' : 'eg_en';
      final query = '''
{
  products(filter: {sku: {eq: "$productSKU"}}) {
    items {
      reviews(pageSize: $perPage, currentPage: $page) {
        items {
          nickname
          summary
          text
          average_rating
          created_at
        }
      }
    }
  }
}''';
      final response = await httpPost(
        '$domain/graphql'.toUri()!,
        headers: {'content-type': 'application/json', 'Store': store},
        body: convert.jsonEncode({'query': query}),
      );
      var list = <ProductReview>[];
      if (response.statusCode == 200) {
        final body = convert.jsonDecode(response.body);
        final items = body?['data']?['products']?['items'];
        if (items is List && items.isNotEmpty) {
          final reviewItems = items.first?['reviews']?['items'];
          if (reviewItems is List) {
            for (final item in reviewItems) {
              final percent = item['average_rating'];
              list.add(ProductReview(
                title: item['summary'],
                detail: item['text'],
                nickname: item['nickname'],
                createdAt: '${item['created_at'] ?? ''}',
                ratings: [
                  if (percent is num)
                    // GraphQL sends a 0-100 percentage; the star row
                    // averages the 0-5 `value`s.
                    Ratings(
                      percent: percent.toInt(),
                      value: (percent / 20).round(),
                    ),
                ],
              ));
            }
          }
        }
      }
      return PagingResponse(data: list);
    } catch (e) {
      rethrow;
    }
  }

  /// Rating-code metadata: rating_id -> ordered list of option value ids
  /// (index i is the (i+1)-star option), from mobiconnect/review/ratingoption.
  List<Map<String, dynamic>>? _ratingOptionsCache;
  Future<List<Map<String, dynamic>>> _getRatingOptions() async {
    if (_ratingOptionsCache != null) return _ratingOptionsCache!;
    final result = <Map<String, dynamic>>[];
    try {
      final res = await httpGet(
          MagentoHelper.buildUrl(domain, 'mobiconnect/review/ratingoption')!,
          headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode == 200) {
        final body = convert.jsonDecode(res.body);
        final first = body is List && body.isNotEmpty ? body[0] : null;
        final dataMap = first is Map ? first['data'] : null;
        final options = dataMap is Map ? dataMap['rating-option'] : null;
        if (options is List) {
          for (final o in options) {
            final ratingId = int.tryParse('${o['rating-id']}');
            final values = (o['option'] as List?)
                ?.map((v) => int.tryParse('${v['value']}'))
                .whereType<int>()
                .toList();
            if (ratingId != null && values != null && values.isNotEmpty) {
              result.add({'rating_id': ratingId, 'values': values});
            }
          }
        }
      }
    } catch (e) {
      printLog('getRatingOptions error: $e');
    }
    if (result.isNotEmpty) {
      _ratingOptionsCache = result;
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> createReview(
      {String? productId, Map<String, dynamic>? data, String? token}) async {
    // Clean, spoof-proof route: POST /products/{sku}/reviews, resource "self"
    // (customer derived server-side from the token).
    final sku = productId;
    if (sku == null || sku.isEmpty) {
      throw Exception('Missing product SKU');
    }
    final star = ((data?['rating'] as num?)?.round() ?? 0).clamp(1, 5);
    final ratingOptions = await _getRatingOptions();
    final ratings = <Map<String, dynamic>>[];
    for (final o in ratingOptions) {
      final values = o['values'] as List<int>;
      // index star-1, guarding shorter lists.
      final valueId = values[(star - 1).clamp(0, values.length - 1)];
      ratings.add({'rating_id': o['rating_id'], 'value_id': valueId});
    }
    final text = '${data?['review'] ?? ''}'.trim();
    final body = {
      'review': {
        'nickname': data?['reviewer'] ?? '',
        // Magento requires a title; derive a short one from the body.
        'summary': text.length > 40 ? '${text.substring(0, 40)}…' : text,
        'text': text,
        'ratings': ratings,
      }
    };
    final res = await httpPost(
      MagentoHelper.buildUrl(
          domain, 'products/${Uri.encodeComponent(sku)}/reviews')!,
      headers: {
        'Authorization': 'Bearer ${token ?? UserBox().userInfo?.cookie}',
        'content-type': 'application/json'
      },
      body: convert.jsonEncode(body),
    );
    final resBody = convert.jsonDecode(res.body);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return resBody is Map
          ? Map<String, dynamic>.from(resBody)
          : {'status': 'pending'};
    }
    throw Exception(
        (resBody is Map ? MagentoHelper.getErrorMessage(resBody) : null) ??
            'Failed to submit review');
  }

  @override
  Future<List<ProductVariation>> getProductVariations(Product product, {String? lang = 'en'}) async {
    try {
      final res = await httpGet(
          MagentoHelper.buildUrl(
              domain, 'configurable-products/${product.sku}/children')!,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'content-type': 'application/json'
          });
      List<ProductAttribute> attributes = await getConfigurableproductsAttributes(product.sku ?? "");
      product.attributes = attributes;

      /// The store's configurable attribute codes vary per attribute set
      /// (all_color, top_size, bottom_size...), so extract them from the
      /// options/list response instead of the hard-coded config list.
      final attributeCodes =
          attributes.map((a) => a.name).whereType<String>().toList();
      var list = <ProductVariation>[];
      if (res.statusCode == 200) {
        for (var item in convert.jsonDecode(res.body)) {
          var prod = ProductVariation.fromMagentoJson(item, product,
              attributeCodes: attributeCodes);
          Product? productStock = await getStockStatus(prod.sku);
          prod.inStock = productStock?.inStock;
          prod.stockQuantity = productStock?.stockQuantity;
          prod.configurable_product_options = product.configurable_product_options;
          prod.configurable_product_links = product.configurable_product_links;
          list.add(prod);
        }
      }

      return list;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<ShippingMethod>> getShippingMethods({CartModel? cartModel, String? token, String? checkoutId, Store? store, String? langCode}) async {
    try {
      print(token);
      var address = cartModel!.address!;
      print(convert.jsonEncode(address.toMagentoJson()));
      var url = token != null
          ? MagentoHelper.buildUrl(
              domain, 'carts/mine/estimate-shipping-methods')!
          : MagentoHelper.buildUrl(
              domain, 'guest-carts/$guestQuoteId/estimate-shipping-methods')!;
      final res = await httpPost(url,
          body: convert.jsonEncode(address.toMagentoJson()),
          headers: token != null
              ? {
                  'Authorization': 'Bearer $token',
                  'content-type': 'application/json'
                }
              : {'content-type': 'application/json'});

      if (res.statusCode == 200) {
        var list = <ShippingMethod>[];
        for (var item in convert.jsonDecode(res.body)) {
          list.add(ShippingMethod.fromMagentoJson(item));
        }
        // if (list.isEmpty) {
        //   throw Exception(S.current.emptyShippingMsg);
        // }
        return list;
      } else {
        final body = convert.jsonDecode(res.body);
        throw Exception(body['message'] != null
            ? MagentoHelper.getErrorMessage(body)
            : S.current.canNotGetShipping);
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<List<PaymentMethod>> getPaymentMethods({CartModel? cartModel, ShippingMethod? shippingMethod, String? token, String? langCode}) async {
    try {
      var address = cartModel!.address;
      final params = {
        'addressInformation': {
          'shipping_address': address?.toMagentoJson()['address'],
          'billing_address': address?.toMagentoJson()['address'],
          'shipping_carrier_code': shippingMethod?.id,
          'shipping_method_code': shippingMethod?.methodId
        }
      };
      print(convert.jsonEncode(params));
      var url = token != null
          ? MagentoHelper.buildUrl(domain, 'carts/mine/shipping-information')!
          : MagentoHelper.buildUrl(
              domain, 'guest-carts/$guestQuoteId/shipping-information')!;
      print(url);
      print(token);
      final res = await httpPost(url,
          body: convert.jsonEncode(params),
          headers: token != null
              ? {
                  'Authorization': 'Bearer $token',
                  'content-type': 'application/json'
                }
              : {'content-type': 'application/json'});

      final body = convert.jsonDecode(res.body);
      if (res.statusCode == 200) {
        var list = <PaymentMethod>[];
        for (var item in body['payment_methods']) {
          if (!item['code'].toString().contains('fake')) {
            list.add(PaymentMethod.fromMagentoJson(item));
          }
        }
        return list;
      } else if (body['message'] != null) {
        throw Exception(MagentoHelper.getErrorMessage(body));
      } else {
        throw Exception(S.current.canNotGetPayments);
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<PagingResponse<Order>> getMyOrders({User? user, dynamic cursor, String? cartId,}) async {
    try {
      //${cursor - 1}
      var endPoint = '?';
      endPoint +=
          'searchCriteria[filter_groups][0][filters][0][field]=customer_email&searchCriteria[filter_groups][0][filters][0][value]=${user!.email}&searchCriteria[filter_groups][0][filters][0][condition_type]=eq';
      endPoint += '&searchCriteria[currentPage]=${cursor}';
      endPoint += '&searchCriteria[sortOrders][1][field]=created_at';
      endPoint += '&searchCriteria[pageSize]=$apiPageSize';
      endPoint += '&dummy=${DateTime.now().millisecondsSinceEpoch}';

      print(accessToken);
      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'orders$endPoint')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      var list = <Order>[];
      if (response.statusCode == 200) {
        for (var item in convert.jsonDecode(response.body)['items']) {
          list.add(Order.fromJson(item));
        }
      }
      return PagingResponse(data: list);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<Order> createOrder({CartModel? cartModel, UserModel? user, bool? paid, String? transactionId}) async {
    try {
      var isGuest = user!.user == null || user.user!.cookie == null;
      var url = !isGuest
          ? MagentoHelper.buildUrl(domain, 'carts/mine/payment-information')!
          : MagentoHelper.buildUrl(
              domain, 'guest-carts/$guestQuoteId/payment-information')!;
      var params = Order().toMagentoJson(cartModel!, null, paid);
      if (isGuest) {
        // Email is optional at checkout — effectiveEmail falls back to the
        // per-phone default when the shopper left the field empty.
        params['email'] = cartModel.address!.effectiveEmail;
        params['firstname'] = cartModel.address!.firstName;
        params['lastname'] = cartModel.address!.lastName;
      }
      if (transactionId != null && transactionId.isNotEmpty) {
        params['paymentMethod'] = {
          'method': params['paymentMethod']['method'],
          'additional_data': {'rzp_payment_id': transactionId}
        };
      }
     // params['order_currency_code'] = "SAR";
      if (cartModel.paymentMethod!.id?.contains('stripe') ?? false) {
        params['paymentMethod'] = {
          'method': params['paymentMethod']['method'],
          'additional_data': {
            'cc_stripejs_token': 'pm_card_visa'
          } // Use pm_card_threeDSecureRequired for 3DS authentication
        };
      }
      print(params);
      final res = await httpPost(url,
          body: convert.jsonEncode(params),
          headers: !isGuest
              ? {
                  'Authorization': 'Bearer ${user.user!.cookie!}',
                  'content-type': 'application/json'
                }
              : {'content-type': 'application/json'});

      final body = convert.jsonDecode(res.body);
      'res.body: ${body}'.log();
      'res.statusCode: ${res.statusCode}'.log();

      if (res.statusCode == 200) {

        var order = await getSingleOrder(user: user, entityId: body.toString());
      //  order.id = body.toString();
     //   order.number = body.toString();
     //   order.status = OrderStatus.pending;
        return order;
      } else {
        if (body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        } else {
          throw Exception(S.current.canNotCreateOrder);
        }
      }
    } catch (e) {
      rethrow;
    }
  }


  Future<Order> getSingleOrder({required UserModel? user, required String entityId}) async {
    try {

      var url =  MagentoHelper.buildUrl(domain, 'orders/$entityId')!;
      print(url);
      print(accessToken);
      final res = await httpGet(url,
          headers:  {
            'Authorization': 'Bearer ${accessToken}',
            'content-type': 'application/json'
          });

      final body = convert.jsonDecode(res.body);
      'res.body: ${body}'.log();
      'res.statusCode: ${res.statusCode}'.log();

      if (res.statusCode == 200) {
        var order = Order.fromJson(body);
        return order;
      } else {
        if (body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        } else {
          throw Exception(S.current.canNotCreateOrder);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future updateOrder(orderId, {status, required token}) async {
    try {
      var response = await httpPost(
        MagentoHelper.buildUrl(domain, 'mstore/me/orders/$orderId/cancel')!,
        body: convert.jsonEncode({}),
        headers: {
          'Authorization': 'Bearer $token',
          'content-type': 'application/json'
        },
      );
      final body = convert.jsonDecode(response.body);
      if (body is Map && body['message'] != null) {
        throw Exception(MagentoHelper.getErrorMessage(body));
      } else {
        return;
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<Order?> cancelOrder({Order? order, String? userCookie,}) async {
    await updateOrder(order!.id, status: 'cancelled', token: userCookie);
    order.status = OrderStatus.cancelled;
    return order;
  }

  @override
  Future<PagingResponse<Product>> searchProducts({name, categoryId, categoryName, tag, attribute, attributeId, page, lang, listingLocation, userId}) async {
    try {
      var endPoint = '?';
      if (name != null) {
        endPoint +=
            'searchCriteria[filter_groups][0][filters][0][field]=name&searchCriteria[filter_groups][0][filters][0][value]=%$name%&searchCriteria[filter_groups][0][filters][0][condition_type]=like';
      }
      if (page != null) {
        endPoint += '&searchCriteria[currentPage]=$page';
      }
      endPoint += '&searchCriteria[pageSize]=$apiPageSize';
      endPoint +=
          '&searchCriteria[filter_groups][1][filters][0][field]=visibility&searchCriteria[filter_groups][1][filters][0][value]=4';

      var response = await httpGet(
          MagentoHelper.buildUrl(domain, 'mstore/products$endPoint')!,
          headers: {'Authorization': 'Bearer $accessToken'});

      var list = <Product>[];
      if (response.statusCode == 200) {
        final body = convert.jsonDecode(response.body);
        if (!MagentoHelper.isEndLoadMore(body)) {
          for (var item in body['items']) {
            var product = parseProductFromJson(item);
            list.add(product);
          }
        }
      }
      return PagingResponse(data: list);
    } catch (err, trace) {
      //  log
      logTalker(
        classFileName: 'MagentoService',
        logType: TalkerType.info,
        message: 'MagentoService: trace:$trace, >>err:$err',
      );

      printError(err, trace);
      rethrow;
    }
  }

  @override
  Future<User> createUser({String? firstName, String? lastName, String? username, String? password, String? phoneNumber, bool isVendor = false,}) async {
    try {
      final payLoad = convert.jsonEncode({
        'customer': {
          'email': username,
          'firstname': firstName,
          'lastname': lastName,
          "custom_attributes":[
            {
              'attribute_code': "mobile",
              'value': phoneNumber,
            },
            {
              'attribute_code': "mobile_token",
              'value': "",
            }
          ]
        },
        'password': password
      });

      'create user payLoad is $payLoad'.log();

      var response =
          await httpPost(MagentoHelper.buildUrl(domain, 'customers')!,
              body: payLoad,
              headers: {'content-type': 'application/json'});

      'create user response is ${response.body}'.log();
      'create user response StatusCode is ${response.statusCode}'.log();

      if (response.statusCode == 200) {
        return await login(username: username, password: password);
      } else {
        final body = convert.jsonDecode(response.body);
        throw Exception(body['message'] != null
            ? MagentoHelper.getErrorMessage(body)
            : 'Can not get token');
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<User> getUserInfo(cookie) async {
    try {
      var res = await httpGet(MagentoHelper.buildUrl(domain, 'customers/me')!,
          headers: {'Authorization': 'Bearer $cookie'});
      final body = convert.jsonDecode(res.body);
      if (body['message'] != null) {
        throw Exception(MagentoHelper.getErrorMessage(body));
      } else {
        User user = User.fromMagentoJson(body, cookie);
        saveDataToLocal(user);
        return user;
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<bool> saveUserInfo(Address? address,bool isDelete) async {
    try {

      var params = <String, dynamic>{};
      params['id'] = UserBox().userInfo?.id;
      params['email'] = UserBox().userInfo?.email;
      params['firstname'] = UserBox().userInfo?.firstName;
      params['lastname'] = UserBox().userInfo?.lastName;
      List<Addresses> addressArr = [];
      UserBox().addresses?.forEach((element){
        Addresses addresses = Addresses();
        addresses.customerId = int.parse(UserBox().userInfo?.id ?? '0');
        if(element.id == address?.id){
          addresses.id = int.parse(element.id ?? '0');
          addresses.firstname = address?.firstName;
          addresses.lastname = address?.lastName;
          addresses.telephone = address?.phoneNumber;
          addresses.street = [];
          addresses.street?.add(address?.street ?? "");
          addresses.city = address?.city;
          addresses.postcode = address?.zipCode;
          addresses.region = Region();
          addresses.region?.region = address?.state;
          addresses.countryId = address?.countryId;
        }else{
          addresses.id = int.parse(element.id ?? '0');
          addresses.firstname = element.firstName;
          addresses.lastname = element.lastName;
          addresses.telephone = element.phoneNumber;
          addresses.street = [];
          addresses.street?.add(element.street ?? "");
          addresses.city = element.city;
          addresses.postcode = element.zipCode;
          addresses.region = Region();
          addresses.region?.region = element.state;
          addresses.countryId = element.countryId;
        }
        if(element.id == address?.id && isDelete) {

        }else{
          addressArr.add(addresses);
        }
      });
      if(address?.id == null || address?.id == 0){
        Addresses addresses = Addresses();
        addresses.customerId = int.parse(UserBox().userInfo?.id ?? '0');
        addresses.firstname = address?.firstName;
        addresses.lastname = address?.lastName;
        addresses.telephone = address?.phoneNumber;
        addresses.street = [];
        addresses.street?.add(address?.street ?? "");
        addresses.city = address?.city;
        addresses.postcode = address?.zipCode;
        addresses.region = Region();
        addresses.region?.region = address?.state;
        addresses.countryId = address?.countryId ?? address?.country;
        addressArr.add(addresses);
      }
      params['addresses'] = addressArr.toList();
      print(convert.jsonEncode({'customer': params}));
      var res = await httpPut(MagentoHelper.buildUrl(domain, 'customers/me')!,
          headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}'
            ,'content-type': 'application/json'},
          body: convert.jsonEncode({'customer': params}));
      final body = convert.jsonDecode(res.body);
      print(body);
      if (body['message'] != null) {
        throw Exception(MagentoHelper.getErrorMessage(body));
      } else {
        User user = User.fromMagentoJson(body, UserBox().userInfo?.cookie);
        saveDataToLocal(user);
        return true;
      }
    } catch (e) {
      rethrow;
    }
  }

  void saveDataToLocal(User user) {
    var listAddress = <Address>[];
    if (user.addresses != null) {
      user.addresses?.forEach((element){
        Address address = Address();
        address.id = element.id.toString();
        address.firstName = element.firstname;
        address.lastName = element.lastname;
        address.email = user.email;
        address.phoneNumber = element.telephone;
        address.street = element.street?.first;
        address.city = element.city;
        address.zipCode = element.postcode;
        address.state = element.region?.region;
        address.country = element.countryId;
        address.countryId = element.countryId;
        listAddress.add(address);
      });
    }
    UserBox().addresses = listAddress;
  }

  @override
  Future<User> login({username, password}) async {
    try {
      var response = await httpPost(
          MagentoHelper.buildUrl(domain, 'integration/customer/token')!,
          body:
              convert.jsonEncode({'username': username, 'password': password}),
          headers: {'content-type': 'application/json'});

      'login response is ${response.body}'.log();
      'login response StatusCode is ${response.statusCode}'.log();

      if (response.statusCode == 200) {
        final token = convert.jsonDecode(response.body);
        var user = await getUserInfo(token);
        return user;
      } else {
        final body = convert.jsonDecode(response.body);
        throw Exception(body['message'] != null
            ? MagentoHelper.getErrorMessage(body)
            : 'Can not get token');
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<User> loginMobile({String? mobile}) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildWithoutRestUrl(domain, 'wapplogin/customer/login?mobile=$mobile')!,
          headers: {'content-type': 'application/json'});

      'login response is ${response.body}'.log();
      'login response StatusCode is ${response.statusCode}'.log();

      if (response.statusCode == 200) {
        final responseData = convert.jsonDecode(response.body);
        final token = responseData['data']['token'];
        var user = await getUserInfo(token);
        return user;
      } else {
        final body = convert.jsonDecode(response.body);
        throw Exception(body['message'] != null
            ? MagentoHelper.getErrorMessage(body)
            : 'Can not get token');
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String> forgotPasswordMobile({String? mobile}) async {
    try {
      var response = await httpGet(
          MagentoHelper.buildWithoutRestUrl(domain, 'wapplogin/customer/forgotPassword?mobile=$mobile')!,
          headers: {'content-type': 'application/json'});

      'login response is ${response.body}'.log();
      'login response StatusCode is ${response.statusCode}'.log();

      if (response.statusCode == 200) {
        final responseData = convert.jsonDecode(response.body);
        final customer = responseData['data']['customer'][0];
        bool success = customer['success'] ?? false;
        String message = customer['message'] ?? "";
        if(success){
          String resetUrl = responseData['data']['customer'][0]['reset_url'];
          return resetUrl;
        }
        return message;
      } else {
        final body = convert.jsonDecode(response.body);
        throw Exception(body['message'] != null
            ? MagentoHelper.getErrorMessage(body)
            : 'Can not get token');
      }
    } catch (err) {
      rethrow;
    }
  }


  @override
  Future<Product?> getProduct(id, {lang}) async {
    var endPoint =
        '?searchCriteria[filterGroups][0][filters][0][field]=entity_id&searchCriteria[filterGroups][0][filters][0][condition_type]=eq';
    endPoint += '&searchCriteria[filterGroups][0][filters][0][value]=$id';
    var response = await httpGet(
        MagentoHelper.buildUrl(domain, 'products$endPoint')!,
        headers: {'Authorization': 'Bearer $accessToken'});
    var products = convert.jsonDecode(response.body)['items'];
    if (products.isEmpty) return null;
    return parseProductFromJson(products[0]);
  }

  Future<bool> deleteItemsInCart(List<Map> items, String? token) async {
    Uri? url;
    try {
      await Future.forEach(items, (Map item) async {
        url = MagentoHelper.buildUrl(
            domain, 'carts/mine/items/${item['item_id']}');
        print(url);
        await httpDelete(
            url!,
            headers: {'Authorization': 'Bearer $token'});
      });
      url = MagentoHelper.buildUrl(domain, 'carts/mine/coupons');
      await httpDelete(url!,
          headers: {'Authorization': 'Bearer $token'});
      return true;
    } catch (err) {
      print(url);
      return true;
     // rethrow;
    }
  }

  @override
  Future<bool> deleteItemInCart(String itemId) async {
    Uri? url;
    try {
        url = MagentoHelper.buildUrl(
            domain, 'carts/mine/items/$itemId');
        await httpDelete(
            url!,
            headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}'});
      return true;
    } catch (err) {
      return true;
      // rethrow;
    }
  }

  Future<bool> addToCart(CartModel cartModel, String? token, quoteId,
      {guestCartId}) async {
    try {
      //add items to cart
      await Future.forEach(cartModel.productsInCart.keys, (dynamic key) async {
        var params = <String, dynamic>{};
        params['qty'] = cartModel.productsInCart[key];
        params['quote_id'] = quoteId;
        params['sku'] = cartModel.productSkuInCart[key];
       // params['order_currency_code'] = "SAR";

        final res = await httpPost(
            guestCartId == null
                ? MagentoHelper.buildUrl(domain, 'carts/mine/items')!
                : MagentoHelper.buildUrl(domain, 'guest-carts/$quoteId/items')!,
            body: convert.jsonEncode({'cartItem': params}),
            headers: token != null
                ? {
                    'Authorization': 'Bearer $token',
                    'content-type': 'application/json'
                  }
                : {'content-type': 'application/json'});
        final body = convert.jsonDecode(res.body);
        if (body['messages'] != null &&
            body['messages']['error'] != null &&
            body['messages']['error'][0].length > 0) {
          throw MagentoHelper.getErrorMessage(body['messages']['error'][0])!;
        } else if (body['message'] != null) {
          throw MagentoHelper.getErrorMessage(body)!;
        } else {
          printLog(body);
          return;
        }
      });
      return true;
    } catch (err) {
      rethrow;
    }
  }

  Future<bool> addItemsToCart(CartModel cartModel, String? token) async {

    Uri? url = MagentoHelper.buildUrl(domain, 'carts/mine');
    try {
      if (token != null) {
        //get cart info
        var res = await httpPost(url!,
            headers: {'Authorization': 'Bearer $token'});
        final cartInfo = convert.jsonDecode(res.body);
        if (res.statusCode == 200) {
          if (cartInfo is int) {
           // await deleteItemsInCart([], token);
            cartModel.shoppingList.forEach((element) async {
              await Services().api.deleteItemInCart(element.itemID ?? "");
            });
            return await addToCart(cartModel, token, cartInfo);
          }else if (cartInfo['items'] is List) {
            await deleteItemsInCart(List<Map>.from(cartInfo['items']), token);
          }
        } else if (res.statusCode == 401) {
          print(url);
          throw Exception('Token expired. Please logout then login again');
        } else if (res.statusCode != 404) {
          print(url);
          throw Exception(MagentoHelper.getErrorMessage(cartInfo));
        }
      }

      //create a quote
      url = token != null
          ? MagentoHelper.buildUrl(domain, 'carts/mine')!
          : MagentoHelper.buildUrl(domain, 'guest-carts')!;
      var res = await httpPost(url,
          headers: token != null ? {'Authorization': 'Bearer $token'} : {});
      if (res.statusCode == 200) {
        if (token != null) {
          final quoteId = convert.jsonDecode(res.body);
          return await addToCart(cartModel, token, quoteId);
        } else {
          String? quoteId = convert.jsonDecode(res.body);
          var response = await httpGet(
              MagentoHelper.buildUrl(domain, 'guest-carts/$quoteId')!);
          final cartInfo = convert.jsonDecode(response.body);
          if (response.statusCode == 200) {
            final cartId = cartInfo['id'];
            guestQuoteId = quoteId;
            return await addToCart(cartModel, token, quoteId,
                guestCartId: cartId);
          } else {
            throw Exception(MagentoHelper.getErrorMessage(cartInfo));
          }
        }
      } else {
        throw Exception(
            MagentoHelper.getErrorMessage(convert.jsonDecode(res.body)));
      }
    } catch (err) {
      rethrow;
    }
  }


  var quoteId;
  Future<String> createCart() async {

    Uri? url = MagentoHelper.buildUrl(domain, 'carts/mine');
    print(url);
    try {
      var res =  await httpPost(url!,
          headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}','content-type': 'application/json'},);
      final body = convert.jsonDecode(res.body);
      if (res.statusCode == 200) {
        quoteId = convert.jsonDecode(res.body);
        return "";
      }else if (res.statusCode == 401) {
        _onLogout();
        throw Exception('Token expired. Please logout then login again');
      } else {
        if (body['message'] != null) {
          return body['message'];
        }else {
          return 'Something went wrong.';
        }
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String> addUpdateItemsToCart(Product product,String sku,int qty,bool isUpdate) async {
    if(!UserBox().isLoggedIn){
      return "";
    }
    try {
      var res = await _sendCartItemRequest(product, sku, qty, isUpdate);
      var body = convert.jsonDecode(res.body);
      var message = body is Map ? MagentoHelper.getErrorMessage(body) : null;

      if (res.statusCode == 401) {
        // Customer token expired — mirror createCart()'s behaviour instead of
        // surfacing the raw "consumer isn't authorized" text.
        _onLogout();
        return S.current.sessionExpired;
      }

      /// A missing/inactive customer quote (typically right after placing an
      /// order) 404s with "No such entity". Recreate the quote and retry once.
      /// Only a fresh add (POST) is safe to retry this way — retrying a PUT
      /// (which carries an *absolute* quantity) as a POST would add that total
      /// on top of any existing line. A PUT that 404s on a stale item_id is
      /// left to the next cart resync instead of being blindly re-added.
      if (res.statusCode == 404) {
        if ((message?.contains('No such entity') ?? false) && !isUpdate) {
          try {
            final created = await createCart();
            if (created.isNotEmpty) {
              return created;
            }
            res = await _sendCartItemRequest(product, sku, qty, false);
            body = convert.jsonDecode(res.body);
            message = body is Map ? MagentoHelper.getErrorMessage(body) : null;
          } catch (_) {
            return S.current.sessionExpired;
          }
        }
      }

      if (res.statusCode == 200) {
        if (!isUpdate && body is Map) {
          product.itemID = body['item_id'].toString();
        }
        return "";
      }
      if (message != null &&
          message.toLowerCase().contains('requested qty is not available')) {
        return S.current.requestedQtyNotAvailable;
      }
      return message ?? 'Something went wrong.';
    } catch (err) {
      rethrow;
    }
  }

  Future<dynamic> _sendCartItemRequest(
      Product product, String sku, int qty, bool isUpdate) {
    final params = <String, dynamic>{};
    params['qty'] = qty;
    if (isUpdate) {
      params['item_id'] = product.itemID;
    }
    params['sku'] = sku;
    params['quote_id'] = quoteId;
    final url = isUpdate
        ? MagentoHelper.buildUrl(domain, 'carts/mine/items/${product.itemID}')!
        : MagentoHelper.buildUrl(domain, 'carts/mine/items')!;
    final headers = {
      'Authorization': 'Bearer ${UserBox().userInfo?.cookie}',
      'content-type': 'application/json'
    };
    return isUpdate
        ? httpPut(url,
            headers: headers, body: convert.jsonEncode({'cartItem': params}))
        : httpPost(url,
            headers: headers, body: convert.jsonEncode({'cartItem': params}));
  }




  Future<double> applyCoupon(String? token, String? coupon) async {
    try {
      var url = token != null
          ? MagentoHelper.buildUrl(domain, 'carts/mine/coupons/$coupon')!
          : MagentoHelper.buildUrl(
              domain, 'guest-carts/$guestQuoteId/coupons/$coupon')!;
      var res = await httpPut(url,
          headers: token != null ? {'Authorization': 'Bearer $token'} : {});
      var body = convert.jsonDecode(res.body);
      if (res.statusCode == 200) {
        var totalUrl = token != null
            ? MagentoHelper.buildUrl(domain, 'carts/mine/totals')!
            : MagentoHelper.buildUrl(
                domain, 'guest-carts/$guestQuoteId/totals')!;
        var res = await httpGet(totalUrl,
            headers: token != null ? {'Authorization': 'Bearer $token'} : {});
        body = convert.jsonDecode(res.body);
        if (body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        } else {
          var discount = double.parse("${body['discount_amount']}");
          return discount < 0 ? discount * (-1) : discount;
        }
      } else {
        throw Exception(MagentoHelper.getErrorMessage(body));
      }
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<Coupons> getCoupons({int page = 1, String search = ''}) async {
    try {
      return Coupons.getListCoupons([]);
    } catch (e) {
      rethrow;
    }
  }


  @override
  Future<Map<String, dynamic>> updateUserInfo(Map<String, dynamic> json, String? token) async {
    try {
      if (isNotBlank(json['user_email'])) {
        var response = await httpPost(
          MagentoHelper.buildUrl(domain, 'mstore/customers/me/changeEmail')!,
          body: convert.jsonEncode({
            'new_email': json['user_email'],
            'current_password': json['current_pass']
          }),
          headers: {
            'Authorization': 'Bearer ${token!}',
            'content-type': 'application/json'
          },
        );
        final body = convert.jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        }
      }else if (isNotBlank(json['user_pass'])) {
        var response = await httpPost(
          MagentoHelper.buildUrl(domain, 'mstore/customers/me/changePassword')!,
          body: convert.jsonEncode({
            'new_password': json['user_pass'],
            'confirm_password': json['user_pass'],
            'current_password': json['current_pass']
          }),
          headers: {
            'Authorization': 'Bearer ${token!}',
            'content-type': 'application/json'
          },
        );

        print(convert.jsonEncode({
          'new_password': json['user_pass'],
          'confirm_password': json['user_pass'],
          'current_password': json['current_pass']
        }));
        final body = convert.jsonDecode(response.body);
        if (isNotBlank(json['phoneNumber'])){
          final payLoad = convert.jsonEncode({
            'customer': {
              'email': UserBox().userInfo?.email,
              'firstname': UserBox().userInfo?.firstName,
              'lastname': UserBox().userInfo?.lastName,
              "custom_attributes":[
                {
                  'attribute_code': "mobile",
                  'value': json['phoneNumber'],
                }
              ]
            }
          });
          var res = await httpPut(MagentoHelper.buildUrl(domain, 'customers/me')!,
              headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}'
                ,'content-type': 'application/json'},
              body: payLoad);
          final body = convert.jsonDecode(res.body);
          print(body);
        }
        if (body is Map && body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        }
      }else if (isNotBlank(json['deviceToken'])) {
        final payLoad = convert.jsonEncode({
          'customer': {
            'email': UserBox().userInfo?.email,
            'firstname': UserBox().userInfo?.firstName,
            'lastname': UserBox().userInfo?.lastName,
            "custom_attributes":[
              {
                'attribute_code': "mobile_token",
                'value': json['deviceToken'],
              }
            ]
          }
        });
        var res = await httpPut(MagentoHelper.buildUrl(domain, 'customers/me')!,
            headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}'
              ,'content-type': 'application/json'},
            body: payLoad);
        final body = convert.jsonDecode(res.body);
        print(body);
        if (body['message'] != null) {
          throw Exception(MagentoHelper.getErrorMessage(body));
        } else {
          User user = User.fromMagentoJson(body, UserBox().userInfo?.cookie);
          return user.toJson();
        }
      }else if (isNotBlank(json['phoneNumber'])){
        final payLoad = convert.jsonEncode({
          'customer': {
            'email': UserBox().userInfo?.email,
            'firstname': UserBox().userInfo?.firstName,
            'lastname': UserBox().userInfo?.lastName,
            "custom_attributes":[
              {
                'attribute_code': "mobile",
                'value': json['phoneNumber'],
              }
            ]
          }
        });
        var res = await httpPut(MagentoHelper.buildUrl(domain, 'customers/me')!,
            headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}'
              ,'content-type': 'application/json'},
            body: payLoad);
        final body = convert.jsonDecode(res.body);
        print(body);
      }
      return json;
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future getCountries() async {
    var response =
        await httpGet(MagentoHelper.buildUrl(domain, 'directory/countries')!);
    final body = convert.jsonDecode(response.body);
    return body;
  }

  @override
  Future getCitiesByStateId(countryId, stateId) async {
    try {
      // Support get city list when user has extension installed https://codecanyon.net/item/magento-city-and-region-manager/17911995
      final response = await httpGet(
          '$domain/city/index/cities/?state=$stateId&country_id=$countryId'
              .toUri()!);
      var body = convert.jsonDecode(response.body);
      return body['cities'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future getCitiesByCountryId(countryId) async {
    try {
      // Support get city list when user has extension installed https://codecanyon.net/item/magento-city-and-region-manager/17911995

     print(MagentoHelper.buildUrl(domain, 'city?country=$countryId')!);
      final response = await httpGet(
          MagentoHelper.buildUrl(domain, 'city?country=$countryId')!);
      var body = convert.jsonDecode(response.body);
      return body[0]['message'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future getZonesByCityId(cityId) async {
    try {
      // Support get city list when user has extension installed https://codecanyon.net/item/magento-city-and-region-manager/17911995
      print(MagentoHelper.buildUrl(domain, 'zone?city=$cityId')!);
      final response = await httpGet(
          MagentoHelper.buildUrl(domain, 'zone?city=$cityId')!);
      var body = convert.jsonDecode(response.body);
      return body[0]['message'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future getZipCodeByAddress(countryId, stateId, city) async {
    try {
      // Support get zipCode when user has extension installed https://codecanyon.net/item/magento-city-and-region-manager/17911995
      final response = await httpGet(
          '$domain/city/index/zips/?city=$city&state=$stateId&country_id=$countryId'
              .toUri()!);
      var body = convert.jsonDecode(response.body);
      return body.first;
    } catch (err) {
      return '';
    }
  }

  Future<bool?> resetPassword(String email) async {
    try {
      var response = await httpPut(
        MagentoHelper.buildUrl(domain, 'customers/password')!,
        body: convert.jsonEncode({'email': email, 'template': 'email_reset'}),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'content-type': 'application/json'
        },
      );

      return convert.jsonDecode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String?> createPaymentIntentStripe(
      {required String totalPrice,
      String? currencyCode,
      String? emailAddress,
      String? name,
      required String paymentMethodId}) async {
    try {
      var response = await httpPost(
        MagentoHelper.buildUrl(domain, 'mstore/stripe/payment-intent')!,
        body: convert.jsonEncode({
          'payment_method_id': paymentMethodId,
          'email': emailAddress,
          'amount': totalPrice,
          'currencyCode': currencyCode,
          'captureMethod': (kStripeConfig['enableManualCapture'] ?? false)
              ? 'manual'
              : 'automatic'
        }),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'content-type': 'application/json'
        },
      );

      var body = convert.jsonDecode(response.body);
      body = body is List && body.isNotEmpty ? body[0] : body;
      if (body['client_secret'] != null) {
        return body['client_secret'];
      } else if (body['message'] != null) {
        throw Exception(body['message']);
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getTaxes(CartModel cartModel) async {
    try {
      var response = await httpGet(
        MagentoHelper.buildUrl(domain, 'taxRates/search?searchCriteria')!,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'content-type': 'application/json'
        },
      );

      var body = convert.jsonDecode(response.body);
      if (body is Map && body['items'] != null && body['items'] is List) {
        var taxes = <Tax>[];
        final address = cartModel.address?.toMagentoJson()['address'];
        body['items'].forEach((item) {
          if ((item['tax_country_id'] == '*' ||
                  item['tax_country_id'] == address['country_id']) &&
              (item['tax_region_id'] == 0 ||
                  item['tax_region_id'] == address['region_id']) &&
              (item['tax_postcode'] == '*' ||
                  item['tax_postcode'] == address['postcode'])) {
            taxes.add(Tax.fromMagentoJson(item, cartModel.getSubTotal() ?? 0));
          }
        });
        taxes = taxes.where((e) => e.amount != null && e.amount! > 0).toList();
        return {
          'items': taxes,
          'total': '${taxes.isNotEmpty ? taxes[0].amount : 0}'
        };
      } else if (body['message'] != null) {
        throw Exception(body['message']);
      }
      return null;
    } catch (err) {
      rethrow;
    }
  }

  @override
  getBannerImages() async {
    final bannersAPIUrl = MagentoHelper.buildUrl(domain, 'mobile/home/config');

    "getBannerImages: $bannersAPIUrl".log();
    print(accessToken);
    try {
      var response = await httpGet(
        MagentoHelper.buildUrl(domain, 'mobile/home/config')!,
        headers: {'Authorization': 'Bearer jd7u3bu9g7ca1vgocv0dvpr77xof57jf'},
      );

      final body = convert.jsonDecode(response.body);

      "💫💫💫💫BannersResponse: $body".log();
       List<BannerImagesModel> bannersList = [];
      (body as List).first.forEach((key, value){
        print('key is $key');
        print('value is $value ');
        bannersList.add(BannerImagesModel.fromJson(value));
      });
      //final bannersList = (body as List).map((i) => BannerImagesModel.fromJson(i)).toList();
      return bannersList;
    } catch (e) {
      //rethrow;

      return null;
    }
  }

  @override
  Future<List<Product>?>? getWishList() async {
    try {
      print(MagentoHelper.buildUrl(domain, 'mobiconnect/wishlist/getwishlist')!);
      print('Bearer ${accessToken}');
      print('customer_id ${UserBox().userInfo?.id}');
      var response = await httpPost(
        MagentoHelper.buildUrl(domain, 'mobiconnect/wishlist/getwishlist')!,
        headers: {
          'Authorization': 'Bearer ${accessToken}',
          'content-type': 'application/json'
        },
        body: convert.jsonEncode({
          "parameters": {
            "customer_id":UserBox().userInfo?.id,
          }
        })
      );

      final body = convert.jsonDecode(response.body);
      var list = <Product>[];

      if (response.statusCode == 200) {
        createCart();
        if (body.isNotEmpty) {
          var firstElement = body.first;
          if (firstElement.containsKey("data")){
            var data = firstElement["data"];
            if (data is Map && data.containsKey("products")) {
              var products = data["products"];
              list = (products as List).map((i) => Product.fromWislitJson(i,domain)).toList();
            }
          }
        }
      }else if (response.statusCode == 401) {
        _onLogout();
        throw Exception('Token expired. Please logout then login again');
      }else{
        if (body['message'] != null) {
          throw Exception(body['message']);
        }else {
          throw Exception('Something went wrong.');
        }
      }
      return list;
    } catch (e) {

      return null;
    }
  }

  //calling for cart list 
  @override
  Future<List<Product>?>? getShoppingList(CartModel model,
      {bool replace = false}) async {
    print('Bearer ${UserBox().userInfo?.cookie}');
    try {
      var response = await httpGet(
        MagentoHelper.buildUrl(domain, 'carts/mine/items')!,
        headers: {
          'Authorization': 'Bearer ${UserBox().userInfo?.cookie}',
          'content-type': 'application/json'
        },
      );

      final body = convert.jsonDecode(response.body);
      var list = <Product>[];
      if (response.statusCode == 200) {
        list = (body as List).map((i) => Product.fromShopJson(i,domain)).toList();
        // When refreshing an existing cart (replace), reset the in-memory
        // product lines to the server's current state first so quantities are
        // not duplicated and items removed on another platform disappear.
        // Coupon / shipping / payment / notes are preserved. Done only after
        // the fetch succeeds so a network error never blanks a cart that still
        // exists on the server. Default (login path) keeps the original merge
        // behaviour untouched.
        if (replace) {
          model.productsInCart.clear();
          model.item.clear();
          model.productVariationInCart.clear();
          model.productsMetaDataInCart.clear();
        }
        model.shoppingList = list;
        list.forEach((product){
          model.addProductToCart(product: product,quantity: product.shopQuantity,isFromApi: true);
        });
      }else if (response.statusCode == 401) {
        _onLogout();
        throw Exception('Token expired. Please logout then login again');
      }else{
        if (body['message'] != null) {
          throw Exception(body['message']);
        }else {
          throw Exception('Something went wrong.');
        }
      }
      return list;
    } catch (e) {

      return null;
    }
  }

  @override
  Future<String?>? addProductToWishList(Product product) async {
    try {
      var response = await httpPost(
        MagentoHelper.buildUrl(domain, 'mobiconnect/wishlist/add')!,
        headers: {
          'Authorization': 'Bearer ${accessToken}',
          'content-type': 'application/json'
        },
        body: convert.jsonEncode({
          "parameters": {
            "customer_id":UserBox().userInfo?.id,
            "prodID": product.id
          }
        }),
      );

      final body = convert.jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (body.isNotEmpty && body[0].containsKey('wishlist-item-id')) {
          product.itemID = body[0]['wishlist-item-id'];
        }
        return "";
      }else if (response.statusCode == 401) {
        _onLogout();
        return 'Token expired. Please logout then login again';
      }else{
        if (body['message'] != null) {
          return body['message'];
        }else {
          return 'Something went wrong.';
        }
      }
    } catch (e) {
      //rethrow;

      return null;
    }
  }

  @override
  Future<String?>? removeProductToWishList(String productId) async {
    try {
      var response = await httpPost(
        MagentoHelper.buildUrl(domain, 'mobiconnect/wishlist/remove')!,
        headers: {
          'Authorization': 'Bearer ${accessToken}',
          'content-type': 'application/json'
        },
        body: convert.jsonEncode({
          "parameters": {
            "customer_id":UserBox().userInfo?.id,
            "itemId": productId
          }
        })
      );

      final body = convert.jsonDecode(response.body);
      if (response.statusCode == 200) {
         return "";
      }else if (response.statusCode == 401) {
        _onLogout();
        return 'Token expired. Please logout then login again';
      }else{
        if (body['message'] != null) {
          return body['message'];
        }else {
          return 'Something went wrong.';
        }
      }
    } catch (e) {
      //rethrow;
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> mobileSendOtp(String number,String otpText) async {
    Map<String, dynamic> parameters = {
      "type": "text",
      "text": otpText,
    };

    Map<String, dynamic> bodyComponents = {
      "type": "body",
      "parameters": [parameters],
    };

    Map<String, dynamic> buttonComponents = {
      "type": "button",
      "sub_type": "url",
      "index": "0",
      "parameters": [parameters],
    };

    Map<String, dynamic> language = {
      "policy": "deterministic",
      "code": "ar",
    };

    Map<String, dynamic> template = {
      "language": language,
      "name": "otp_new",
      "components": [bodyComponents, buttonComponents],
    };

    Map<String, dynamic> mainBody = {
      "messaging_product": "whatsapp",
      "recipient_type": "individual",
      "to": number,
      "type": "template",
      "template": template,
    };
    try {
      var response = await httpPost("https://graph.facebook.com/v20.0/122095038332010689/messages".toUri()!,
        headers: {
          'content-type': 'application/json',
          'Authorization': 'Bearer EAAXa7lItDpYBO84bpz10qjSzZAKcXe6YnUNgWEMsCarHKEUUOc7wFk3e4opjOESdKT1xGwguyV8yeuJu3jjfh3SvUeVOryl6jR4EZBRZAl4SUfwbgS2aGCipWTusU9tEyZBpPgjncTojB7dn6aocFw1wtQ0dnRIyLoPcdhSZAzc3ycQCVZA3L6ZBU5Blp7n2HX8LQVlTwg3fA3Ingb4'
        },
        body: convert.jsonEncode(mainBody)
      );
      final body = convert.jsonDecode(response.body);
      print(body);
      return body;
    } catch (e) {
      return null;
    }
  }

  void _onLogout() {
    if(UserBox().isLoggedIn) {
      eventBus.fire(const EventExpiredCookie());
    }
  }

}
//We'll email you a link to reset your password.
//https://stg.locafy.market/eg-en/rest/V1/mstore/brands
//https://stg.locafy.market/eg-en/rest/V1/products?searchCriteria[filterGroups][0][filters][0][field]=entity_id&searchCriteria[filterGroups][0][filters][0][condition_type]=eq&searchCriteria[filterGroups][0][filters][0][value]=29189
