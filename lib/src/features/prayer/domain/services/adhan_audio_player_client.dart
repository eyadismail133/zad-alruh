import 'dart:async';

export 'online_audio_player_client.dart';

/// The status of playback represented in an event snapshot.
enum AdhanPlaybackStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  stopped,
  error,
}

/// A single typed playback event carrying request token and snapshot data.
class AdhanPlaybackEvent {
  final String requestToken;
  final AdhanPlaybackStatus status;
  final Duration position;
  final Duration? duration;
  final String? errorMessage;

  const AdhanPlaybackEvent({
    required this.requestToken,
    required this.status,
    this.position = Duration.zero,
    this.duration,
    this.errorMessage,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanPlaybackEvent &&
          runtimeType == other.runtimeType &&
          requestToken == other.requestToken &&
          status == other.status &&
          position == other.position &&
          duration == other.duration &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        requestToken,
        status,
        position,
        duration,
        errorMessage,
      );

  @override
  String toString() =>
      'AdhanPlaybackEvent(token: $requestToken, status: $status, pos: $position, dur: $duration, err: $errorMessage)';
}

/// Outcome of attempting to start playback.
enum PlaybackStartupResult {
  started,
  cancelled,
  failed,
}

/// Abstract client boundary for adhan audio playback, enabling deterministic
/// testing and platform decoupling.
abstract class AdhanAudioPlayerClient {
  /// Stream emitting typed playback event snapshots tagged with unique requestToken.
  Stream<AdhanPlaybackEvent> get playbackEventStream;

  /// Stream emitting playback position updates.
  Stream<Duration> get positionStream;

  /// Stream emitting total duration updates when media is loaded.
  Stream<Duration?> get durationStream;

  /// Stream emitting whether audio is actively playing.
  Stream<bool> get playingStream;

  /// Stream emitting an event when the current audio track finishes naturally.
  Stream<bool> get completedStream;

  /// Stream emitting error messages from playback or loading failures.
  Stream<String> get errorStream;

  /// Starts playback of the given bundled asset path with an optional caller request token.
  Future<PlaybackStartupResult> playAsset(
    String assetPath, {
    String? requestToken,
  });

  /// Stops playback immediately.
  Future<void> stop();

  /// Releases underlying player resources.
  Future<void> dispose();
}
