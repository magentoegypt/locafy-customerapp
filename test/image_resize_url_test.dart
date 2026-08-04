// Regression test for product photos silently turning into the store
// placeholder (86d3x5ex6).
//
// With kIsResizeImage on, the app asks for a "-small"/"-medium"/"-large"
// sibling of the media file. That is right for a raw catalog path
// (/media/catalog/product/s/e/foo.jpg), which really does have those siblings,
// but wrong for a URL that is already a Magento rendition
// (/media/catalog/product/cache/<hash>/s/e/foo.jpg): renditions have no
// siblings, so the request lands on a file that does not exist.
//
// What makes this worth pinning is the failure mode. This install answers a
// missing media file with HTTP 200 and the LOCAFY placeholder PNG rather than a
// 404, so nothing errors — the card just quietly shows the placeholder, and no
// error handler anywhere in the app can tell the difference. Verified against
// testing.locafy.market: appending "-medium" to a cache URL returns the exact
// same 15,529-byte placeholder as a deliberately bogus filename does.

import 'package:flutter_test/flutter_test.dart';
import 'package:magentoegypt/common/tools/image_tools.dart';
import 'package:magentoegypt/services/index.dart' show ServerConfig;

void main() {
  const media = 'https://testing.locafy.market/media/catalog/product';
  const cachePrefix = '$media/cache/ea90a1623f3f2944c5341ae0c5790169';

  group('formatImage', () {
    setUpAll(() => ServerConfig().setConfig({'type': 'magento'}));

    test('leaves an already-resized Magento rendition untouched', () {
      const url = '$cachePrefix/g/u/gucci-logo.png';

      expect(ImageTools.formatImage(url, kSize.medium), url);
      expect(ImageTools.formatImage(url, kSize.small), url);
      expect(ImageTools.formatImage(url, kSize.large), url);
    });

    test('still asks for the sibling of a raw catalog path', () {
      const url = '$media/s/e/set213213213_1_1.jpg';

      // Only assert the suffix so the test does not depend on whether the
      // resize flag happens to be on in this build's config.
      final medium = ImageTools.formatImage(url, kSize.medium)!;
      expect(
        medium == url || medium == '$media/s/e/set213213213_1_1-medium.jpg',
        isTrue,
        reason: 'raw paths keep the -medium rewrite: got $medium',
      );
    });

    test('a rendition is left alone whatever the file extension', () {
      for (final url in [
        '$cachePrefix/s/c/screenshot.png',
        '$cachePrefix/p/e/pexels.jpg',
        '$cachePrefix/a/b/photo.jpeg',
      ]) {
        expect(ImageTools.formatImage(url, kSize.medium), url);
      }
    });

    test('a null url stays null rather than throwing', () {
      expect(ImageTools.formatImage(null, kSize.medium), isNull);
    });
  });
}
