
class ProdcutOptionAttribute {
  Swatch? swatch;
  String? label;
  String? value;

  ProdcutOptionAttribute({this.swatch, this.label, this.value});

  ProdcutOptionAttribute.fromJson(Map<String, dynamic> json) {
    swatch =
    json['swatch'] != null ? new Swatch.fromJson(json['swatch']) : null;
    label = json['label'];
    value = json['value'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.swatch != null) {
      data['swatch'] = this.swatch!.toJson();
    }
    data['label'] = this.label;
    data['value'] = this.value;
    return data;
  }
}

class Swatch {
  String? type;
  String? value;

  Swatch({this.type, this.value});

  Swatch.fromJson(Map<String, dynamic> json) {
    type = json['type'];
    value = json['value'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['type'] = this.type;
    data['value'] = this.value;
    return data;
  }
}