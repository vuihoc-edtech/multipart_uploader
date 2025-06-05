/// Network speed metrics để auto-tuning
class NetworkMetrics {
  double _averageSpeedMBps = 0;
  int _measurementCount = 0;

  void updateSpeed(int bytesTransferred, Duration duration) {
    if (duration.inMilliseconds > 0) {
      final speedMBps =
          (bytesTransferred / 1024 / 1024) / (duration.inMilliseconds / 1000);
      _averageSpeedMBps = (_averageSpeedMBps * _measurementCount + speedMBps) /
          (_measurementCount + 1);
      _measurementCount++;
    }
  }

  void reset() {
    _averageSpeedMBps = 0;
    _measurementCount = 0;
  }

  double get averageSpeedMBps => _averageSpeedMBps;
  bool get hasMetrics => _measurementCount > 0;
}
