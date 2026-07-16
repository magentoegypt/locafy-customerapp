import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/config.dart';
import '../../../models/index.dart';
import 'item_category.dart';

class ProductCategoryMenu extends StatefulWidget {
  final bool enableSearchHistory;
  final String isComingFrom;
  final bool imageLayout;
  final String? newCategoryId;
  final Function(String?,String?)? onTap;

  const ProductCategoryMenu({
    super.key,
    this.enableSearchHistory = false,
    this.isComingFrom = "",
    this.imageLayout = false,
    this.newCategoryId,
    this.onTap,
  });

  @override
  StateProductCategoryMenu createState() => StateProductCategoryMenu();
}

class StateProductCategoryMenu extends State<ProductCategoryMenu> {
  bool get categoryImageMenu => kAdvanceConfig.categoryImageMenu;

  Widget renderListCategories(List<Category> categories) {
    var categoryMenu = categoryImageMenu;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      color: Theme.of(context).colorScheme.background,
      constraints: const BoxConstraints(minHeight: 50),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: widget.isComingFrom == "product_screen" ?  Axis.horizontal:Axis.vertical,
          child: widget.isComingFrom == "product_screen" ?  Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              categories.length,
              (index) {
                var category = categories[index];
                var highlightColor = widget.newCategoryId == category.id
                    ? Theme.of(context).colorScheme.secondary.withOpacity(0.2)
                    : Colors.transparent;
                return GestureDetector(
                  onTap: () => widget.onTap?.call(category.id,category.name!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    margin: const EdgeInsets.only(left: 5, top: 10, bottom: 4),
                    decoration: BoxDecoration(
                      color: highlightColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        category.name!.toUpperCase(),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ): Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              categories.length,
                  (index) {
                var category = categories[index];
                return ItemCategory(
                  categoryId: category.id,
                  categoryName: category.name!,
                  categoryImage: categoryMenu && widget.imageLayout
                      ? category.image
                      : null,
                  newCategoryId: widget.newCategoryId,
                  onTap: widget.onTap,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableSearchHistory) {
      return const SizedBox(width: double.infinity);
    }

    return Consumer<CategoryModel>(builder: (context, categoryModel, child) {
      if (categoryModel.isLoading) {
        return Center(child: kLoadingWidget(context));
      }

      /// Website parity: a category page lists its OWN child categories —
      /// Boys -> Outwear / Homewear / Footwear / Underwear.
      ///
      /// This used to walk UP to the parent and list the parent's children,
      /// i.e. the current category's SIBLINGS, which is exactly what QA
      /// reported as the page showing "the remaining subcategories of the main
      /// category" (86d3g3mea). A leaf category (a sub-subcategory such as
      /// "Outwear boy") has no children, so the row now disappears on its own —
      /// which is what 86d3g43qr asks for ("all tabs showing categories or
      /// subcategories should be removed from this page").
      final children =
          getSubCategories(categoryModel.categories, widget.newCategoryId) ??
              <Category>[];
      if (children.isEmpty) {
        return const SizedBox(width: double.infinity);
      }
      return renderListCategories(children);
    });
  }

  List<Category>? getSubCategories(categories, id) {
    return categories.where((o) => o.parent == id).toList();
  }
}
