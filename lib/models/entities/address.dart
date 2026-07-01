import '../../common/constants.dart';

class Address {
  String? id;
  String? firstName;
  String? lastName;
  String? email;
  String? street;
  String? apartment;
  String? block;
  String? city;
  String? state;
  String? country;
  String? countryId;
  String? phoneNumber;
  String? zipCode;
  String? mapUrl;
  String? latitude;
  String? longitude;

  Address(
      {this.firstName,
      this.lastName,
      this.email,
      this.street,
      this.apartment,
      this.block,
      this.city,
      this.state,
      this.country,
      this.phoneNumber,
      this.zipCode,
      this.mapUrl,
      this.latitude,
      this.longitude});

  Address.fromJson(Map parsedJson) {
    id = parsedJson['id'] ?? 0;
    firstName = parsedJson['first_name'] ?? '';
    lastName = parsedJson['last_name'] ?? '';
    apartment = parsedJson['company'] ?? '';
    street = parsedJson['address_1'] ?? '';
    block = parsedJson['address_2'] ?? '';
    city = parsedJson['city'] ?? '';
    state = parsedJson['state'] ?? '';
    country = parsedJson['country'] ?? '';
    countryId = parsedJson['countryId'] ?? '';
    email = parsedJson['email'] ?? '';
    // final alphanumeric = RegExp(r'^[a-zA-Z0-9]+$');
    // if (alphanumeric.hasMatch(firstName!)) {
    //   phoneNumber = firstName;
    // }
    phoneNumber = parsedJson['phone'] ?? '';
    zipCode = parsedJson['postcode'];
  }

  Address.fromOpencartJson(Map parsedJson) {
    id = parsedJson['id'];
    firstName = parsedJson['firstname'];
    lastName = parsedJson['lastname'];
    apartment = parsedJson['company'];
    street = parsedJson['address_1'];
    block = parsedJson['address_2'];
    city = parsedJson['city'];
    state = parsedJson['zone_id'];
    country = parsedJson['country'];
    countryId = parsedJson['countryId'];
    zipCode = parsedJson['postcode'];
  }

  Address.fromMagentoJson(Map<String, dynamic> parsedJson) {
    id = parsedJson['id'];
    firstName = parsedJson['firstname'];
    lastName = parsedJson['lastname'];
    if (parsedJson['street'] != null) {
      var streets = List.from(parsedJson['street']);
      street = streets.isNotEmpty ? streets[0] : '';
      block = streets.length > 1 ? streets[1] : '';
    }

    city = parsedJson['city'];
    state = parsedJson['region'];
    country = parsedJson['country'];
    countryId = parsedJson['countryId'];
    email = parsedJson['email'];
    phoneNumber = parsedJson['mobile'];
    zipCode = parsedJson['postcode'];
  }

  Address.fromPrestaJson(Map<String, dynamic> parsedJson) {
    id = parsedJson['id'];
    firstName = parsedJson['firstname'];
    lastName = parsedJson['lastname'];
    street = parsedJson['address1'];
    block = parsedJson['address2'];
    city = parsedJson['city'];
    country = parsedJson['country'];
    countryId = parsedJson['countryId'];
    phoneNumber = parsedJson['phone'];
    zipCode = parsedJson['postcode'];
  }

  Map<String, dynamic> toJson() {
    var address = <String, dynamic>{
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'address_1': street ?? '',
      'address_2': block ?? '',
      'company': apartment ?? '',
      'city': city,
      'state': state,
      'country': country,
      'countryId': countryId,
      'phone': phoneNumber,
      'postcode': zipCode,
      'mapUrl': mapUrl,
    };
    if (email != null && email!.isNotEmpty) {
      address['email'] = email;
    }
    return address;
  }

  Map<String, dynamic> toWCFMJson() {
    var address = toJson();
    if (street?.isNotEmpty ?? false) {
      address['wcfmmp_user_location'] = street;
    }
    if (latitude?.isNotEmpty ?? false) {
      address['wcfmmp_user_location_lat'] = latitude;
    }
    if (longitude?.isNotEmpty ?? false) {
      address['wcfmmp_user_location_lng'] = longitude;
    }
    return address;
  }

  Address.fromLocalJson(Map json) {
    try {
      id = json['id'];
      firstName = json['first_name'];
      lastName = json['last_name'];
      street = json['address_1'];
      block = json['address_2'];
      apartment = json['company'];
      city = json['city'];
      state = json['state'];
      country = json['country'];
      countryId = json['countryId'];
      email = json['email'];
      phoneNumber = json['phone'];
      zipCode = json['postcode'];
      mapUrl = json['mapUrl'];
    } catch (e) {
      printLog(e.toString());
    }
  }

  Map<String, dynamic> toMagentoJson() {
    return {
      'address': {
        'country_id': country,
        // 'region_id': state != null && int.tryParse(state!) != null
        //     ? int.parse(state!)
        //     : 0,
        'street': [
          street,
          '$apartment${(block?.isEmpty ?? true) ? '' : ' - $block'}',
        ],
        'postcode': zipCode,
        'region': state,
        'city': city,
        'firstname': firstName,
        'lastname': lastName,
        // Email is optional; fall back to a provisional default when empty so
        // Magento still receives a value. Final default rule is a follow-up.
        'email': (email?.isNotEmpty ?? false)
            ? email
            : 'guest${(phoneNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '')}@locafy.market',
        'telephone': phoneNumber,
        'same_as_billing': 1
      }
    };
  }

  Map<String, dynamic> toOpencartJson() {
    return {
      'id': id,
      'zone_id': state,
      'country_id': countryId ?? country,
      'address_1': street ?? '',
      'address_2': block ?? '',
      'company': apartment ?? '',
      'postcode': zipCode,
      'city': city,
      'firstname': firstName,
      'lastname': lastName,
      'email': email,
      'telephone': phoneNumber
    };
  }

  bool isValid() {
    // Email is optional at checkout; a default is substituted before submit.
    return firstName!.isNotEmpty &&
        lastName!.isNotEmpty &&
        street!.isNotEmpty &&
        city!.isNotEmpty &&
        state!.isNotEmpty &&
        country!.isNotEmpty &&
        phoneNumber!.isNotEmpty;
  }

  Map<String, String?> toJsonEncodable() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'address_1': street ?? '',
      'address_2': block ?? '',
      'company': apartment ?? '',
      'city': city,
      'state': state,
      'countryId': countryId,
      'country': country,
      'email': email,
      'phone': phoneNumber,
      'postcode': zipCode,
      'mapUrl': mapUrl,
    };
  }

  Address.fromShopifyJson(Map json) {
    try {
      id = json['id'];
      firstName = json['firstName'];
      lastName = json['lastName'];
      street = json['address1'];
      block = json['address2'];
      apartment = json['company'];
      city = json['city'];
      state = json['pronvice'];
      country = json['country'];
      email = json['email'];
      phoneNumber = json['phone'];
      zipCode = json['zip'];
      mapUrl = json['mapUrl'];
    } catch (e) {
      printLog(e.toString());
    }
  }

  Map<String, dynamic> toShopifyJson() {
    return {
      'address': {
        'province': state,
        'country': country,
        'address1': street,
        'address2': block,
        'company': apartment,
        'zip': zipCode,
        'city': city,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phoneNumber,
      }
    };
  }

  Address.fromOpencartOrderJson(Map json) {
    try {
      id = json['id'];
      firstName = json['shipping_firstname'];
      lastName = json['shipping_lastname'];
      street = json['shipping_address_1'];
      block = json['shipping_address_2'];
      apartment = json['shipping_company'];
      city = json['shipping_city'];
      state = json['shipping_zone'];
      country = json['shipping_country'];
      email = json['email'];
      phoneNumber = json['mobile'];
      zipCode = json['shipping_postcode'];
    } catch (e) {
      printLog(e.toString());
    }
  }

  Address.fromBigCommerceJson(Map json) {
    try {
      id = json['id'];
      firstName = json['first_name'];
      lastName = json['last_name'];
      apartment = json['company'];
      street = json['street_1'];
      block = json['street_2'];
      city = json['city'];
      state = json['state'];
      zipCode = json['zip'];
      country = json['country'];
      countryId = json['country_iso2'];
      phoneNumber = json['phone'];
      email = json['email'];
    } catch (e) {
      printLog(e.toString());
    }

    //   Map<String, dynamic> toBigCommerceJson() {
    //     final data = <String, dynamic>{};
    //     data['first_name'] = firstName;
    //     data['last_name'] = lastName;
    //     data['company'] = apartment;
    //     data['street_1'] = street;
    //     data['street_2'] = block;
    //     data['city'] = city;
    //     data['state'] = state;
    //     data['zip'] = zipCode;
    //     data['country'] = country;
    //     data['country_iso2'] = countryId;
    //     data['phone'] = phoneNumber;
    //     data['email'] = email;
    //     return data;
    //   }
  }

  @override
  String toString() {
    var output = '';
    if (street != null) {
      output += ' $street';
    }
    if (country != null) {
      output += ' $country';
    }
    if (city != null) {
      output += ' $city';
    }

    return output.trim();
  }

  String get fullName => [firstName ?? '', lastName ?? ''].join(' ').trim();

  String get fullAddress => [
        block ?? '',
        apartment ?? '',
        street ?? '',
        city ?? '',
        state ?? '',
        zipCode ?? '',
        country ?? '',
      ].join(' ').trim();
}

class ListAddress {
  List<Address> list = [];

  List<Map<String, String?>> toJsonEncodable() {
    return list.map((item) {
      return item.toJsonEncodable();
    }).toList();
  }
}
