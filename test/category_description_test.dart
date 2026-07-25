// The L3 category page shows the category's own description — the SEO box the
// website renders under the category title.
//
// Magento stores it as PageBuilder markup: the authored HTML is *escaped* text
// inside a `data-content-type="html"` node, carries inline styles, and drives
// its own "Read More" from a <script> the app can't run. The parser has to dig
// the prose out of that and drop everything else, so this pins the shape the
// store actually sends (verbatim structure from category 145, Jackets & Coats)
// rather than tidy HTML.

import 'package:flutter_test/flutter_test.dart';
import 'package:magentoegypt/screens/products/widgets/category_description.dart';

/// Trimmed verbatim payload of `GET V1/categories/145` -> custom_attributes
/// -> description on the English store view.
const _seoBox = r'''
<div data-content-type="html" data-appearance="default" data-element="main">&lt;div id="locafy-seo-box-3" style="max-width:900px; margin:40px auto; font-family:Arial, sans-serif;"&gt;

    &lt;div id="locafy-wrapper-3" style="background:#ececec; padding:25px 30px; border-radius:8px;"&gt;

        &lt;h2 style="font-size:20px; font-weight:700; margin:0 0 10px 0; color:#222;"&gt;
            Jackets &amp; Coats for Every Occasion
        &lt;/h2&gt;

        &lt;div style="font-size:14px; color:#555; margin-top:4px;"&gt;
            Outerwear • Local Brands • Everyday Essentials
        &lt;/div&gt;

        &lt;div id="locafy-readmore-3" style="cursor:pointer; color:#004aff;"&gt;
            Read More
        &lt;/div&gt;

        &lt;!-- COLLAPSIBLE CONTENT --&gt;
        &lt;div id="locafy-content-3" style="display:none; padding-top:10px;"&gt;

            &lt;p style="font-size:15px; margin-bottom:16px;"&gt;
                Locafy&rsquo;s Jackets &amp; Coats line will help you stay fashionable and ready for any season.
            &lt;/p&gt;

            &lt;h3 style="font-size:18px; font-weight:700;"&gt;Frequently Asked Questions&lt;/h3&gt;

            &lt;p style="font-size:15px; font-weight:600;"&gt;
                1. Can I exchange a jacket for a different size?
            &lt;/p&gt;

            &lt;p style="font-size:15px; margin-bottom:0;"&gt;
                Want to know more? Browse our
                &lt;a href="/eg-en/faqs-english" style="color:#004aff;"&gt;FAQs&lt;/a&gt;
                to see how easy it is to shop or sell with us.
            &lt;/p&gt;

        &lt;/div&gt;

    &lt;/div&gt;

&lt;/div&gt;

&lt;script&gt;
document.addEventListener("DOMContentLoaded", function () {
    var toggle = document.getElementById("locafy-readmore-3");
    toggle.addEventListener("click", function () { content.style.display = "block"; });
});
&lt;/script&gt;
</div>
''';

/// What an L1/L2 node carries instead: a PageBuilder banner — a <style> block
/// and markup, with no prose worth showing under the category title.
const _bannerOnly = r'''
<div data-content-type="html" data-appearance="default" data-element="main">&lt;style&gt;#html-body [data-pb-style=XD27L7O]{display:none}
.category-banner { margin:0 auto; max-width:1280px; }&lt;/style&gt;
&lt;div class="category-banner"&gt;&lt;img src="/media/wysiwyg/womenswear.jpg" alt="" /&gt;&lt;/div&gt;
</div>
''';

/// The L3 shape (category 144, Menswear > Clothing): a PageBuilder tile grid
/// linking the subcategories, and only *then* the SEO box. Stored unescaped
/// here — both variants occur in the catalogue.
const _l3TileGridThenSeoBox = '''
<div data-content-type="html" data-element="main">
  <style>#html-body [data-pb-style=JKQKXKN]{display:none}</style>
  <div class="category-tiles">
    <a href="/eg-en/loca-men/clothing/t-shirt.html"><img src="/media/a.jpg" alt="" /><p>SHIRTS & T-SHIRTS</p></a>
    <a href="/eg-en/loca-men/clothing/pants.html"><img src="/media/b.jpg" alt="" /><p>PANTS</p></a>
    <a href="/eg-en/loca-men/clothing/jeans.html"><img src="/media/c.jpg" alt="" /><p>JEANS</p></a>
  </div>
</div>
<div data-content-type="html" data-element="main">
  <div id="locafy-seo-box" style="max-width:900px;">
    <div id="locafy-wrapper" style="background:#ececec;">
      <h2 style="font-size:20px;">Menswear Clothing on Locafy</h2>
      <div style="font-size:14px;">Quality • Local Brands • Everyday Essentials</div>
      <div id="locafy-readmore">Read More</div>
      <div id="locafy-content" style="display:none;">
        <p>Locafy brings together everyday menswear from trusted Egyptian brands.</p>
      </div>
    </div>
  </div>
</div>
''';

void main() {
  group('category description parsing', () {
    test('an L3 description starts at the SEO box, not the tile grid', () {
      final blocks = parseCategoryDescription(_l3TileGridThenSeoBox);

      // The tile labels are the subcategory strip the page already shows; as
      // paragraphs they would read as a stray list of shouty one-word lines.
      expect(blocks.map((b) => b.text), isNot(contains('PANTS')));
      expect(blocks.map((b) => b.text), isNot(contains('SHIRTS & T-SHIRTS')));

      expect(blocks.first.tag, 'h2');
      expect(blocks.first.text, 'Menswear Clothing on Locafy');
      expect(blocks.last.text,
          'Locafy brings together everyday menswear from trusted Egyptian brands.');
    });

    test('digs the prose out of the escaped PageBuilder wrapper', () {
      final blocks = parseCategoryDescription(_seoBox);

      expect(blocks, isNotEmpty);
      expect(blocks.first.tag, 'h2');
      // Entities are escaped twice over (&amp; inside escaped markup); the
      // heading must read as prose, not as "Jackets &amp; Coats".
      expect(blocks.first.text, 'Jackets & Coats for Every Occasion');

      final paragraphs = blocks.where((b) => b.tag == 'p').toList();
      expect(paragraphs.first.text,
          startsWith('Locafy’s Jackets & Coats line will help you'));
      // An <a> inside a paragraph keeps its label inline rather than dropping
      // the sentence or leaking the href.
      expect(paragraphs.last.text,
          'Want to know more? Browse our FAQs to see how easy it is to shop or sell with us.');

      expect(blocks.any((b) => b.tag == 'h3'), isTrue);
    });

    test('drops the JS-driven read-more trigger and the script behind it', () {
      final texts = parseCategoryDescription(_seoBox).map((b) => b.text);

      // The trigger is a <div> the app replaces with its own expander, and the
      // <script> would otherwise render as a wall of code.
      expect(texts, isNot(contains('Read More')));
      expect(texts.any((t) => t.contains('addEventListener')), isFalse);
    });

    test('a banner-only description renders nothing rather than raw CSS', () {
      // The whole widget hides on an empty result, which is what should happen
      // on the L1/L2 nodes that carry a banner instead of copy.
      expect(parseCategoryDescription(_bannerOnly), isEmpty);
    });

    test('plain HTML with no PageBuilder wrapper still parses', () {
      final blocks = parseCategoryDescription(
          '<h2>Sneakers</h2><p>Shop local Egyptian brands.</p>');

      expect(blocks.map((b) => b.text).toList(),
          ['Sneakers', 'Shop local Egyptian brands.']);
    });

    test('an empty or broken description is not an error', () {
      expect(parseCategoryDescription(''), isEmpty);
      expect(parseCategoryDescription('   '), isEmpty);
      expect(parseCategoryDescription('<p></p><div></div>'), isEmpty);
    });
  });
}
