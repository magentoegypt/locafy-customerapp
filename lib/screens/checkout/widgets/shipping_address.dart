import 'package:collection/collection.dart' show IterableExtension;
import 'package:country_pickers/country.dart' as picker_country;
import 'package:country_pickers/country_pickers.dart' as picker;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import 'package:inspireui/inspireui.dart';
import 'package:provider/provider.dart';

import '../../../common/config.dart';
import '../../../common/config/models/address_field_config.dart';
import '../../../common/constants.dart';
import '../../../common/tools/flash.dart';
import '../../../core/colors.dart';
import '../../../data/boxes.dart';
import '../../../generated/l10n.dart';
import '../../../models/index.dart'
    show Address, CartModel, City, Country, CountryState, UserModel;
import '../../../services/index.dart';
import '../../../widgets/common/common_safe_area.dart';
import '../../../widgets/common/flux_image.dart';
import '../../users/otp_dialog.dart';
import '../choose_address_screen.dart';

part 'shipping_address_extension.dart';

var dialCode = kPhoneNumberConfig.dialCodeDefault;
var isoCode = kPhoneNumberConfig.countryCodeDefault;
bool isPickerEnabled = true;
class ShippingAddress extends StatefulWidget {
  final Function? onNext;
  final Address? address;
  final bool isFromAddrssHistory;
  final bool isFromCheckout;

   ShippingAddress({this.onNext,this.address,required this.isFromAddrssHistory,required this.isFromCheckout});

  @override
  State<ShippingAddress> createState() => _ShippingAddressState();
}

class _ShippingAddressState extends State<ShippingAddress> {
  final _formKey = GlobalKey<FormState>();
  List<Address?> listAddress = [];

  final Map<int, AddressFieldType> _fieldPosition = {};

  final Map<int, AddressFieldConfig> _configs = {};

  final Map<AddressFieldType, TextEditingController> _textControllers = {
    AddressFieldType.firstName: TextEditingController(),
    AddressFieldType.lastName: TextEditingController(),
    AddressFieldType.phoneNumber: TextEditingController(),
    AddressFieldType.email: TextEditingController(),
    AddressFieldType.country: TextEditingController(),
    AddressFieldType.state: TextEditingController(),
    AddressFieldType.city: TextEditingController(),
    AddressFieldType.apartment: TextEditingController(),
    AddressFieldType.block: TextEditingController(),
    AddressFieldType.street: TextEditingController(),
    AddressFieldType.zipCode: TextEditingController(),
  };

  final Map<AddressFieldType, FocusNode> _focusNodes = {
    AddressFieldType.firstName: FocusNode(),
    AddressFieldType.lastName: FocusNode(),
    AddressFieldType.phoneNumber: FocusNode(),
    AddressFieldType.email: FocusNode(),
    AddressFieldType.state: FocusNode(),
    AddressFieldType.city: FocusNode(),
    AddressFieldType.apartment: FocusNode(),
    AddressFieldType.block: FocusNode(),
    AddressFieldType.street: FocusNode(),
    AddressFieldType.zipCode: FocusNode(),
  };

  Address? address;
  List<Country>? countries = [];
  List<CountryState>? states = [];
  List<City>? cities = [];
  List<City>? zones = [];
  var selectIndex = -1;
  String? phoneNumber,phoneNumberWithoutCountryCode;

  @override
  void dispose() {
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    /// Init field positions.
    if(widget.isFromCheckout && UserBox().isLoggedIn){
      getDataFromLocal();
    }else{
      for (var config in Configurations.addressFields) {
        final index = _fieldPosition.values.length;
        _configs[index] = config;
        _fieldPosition[index] = config.type;
      }
      if(widget.isFromAddrssHistory){
        address = Address();
        if(widget.address != null) {
          address?.id = widget.address?.id;
          address?.firstName = widget.address?.firstName;
          address?.lastName = widget.address?.lastName;
          address?.email = widget.address?.email;
          address?.phoneNumber = widget.address?.phoneNumber;
          address?.street = widget.address?.street;
          address?.city = widget.address?.city;
          address?.zipCode = widget.address?.zipCode;
          address?.state = widget.address?.state;
          address?.country = widget.address?.country;
          address?.countryId = widget.address?.countryId;
          loadUserInfoFromAddress(address);
          _textControllers[AddressFieldType.country]?.text = address?.country ?? "";
          // _textControllers[AddressFieldType.country]?.text = address!.countryId!;
          _textControllers[AddressFieldType.street]?.text = address?.street ?? "";
          _textControllers[AddressFieldType.city]?.text = address?.city ?? "";
          _textControllers[AddressFieldType.state]?.text = address?.state ?? "";
          _textControllers[AddressFieldType.zipCode]?.text = address?.zipCode ?? "";
        }
        loadCountry();
        refresh();
      }else{
        /// Pre-fill the address fields.
        WidgetsBinding.instance.endOfFrame.then(
              (_) async {
            /// Load saved addresses.
            final addressValue =
            await Provider.of<CartModel>(context, listen: false).getAddress();
            if (addressValue != null) {
              updateAddress(addressValue);
            } else {
              var user = Provider.of<UserModel>(context, listen: false).user;
              setState(() {
                // No default region: address.state is filled with the
                // governorate the user picks in the City dropdown. Seeding it
                // with DefaultStateISOCode made the summary show "SG".
                address = Address(country: kPaymentConfig.defaultCountryISOCode);
                _textControllers[AddressFieldType.country]?.text =
                address!.country!;
                _textControllers[AddressFieldType.state]?.text =
                    address!.state ?? '';
                if (user != null) {
                  address!.firstName = user.firstName;
                  address!.lastName = user.lastName;
                  address!.email = user.email;
                  loadUserInfoFromAddress(address);
                }
              });
            }

            /// Init default fields.
            for (var field in _configs.values) {
              if ([
                AddressFieldType.searchAddress,
                AddressFieldType.selectAddress,
                AddressFieldType.country,
                AddressFieldType.state,
              ].contains(field.type)) {
                /// Not support default value.
                continue;
              }

              /// Replace current value with default value.
              /// Force to use default value for non-editable field.
              if (field.defaultValue.isNotEmpty && !field.editable) {
                _textControllers[field.type]?.text = field.defaultValue;
                onTextFieldSaved(field.defaultValue, field.type);
              }

              /// When the field is editable, replacing only when it's empty.
              if (field.defaultValue.isNotEmpty &&
                  field.editable &&
                  (_textControllers[field.type]?.text.isEmpty ?? false)) {
                _textControllers[field.type]?.text = field.defaultValue;
                onTextFieldSaved(field.defaultValue, field.type);
              }
            }

            /// Load country list.
            countries = await Services().widget.loadCountries();
            var country = countries!.firstWhereOrNull((element) =>
            element.id == address?.country || element.code == address?.country);
            if (country == null) {
              if (countries!.isNotEmpty) {
                country = countries![0];
                address!.country = countries![0].code;
              } else {
                country = Country.fromConfig(address!.country, null, null, []);
              }
            } else {
              address!.country = country.code;
              address!.countryId = country.id;
            }
            _textControllers[AddressFieldType.country]?.text = country.code!;
            refresh();

            /// Load states.
            // states = await Services().widget.loadStates(country);
            // refresh();

            /// Load cities.
            // var state = states?.firstWhereOrNull(
            //       (element) =>
            //   element.id == address?.state || element.code == address?.state,
            // );

            cities = await Services().widget.loadCitiesWithCountry(country);
            // The city list holds the governorates (Magento regions); the
            // current selection lives in address.state.
            var city = cities?.firstWhereOrNull(
                  (element) => element.name == address?.state,
            );
            city ??= cities?.firstOrNull;

            /// Load zipCode
            if (city != null) {
               zones =
              await Services().widget.loadZones(city);
              // if (zipCode != null) {
              //   /// Override the default value with this value
              //   address!.zipCode = zipCode;
              //   _textControllers[AddressFieldType.zipCode]?.text = zipCode;
              // }
            }
            refresh();
                    },
        );
      }
    }
  }

  Future<void> loadCountry() async {
    countries = await Services().widget.loadCountries();
    var country = countries!.firstWhereOrNull((element) =>
    element.id == address?.country || element.code == address?.countryId);
    if (country == null) {
      if (countries!.isNotEmpty) {
        country = countries![0];
        address!.country = countries![0].code;
      } else {
        country = Country.fromConfig(address!.country, null, null, []);
      }
    } else {
      address!.country = country.code;
      address!.countryId = country.id;
    }
    _textControllers[AddressFieldType.country]?.text = country.code!;
    refresh();

    // Load the governorate (region) and district lists so the add/edit
    // address form shows the same dropdowns as the checkout address step.
    cities = await Services().widget.loadCitiesWithCountry(country);
    var city = cities?.firstWhereOrNull(
      (element) => element.name == address?.state,
    );
    city ??= cities?.firstOrNull;
    if (city != null) {
      final zonesList = await Services().widget.loadZones(city);
      if (zonesList != null) {
        zones = zonesList;
      }
    }
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    if(widget.isFromCheckout && UserBox().isLoggedIn){
      return listViewAddress();
    }else{
      if(widget.isFromAddrssHistory){
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColorLight,
            leading: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
              },
              child: const Icon(Icons.arrow_back_ios),
            ),
            title: Text(
              S.of(context).address,
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          body: addressForm(),
        );
      }else{
        return addressForm();
      }
    }

  }

  Widget addressForm(){
    var countryName = S.of(context).country;
    final currentCountry =
        _textControllers[AddressFieldType.country]?.text ?? '';
    if (currentCountry.isNotEmpty) {
      try {
        countryName =
            picker.CountryPickerUtils.getCountryByIsoCode(currentCountry).name;
      } catch (e) {
        countryName = S.of(context).country;
      }
    }

    if (address == null) {
      return SizedBox(height: 100, child: kLoadingWidget(context));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 50.0,
              ),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                      _fieldPosition.length,
                          (index) {
                        final isVisible = _configs[index]?.visible ?? true;
                        if (!isVisible) {
                          return const SizedBox();
                        }

                        final currentFieldType =
                            _fieldPosition[index] ?? AddressFieldType.unknown;

                        if (currentFieldType == AddressFieldType.country) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Text(
                                S.of(context).country,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.grey),
                              ),
                              (countries!.length == 1)
                                  ? Text(
                                picker.CountryPickerUtils
                                    .getCountryByIsoCode(
                                    countries![0].code!)
                                    .name,
                                style: const TextStyle(fontSize: 18),
                              )
                                  : GestureDetector(
                                onTap: _openCountryPickerDialog,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 20),
                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                        mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                        children: <Widget>[
                                          Expanded(
                                            child: Text(countryName,
                                                style: const TextStyle(
                                                    fontSize: 17.0)),
                                          ),
                                          const Icon(
                                              Icons.arrow_drop_down)
                                        ],
                                      ),
                                    ),
                                    const Divider(
                                      height: 1,
                                      color: kGrey900,
                                    )
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        if (currentFieldType == AddressFieldType.state &&
                            (states?.isNotEmpty ?? false)) {
                          return renderStateInput();
                        }

                        if (currentFieldType == AddressFieldType.city &&
                            (cities?.isNotEmpty ?? false)) {
                          return renderCityInput(index);
                        }

                        if (currentFieldType == AddressFieldType.email &&
                           widget.isFromAddrssHistory) {
                          return SizedBox();
                        }
                        if (currentFieldType == AddressFieldType.apartment &&
                            widget.isFromAddrssHistory) {
                          return SizedBox();
                        }
                        if (currentFieldType == AddressFieldType.block &&
                            (zones?.isNotEmpty ?? false)) {
                          return renderZoneInput(index);
                        }

                        if (currentFieldType ==
                            AddressFieldType.searchAddress) {
                          if (kPaymentConfig.allowSearchingAddress &&
                              kGoogleApiKey.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 10.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ButtonTheme(
                                      height: 60,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                          Theme.of(context).primaryColor,
                                          elevation: 0.0,
                                        ),
                                        onPressed: () async {
                                          // final result =
                                          //     await Navigator.of(context).push(
                                          //   MaterialPageRoute(
                                          //     builder: (context) => PlacePicker(
                                          //       kIsWeb
                                          //           ? kGoogleApiKey.web
                                          //           : isIos
                                          //               ? kGoogleApiKey.ios
                                          //               : kGoogleApiKey.android,
                                          //     ),
                                          //   ),
                                          // );
                                          //
                                          // if (result is LocationResult) {
                                          //   address!.country = result.country;
                                          //   address!.street = result.street;
                                          //   address!.state = result.state;
                                          //   address!.city = result.city;
                                          //   address!.zipCode = result.zip;
                                          //   if (result.latLng?.latitude !=
                                          //           null &&
                                          //       result.latLng?.latitude !=
                                          //           null) {
                                          //     address!.mapUrl =
                                          //         'https://maps.google.com/maps?q=${result.latLng?.latitude},${result.latLng?.longitude}&output=embed';
                                          //     address!.latitude = result
                                          //         .latLng?.latitude
                                          //         .toString();
                                          //     address!.longitude = result
                                          //         .latLng?.longitude
                                          //         .toString();
                                          //   }
                                          //
                                          //   loadAddressFields(address);
                                          //   final c = Country(
                                          //       id: result.country,
                                          //       name: result.country);
                                          //   states = await Services()
                                          //       .widget
                                          //       .loadStates(c);
                                          //   setState(() {});
                                          // }
                                        },
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.center,
                                          children: <Widget>[
                                            const Icon(
                                              CupertinoIcons
                                                  .arrow_up_right_diamond,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 10.0),
                                            Text(S
                                                .of(context)
                                                .searchingAddress
                                                .toUpperCase()),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox();
                        }
                        if (currentFieldType ==
                            AddressFieldType.selectAddress && widget.isFromAddrssHistory) {
                          return const SizedBox();
                        }
                        if (currentFieldType ==
                            AddressFieldType.selectAddress && !widget.isFromAddrssHistory) {
                          if(!UserBox().isLoggedIn)
                            return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: ButtonTheme(
                              height: 60,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor:
                                  Theme.of(context).primaryColor,
                                  elevation: 0.0,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ChooseAddressScreen(updateAddress,false),
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    const Icon(
                                      CupertinoIcons.person_crop_square,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10.0),
                                    Text(
                                      S.of(context).selectAddress.toUpperCase(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final currentFieldController =
                        _textControllers[currentFieldType];
                        final currentFieldFocusNode =
                        _focusNodes[currentFieldType];

                        var hasNext = false;
                        var nextFieldIndex = index + 1;
                        late var nextFieldType;
                        late var nextFieldFocus;
                        while (nextFieldIndex < _fieldPosition.length) {
                          nextFieldType = _fieldPosition[nextFieldIndex];
                          nextFieldFocus = _focusNodes[nextFieldType];
                          if (nextFieldType == AddressFieldType.country ||
                              (nextFieldType == AddressFieldType.state &&
                                  (states?.isNotEmpty ?? false)) ||
                              (nextFieldType == AddressFieldType.city &&
                                  (cities?.isNotEmpty ?? false))) {
                            hasNext = false;
                            break;
                          }
                          if (nextFieldFocus != null) {
                            hasNext = true;
                            break;
                          }
                          nextFieldIndex++;
                        }

                        // if (currentFieldType == AddressFieldType.phoneNumber &&
                        //     kPhoneNumberConfig.enablePhoneNumberValidation)
                        if (currentFieldType == AddressFieldType.phoneNumber)
                        {
                          return Directionality(
                              textDirection: TextDirection.ltr,
                              child: Column(
                                  children:[
                                  IgnorePointer(
                                  ignoring: !isPickerEnabled, // true = disable
                                  child: InternationalPhoneNumberInput(
                                      /// Auto focus first field if it's empty.
                                      autoFocus: index == 0 &&
                                          (currentFieldController?.text.isEmpty ?? false),
                                      textFieldController: currentFieldController,
                                      focusNode: currentFieldFocusNode,
                                      // isReadOnly: isFieldReadOnly(index),
                                      autofillHints: currentFieldType.autofillHint != null
                                          ? ['${currentFieldType.autofillHint}']
                                          : null,
                                      inputDecoration: InputDecoration(
                                        labelText: getFieldLabel(currentFieldType),
                                      ),
                                      keyboardType: getKeyboardType(currentFieldType),
                                      keyboardAction: hasNext
                                          ? TextInputAction.next
                                          : TextInputAction.done,
                                      onFieldSubmitted: (_) {
                                        if (hasNext) {
                                          nextFieldFocus?.requestFocus();
                                        }
                                      },
                                      onSaved: (value) {
                                        phoneNumber = value.phoneNumber;
                                        phoneNumberWithoutCountryCode = value.parseNumber();
                                        onTextFieldSaved(
                                          value.phoneNumber,
                                          currentFieldType,
                                        );
                                      },
                                      onInputChanged: (PhoneNumber number) {
                                        phoneNumber = number.phoneNumber;
                                        phoneNumberWithoutCountryCode = number.parseNumber();
                                        dialCode = number.dialCode ?? kPhoneNumberConfig.dialCodeDefault;
                                        isoCode = number.isoCode ?? kPhoneNumberConfig.countryCodeDefault;
                                      },
                                      onInputValidated: (value) => {},
                                      spaceBetweenSelectorAndTextField: 0,
                                      selectorConfig: SelectorConfig(
                                        //  enable: kPhoneNumberConfig.useInternationalFormat,
                                        showFlags: kPhoneNumberConfig.showCountryFlag,
                                        selectorType: kPhoneNumberConfig.selectorType,
                                        setSelectorButtonAsPrefixIcon:
                                        kPhoneNumberConfig.selectorFlagAsPrefixIcon,
                                        leadingPadding: 0,
                                        trailingSpace: false,
                                      ),
                                      selectorTextStyle:
                                      Theme.of(context).textTheme.titleMedium,
                                      ignoreBlank: !(_configs[index]?.required ?? true),
                                      initialValue: PhoneNumber(
                                        dialCode: dialCode,
                                        isoCode:  isoCode,
                                        phoneNumber: currentFieldController?.text,
                                      ),
                                      formatInput: kPhoneNumberConfig.formatInput,
                                      // Cap the national number at 10 digits
                                      // (Egyptian mobile length, without the
                                      // leading 0) — matches the login/register
                                      // validation and stops over-long entries.
                                      maxLength: 10,
                                      countries: kPhoneNumberConfig.customCountryList,
                                    )),
                                    // SizedBox(height: 5,),
                                    // Align(
                                    //   alignment: Alignment.topRight,
                                    //   child: Wrap(
                                    //     children: [
                                    //       Material(
                                    //         color: Theme.of(context).primaryColor,
                                    //         borderRadius: const BorderRadius.all(Radius.circular(5.0)),
                                    //         elevation: 0,
                                    //         child: MaterialButton(
                                    //           onPressed: !isPickerEnabled ? null:() async {
                                    //             if((phoneNumber ?? "").trim().isEmpty){
                                    //               _showMessage(S.of(context).enterMobile);
                                    //             }else if((phoneNumber ?? "").trim().startsWith("0")){
                                    //               _showMessage(S.of(context).validMobileWithout0);
                                    //             }else if((phoneNumber ?? "").trim().length <= 10){
                                    //               _showMessage(S.of(context).validMobile);
                                    //             }else{
                                    //               String currentOtp = OtpDialog.generateOtp();
                                    //               final json = await Services().api.mobileSendOtp((phoneNumber ?? "").trim(),currentOtp);
                                    //               final message = json?['error']?['message'] ?? '';
                                    //               if(message.isEmpty){
                                    //                 OtpDialog.showOtpDialog(context, (phoneNumber ?? "").trim(),currentOtp,((otpCode,actionFrom) async {
                                    //                   if(actionFrom == "resend"){
                                    //                     Services().api.mobileSendOtp((phoneNumber ?? "").trim(),currentOtp);
                                    //                   }else{
                                    //                     if(actionFrom == "verify"){
                                    //                       setState(() {
                                    //                         currentFieldFocusNode?.unfocus();
                                    //                         isPickerEnabled = false;
                                    //                       });
                                    //                     }
                                    //                   }
                                    //                 }));
                                    //               }else{
                                    //                 _showMessage(json?["message"]);
                                    //               }
                                    //             }
                                    //           },
                                    //           elevation: 0.0,
                                    //           height: 42.0,
                                    //           padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                    //           child: Text(
                                    //             S.of(context).generateOtp,
                                    //             style: TextStyle(
                                    //               color: AppColors.textColor(context),
                                    //               fontWeight: FontWeight.bold,
                                    //             ),
                                    //           ),
                                    //         ),
                                    //       ),
                                    //     ],
                                    //   ),
                                    // ),
                                  ]
                              )
                          );
                        }

                        return TextFormField(
                          /// Auto focus first field if it's empty.
                          autofocus: index == 0 &&
                              (currentFieldController?.text.isEmpty ?? false),
                          autocorrect: false,
                          controller: currentFieldController,
                          focusNode: currentFieldFocusNode,
                          readOnly: isFieldReadOnly(index),
                          autofillHints: currentFieldType.autofillHint != null
                              ? ['${currentFieldType.autofillHint}']
                              : null,
                          decoration: InputDecoration(
                            labelText: getFieldLabel(currentFieldType),
                          ),
                          keyboardType: getKeyboardType(currentFieldType),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: hasNext
                              ? TextInputAction.next
                              : TextInputAction.done,
                          validator: (val) {
                            final config = _configs[index];
                            if (config == null) {
                              return null;
                            }
                            return validateField(val, config, currentFieldType);
                          },
                          onFieldSubmitted: (_) {
                            if (hasNext) {
                              nextFieldFocus?.requestFocus();
                            }
                          },
                          onSaved: (value) => onTextFieldSaved(
                            value,
                            currentFieldType,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildBottom(),
      ],
    );
  }

  Widget listViewAddress(){
    return Column(
      children: [
        Expanded(child: SingleChildScrollView(
          child: Column(
            children: [
              if (listAddress.isEmpty)
                Center(
                  child: Image.asset(
                    kEmptySearch,
                    width: 120,
                    height: 120,
                  ),
                ),
              if (listAddress.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: kLoadingWidget(context),
                ),
              ...List.generate(listAddress.length, (index) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: GestureDetector(
                      onTap: () {
                        Provider.of<CartModel>(context, listen: false)
                            .setAddress(listAddress[index]);
                      },
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                            color: Theme.of(context).primaryColorLight),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: <Widget>[
                              const SizedBox(width: 10),
                              Expanded(
                                child: convertToCard(
                                    context, listAddress[index]!),
                              ),
                              Checkbox(
                                value: selectIndex == index ? true:false, // or your dynamic value
                                onChanged: (bool? value) async {
                                  Provider.of<CartModel>(context, listen: false)
                                      .setAddress(listAddress[index]);
                                  setState(() {
                                    selectIndex = index;
                                  });
                                },
                                activeColor: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        )),
        _buildBottom(),
      ],
    );
  }

  Widget convertToCard(BuildContext context, Address address) {
    final s = S.of(context);

    Widget row(String label, String? value) {
      if (value == null || value.isEmpty || value == 'null') {
        return const SizedBox();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$label:  ',
              style: TextStyle(color: Theme.of(context).primaryColor),
            ),
            Flexible(
              child: Column(
                children: <Widget>[Text(value)],
              ),
            )
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10.0),
        row(s.streetName, address.street),
        // Same wording as the form/website: City = governorate (region,
        // address.state), Zone = district (address.city).
        row(s.city, address.state),
        row(s.zone, address.city),
        row(s.country, address.country),
        row(s.zipCode, address.zipCode),
        const SizedBox(height: 6.0),
      ],
    );
  }

  void getDataFromLocal() {
    var list = List<Address>.from(UserBox().addresses ?? <Address>[]);
    listAddress = list;
    setState(() {});
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showMessage(
      String text, {
        bool isError = true,
      }) {
    if (!mounted) {
      return;
    }
    FlashHelper.message(
      context,
      message: text,
      isError: isError,
    );
  }
}
