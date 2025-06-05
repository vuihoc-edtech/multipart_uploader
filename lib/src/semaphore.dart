import 'dart:async';
import 'dart:collection';

/// Semaphore để giới hạn số lượng concurrent operations
class Semaphore {
  int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }

  /// Update capacity động trong quá trình runtime
  void updateCapacity(int newCapacity) {
    final diff = newCapacity - maxCount;
    maxCount = newCapacity;
    _currentCount += diff;

    // Release thêm permits nếu capacity tăng
    if (diff > 0) {
      for (int i = 0; i < diff && _waitQueue.isNotEmpty; i++) {
        final completer = _waitQueue.removeFirst();
        _currentCount--;
        completer.complete();
      }
    }

    // Đảm bảo _currentCount không âm
    _currentCount = _currentCount.clamp(0, maxCount);
  }
}
