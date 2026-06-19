import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';

import '../../common/config.dart';
import '../../common/constants.dart';
import '../../common/tools.dart';
import '../../generated/l10n.dart';
import '../../models/entities/product.dart';

enum VariantLayout { inline, dropdown }

class BasicSelection extends StatelessWidget {
  final Product? product;
  final Map<String?, String?>? imageUrls;
  final List<String?> options;
  final String? value;
  final String? title;
  final String? type;
  final Function? onChanged;
  final VariantLayout? layout;

  const BasicSelection(
      {super.key,
        required this.product,
      required this.options,
      required this.title,
      required this.value,
      this.type,
      this.layout,
      this.onChanged,
      this.imageUrls});

  @override
  Widget build(BuildContext context) {
    var primaryColor = Theme.of(context).primaryColor;
    if (const ['option', 'dropdown'].contains(type)) {
      return OptionSelection(
        options: options,
        value: value,
        title: title,
        onChanged: onChanged,
      );
    }
    final validValue = options.contains(value) ? value : null;
    if (type == 'image') {
      return ImageSelection(
        imageUrls: imageUrls,
        options: options,
        value: value,
        title: title,
        onChanged: onChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  // ignore: prefer_single_quotes
                  "${title![0].toUpperCase()}${title!.substring(1)}",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ],
        ),

        DropdownButtonFormField<String>(
          initialValue: validValue,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
            ),
          ),
          icon: const Icon(Icons.arrow_drop_down),
          items: options.map<DropdownMenuItem<String>>((item) {
            final optionValue = item ?? '';

            if (type == 'color') {
              final colorCode = getColorCode(optionValue);
              final isImage = colorCode.contains("http");
              final bgColor = HexColor(isImage ? '#ffffff' : colorCode);

              return DropdownMenuItem<String>(
                value: optionValue,
                child: Row(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: bgColor,
                        image: isImage
                            ? DecorationImage(
                          image: NetworkImage(colorCode),
                          fit: BoxFit.cover,
                        )
                            : null,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.3),
                        ),
                      ),
                      child: optionValue.toUpperCase() == (value ?? '').toUpperCase()
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        optionValue,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return DropdownMenuItem<String>(
                value: optionValue,
                child: Text(
                  optionValue,
                  style: TextStyle(
                    color: optionValue == value
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.secondary,
                    fontSize: 14,
                  ),
                ),
              );
            }
          }).toList(),
          onChanged: (newValue) {
            if (onChanged != null) {
              onChanged!(newValue);
            }
          },
        ),

        // Wrap(
        //   spacing: 0.0,
        //   runSpacing: 12.0,
        //   children: <Widget>[
        //     for (var item in options)
        //       GestureDetector(
        //         onTap: () => onChanged!(item),
        //         behavior: HitTestBehavior.opaque,
        //         child: Tooltip(
        //           message: item.toString(),
        //           verticalOffset: 32,
        //           preferBelow: false,
        //           child: AnimatedContainer(
        //             duration: const Duration(milliseconds: 300),
        //             curve: Curves.easeIn,
        //             margin: const EdgeInsets.only(
        //               right: 12.0,
        //               top: 8.0,
        //             ),
        //             decoration: type == 'color'
        //                 ? BoxDecoration(
        //                     color: item!.toUpperCase() == value!.toUpperCase()
        //                         ? HexColor(getColorCode(item).contains("http") ? '#ffffff':getColorCode(item))
        //                     // HexColor(kNameToHex[getColorCode(item)
        //                     //             .toString()
        //                     //             .replaceAll(' ', '_')
        //                     //             .toLowerCase()] ??
        //                     //         '#ffffff')
        //                         : HexColor(getColorCode(item).contains("http") ? '#ffffff':getColorCode(item))
        //                             .withOpacity(1.0),
        //               image: getColorCode(item).contains("http") ? DecorationImage(
        //                 image: NetworkImage(getColorCode(item)),
        //                 fit: BoxFit.fill,
        //               ):null,
        //                     borderRadius: BorderRadius.circular(25),
        //                     border: Border.all(
        //                       width: 1.0,
        //                       color: Theme.of(context)
        //                           .colorScheme
        //                           .secondary
        //                           .withOpacity(0.3),
        //                     ),
        //                   )
        //                 : BoxDecoration(
        //                     color: item!.toUpperCase() == value!.toUpperCase()
        //                         ? primaryColor
        //                         : Colors.transparent,
        //                     borderRadius: BorderRadius.circular(5.0),
        //                     border: Border.all(
        //                       color: Theme.of(context)
        //                           .colorScheme
        //                           .secondary
        //                           .withOpacity(0.3),
        //                     ),
        //                   ),
        //             child: type == 'color'
        //                 ? SizedBox(
        //                     height: 25,
        //                     width: 25,
        //                     child: item == value
        //                         ? const Icon(
        //                             Icons.check,
        //                             color: Colors.white,
        //                             size: 16,
        //                           )
        //                         : const SizedBox(),
        //                   )
        //                 : Container(
        //                     constraints: const BoxConstraints(minWidth: 40),
        //                     padding:
        //                         const EdgeInsets.only(left: 10.0, right: 10.0),
        //                     child: Padding(
        //                       padding:
        //                           const EdgeInsets.only(top: 10, bottom: 10),
        //                       child: Text(
        //                         item,
        //                         textAlign: TextAlign.center,
        //                         style: TextStyle(
        //                           color: item == value
        //                               ? Colors.white
        //                               : Theme.of(context).colorScheme.secondary,
        //                           fontSize: 14,
        //                         ),
        //                       ),
        //                     ),
        //                   ),
        //           ),
        //         ),
        //       )
        //   ],
        // ),

      ],
    );
  }
   String getColorCode(String item){
     String colorCode = "#ffffff";
     product?.productOptions?.forEach((element){
         if(element.label == item){
           colorCode = element.swatch?.value ?? "#ffffff";
         }
     });
     return colorCode;
  }
}

class OptionSelection extends StatelessWidget {
  final List<String?> options;
  final String? value;
  final String? title;
  final Function? onChanged;
  final VariantLayout? layout;

  const OptionSelection({
    super.key,
    required this.options,
    required this.value,
    this.title,
    this.layout,
    this.onChanged,
  });

  // ignore: always_declare_return_types
  showOptions(context) {
    showModalBottomSheet(
      context: context,
      // https://github.com/inspireui/support/issues/4814#issuecomment-684179116
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.5,
          snap: true,
          snapSizes: const [
            0.5,
            0.85,
          ],
          minChildSize: 0.25,
          builder: (BuildContext context, ScrollController scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    title: Text(
                      S.of(context).selectTheSize,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withOpacity(0.8),
                          ),
                    ),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  for (final option in options)
                    ListTile(
                      onTap: () {
                        onChanged!(option);
                        Navigator.pop(context);
                      },
                      title: Text(
                        option!.replaceAll('&amp;', '&'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showOptions(context),
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  // ignore: prefer_single_quotes
                  "${title![0].toUpperCase()}${title!.substring(1)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              Text(
                value!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: kGrey600)
            ],
          ),
        ),
      ),
    );
  }
}

class ColorSelection extends StatelessWidget {
  final List<String> options;
  final String value;
  final Function? onChanged;
  final VariantLayout? layout;

  const ColorSelection(
      {super.key,
      required this.options,
      required this.value,
      this.layout,
      this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (layout == VariantLayout.dropdown) {
      return GestureDetector(
        onTap: () => showOptions(context),
        child: Container(
          decoration:
              BoxDecoration(border: Border.all(width: 1.0, color: kGrey200)),
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(S.of(context).color,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                    height: 20,
                    width: 20,
                    decoration: BoxDecoration(
                        color: kNameToHex[value.toLowerCase()] != null
                            ? HexColor(kNameToHex[value.toLowerCase()]!)
                            : Colors.transparent)),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down, size: 16, color: kGrey600)
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 25,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Center(
              child: Text(
                S.of(context).color,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 15.0),
            for (var item in options)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeIn,
                margin: const EdgeInsets.only(right: 20.0),
                decoration: BoxDecoration(
                  color: item == value
                      ? HexColor(kNameToHex[item.toLowerCase()]!)
                      : HexColor(kNameToHex[item.toLowerCase()]!)
                          .withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                      width: 1.0,
                      color: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.5)),
                ),
                child: InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onTap: () {
                    onChanged!(item);
                  },
                  child: SizedBox(
                    height: 25,
                    width: 25,
                    child: item == value
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          )
                        : const SizedBox(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void showOptions(context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final option in options)
                ListTile(
                  onTap: () {
                    onChanged!(option);
                    Navigator.pop(context);
                  },
                  title: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3.0),
                        border: Border.all(
                            width: 1.0,
                            color: Theme.of(context).colorScheme.secondary),
                        color: HexColor(kNameToHex[option.toLowerCase()]!),
                      ),
                    ),
                  ),
                ),
              Container(
                height: 1,
                decoration: const BoxDecoration(color: kGrey200),
              ),
              ListTile(
                title: Text(
                  S.of(context).selectTheColor,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ImageSelection extends StatelessWidget {
  final Map<String?, String?>? imageUrls;
  final List<String?> options;
  final String? value;
  final String? title;
  final Function? onChanged;
  final VariantLayout? layout;

  const ImageSelection({
    super.key,
    required this.options,
    required this.value,
    this.title,
    this.layout,
    this.onChanged,
    this.imageUrls,
  });

  @override
  Widget build(BuildContext context) {
    final size = kProductDetail.attributeImagesSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  // ignore: prefer_single_quotes
                  "${title![0].toUpperCase()}${title!.substring(1)}",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 0.0,
          children: <Widget>[
            for (var item in options)
              GestureDetector(
                onTap: () => onChanged!(item),
                child: Tooltip(
                  message: HtmlUnescape().convert(item!),
                  preferBelow: false,
                  verticalOffset: 32,
                  child: Container(
                    margin: const EdgeInsets.all(8.0),
                    child: Container(
                      width: size + 2,
                      height: size + 2,
                      padding: const EdgeInsets.all(2.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5.0),
                        border: Border.all(
                          width: 1.0,
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withOpacity(
                                  item.toUpperCase() == value!.toUpperCase()
                                      ? 0.6
                                      : 0.3),
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (imageUrls![item]?.isNotEmpty ?? false)
                            Positioned.fill(
                              child: ImageResize(
                                url: imageUrls![item],
                                height: size,
                                width: size,
                              ),
                            )
                          else
                            Positioned.fill(
                              child: Center(
                                child: Text(
                                  HtmlUnescape().convert(item),
                                ),
                              ),
                            ),
                          if (item.toUpperCase() == value!.toUpperCase())
                            Positioned.fill(
                              child: Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .background
                                    .withOpacity(0.6),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
          ],
        ),
      ],
    );
  }
}
