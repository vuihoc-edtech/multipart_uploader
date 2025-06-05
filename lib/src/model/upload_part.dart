import 'enum.dart';

class UploadPart {
  // Part id
  final int id;
  final String url;
  final int offset;
  final int length;
  String? etag;

  int uploadedBytes = 0;
  bool isUploaded = false;
  PartStatus status = PartStatus.notStarted;

  UploadPart({
    required this.url,
    required this.offset,
    required this.length,
    this.id = 0,
    this.etag,
  });

  factory UploadPart.fromJson(Map<String, dynamic> json) {
    return UploadPart(
      id: json['part'] ?? 0,
      url: json['url'],
      offset: json['offset'],
      length: int.tryParse(json['length'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'part': id,
      'offset': offset,
      'length': length,
      'url': url,
      'ETag': etag,
      'PartNumber': id,
    };
  }
}
