import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

import '../../../frameworks/magento/services/magento_service.dart';
import '../../../generated/l10n.dart';
import '../../../models/app_model.dart';
import '../../../services/index.dart';

/// The category's own description — the SEO box the website renders directly
/// under the category title (e.g. loca-men/clothing/jackets.html): a heading,
/// body copy and an FAQ, collapsed behind a "Read more".
///
/// Locafy authors it on the deepest (L3) categories only; the L1/L2 nodes
/// carry PageBuilder banner markup instead, which is nav duplication rather
/// than prose — [MagentoService.fetchCategoryDescription] filters those out.
/// The stored HTML is heavily inline-styled and its own read-more is
/// JS-driven, so the markup is reduced to text blocks here and re-rendered
/// with the app's own expander.
class CategoryDescription extends StatefulWidget {
  final String? categoryId;

  const CategoryDescription({super.key, this.categoryId});

  @override
  State<CategoryDescription> createState() => _CategoryDescriptionState();
}

class _CategoryDescriptionState extends State<CategoryDescription> {
  List<CategoryDescriptionBlock> _blocks = const [];
  bool _expanded = false;

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

  Future<void> _load() async {
    final id = widget.categoryId;
    if (id == _pendingId) return;
    _pendingId = id;
    // A rebuild always follows the call sites (first build / category switch),
    // so reset in place rather than asking for another one.
    _blocks = const [];
    _expanded = false;

    final api = Services().api;
    if (id == null || id.isEmpty || api is! MagentoService) return;

    final lang = Provider.of<AppModel>(context, listen: false).langCode;
    final html = await api.fetchCategoryDescription(id, lang: lang);
    if (!mounted || _pendingId != id || html == null) return;
    setState(() => _blocks = parseCategoryDescription(html));
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // Collapsed state shows the heading plus the opening paragraph — the same
    // teaser the website leaves above its "read more" link.
    final visible = _expanded ? _blocks : _blocks.take(2).toList();
    final hasMore = _blocks.length > visible.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in visible) _buildBlock(context, block),
          if (hasMore || _expanded)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _expanded ? S.of(context).readLess : S.of(context).readMore,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, CategoryDescriptionBlock block) {
    final theme = Theme.of(context);
    switch (block.tag) {
      case 'h1':
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            block.text,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      case 'h3':
      case 'h4':
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 12),
          child: Text(
            block.text,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: theme.textTheme.bodyMedium),
              Expanded(child: Text(block.text, style: _bodyStyle(theme))),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(block.text, style: _bodyStyle(theme)),
        );
    }
  }

  TextStyle? _bodyStyle(ThemeData theme) => theme.textTheme.bodyMedium?.copyWith(
        height: 1.6,
        color: theme.colorScheme.secondary.withOpacity(0.8),
      );
}

class CategoryDescriptionBlock {
  final String tag;
  final String text;

  const CategoryDescriptionBlock(this.tag, this.text);
}

/// Reduce the stored category HTML to renderable text blocks.
///
/// PageBuilder keeps the authored markup HTML-escaped inside a
/// `data-content-type="html"` node, so the first parse yields the real markup
/// as *text* — parse that again to get elements. `<style>`/`<script>` and any
/// leftover CSS fragment are dropped so a category whose description is a
/// styled banner renders nothing rather than raw code.
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
  final blocks = <CategoryDescriptionBlock>[];
  for (final element in document.querySelectorAll('h1, h2, h3, h4, p, li')) {
    final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // A truncated PageBuilder <style> block or stray markup — not prose.
    if (text.isEmpty || text.contains('{') || text.contains('}')) continue;
    blocks.add(CategoryDescriptionBlock(element.localName!, text));
  }
  return blocks;
}
