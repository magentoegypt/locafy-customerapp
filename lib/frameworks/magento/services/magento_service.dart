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

  MagentoService({
    required String domain,
    String? blogDomain,
    required this.accessToken,
  })  : attributes = null,
        guestQuoteId = null,
        super(domain: domain, blogDomain: blogDomain);

  Product parseProductFromJson(productJson) {
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
    product.description = description ??
        MagentoHelper.getCustomAttribute(
            productJson['custom_attributes'], 'short_description');
    product.size_chart = MagentoHelper.getCustomAttribute(
        productJson['custom_attributes'], 'size_chart');
    if (productJson['type_id'] == 'configurable') {
      if (product.price == null) {
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
      product.regularPrice = product.price;
      product.salePrice = product.price;
      product.onSale = false;
    } else {
      product.price = '$price';
      product.regularPrice = "${productJson["price"]}";
      product.salePrice = onSale ? salePrice : product.price;
      product.onSale = onSale;
    }

    product.minimalPrice = minimalPrice;
    if (minimalPrice != null) {
      product.original_price = product.price;
      product.price = minimalPrice;
      product.salePrice = minimalPrice;
    }
    product.images = images;
    product.imageFeature = images.isNotEmpty ? images[0] : null;

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
        endPoint +=
            '&searchCriteria[filter_groups][0][filters][1][field]=price&searchCriteria[filter_groups][0][filters][1][value]=$minPrice&searchCriteria[filter_groups][0][filters][1][condition_type]=gteq';
      }
      if (maxPrice != null) {
        endPoint +=
            '&searchCriteria[filter_groups][2][filters][1][field]=price&searchCriteria[filter_groups][2][filters][1][value]=$maxPrice&searchCriteria[filter_groups][2][filters][1][condition_type]=lteq';
      }
      //Search by SKU
      if (search != null) {
        if (kAdvanceConfig.enableSkuSearch) {
          endPoint +=
              'searchCriteria[filter_groups][0][filters][0][field]=name&searchCriteria[filter_groups][0][filters][0][value]=%$search%&searchCriteria[filter_groups][0][filters][0][condition_type]=like&searchCriteria[filter_groups][0][filters][1][field]=sku&searchCriteria[filter_groups][0][filters][1][value]=%$search%&searchCriteria[filter_groups][0][filters][1][condition_type]=like';
        } else {
          endPoint +=
              'searchCriteria[filter_groups][0][filters][0][field]=name&searchCriteria[filter_groups][0][filters][0][value]=%$search%&searchCriteria[filter_groups][0][filters][0][condition_type]=like';
        }
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
  Future<PagingResponse<Review>>? getReviews(productId, {int page = 1, int perPage = 10}) async {
    '********** getReviews is called'.log();

    try {
      final response = await http.get(
        Uri.parse(
            '$domain/index.php/rest/V1/products/$productId/reviews'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'content-type': 'application/json'
        },
      );

      var list = <Review>[];
      if (response.statusCode == 200) {
        // for (var item in convert.jsonDecode(response.body)) {
        //   list.add(Review.fromMagentoJson(item));
        // }
        '**********inside response status code 200'.log();

        '********** ${response.body}'.log();
      } else {
        '********** ${response.statusCode}'.log();
        '********** ${response.body}'.log();
      }
      return PagingResponse(data: list);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<PagingResponse<ProductReview>>? getProductReviews(productSKU, {int page = 1, int perPage = 10}) async {
    '********** getReviews is called'.log();

    try {
      final response = await http.get(
        Uri.parse(
            '$domain/index.php/rest/V1/products/$productSKU/reviews'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'content-type': 'application/json'
        },
      );

      var list = <ProductReview>[];
      if (response.statusCode == 200) {
        for (var item in convert.jsonDecode(response.body)) {
          list.add(ProductReview.fromJson(item));
        }
        '**********inside response status code 200'.log();

        '********** ${response.body}'.log();
      } else {
        '********** ${response.statusCode}'.log();
        '********** ${response.body}'.log();
      }
      return PagingResponse(data: list);
    } catch (e) {
      rethrow;
    }
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
      var list = <ProductVariation>[];
      if (res.statusCode == 200) {
        for (var item in convert.jsonDecode(res.body)) {
          var prod = ProductVariation.fromMagentoJson(item, product);
          Product? productStock = await getStockStatus(prod.sku);
          prod.inStock = productStock?.inStock;
          prod.configurable_product_options = product.configurable_product_options;
          prod.configurable_product_links = product.configurable_product_links;
          prod.price = product.price;//productStock?.price;
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
        params['email'] = cartModel.address!.email;
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
    Uri? url;
    var params = <String, dynamic>{};
    params['qty'] = qty;
    if(isUpdate){
    params['item_id'] = product.itemID;
    }
    params['sku'] = sku;
    params['quote_id'] = quoteId;
    print(convert.jsonEncode(params));
    try {
      //create a quote
      url = isUpdate
          ? MagentoHelper.buildUrl(domain, 'carts/mine/items/${product.itemID}')!
          : MagentoHelper.buildUrl(domain, 'carts/mine/items')!;
      var res =  isUpdate
          ? await httpPut(url,
          headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}','content-type': 'application/json'},
          body: convert.jsonEncode({'cartItem': params}))
          : await httpPost(url,
          headers: {'Authorization': 'Bearer ${UserBox().userInfo?.cookie}','content-type': 'application/json'},
          body: convert.jsonEncode({'cartItem': params}));
      final body = convert.jsonDecode(res.body);
      print(body);
      if (res.statusCode == 200) {
        if(!isUpdate){
          product.itemID = body["item_id"].toString();
        }
        return "";
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