import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

import '../../../common/tools.dart';
import '../../../frameworks/magento/services/magento_service.dart';
import '../../../generated/l10n.dart';
import '../../../models/app_model.dart';
import '../../../services/index.dart';
import '../../../services/service_config.dart';

/// Palette lifted from the authored SEO box so the app card matches the
/// website's rendering of the same content.
const _kAccent = Color(0xFF004AFF);
const _kAccentLight = Color(0xFF4F7CFF);
const _kCalloutBg = Color(0xFFF3F6FF);
const _kBorder = Color(0xFFE5E7EB);
const _kHeadingText = Color(0xFF111827);
const _kBodyText = Color(0xFF374151);
const _kMutedText = Color(0xFF6B7280);

/// The category's own description — the SEO box the website renders under the
/// category title on an L3 page (`category.level == 3`): a heading, a tagline,
/// and a pill that expands the body copy, links and FAQ.
///
/// The stored HTML is PageBuilder markup — inline-styled, sometimes escaped
/// inside a `data-content-type="html"` node, and driven by a `<script>` the
/// app can't run — so it is reduced to typed blocks here and re-rendered with
/// Flutter widgets styled to match the website's card.
class CategoryDescription extends StatefulWidget {
  final String? categoryId;

  const CategoryDescription({super.key, this.categoryId});

  @override
  State<CategoryDescription> createState() => _CategoryDescriptionState();
}

class _CategoryDescriptionState extends State<CategoryDescription> {
  List<CategoryDescriptionBlock> _blocks = const [];
  bool _expanded = false;

  /// One recognizer per distinct link, built with the blocks and disposed with
  /// the state — building them per frame would leak a recognizer a frame.
  final Map<String, TapGestureRecognizer> _linkTaps = {};

  /// Guards against a slow response for a category the user has already
  /// switched away from (the subcategory strip changes category in place).
  String? _pendingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant CategoryDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _load();
    }
  }

  @override
  void dispose() {
    _disposeLinkTaps();
    super.dispose();
  }

  void _disposeLinkTaps() {
    for (final recognizer in _linkTaps.values) {
      recognizer.dispose();
    }
    _linkTaps.clear();
  }

  Future<void> _load() async {
    final id = widget.categoryId;
    if (id == _pendingId) return;
    _pendingId = id;
    // A rebuild always follows the call sites (first build / category switch),
    // so reset in place rather than asking for another one.
    _blocks = const [];
    _expanded = false;
    _disposeLinkTaps();

    final api = Services().api;
    if (id == null || id.isEmpty || api is! MagentoService) return;

    final lang = Provider.of<AppModel>(context, listen: false).langCode;
    final html = await api.fetchCategoryDescription(id, lang: lang);
    if (!mounted || _pendingId != id || html == null) return;
    final blocks = parseCategoryDescription(html);
    for (final block in blocks) {
      for (final span in block.spans) {
        final href = span.href;
        if (href == null || _linkTaps.containsKey(href)) continue;
        _linkTaps[href] = TapGestureRecognizer()..onTap = () => _openLink(href);
      }
    }
    setState(() => _blocks = blocks);
  }

  /// The copy links to storefront pages (`/eg-en/kidswear.html`,
  /// `/eg-ar/why-sell-on-locafy-ar`). There is no in-app route for a CMS page
  /// and no url_path on the category tree to match the rest against, so these
  /// open the website rather than pretending to be app navigation.
  void _openLink(String href) {
    final url = href.startsWith('http')
        ? href
        : '${ServerConfig().url}${href.startsWith('/') ? '' : '/'}$href';
    Tools.launchURL(url);
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();

    final title = _blocks.first;
    final rest = _blocks.skip(1).toList();
    // The tagline sits with the title above the toggle, like the website; the
    // body starts after it.
    final hasTagline = rest.isNotEmpty && rest.first.kind == CategoryDescriptionKind.tagline;
    final tagline = hasTagline ? rest.first : null;
    final body = hasTagline ? rest.skip(1).toList() : rest;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The 6px accent bar across the top of the card.
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kAccent, _kAccentLight]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBlock(title),
                if (tagline != null) _buildBlock(tagline),
                if (body.isNotEmpty) _buildToggle(),
                if (_expanded) ...body.map(_buildBlock),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _expanded ? S.of(context).hideDetails : S.of(context).readMore,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(CategoryDescriptionBlock block) {
    switch (block.kind) {
      case CategoryDescriptionKind.title:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _text(block,
              const TextStyle(
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: _kHeadingText,
              )),
        );
      case CategoryDescriptionKind.tagline:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _text(block,
              const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                color: _kMutedText,
              )),
        );
      case CategoryDescriptionKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: _text(block,
              const TextStyle(
                fontSize: 18,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: _kHeadingText,
              )),
        );
      case CategoryDescriptionKind.question:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _text(block,
              const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: _kHeadingText,
              )),
        );
      case CategoryDescriptionKind.callout:
        final href = block.spans.first.href;
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: href == null ? null : () => _openLink(href),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kCalloutBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _text(
                  block,
                  const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kAccent,
                  ),
                  // The whole box is the tap target; a second one inside it
                  // would just be the same destination.
                  plain: true,
                ),
              ),
            ),
          ),
        );
      case CategoryDescriptionKind.divider:
        return const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 16),
          child: Divider(height: 1, thickness: 1, color: _kBorder),
        );
      case CategoryDescriptionKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(color: _kBodyText)),
              Expanded(child: _text(block, _bodyStyle)),
            ],
          ),
        );
      case CategoryDescriptionKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _text(block, _bodyStyle),
        );
    }
  }

  static const _bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.7,
    color: _kBodyText,
  );

  /// Renders a block's runs, styling the linked ones and wiring their taps.
  /// [plain] keeps the link styling but drops the inline tap target, for a
  /// block that is itself one big link.
  Widget _text(CategoryDescriptionBlock block, TextStyle style,
      {bool plain = false}) {
    if (block.spans.length == 1 && block.spans.first.href == null) {
      return Text(block.spans.first.text, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final span in block.spans)
            TextSpan(
              text: span.text,
              style: span.href == null
                  ? null
                  : const TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w600,
                    ),
              recognizer:
                  (plain || span.href == null) ? null : _linkTaps[span.href],
            ),
        ],
      ),
      style: style,
    );
  }

}

enum CategoryDescriptionKind { title, tagline, heading, paragraph, question, callout, divider, bullet }

/// A run of text inside a block; [href] marks it as a link.
class CategoryDescriptionSpan {
  final String text;
  final String? href;

  const CategoryDescriptionSpan(this.text, {this.href});
}

class CategoryDescriptionBlock {
  final CategoryDescriptionKind kind;
  final List<CategoryDescriptionSpan> spans;

  const CategoryDescriptionBlock(this.kind, this.spans);

  /// The block's text with the link runs folded back in — used by tests and
  /// anything that only needs the words.
  String get text => spans.map((s) => s.text).join();

  bool get isTitle => kind == CategoryDescriptionKind.title;
  bool get isTagline => kind == CategoryDescriptionKind.tagline;
  bool get isHeading => kind == CategoryDescriptionKind.heading;
  bool get isCallout => kind == CategoryDescriptionKind.callout;
  bool get isDivider => kind == CategoryDescriptionKind.divider;
  bool get isQuestion => kind == CategoryDescriptionKind.question;
}

/// Reduce the stored category HTML to renderable blocks.
///
/// PageBuilder keeps the authored markup HTML-escaped inside a
/// `data-content-type="html"` node, so the first parse yields the real markup
/// as *text* — parse that again to get elements.
///
/// The copy lives in a `locafy-seo-box…` wrapper, which is what the website
/// renders as the category description. An L3 description usually leads with
/// a PageBuilder tile grid linking its subcategories — the app already has
/// that strip, and the tile labels would otherwise come through as a list of
/// shouty one-word paragraphs — so when the wrapper is there, only its
/// contents are read.
List<CategoryDescriptionBlock> parseCategoryDescription(String html) {
  try {
    final outer = html_parser.parse(html);
    final inner = outer.body?.text ?? '';
    final blocks = _collect(outer);
    if (inner.contains('<') && inner.contains('>')) {
      final nested = _collect(html_parser.parse(inner));
      if (nested.isNotEmpty) return nested;
    }
    return blocks;
  } catch (_) {
    return const [];
  }
}

List<CategoryDescriptionBlock> _collect(dom.Document document) {
  document.querySelectorAll('style, script').forEach((e) => e.remove());
  // `locafy-seo-box`, `locafy-seo-box-3`, `locafy-seo-box-kboys`, … — the
  // suffix varies per category, the prefix doesn't.
  final scope = document.querySelector('[id^="locafy-seo-box"]') ??
      document.documentElement;
  final blocks = <CategoryDescriptionBlock>[];
  if (scope != null) _walk(scope, blocks);

  if (blocks.isEmpty) return blocks;
  // The first heading is the card title; a text-only <div> ahead of the body
  // copy is the tagline that sits under it.
  final first = blocks.first;
  if (first.kind == CategoryDescriptionKind.heading) {
    blocks[0] = CategoryDescriptionBlock(CategoryDescriptionKind.title, first.spans);
  }
  return blocks;
}

void _walk(dom.Element element, List<CategoryDescriptionBlock> blocks) {
  for (final child in element.children) {
    final tag = child.localName;
    final style = child.attributes['style'] ?? '';
    final id = child.id;

    // The website's own expander — this card supplies its own.
    if (tag == 'button' || id.contains('readmore')) continue;

    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
        _add(blocks, CategoryDescriptionKind.heading, child);
        continue;
      case 'p':
        _add(blocks, _paragraphKind(child), child);
        continue;
      case 'li':
        _add(blocks, CategoryDescriptionKind.bullet, child);
        continue;
      case 'div':
        // The FAQ block is wrapped in a div with a top rule.
        if (style.contains('border-top')) {
          blocks.add(const CategoryDescriptionBlock(CategoryDescriptionKind.divider, []));
        }
        // A div with no element children is a text line: the tagline above
        // the body, or a stray line of copy further down.
        if (child.children.isEmpty) {
          final hasBody = blocks.any((b) => b.kind != CategoryDescriptionKind.heading);
          _add(blocks, hasBody ? CategoryDescriptionKind.paragraph : CategoryDescriptionKind.tagline, child);
          continue;
        }
        _walk(child, blocks);
        continue;
      default:
        _walk(child, blocks);
    }
  }
}

/// A paragraph whose whole content is one boxed link is the "learn more"
/// callout; one set in bold is an FAQ question.
CategoryDescriptionKind _paragraphKind(dom.Element p) {
  final links = p.querySelectorAll('a');
  if (links.length == 1 &&
      (links.first.attributes['style'] ?? '').contains('background') &&
      p.text.trim() == links.first.text.trim()) {
    return CategoryDescriptionKind.callout;
  }
  final weight = RegExp(r'font-weight:\s*(\d+)')
      .firstMatch(p.attributes['style'] ?? '')
      ?.group(1);
  if (weight != null && (int.tryParse(weight) ?? 400) >= 600) {
    return CategoryDescriptionKind.question;
  }
  return CategoryDescriptionKind.paragraph;
}

void _add(
    List<CategoryDescriptionBlock> blocks, CategoryDescriptionKind kind, dom.Element element) {
  final spans = _spans(element);
  if (spans.isEmpty) return;
  // A leftover CSS fragment from a truncated PageBuilder style block — not
  // prose, and not something to show a shopper.
  final text = spans.map((s) => s.text).join();
  if (text.contains('{') || text.contains('}')) return;
  blocks.add(CategoryDescriptionBlock(kind, spans));
}

/// Flatten an element into text runs, keeping `<a>` runs separate so they can
/// be styled and tapped.
List<CategoryDescriptionSpan> _spans(dom.Element element) {
  final spans = <CategoryDescriptionSpan>[];

  void visit(dom.Node node, String? href) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.trim().isEmpty && spans.isEmpty) return;
      spans.add(CategoryDescriptionSpan(text, href: href));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (tag == 'style' || tag == 'script' || tag == 'button') return;
    final linkHref = tag == 'a' ? (node.attributes['href'] ?? href) : href;
    for (final child in node.nodes) {
      visit(child, linkHref);
    }
  }

  for (final node in element.nodes) {
    visit(node, null);
  }

  // Merge neighbouring runs that share a destination, then trim the ends.
  final merged = <CategoryDescriptionSpan>[];
  for (final span in spans) {
    if (merged.isNotEmpty && merged.last.href == span.href) {
      merged[merged.length - 1] = CategoryDescriptionSpan(
        merged.last.text + span.text,
        href: span.href,
      );
    } else {
      merged.add(span);
    }
  }
  if (merged.isNotEmpty) {
    merged[0] = CategoryDescriptionSpan(merged.first.text.trimLeft(),
        href: merged.first.href);
    merged[merged.length - 1] = CategoryDescriptionSpan(
        merged.last.text.trimRight(),
        href: merged.last.href);
  }
  merged.removeWhere((s) => s.text.isEmpty);
  // Links carry their own padding in the source ("\n  t-shirts\n"); tighten
  // them so the sentence reads as one line.
  for (var i = 0; i < merged.length; i++) {
    if (merged[i].href != null) {
      merged[i] =
          CategoryDescriptionSpan(merged[i].text.trim(), href: merged[i].href);
    }
  }
  return merged.where((s) => s.text.isNotEmpty).toList();
}
