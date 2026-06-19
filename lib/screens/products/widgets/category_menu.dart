import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/config.dart';
import '../../../generated/l10n.dart';
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
      var parentCategoryId = widget.newCategoryId;

      parentCategoryId =
          getParentCategories(categoryModel.categories, parentCategoryId) ??
              parentCategoryId;
      var parentCategory =
          categoryModel.categoryList[parentCategoryId.toString()]?.copyWith() ??
              Category(subCategories: [], id: parentCategoryId);
      parentCategory.name = S.of(context).seeAll;
      final listSubCategory =
          getSubCategories(categoryModel.categories, parentCategoryId)!;
      if (categoryModel.isLoading) {
        return Center(child: kLoadingWidget(context));
      }
      if (listSubCategory.length < 2) {
        return const SizedBox(width: double.infinity);
      }
    //  listSubCategory.insert(0, parentCategory);
      return renderListCategories(listSubCategory);
    });
  }

  String? getParentCategories(List<Category>? categories, id) {
    for (var item in (categories ?? <Category>[])) {
      if (item.id == id) {
        return (item.parent == null || item.isRoot) ? null : item.parent;
      }
    }
    return null;
  }

  List<Category>? getSubCategories(categories, id) {
    return categories.where((o) => o.parent == id).toList();
  }
}
