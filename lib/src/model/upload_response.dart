import 'upload_part.dart';

class UploadResponse {
  final List<UploadPart> s3UploadUrl;
  final String s3Link;

  UploadResponse({required this.s3UploadUrl, required this.s3Link});

  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    return UploadResponse(
      s3UploadUrl: (json['s3UploadUrl'] as List)
          .map((part) => UploadPart.fromJson(part))
          .toList(),
      s3Link: json['s3Link'],
    );
  }
}
