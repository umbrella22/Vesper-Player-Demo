/// Publishes edits immediately and persists them in submission order.
/// Failed edits can only roll back the latest revision, to the last saved value.
final class OptimisticValue<T> {
  OptimisticValue({
    required T initialValue,
    required this.persist,
    required this.onChanged,
  }) : _value = initialValue,
       _savedValue = initialValue;

  final Future<void> Function(T value) persist;
  final void Function(T value) onChanged;
  T _value;
  T _savedValue;
  var _revision = 0;
  var _disposed = false;
  Future<void> _pending = Future<void>.value();

  T get value => _value;

  Future<void> setValue(T next) {
    if (_disposed || next == _value) return Future<void>.value();
    final revision = ++_revision;
    _value = next;
    final operation = _pending.then((_) async {
      try {
        await persist(next);
        _savedValue = next;
      } catch (_) {
        if (!_disposed && revision == _revision && _value != _savedValue) {
          _value = _savedValue;
          onChanged(_value);
        }
        rethrow;
      }
    });
    // A failed save must not prevent a later edit from being persisted.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    onChanged(next);
    return operation;
  }

  void dispose() {
    _disposed = true;
  }
}
