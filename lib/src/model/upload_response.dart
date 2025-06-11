import 'upload_part.dart';

class UploadResponse {
  final List<UploadPart> s3UploadUrl;
  final String s3Link;
  final String? uploadId;
  final String s3Key;

  UploadResponse({
    required this.s3UploadUrl,
    required this.s3Link,
    this.uploadId,
    required this.s3Key,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    return UploadResponse(
      s3UploadUrl: (json['s3UploadUrl'] as List)
          .map((part) => UploadPart.fromJson(part))
          .toList(),
      s3Link: json['s3Link'],
      uploadId: json['uploadId'],
      s3Key: json['s3Key'],
    );
  }
}
