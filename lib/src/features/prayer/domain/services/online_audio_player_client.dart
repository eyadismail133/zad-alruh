import 'dart:async';
import 'adhan_audio_player_client.dart';

/// Narrow optional online capability interface for audio player clients
/// capable of streaming remote audio URLs over HTTPS.
abstract class OnlineAudioPlayerClient {
  /// Starts playback of the given remote audio URL with an optional caller request token.
  Future<PlaybackStartupResult> playUrl(
    String url, {
    String? requestToken,
  });

  /// Pauses the current playback session if active. Returns true if pause was executed, false if cancelled/no-op.
  Future<bool> pause({String? requestToken});

  /// Resumes playback if currently paused. Returns true if resume was executed, false if cancelled/no-op.
  Future<bool> resume({String? requestToken});

  /// Seeks to the specified position in the current playback track.
  Future<void> seek(Duration position, {String? requestToken});
}
