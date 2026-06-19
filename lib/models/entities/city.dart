class City {
  String? id;
  String? name;
  City({this.id, this.name});

  City.fromConfig(dynamic parsedJson) {
    if (parsedJson is Map) {
      id = parsedJson['id'];
      name = parsedJson['name'];
    }
    if (parsedJson is String) {
      id = parsedJson;
      name = parsedJson;
    }
  }

  City.cityConfig(dynamic parsedJson) {
    if (parsedJson is Map) {
      id = parsedJson['entity_id'];
      name = parsedJson['states_name'];
    }
    if (parsedJson is String) {
      id = parsedJson;
      name = parsedJson;
    }
  }

  City.zoneConfig(dynamic parsedJson) {
    if (parsedJson is Map) {
      id = parsedJson['entity_id'];
      name = parsedJson['cities_name'];
    }
    if (parsedJson is String) {
      id = parsedJson;
      name = parsedJson;
    }
  }
}
