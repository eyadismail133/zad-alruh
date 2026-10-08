import 'dart:async';
import 'package:flutter/foundation.dart';

/// Central mutation barrier fencing ALL accepted database writes, updates,
/// initializers, and retries across all feature families during reset execution.
///
/// Implements [ChangeNotifier] so external listeners (Riverpod providers,
/// audio adapters, native coordinators) receive immediate reactive updates.
class ProgressMutationBarrier extends ChangeNotifier {
  bool _isResetInProgress = false;
  int _generation = 0;
  int _activeResetToken = 0;
  final Set<Future<void>> _activeOperations = <Future<void>>{};

  /// Whether a reset operation is currently in progress.
  bool get isResetInProgress => _isResetInProgress;

  /// Public contract indicating whether media playback start is currently allowed.
  /// Audio starts MUST be fenced while reset is executing.
  bool get isAudioStartAllowed => !_isResetInProgress;

  /// Monotonically increasing generation counter.
  /// Advanced on every reset invocation to cancel in-flight or queued operations.
  int get currentGeneration => _generation;

  /// Synchronously checks whether a mutation is allowed.
  /// Throws [StateError] if a reset is currently underway.
  void checkMutationAllowed([String? operationName]) {
    if (_isResetInProgress) {
      final name = operationName != null ? ' ($operationName)' : '';
      throw StateError(
        'Cannot accept mutation$name while reset is in progress',
      );
    }
  }

  /// Verifies that the given [capturedGeneration] is still valid.
  /// Throws [StateError] if the generation has been superseded by a reset.
  void checkGeneration(int capturedGeneration, [String? operationName]) {
    if (_isResetInProgress || capturedGeneration != _generation) {
      final name = operationName != null ? ' ($operationName)' : '';
      throw StateError(
        'Operation$name cancelled by reset: generation mismatch ($capturedGeneration vs $_generation)',
      );
    }
  }

  /// Runs and tracks an asynchronous mutation under the barrier.
  /// Captures generation synchronously at acceptance, tracks the in-flight operation,
  /// rechecks generation after completion, and allows draining before reset.
  Future<T> runTrackedMutation<T>(
    String operationName,
    Future<T> Function(int generation) action,
  ) async {
    checkMutationAllowed(operationName);
    final gen = _generation;
    final completer = Completer<void>();
    _activeOperations.add(completer.future);
    try {
      final result = await action(gen);
      checkGeneration(gen, operationName);
      return result;
    } finally {
      _activeOperations.remove(completer.future);
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Drains any in-flight active operations before reset proceeds to DB wipe.
  /// Throws [TimeoutException] if in-flight operations do not complete within [timeout].
  /// This timeout MUST propagate to abort the reset before audio stop, native cancellation, or SQLite wipe.
  Future<void> drainActiveOperations({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_activeOperations.isEmpty) return;
    await Future.wait(_activeOperations.toList()).timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException(
          'Timed out waiting for active operations to drain before reset',
          timeout,
        );
      },
    );
  }

  /// Synchronously begins the reset fence.
  /// Immediately prevents any subsequent mutations from being accepted,
  /// increments the generation counter, and returns the unique reset token.
  /// If a reset is already in progress, throws [StateError] to prevent duplicate concurrent resets.
  int beginReset() {
    if (_isResetInProgress) {
      throw StateError('Reset operation is already in progress');
    }
    _isResetInProgress = true;
    final token = ++_generation;
    _activeResetToken = token;
    notifyListeners();
    return token;
  }

  /// Ends the reset fence.
  /// Only the owner matching [token] can release the fence.
  /// Restores write permissions if [success] is true, or releases the fence
  /// after failure without leaving the system in a permanently locked state.
  void endReset({required int token, required bool success}) {
    if (!_isResetInProgress || _activeResetToken != token) {
      return;
    }
    _isResetInProgress = false;
    _activeResetToken = 0;
    notifyListeners();
  }
}
