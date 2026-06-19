import 'package:inspireui/inspireui.dart';
import '../../../common/config.dart';

class MagentoHelper {
  static String? getCustomAttribute(customAttributes, attribute) {
    String? value;
    if (customAttributes != null && customAttributes.length > 0) {
      for (var item in customAttributes) {
        if (item['attribute_code'] == attribute) {
          value = item['value'];
          break;
        }
      }
    }
    return value;
  }

  static String getProductImageUrlByName(domain, imageName) {
    // latest provided by FLuxstore Support
    return '$domain/media/catalog/product$imageName';

    // previous within Code
    //return '$domain/pub/media/catalog/product$imageName';
  }

  static String getProductImageUrl(domain, item, [attribute = 'thumbnail']) {
    final imageName = getCustomAttribute(item['custom_attributes'], attribute);
    if (imageName != null) {
      return imageName.contains('http')
          ? imageName
          : getProductImageUrlByName(domain, imageName);
    } else {
      return '';
    }
  }

  static String getCategoryImageUrl(domain, item, [attribute = 'image']) {
    final imageName = getCustomAttribute(item['custom_attributes'], attribute);
    if (imageName != null) {
      return '$domain/pub/media/catalog/category/$imageName';
    }
    return '';
  }

  static String? getErrorMessage(body) {
    String? message = body['message'];
    if (body['parameters'] != null && body['parameters'].length > 0) {
      final params = body['parameters'];
      final keys = params is List ? params : params.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (params is List) {
          message = message!.replaceAll('%${i + 1}', keys[i].toString());
        } else {
          message =
              message!.replaceAll('%${keys[i]}', params[keys[i]].toString());
        }
      }
    }
    return message;
  }

  static Uri? buildWithoutRestUrl(String? domain, String endpoint, [String? locale]) {
    final languages = getLanguages();
    // if (isNotBlank(locale)) {
    //   var language = languages.firstWhereOrNull(
    //       (o) => o['code'] == locale && isNotBlank(o['storeViewCode']));
    //   if (language != null) {
    //     return "$domain/${language["storeViewCode"]}/rest/V1/$endpoint" //"$domain/index.php/rest/${language["storeViewCode"]}/V1/$endpoint"
    //         .toUri();
    //   }
    // }
    return '$domain/eg-en/$endpoint'.toUri();
    //'$domain/${SettingsBox().languageCode}/rest/V1/$endpoint'.toUri();
    // '$domain/index.php/rest/V1/$endpoint'.toUri();
  }

  static Uri? buildUrl(String? domain, String endpoint, [String? locale]) {
    final languages = getLanguages();
    // if (isNotBlank(locale)) {
    //   var language = languages.firstWhereOrNull(
    //       (o) => o['code'] == locale && isNotBlank(o['storeViewCode']));
    //   if (language != null) {
    //     return "$domain/${language["storeViewCode"]}/rest/V1/$endpoint" //"$domain/index.php/rest/${language["storeViewCode"]}/V1/$endpoint"
    //         .toUri();
    //   }
    // }
    return '$domain/eg-en/rest/V1/$endpoint'.toUri();
    //'$domain/${SettingsBox().languageCode}/rest/V1/$endpoint'.toUri();
    // '$domain/index.php/rest/V1/$endpoint'.toUri();
  }

  static bool isEndLoadMore(body) {
    int totalCount = body['total_count'];
    int pageSize = body['search_criteria']['page_size'];
    int currentPage = body['search_criteria']['current_page'];
    var maxPage = (totalCount / pageSize).ceil();
    return currentPage > maxPage;
  }
}
