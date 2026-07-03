import 'package:flutter/foundation.dart';

import '../../frameworks/magento/services/magento_service.dart';
import '../../services/index.dart';
import '../entities/category_filter.dart';

/// Web-parity layered-navigation filters for the product-listing (category)
/// page: the available attribute options + counts fetched from the storefront
/// GraphQL `aggregations`, plus the shopper's current selection.
///
/// Selection is keyed by `attribute_code` → set of selected option ids. The
/// product query applies these as extra REST `searchCriteria[filter_groups]`
/// (one group per attribute — values OR'd within an attribute, attributes
/// AND'd across each other), exactly mirroring Magento layered navigation and
/// the website. See docs/qa-followups.md item 3.
class CategoryFilterModel extends ChangeNotifier {
  List<CategoryFilterAttribute> _attributes = const [];
  List<CategoryFilterAttribute> get attributes => _attributes;

  /// attribute_code -> selected option ids.
  final Map<String, Set<String>> _selected = {};

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// The category the currently-held [attributes]/selection belong to, so the
  /// selection can be reset when the shopper navigates to a different one.
  String? _categoryId;

  bool get hasSelection => _selected.values.any((s) => s.isNotEmpty);

  int get selectedCount =>
      _selected.values.fold(0, (sum, s) => sum + s.length);

  bool isSelected(String code, String value) =>
      _selected[code]?.contains(value) ?? false;

  /// Selected filters as `attribute_code` -> option ids, with empty
  /// attributes dropped. Consumed by the product query to build REST filter
  /// groups.
  Map<String, List<String>> get selectedFilters => {
        for (final entry in _selected.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.toList(),
      };

  /// All currently-selected options flattened, for rendering removable chips
  /// in the listing toolbar.
  List<CategoryFilterOption> get selectedOptions => [
        for (final attr in _attributes)
          for (final opt in attr.options)
            if (isSelected(opt.code, opt.value)) opt,
      ];

  /// Load the available filters for [categoryId]. When the category changes,
  /// any prior selection is cleared synchronously (filters are
  /// category-scoped) so a stale selection can never leak onto a new
  /// category's product query. Safe to call without awaiting.
  Future<void> load(String? categoryId, String lang) async {
    final api = Services().api;
    if (api is! MagentoService || categoryId == null) {
      _selected.clear();
      _attributes = const [];
      _categoryId = categoryId;
      notifyListeners();
      return;
    }

    if (categoryId != _categoryId) {
      _selected.clear();
      _attributes = const [];
    }
    _categoryId = categoryId;
    _isLoading = true;
    notifyListeners();

    try {
      final result =
          await api.fetchCategoryFilters(categoryId: categoryId, lang: lang);
      // Guard against a stale response arriving after the shopper moved on.
      if (categoryId == _categoryId) {
        _attributes = result;
      }
    } catch (_) {
      if (categoryId == _categoryId) _attributes = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggle(String code, String value) {
    final set = _selected.putIfAbsent(code, () => <String>{});
    if (!set.remove(value)) set.add(value);
    if (set.isEmpty) _selected.remove(code);
    notifyListeners();
  }

  void clearAll() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }
}
