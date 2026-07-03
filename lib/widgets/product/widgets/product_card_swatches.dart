import 'package:flutter/material.dart';
import 'package:inspireui/inspireui.dart' show HexColor;

import '../../../models/entities/ProdcutOptionAttribute.dart';
import '../../../models/entities/product.dart';

/// Compact colour-swatch strip for a product grid card. Shows the available
/// colours of a configurable product (from extension_attributes.swatches) as
/// small dots, so shoppers can see the colour options without opening the PDP.
/// Renders nothing unless the product genuinely has 2+ colour options.
class ProductCardSwatches extends StatelessWidget {
  final Product product;
  final int maxDots;

  const ProductCardSwatches({
    super.key,
    required this.product,
    this.maxDots = 4,
  });

  ConfigurableSwatch? _colorSwatch() {
    final swatches = product.swatches;
    if (swatches == null || swatches.isEmpty) {
      return null;
    }
    ConfigurableSwatch? candidate;
    for (final s in swatches) {
      final isColorAttr = s.attributeCode == 'all_color' ||
          s.options.any((o) => o.isColor || (o.productImage?.isNotEmpty ?? false));
      if (isColorAttr && s.options.length > 1) {
        // Prefer the canonical colour attribute.
        if (s.attributeCode == 'all_color') {
          return s;
        }
        candidate ??= s;
      }
    }
    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final swatch = _colorSwatch();
    if (swatch == null) {
      return const SizedBox.shrink();
    }
    final options = swatch.options
        .where((o) =>
            (o.swatchValue?.isNotEmpty ?? false) ||
            (o.productImage?.isNotEmpty ?? false))
        .toList();
    if (options.length < 2) {
      return const SizedBox.shrink();
    }

    final shown = options.take(maxDots).toList();
    final extra = options.length - shown.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == shown.length - 1 ? 0 : 4),
              child: _dot(context, shown[i]),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, SwatchOption option) {
    final border = Border.all(
      color: Theme.of(context).colorScheme.secondary.withOpacity(0.35),
    );
    final hex = option.swatchValue;
    final isHex = option.isColor && (hex?.startsWith('#') ?? false);

    if (isHex) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: HexColor(hex!),
          shape: BoxShape.circle,
          border: border,
        ),
      );
    }

    // Fall back to a tiny product-image dot when there's no hex colour.
    final imageUrl = (option.productImage?.isNotEmpty ?? false)
        ? option.productImage
        : ((hex?.contains('http') ?? false) ? hex : null);
    if (imageUrl != null) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(shape: BoxShape.circle, border: border),
        child: ClipOval(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
