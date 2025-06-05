# MultipartUploader

MultipartUploader là một thư viện Flutter giúp upload file lên S3 với khả năng chia nhỏ file, tự động điều chỉnh số lượng upload song song, và khả năng tiếp tục upload khi bị ngắt kết nối.

## Tính năng

- **Chia nhỏ file**: Tự động chia file thành các phần nhỏ để upload song song
- **Auto-tuning**: Tự động điều chỉnh số lượng upload song song dựa trên kích thước file và tốc độ mạng
- **Resume upload**: Khả năng tiếp tục upload khi bị ngắt kết nối mạng
- **Progress tracking**: Theo dõi tiến trình upload với callback
- **Retry mechanism**: Cơ chế retry thông minh khi gặp lỗi
- **Network metrics**: Đo lường và điều chỉnh dựa trên tốc độ mạng thực tế

## Cài đặt

Thêm multipart_uploader vào `pubspec.yaml` của dự án:

```yaml
dependencies:
  multipart_uploader: ^1.0.0
```

## Cách sử dụng

### 1. Khởi tạo MultipartUploader

```dart
final uploader = MultipartUploader();
```

### 2. Upload file với auto-tuning

```dart
// Lấy thông tin upload từ server
final uploadResponse = await getUploadLinkFromServer(file);

// Upload file với auto-tuning và theo dõi tiến trình
try {
  final uploadedUrl = await uploader.uploadFileOptimizedWithAutoTuning(
    file,
    uploadResponse: uploadResponse,
    onProgress: (progress) {
      // Cập nhật UI với tiến trình upload (0-100)
      setState(() => uploadProgress = progress);
    },
    onError: (error) {
      // Xử lý lỗi nếu cần
      print('Upload error: $error');
    },
  );
  
  // Xử lý khi upload thành công
  print('File uploaded successfully: $uploadedUrl');
} catch (e) {
  // Xử lý lỗi upload
  
  // Kiểm tra xem có thể tiếp tục upload không
  final canContinue = e.toString().contains('Network appears to be down') &&
                     uploader.status == UploaderStatus.failed;
  
  if (canContinue) {
    // Cho phép người dùng tiếp tục upload
    showContinueUploadDialog();
  }
}
```

### 3. Tiếp tục upload sau khi bị ngắt kết nối

```dart
try {
  final uploadedUrl = await uploader.continueUpload(
    onProgress: (progress) {
      setState(() => uploadProgress = progress);
    }
  );
  
  // Xử lý khi upload thành công
  print('File upload continued successfully: $uploadedUrl');
} catch (e) {
  // Xử lý lỗi
  print('Continue upload failed: $e');
}
```

### 4. Theo dõi trạng thái upload

```dart
// Kiểm tra trạng thái uploader
if (uploader.status == UploaderStatus.completed) {
  print('Upload completed!');
}

// Hiển thị thông tin về tốc độ upload
Text('Speed: ${uploader.speed} MB/s');

// Hiển thị thông tin về file và parts
Text('File Size: ${(uploader.fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
Text('Parts: ${uploader.parts.length}');
```

### 5. Giải phóng tài nguyên

```dart
@override
void dispose() {
  uploader.dispose();
  super.dispose();
}
```

## Ví dụ đầy đủ

Xem ví dụ đầy đủ trong thư mục `/example` để thấy cách triển khai chi tiết, bao gồm:
- Cách chọn file
- Cách cấu hình upload
- Xử lý lỗi và tiếp tục upload
- Hiển thị thông tin tiến trình

## Thông tin bổ sung

### Lưu ý khi triển khai server

Server cần cung cấp một API endpoint trả về thông tin upload với định dạng phù hợp với `UploadResponse`. 
Xem ví dụ trong file `/example/lib/upload_screen.dart` để tham khảo cách gọi API và xử lý response.
