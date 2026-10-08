import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../prayer/domain/models/adhan_voice.dart';
import '../../../prayer/domain/services/adhan_audio_player_client.dart';
import '../../../prayer/domain/services/just_audio_player_client.dart';
import '../../../prayer/domain/services/native_prayer_audio_control.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../../quran/domain/models/quran_audio_source.dart';

enum AdhanAudioStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  error,
}

enum AudioPlaybackSource {
  none,
  adhan,
  quran,
}

@immutable
class AdhanAudioState {
  final AdhanAudioStatus status;
  final String? activeVoiceId;
  final int? activeSurahNumber;
  final String? activeSurahName;
  final String? reciterName;
  final String? riwayahName;
  final AudioPlaybackSource sourceType;
  final Duration position;
  final Duration totalDuration;
  final String? errorMessage;

  const AdhanAudioState({
    this.status = AdhanAudioStatus.idle,
    this.activeVoiceId,
    this.activeSurahNumber,
    this.activeSurahName,
    this.reciterName,
    this.riwayahName,
    this.sourceType = AudioPlaybackSource.none,
    this.position = Duration.zero,
    this.totalDuration = Duration.zero,
    this.errorMessage,
  });

  bool get isPlaying => status == AdhanAudioStatus.playing;
  bool get isLoading => status == AdhanAudioStatus.loading;
  bool get isBuffering => status == AdhanAudioStatus.buffering;
  bool get isPaused => status == AdhanAudioStatus.paused;
  bool get isCompleted => status == AdhanAudioStatus.completed;
  bool get hasError => status == AdhanAudioStatus.error;

  bool isVoicePlaying(String voiceId) =>
      isPlaying && activeVoiceId == voiceId;
  bool isVoiceActive(String voiceId) =>
      activeVoiceId == voiceId &&
      (isPlaying || isLoading || isBuffering || isPaused);

  bool get isSurahActive =>
      activeSurahNumber != null &&
      (isPlaying || isLoading || isBuffering || isPaused);
  bool isSurahPlaying(int surahNumber) =>
      isPlaying && activeSurahNumber == surahNumber;
  bool isSurahActiveNumber(int surahNumber) =>
      activeSurahNumber == surahNumber &&
      (isPlaying || isLoading || isBuffering || isPaused);

  AdhanAudioState copyWith({
    AdhanAudioStatus? status,
    String? activeVoiceId,
    int? activeSurahNumber,
    String? activeSurahName,
    String? reciterName,
    String? riwayahName,
    AudioPlaybackSource? sourceType,
    Duration? position,
    Duration? totalDuration,
    String? errorMessage,
    bool clearError = false,
    bool clearActiveVoice = false,
    bool clearActiveSurah = false,
  }) {
    return AdhanAudioState(
      status: status ?? this.status,
      activeVoiceId: clearActiveVoice
          ? null
          : (activeVoiceId ?? this.activeVoiceId),
      activeSurahNumber: clearActiveSurah
          ? null
          : (activeSurahNumber ?? this.activeSurahNumber),
      activeSurahName: clearActiveSurah
          ? null
          : (activeSurahName ?? this.activeSurahName),
      reciterName: clearActiveSurah
          ? null
          : (reciterName ?? this.reciterName),
      riwayahName: clearActiveSurah
          ? null
          : (riwayahName ?? this.riwayahName),
      sourceType: (clearActiveVoice && clearActiveSurah)
          ? AudioPlaybackSource.none
          : (sourceType ?? this.sourceType),
      position: position ?? this.position,
      totalDuration: totalDuration ?? this.totalDuration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanAudioState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          activeVoiceId == other.activeVoiceId &&
          activeSurahNumber == other.activeSurahNumber &&
          activeSurahName == other.activeSurahName &&
          reciterName == other.reciterName &&
          riwayahName == other.riwayahName &&
          sourceType == other.sourceType &&
          position == other.position &&
          totalDuration == other.totalDuration &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        status,
        activeVoiceId,
        activeSurahNumber,
        activeSurahName,
        reciterName,
        riwayahName,
        sourceType,
        position,
        totalDuration,
        errorMessage,
      );

  @override
  String toString() =>
      'AdhanAudioState(status: $status, voice: $activeVoiceId, surah: $activeSurahNumber, pos: $position/$totalDuration)';
}

final nativePrayerAudioControlProvider =
    Provider<NativePrayerAudioControl>((ref) {
  return MethodChannelNativePrayerAudioControl();
});

final adhanAudioPlayerClientProvider = Provider<AdhanAudioPlayerClient>((ref) {
  final nativeControl = ref.watch(nativePrayerAudioControlProvider);
  final progressRepo = ref.read(progressRepositoryProvider);
  final client = JustAudioPlayerClient(
    nativeAudioControl: nativeControl,
    isResetBarrierActive: () => progressRepo.mutationBarrier.isResetInProgress,
    getResetGeneration: () => progressRepo.mutationBarrier.currentGeneration,
  );
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

final adhanAudioControllerProvider =
    StateNotifierProvider<AdhanAudioController, AdhanAudioState>((ref) {
  final client = ref.watch(adhanAudioPlayerClientProvider);
  return AdhanAudioController(client);
});

// Generic aliases for shared audio ownership
typedef SharedAudioController = AdhanAudioController;
typedef SharedAudioState = AdhanAudioState;
final sharedAudioControllerProvider = adhanAudioControllerProvider;
final sharedAudioPlayerClientProvider = adhanAudioPlayerClientProvider;

class AdhanAudioController extends StateNotifier<AdhanAudioState> {
  final AdhanAudioPlayerClient _client;
  StreamSubscription<AdhanPlaybackEvent>? _eventSub;
  int _tokenCounter = 0;
  String? _currentToken;

  AdhanAudioController(this._client) : super(const AdhanAudioState()) {
    _eventSub = _client.playbackEventStream.listen((event) {
      if (!mounted) return;
      // Drop any events for stale or older tokens
      if (event.requestToken != _currentToken) return;

      switch (event.status) {
        case AdhanPlaybackStatus.loading:
          state = state.copyWith(status: AdhanAudioStatus.loading);
          break;
        case AdhanPlaybackStatus.buffering:
          state = state.copyWith(
            status: AdhanAudioStatus.buffering,
            position: event.position,
            totalDuration: event.duration ?? state.totalDuration,
          );
          break;
        case AdhanPlaybackStatus.playing:
          state = state.copyWith(
            status: AdhanAudioStatus.playing,
            position: event.position,
            totalDuration: event.duration ?? state.totalDuration,
          );
          break;
        case AdhanPlaybackStatus.paused:
          state = state.copyWith(
            status: AdhanAudioStatus.paused,
            position: event.position,
            totalDuration: event.duration ?? state.totalDuration,
          );
          break;
        case AdhanPlaybackStatus.completed:
          state = state.copyWith(
            status: AdhanAudioStatus.completed,
            position: Duration.zero,
          );
          break;
        case AdhanPlaybackStatus.stopped:
        case AdhanPlaybackStatus.idle:
          state = state.copyWith(
            status: AdhanAudioStatus.idle,
            clearActiveVoice: true,
            clearActiveSurah: true,
            position: Duration.zero,
          );
          break;
        case AdhanPlaybackStatus.error:
          state = state.copyWith(
            status: AdhanAudioStatus.error,
            errorMessage: event.errorMessage ??
                (state.sourceType == AudioPlaybackSource.quran
                    ? 'تعذر تشغيل التلاوة. يرجى التحقق من الاتصال بالإنترنت والمحاولة مجدداً.'
                    : 'تعذر تشغيل التسجيل الصوتي. يرجى إعادة المحاولة.'),
          );
          break;
      }
    });
  }

  Future<void> playVoice(AdhanVoice voice) async {
    final String token = 'req_${++_tokenCounter}';
    _currentToken = token;

    state = state.copyWith(
      status: AdhanAudioStatus.loading,
      activeVoiceId: voice.id,
      clearActiveSurah: true,
      sourceType: AudioPlaybackSource.adhan,
      position: Duration.zero,
      totalDuration: Duration(seconds: voice.durationSeconds),
      clearError: true,
    );

    try {
      final startupResult = await _client.playAsset(
        voice.audioAssetPath,
        requestToken: token,
      );

      if (_currentToken == token && mounted) {
        if (startupResult == PlaybackStartupResult.started) {
          if (state.status != AdhanAudioStatus.completed &&
              state.status != AdhanAudioStatus.error) {
            state = state.copyWith(
              status: AdhanAudioStatus.playing,
              activeVoiceId: voice.id,
            );
          }
        } else if (startupResult == PlaybackStartupResult.cancelled) {
          state = state.copyWith(
            status: AdhanAudioStatus.idle,
            clearActiveVoice: true,
            clearActiveSurah: true,
            position: Duration.zero,
          );
        }
      }
    } catch (_) {
      if (_currentToken == token && mounted) {
        state = state.copyWith(
          status: AdhanAudioStatus.error,
          errorMessage: 'تعذر تشغيل التسجيل الصوتي. يرجى إعادة المحاولة.',
        );
      }
    }
  }

  /// Initiates user-selected full-surah recitation from verified MP3Quran source.
  Future<void> playSurah({
    required int surahNumber,
    required String surahName,
    String reciterName = 'مشاري العفاسي',
    String riwayahName = 'حفص عن عاصم - مرتل',
  }) async {
    if (surahNumber < 1 || surahNumber > 114) {
      state = state.copyWith(
        status: AdhanAudioStatus.error,
        errorMessage: 'رقم السورة غير صالح (يجب أن يكون بين ١ و ١١٤).',
      );
      return;
    }

    final String token = 'quran_${++_tokenCounter}';
    _currentToken = token;

    final String url = QuranAudioSource.getSurahAudioUrl(surahNumber);

    state = state.copyWith(
      status: AdhanAudioStatus.loading,
      activeSurahNumber: surahNumber,
      activeSurahName: surahName,
      reciterName: reciterName,
      riwayahName: riwayahName,
      clearActiveVoice: true,
      sourceType: AudioPlaybackSource.quran,
      position: Duration.zero,
      totalDuration: Duration.zero,
      clearError: true,
    );

    try {
      if (_client is OnlineAudioPlayerClient) {
        final onlineClient = _client as OnlineAudioPlayerClient;
        final startupResult = await onlineClient.playUrl(
          url,
          requestToken: token,
        );

        if (_currentToken == token && mounted) {
          if (startupResult == PlaybackStartupResult.started) {
            if (state.status != AdhanAudioStatus.completed &&
                state.status != AdhanAudioStatus.error) {
              state = state.copyWith(
                status: AdhanAudioStatus.playing,
                activeSurahNumber: surahNumber,
                activeSurahName: surahName,
              );
            }
          } else if (startupResult == PlaybackStartupResult.cancelled) {
            state = state.copyWith(
              status: AdhanAudioStatus.idle,
              clearActiveVoice: true,
              clearActiveSurah: true,
              position: Duration.zero,
            );
          }
        }
      } else {
        if (_currentToken == token && mounted) {
          state = state.copyWith(
            status: AdhanAudioStatus.error,
            errorMessage: 'مشغل الصوت الحالي لا يدعم البث عبر الإنترنت.',
          );
        }
      }
    } catch (_) {
      if (_currentToken == token && mounted) {
        state = state.copyWith(
          status: AdhanAudioStatus.error,
          errorMessage:
              'تعذر تشغيل التلاوة. يرجى التحقق من الاتصال بالإنترنت والمحاولة مجدداً.',
        );
      }
    }
  }

  Future<void> pause() async {
    final String? opToken = _currentToken;
    if (opToken == null || !mounted) return;

    if (_client is OnlineAudioPlayerClient &&
        (state.isPlaying || state.isBuffering)) {
      try {
        final paused = await (_client as OnlineAudioPlayerClient).pause(
          requestToken: opToken,
        );
        if (!mounted || _currentToken != opToken) return;
        if (paused) {
          state = state.copyWith(status: AdhanAudioStatus.paused);
        }
      } catch (_) {
        if (!mounted || _currentToken != opToken) return;
        state = state.copyWith(
          status: AdhanAudioStatus.error,
          errorMessage: 'تعذر إيقاف التشغيل مؤقتاً.',
        );
      }
    }
  }

  Future<void> resume() async {
    final String? opToken = _currentToken;
    if (opToken == null || !mounted) return;

    if (_client is OnlineAudioPlayerClient && state.isPaused) {
      try {
        final resumed = await (_client as OnlineAudioPlayerClient).resume(
          requestToken: opToken,
        );
        if (!mounted || _currentToken != opToken) return;
        if (resumed) {
          state = state.copyWith(status: AdhanAudioStatus.playing);
        }
      } catch (_) {
        if (!mounted || _currentToken != opToken) return;
        state = state.copyWith(
          status: AdhanAudioStatus.error,
          errorMessage: 'تعذر استئناف التشغيل.',
        );
      }
    }
  }

  Future<void> seek(Duration position) async {
    final String? opToken = _currentToken;
    if (opToken == null || !mounted) return;

    if (_client is OnlineAudioPlayerClient &&
        (state.isPlaying || state.isPaused || state.isBuffering)) {
      try {
        await (_client as OnlineAudioPlayerClient).seek(
          position,
          requestToken: opToken,
        );
        if (!mounted || _currentToken != opToken) return;
      } catch (_) {
        if (!mounted || _currentToken != opToken) return;
      }
    }
  }

  Future<void> stop() async {
    final String stopToken = 'stop_${++_tokenCounter}';
    _currentToken = stopToken;
    try {
      await _client.stop();
      if (mounted && _currentToken == stopToken) {
        state = state.copyWith(
          status: AdhanAudioStatus.idle,
          clearActiveVoice: true,
          clearActiveSurah: true,
          position: Duration.zero,
          clearError: true,
        );
      }
    } catch (e) {
      if (mounted && _currentToken == stopToken) {
        state = state.copyWith(
          status: AdhanAudioStatus.error,
          errorMessage: 'تعذر إيقاف التشغيل الصوتي. يرجى إعادة المحاولة.',
        );
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _currentToken = null;
    _eventSub?.cancel();
    _client.stop().catchError((_) {});
    super.dispose();
  }
}
