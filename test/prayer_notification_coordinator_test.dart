import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/more/presentation/settings_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/repositories/in_memory_city_repository.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/adhan_voice.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/selected_city.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_session.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/just_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/native_prayer_audio_control.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/native_prayer_channel_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_calculator.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_notification_coordinator.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/adhan_audio_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/prayers_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/prayers_screen.dart';
import 'package:zad_alruh/src/features/progress/data/models/favorite.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/user_preferences.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

// =============================================================================
// Real SDK Audio Player Doubles
// =============================================================================

class MockAudioPlayer extends Fake implements AudioPlayer {
  final _positionSubject = StreamController<Duration>.broadcast();
  final _durationSubject = StreamController<Duration?>.broadcast();
  final _playingSubject = StreamController<bool>.broadcast();
  final _playerStateSubject = StreamController<PlayerState>.broadcast();
  final _errorSubject = StreamController<PlayerException>.broadcast();
  final _playbackEventSubject = StreamController<PlaybackEvent>.broadcast();

  String? currentAsset;
  bool isPlaying = false;
  int playCallCount = 0;
  int stopCallCount = 0;
  int setAssetCallCount = 0;
  bool throwOnStop = false;

  @override
  Stream<Duration> get positionStream => _positionSubject.stream;
  @override
  Stream<Duration?> get durationStream => _durationSubject.stream;
  @override
  Stream<bool> get playingStream => _playingSubject.stream;
  @override
  Stream<PlayerState> get playerStateStream => _playerStateSubject.stream;
  @override
  Stream<PlayerException> get errorStream => _errorSubject.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventSubject.stream;

  @override
  bool get playing => isPlaying;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 120);

  @override
  Future<Duration?> setAsset(
    String asset, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    setAssetCallCount++;
    currentAsset = asset;
    _durationSubject.add(const Duration(seconds: 120));
    _playerStateSubject.add(PlayerState(false, ProcessingState.ready));
    return const Duration(seconds: 120);
  }

  @override
  Future<void> play() async {
    playCallCount++;
    isPlaying = true;
    _playingSubject.add(true);
    _playerStateSubject.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (throwOnStop) {
      throw StateError('Simulated SDK audio stop failure during reset');
    }
    isPlaying = false;
    _playingSubject.add(false);
    _playerStateSubject.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> dispose() async {
    try {
      await stop();
    } catch (_) {}
    await _positionSubject.close();
    await _durationSubject.close();
    await _playingSubject.close();
    await _playerStateSubject.close();
    await _errorSubject.close();
    await _playbackEventSubject.close();
  }
}

class FakeAdhanAudioSession implements AdhanAudioSession {
  final _interruptionController = StreamController<void>.broadcast();
  final _noisyController = StreamController<void>.broadcast();

  bool isActivated = false;

  @override
  Stream<void> get interruptionStream => _interruptionController.stream;
  @override
  Stream<void> get becomingNoisyStream => _noisyController.stream;

  @override
  Future<bool> activate() async {
    isActivated = true;
    return true;
  }

  @override
  Future<void> deactivate() async {
    isActivated = false;
  }

  @override
  Future<void> dispose() async {
    await _interruptionController.close();
    await _noisyController.close();
  }
}

class FakeNativePrayerAudioControl implements NativePrayerAudioControl {
  int acquireCallCount = 0;
  int releaseCallCount = 0;
  String? activeLeaseToken;

  @override
  Future<bool> stopActivePlayback() async => true;

  @override
  Future<ManualPlaybackLeaseResult> acquireManualPlaybackLease({
    required String requestId,
  }) async {
    acquireCallCount++;
    final token = 'mock_lease_$acquireCallCount';
    activeLeaseToken = token;
    return ManualPlaybackLeaseResult(acquired: true, leaseToken: token);
  }

  @override
  Future<bool> releaseManualPlaybackLease({
    required String leaseToken,
  }) async {
    releaseCallCount++;
    if (activeLeaseToken == leaseToken) {
      activeLeaseToken = null;
    }
    return true;
  }

  @override
  Future<bool> isManualPlaybackLeaseActive() async => activeLeaseToken != null;
}

// =============================================================================
// Test Suite
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  const channelName = 'dev.zadalruh.zad_alruh/prayer_alarm';
  final fixedClock = DateTime.utc(2026, 10, 7, 0, 0, 0);

  late Directory tempDir;
  late String dbPath;

  setUpAll(() async {
    PrayerCalculator.ensureTimeZonesInitialized();

    // Load fonts for compact UI tests
    final amiriFile = File('assets/fonts/Amiri-Quran-Regular.ttf');
    if (await amiriFile.exists()) {
      final amiriBytes = await amiriFile.readAsBytes();
      final fontLoaderAmiri = FontLoader('Amiri Quran');
      fontLoaderAmiri.addFont(Future.value(ByteData.sublistView(amiriBytes)));
      await fontLoaderAmiri.load();
    }

    final fontLoaderPlex = FontLoader('IBM Plex Sans Arabic');
    for (final fontPath in [
      'assets/fonts/IBM-Plex-Sans-Arabic-Regular.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-Medium.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-SemiBold.ttf',
      'assets/fonts/IBM-Plex-Sans-Arabic-Bold.ttf',
    ]) {
      final f = File(fontPath);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        fontLoaderPlex.addFont(Future.value(ByteData.sublistView(bytes)));
      }
    }
    await fontLoaderPlex.load();

    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? 'D:/tools/flutter';
    final iconFile = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    ByteData iconData;
    if (iconFile.existsSync()) {
      final bytes = await iconFile.readAsBytes();
      expect(bytes.isNotEmpty, isTrue);
      iconData = ByteData.sublistView(bytes);
    } else {
      iconData = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      expect(iconData.lengthInBytes, greaterThan(0));
    }
    final fontLoaderIcons = FontLoader('MaterialIcons')
      ..addFont(Future.value(iconData));
    await fontLoaderIcons.load();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zad_alruh_notif_test_');
    dbPath = p.join(tempDir.path, 'test_notif.db');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SelectedCity createCairoCity() {
    return SelectedCity(
      id: 360630,
      name: 'Cairo',
      asciiName: 'Cairo',
      arabicName: 'القاهرة',
      countryCode: 'EG',
      latitude: 30.0444,
      longitude: 31.2357,
      timezone: 'Africa/Cairo',
      population: 9500000,
    );
  }

  SelectedCity createAlexandriaCity() {
    return SelectedCity(
      id: 361058,
      name: 'Alexandria',
      asciiName: 'Alexandria',
      arabicName: 'الإسكندرية',
      countryCode: 'EG',
      latitude: 31.2001,
      longitude: 29.9187,
      timezone: 'Africa/Cairo',
      population: 5200000,
    );
  }

  SelectedCity createLongyearbyenCity() {
    return SelectedCity(
      id: 2729907,
      name: 'Longyearbyen',
      asciiName: 'Longyearbyen',
      arabicName: 'لونغياربين',
      countryCode: 'SJ',
      latitude: 78.2232,
      longitude: 15.6267,
      timezone: 'Arctic/Longyearbyen',
      population: 2000,
    );
  }

  Map<String, dynamic> buildValidGetStateMap({
    bool enabled = true,
    int generationToken = 1,
    bool canScheduleExactAlarms = true,
    bool notificationsAllowed = true,
    bool isPlaybackStatusChannelBlocked = false,
    bool isDndOrSilentActive = false,
    bool isServiceRunning = false,
    bool isManualPlaybackLeaseActive = false,
    int futureEventsCount = 50,
    int pendingCleanupCount = 0,
    int cityId = 360630,
    String cityNameAr = 'القاهرة',
    String timezone = 'Africa/Cairo',
    int coverageHorizonUtc = 1800000000,
    int consumedLedgerCount = 0,
  }) {
    return <String, dynamic>{
      'enabled': enabled,
      'generationToken': generationToken,
      'canScheduleExactAlarms': canScheduleExactAlarms,
      'notificationsAllowed': notificationsAllowed,
      'isPlaybackStatusChannelBlocked': isPlaybackStatusChannelBlocked,
      'isDndOrSilentActive': isDndOrSilentActive,
      'isServiceRunning': isServiceRunning,
      'isManualPlaybackLeaseActive': isManualPlaybackLeaseActive,
      'futureEventsCount': futureEventsCount,
      'pendingCleanupCount': pendingCleanupCount,
      'cityId': cityId,
      'cityNameAr': cityNameAr,
      'timezone': timezone,
      'coverageHorizonUtc': coverageHorizonUtc,
      'consumedLedgerCount': consumedLedgerCount,
    };
  }

  group('PrayerNotificationCoordinator - Core Invariants', () {
    test(
      'builds 10-day canonical prayer plan strictly excluding sunrise with full_adhan mode',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        Map<String, dynamic>? receivedPlan;
        int replacePlanCalls = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 42};
          }
          if (call.method == 'replacePlan') {
            replacePlanCalls++;
            receivedPlan = Map<String, dynamic>.from(call.arguments as Map);
            final events = receivedPlan!['events'] as List;
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 43,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': events.length,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم تحديث جدول مواعيد الصلاة بنجاح',
            };
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: true,
              generationToken: 43,
              futureEventsCount: 50,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
          generalAdhanVoice: 'adam',
          fajrAdhanVoice: 'malmo_fajr',
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        final success = await coordinator.enableNotifications();

        expect(success, isTrue);
        expect(replacePlanCalls, 1);
        expect(receivedPlan, isNotNull);

        expect(receivedPlan!['expectedToken'], 42);
        expect(receivedPlan!['cityId'], cairo.id);
        expect(receivedPlan!['cityNameAr'], cairo.arabicName);
        expect(receivedPlan!['timezone'], cairo.timezone);
        expect(receivedPlan!['generalVoiceId'], 'adam');
        expect(receivedPlan!['fajrVoiceId'], 'malmo_fajr');
        expect(receivedPlan!['mode'], 'full_adhan');

        final events = (receivedPlan!['events'] as List)
            .cast<Map<dynamic, dynamic>>();

        expect(events.length, lessThanOrEqualTo(50));
        expect(events.length, greaterThanOrEqualTo(40));

        final prayerKeys = events.map((e) => e['prayerKey']).toSet();
        expect(
          prayerKeys,
          containsAll(['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']),
        );
        expect(prayerKeys, isNot(contains('sunrise')));

        for (final event in events) {
          expect(event['mode'], 'full_adhan');
          final prayerKey = event['prayerKey'];
          if (prayerKey == 'fajr') {
            expect(event['voiceId'], 'malmo_fajr');
          } else {
            expect(event['voiceId'], 'adam');
          }
          final triggerMillis = event['triggerEpochMillis'] as int;
          expect(triggerMillis, greaterThan(fixedClock.millisecondsSinceEpoch));
        }

        expect(coordinator.state.status, PrayerNotificationStatus.activeExact);
        expect(coordinator.state.plannedFutureEventsCount, events.length);
        expect(coordinator.state.acceptedScheduledCount, events.length);
      },
    );

    test(
      'gates explicit enable behind POST_NOTIFICATIONS permission',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'requestNotificationPermission') {
            return false;
          }
          if (call.method == 'disableAlarms') {
            return <String, dynamic>{
              'success': true,
              'token': 1,
            };
          }
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: false,
              notificationsAllowed: false,
              futureEventsCount: 0,
              pendingCleanupCount: 0,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        final success = await coordinator.enableNotifications();

        expect(success, isFalse);
        expect(coordinator.state.status,
            PrayerNotificationStatus.permissionDenied);
        expect(coordinator.state.notificationsAllowed, isFalse);

        final persistedPrefs = await repo.getPreferences();
        expect(persistedPrefs.notificationsEnabled, isFalse);
      },
    );

    test(
      'aborts on stale CAS authorization token without retrying stale plan',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        int replaceCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 5};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'replacePlan') {
            replaceCalls++;
            return <String, dynamic>{
              'success': false,
              'authorizationInvalidated': false,
              'errorCode': 'STALE_AUTHORIZATION_TOKEN',
              'messageAr': 'انتهت صلاحية رمز التفويض الحالي.',
            };
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        final success = await coordinator.enableNotifications();

        expect(success, isFalse);
        expect(replaceCalls, 1);
        expect(coordinator.state.status,
            PrayerNotificationStatus.partialFailure);
        expect(coordinator.state.technicalCode, 'STALE_AUTHORIZATION_TOKEN');
      },
    );

    test(
      'exposes partialFailure when native returns incomplete cleanup or scheduling',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 100};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'replacePlan') {
            return <String, dynamic>{
              'success': false,
              'authorizationInvalidated': true,
              'partialFailure': true,
              'token': 101,
              'scheduledCount': 35,
              'attemptedCount': 50,
              'exactScheduledCount': 35,
              'companionScheduledCount': 35,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'errorCode': 'OS_CLEANUP_INCOMPLETE',
              'messageAr':
                  'تم جدولة المواعيد ولكن لم تكتمل كافة عمليات تنظيف النظام.',
            };
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        final result = await coordinator.enableNotifications();

        expect(result, isFalse);
        expect(coordinator.state.status,
            PrayerNotificationStatus.partialFailure);
        expect(coordinator.state.technicalCode, 'OS_CLEANUP_INCOMPLETE');
        expect(coordinator.state.acceptedScheduledCount, 35);
        expect(coordinator.state.plannedFutureEventsCount, greaterThanOrEqualTo(35));
        expect(coordinator.state.errorMessageAr, contains('تنظيف'));
      },
    );

    test(
      'inexact companion fallback mode reflected when exact alarm capability is restricted',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 10};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return false;
          if (call.method == 'replacePlan') {
            final plan = Map<String, dynamic>.from(call.arguments as Map);
            final events = plan['events'] as List;
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 11,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': 0,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': false,
              'companionAlarmsUsed': true,
              'messageAr': 'تم تحديث جدول مواعيد الصلاة بنجاح',
            };
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        final success = await coordinator.enableNotifications();

        expect(success, isTrue);
        expect(coordinator.state.status, PrayerNotificationStatus.activeInexact);
        expect(coordinator.state.isApproximate, isTrue);
        expect(coordinator.state.canScheduleExactAlarms, isFalse);
        expect(coordinator.state.exactScheduledCount, 0);
        expect(coordinator.state.companionScheduledCount, 50);
      },
    );

    test(
      'settings or voice change triggers plan replacement with updated fingerprint',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        final List<Map<String, dynamic>> scheduledPlans = [];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': scheduledPlans.length + 1};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'replacePlan') {
            final plan = Map<String, dynamic>.from(call.arguments as Map);
            scheduledPlans.add(plan);
            final events = plan['events'] as List;
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': scheduledPlans.length + 10,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': events.length,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم تحديث جدول مواعيد الصلاة بنجاح',
            };
          }
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: true,
              generationToken: scheduledPlans.length + 10,
              futureEventsCount: 50,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
          generalAdhanVoice: 'adam',
          fajrAdhanVoice: 'malmo_fajr',
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);

        // 1. Initial enable: scheduled with adam
        await coordinator.enableNotifications();
        expect(scheduledPlans.length, 1);
        expect(scheduledPlans.first['generalVoiceId'], 'adam');

        // 2. Change general adhan voice to atcovi:
        await container
            .read(preferencesControllerProvider.notifier)
            .setGeneralAdhanVoice('atcovi');

        // 3. Reconcile:
        await coordinator.reconcile(passive: false);

        expect(scheduledPlans.length, 2);
        expect(scheduledPlans.last['generalVoiceId'], 'atcovi');
      },
    );

    test(
      'planned future events count is strictly distinct from accepted native registration counts',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 1};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'replacePlan') {
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 2,
              'scheduledCount': 50,
              'attemptedCount': 50,
              'exactScheduledCount': 50,
              'companionScheduledCount': 50,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم تحديث جدول مواعيد الصلاة بنجاح',
            };
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        await coordinator.enableNotifications();

        expect(coordinator.state.plannedFutureEventsCount, 50);
        expect(coordinator.state.acceptedScheduledCount, 50);
        expect(coordinator.state.exactScheduledCount, 50);
      },
    );
  });

  group('PrayerNotificationCoordinator - Failed Reset Latch & Recovery', () {
    test(
      'failed reset before SQLite wipe disables native store and survives NEW ProviderContainer as recoveryRequired latch with real SDK doubles',
      () async {
        final db1 = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo1 = ProgressRepository(db1);

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        bool nativeStoreEnabled = true;
        int disableAlarmsCalls = 0;
        int currentToken = 77;
        int registeredFutureEvents = 50;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': currentToken};
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'disableAlarms') {
            disableAlarmsCalls++;
            nativeStoreEnabled = false;
            registeredFutureEvents = 0;
            currentToken = 77;
            return <String, dynamic>{'success': true, 'token': 77};
          }
          if (call.method == 'resetAll') {
            return <String, dynamic>{'success': true, 'token': 78};
          }
          if (call.method == 'replacePlan') {
            final plan = Map<String, dynamic>.from(call.arguments as Map);
            final events = plan['events'] as List;
            nativeStoreEnabled = true;
            currentToken = 79;
            registeredFutureEvents = events.length;
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 79,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': events.length,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم التحديث بنجاح',
            };
          }
          if (call.method == 'stopActivePlayback') {
            return <String, dynamic>{'stopped': true};
          }
          if (call.method == 'acquireManualPlaybackLease') {
            return <String, dynamic>{'acquired': true, 'leaseToken': 'lease_1'};
          }
          if (call.method == 'releaseManualPlaybackLease') {
            return <String, dynamic>{'released': true};
          }
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: nativeStoreEnabled,
              generationToken: currentToken,
              futureEventsCount: registeredFutureEvents,
              pendingCleanupCount: 0,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          return null;
        });

        // Seed 9 tables before reset using supported page-only reading save
        await repo1.saveReadingProgress(
          const ReadingProgress(lastPage: 42),
        );
        await repo1.createBookmark(name: 'علامة 1', pageNumber: 42);
        await repo1.addFavorite(
          const Favorite(contentKind: 'dua', stableId: 'd1', title: 'دعاء الصباح'),
        );
        await repo1.startDhikrSession(
          sessionId: 'session_1',
          dhikrId: 'd1',
          category: 'morning',
          targetCount: 33,
          dateBucket: '2026-10-07',
        );
        await repo1.updateDailyTask(
          dateBucket: '2026-10-07',
          quranCompleted: true,
        );
        await repo1.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: true,
        ));

        // Snapshot ALL 9 SQL tables before failed reset
        final rawDb1 = await db1.database;
        final snapReading = await rawDb1.query('reading_progress');
        final snapBookmarks = await rawDb1.query('bookmarks');
        final snapFavorites = await rawDb1.query('favorites');
        final snapDhikr = await rawDb1.query('dhikr_sessions');
        final snapDaily = await rawDb1.query('daily_progress');
        final snapPrefs = await rawDb1.query('user_preferences');
        final snapHisn = await rawDb1.query('hisn_daily_item_progress');
        final snapQuranPages = await rawDb1.query('daily_quran_pages');
        final snapSourceConfirmations = await rawDb1.query('daily_source_confirmations');

        final mockPlayer = MockAudioPlayer();
        final mockSession = FakeAdhanAudioSession();
        final fakeNative = FakeNativePrayerAudioControl();

        final audioClient = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: mockSession,
          nativeAudioControl: fakeNative,
        );

        final container1 = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db1),
            progressRepositoryProvider.overrideWithValue(repo1),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
            adhanAudioPlayerClientProvider.overrideWithValue(audioClient),
          ],
        );

        try {
          final audioController =
              container1.read(adhanAudioControllerProvider.notifier);
          await audioController.playVoice(AdhanVoice.adam);
          expect(mockPlayer.isPlaying, isTrue);
          expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

          // SDK audio stop will fail during reset
          mockPlayer.throwOnStop = true;

          final prefsController =
              container1.read(preferencesControllerProvider.notifier);
          await container1.read(preferencesControllerProvider.future);

          try {
            await prefsController.resetAllState();
            fail('resetAllState was expected to fail at audioController.stop');
          } catch (e) {
            expect(e.toString(), contains('Simulated SDK audio stop failure'));
          }

          expect(disableAlarmsCalls, 1);
          expect(nativeStoreEnabled, isFalse);

          // Verify all 9 tables intact by comparing exact snapshots
          expect(await rawDb1.query('reading_progress'), snapReading);
          expect(await rawDb1.query('bookmarks'), snapBookmarks);
          expect(await rawDb1.query('favorites'), snapFavorites);
          expect(await rawDb1.query('dhikr_sessions'), snapDhikr);
          expect(await rawDb1.query('daily_progress'), snapDaily);
          expect(await rawDb1.query('user_preferences'), snapPrefs);
          expect(await rawDb1.query('hisn_daily_item_progress'), snapHisn);
          expect(await rawDb1.query('daily_quran_pages'), snapQuranPages);
          expect(await rawDb1.query('daily_source_confirmations'), snapSourceConfirmations);

          expect(snapReading.first['last_page'], 42);
          expect(snapPrefs.first['notifications_enabled'], 1);

          // Await confirmed audio stop and native lease release BEFORE container1 dispose
          mockPlayer.throwOnStop = false;
          await audioClient.stop();
          expect(mockPlayer.isPlaying, isFalse);
          expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
        } finally {
          mockPlayer.throwOnStop = false;
          try {
            await audioClient.stop();
            await audioClient.dispose();
          } catch (_) {}
          container1.dispose();
          await repo1.close();
        }

        // -------------------------------------------------------------
        // 2. SIMULATE APP REBOOT / BRAND NEW ProviderContainer & Repo
        // -------------------------------------------------------------
        final db2 = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo2 = ProgressRepository(db2);
        addTearDown(() => repo2.close());

        final container2 = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db2),
            progressRepositoryProvider.overrideWithValue(repo2),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container2.dispose);

        await container2.read(preferencesControllerProvider.future);
        await container2.read(cityRepositoryProvider.future);
        await container2.pump();

        final effectiveCity2 =
            container2.read(effectivePrayerSettingsProvider).requireValue;
        expect(effectiveCity2.city.id, cairo.id);

        final newCoordinator =
            container2.read(prayerNotificationCoordinatorProvider);
        await newCoordinator.reconcile(passive: true);

        expect(newCoordinator.state.status,
            PrayerNotificationStatus.recoveryRequired);
        expect(newCoordinator.state.isRecoveryRequired, isTrue);

        // Explicit recovery via recoverFromLatch
        await newCoordinator.recoverFromLatch();
        expect(
          newCoordinator.state.status,
          PrayerNotificationStatus.activeExact,
          reason: '${newCoordinator.state.technicalCode}: ${newCoordinator.state.errorMessageAr}',
        );
        expect(newCoordinator.state.acceptedScheduledCount, greaterThan(0));
        expect(newCoordinator.state.plannedFutureEventsCount, greaterThan(0));
        expect(newCoordinator.state.isRecoveryRequired, isFalse);

        // Verify SQL reading progress page 42 is preserved in db2
        final rawDb2 = await db2.database;
        final readingRows2 = await rawDb2.query('reading_progress');
        expect(readingRows2.first['last_page'], 42);
        final prefsRows2 = await rawDb2.query('user_preferences');
        expect(prefsRows2.first['notifications_enabled'], 1);
      },
    );

    test(
      'passive reconcile detects pending cleanup count > 0 as recoveryRequired',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: false,
              generationToken: 99,
              futureEventsCount: 0,
              pendingCleanupCount: 3,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        await container.read(preferencesControllerProvider.future);
        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);
        await coordinator.reconcile(passive: true);

        expect(coordinator.state.status,
            PrayerNotificationStatus.recoveryRequired);
        expect(coordinator.state.pendingCleanupCount, 3);
      },
    );
  });

  group('PrayerNotificationCoordinator - Gated Lifetime & Concurrency Guards', () {
    test('city change during replacement aborts stale plan', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(db);
      addTearDown(() => repo.close());

      final cairo = createCairoCity();
      final alex = createAlexandriaCity();
      final cityRepo = InMemoryCityRepository([cairo, alex]);

      final tokenEnteredCompleter = Completer<void>();
      final tokenCompleter = Completer<Map<String, dynamic>>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'requestNotificationPermission') return true;
        if (call.method == 'canScheduleExactAlarms') return true;
        if (call.method == 'getAuthorizationToken') {
          if (!tokenEnteredCompleter.isCompleted) {
            tokenEnteredCompleter.complete();
          }
          return tokenCompleter.future;
        }
        if (call.method == 'replacePlan') {
          final plan = Map<String, dynamic>.from(call.arguments as Map);
          final events = plan['events'] as List;
          return <String, dynamic>{
            'success': true,
            'authorizationInvalidated': true,
            'token': 123,
            'scheduledCount': events.length,
            'attemptedCount': events.length,
            'exactScheduledCount': events.length,
            'companionScheduledCount': events.length,
            'exactAlarmsUsed': true,
            'companionAlarmsUsed': true,
            'messageAr': 'تم التحديث',
          };
        }
        return null;
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
        ],
      );
      addTearDown(container.dispose);

      await repo.savePreferences(UserPreferences(
        selectedCityId: cairo.id,
        selectedCity: cairo.arabicName!,
        selectedTimezone: cairo.timezone,
        notificationsEnabled: false,
      ));

      final coordinator =
          container.read(prayerNotificationCoordinatorProvider);

      final enableFuture = coordinator.enableNotifications();

      // Wait until getAuthorizationToken is genuinely reached
      await tokenEnteredCompleter.future;

      // Mid-flight: change city to Alexandria
      await container
          .read(preferencesControllerProvider.notifier)
          .setSelectedCity(alex);

      tokenCompleter.complete(<String, dynamic>{'token': 10});

      final success = await enableFuture;
      expect(success, isFalse);
    });

    test('pending permission disable synchronously invalidates in-flight operation', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(db);
      addTearDown(() => repo.close());

      final cairo = createCairoCity();
      final cityRepo = InMemoryCityRepository([cairo]);

      final permissionCompleter = Completer<bool>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'requestNotificationPermission') {
          return permissionCompleter.future;
        }
        if (call.method == 'disableAlarms') {
          return <String, dynamic>{'success': true, 'token': 88};
        }
        if (call.method == 'getState') {
          return buildValidGetStateMap(
            enabled: false,
            generationToken: 88,
            notificationsAllowed: false,
            futureEventsCount: 0,
            pendingCleanupCount: 0,
            cityId: cairo.id,
            cityNameAr: cairo.arabicName!,
            timezone: cairo.timezone,
          );
        }
        return null;
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
        ],
      );
      addTearDown(container.dispose);

      await repo.savePreferences(UserPreferences(
        selectedCityId: cairo.id,
        selectedCity: cairo.arabicName!,
        selectedTimezone: cairo.timezone,
        notificationsEnabled: false,
      ));

      final coordinator =
          container.read(prayerNotificationCoordinatorProvider);

      final enableFuture = coordinator.enableNotifications();

      await coordinator.disableNotifications();

      permissionCompleter.complete(true);

      final enableResult = await enableFuture;
      expect(enableResult, isFalse);
      expect(coordinator.state.status, PrayerNotificationStatus.disabled);
    });

    test('enableA -> disable -> enableB completes without hang or resurrecting enableA', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(db);
      addTearDown(() => repo.close());

      final cairo = createCairoCity();
      final cityRepo = InMemoryCityRepository([cairo]);

      final permissionACompleter = Completer<bool>();
      int replacePlanCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'requestNotificationPermission') {
          if (!permissionACompleter.isCompleted) {
            return permissionACompleter.future;
          }
          return true;
        }
        if (call.method == 'canScheduleExactAlarms') return true;
        if (call.method == 'getAuthorizationToken') {
          return <String, dynamic>{'token': 10 + replacePlanCalls};
        }
        if (call.method == 'disableAlarms') {
          return <String, dynamic>{'success': true, 'token': 99};
        }
        if (call.method == 'replacePlan') {
          replacePlanCalls++;
          final plan = Map<String, dynamic>.from(call.arguments as Map);
          final events = plan['events'] as List;
          return <String, dynamic>{
            'success': true,
            'token': 100 + replacePlanCalls,
            'scheduledCount': events.length,
            'attemptedCount': events.length,
            'exactScheduledCount': events.length,
            'companionScheduledCount': events.length,
            'exactAlarmsUsed': true,
            'companionAlarmsUsed': true,
            'messageAr': 'تم التحديث بنجاح',
          };
        }
        if (call.method == 'getState') {
          return buildValidGetStateMap(
            enabled: true,
            generationToken: 100 + replacePlanCalls,
            canScheduleExactAlarms: true,
            notificationsAllowed: true,
            futureEventsCount: 50,
            pendingCleanupCount: 0,
            cityId: cairo.id,
            cityNameAr: cairo.arabicName!,
            timezone: cairo.timezone,
          );
        }
        return null;
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
        ],
      );
      addTearDown(container.dispose);

      await repo.savePreferences(UserPreferences(
        selectedCityId: cairo.id,
        selectedCity: cairo.arabicName!,
        selectedTimezone: cairo.timezone,
        notificationsEnabled: false,
      ));

      final coordinator =
          container.read(prayerNotificationCoordinatorProvider);

      final enableAFuture = coordinator.enableNotifications();

      await coordinator.disableNotifications();

      permissionACompleter.complete(true);
      final enableBFuture = coordinator.enableNotifications();

      final resultA = await enableAFuture;
      final resultB = await enableBFuture;

      expect(resultA, isFalse);
      expect(resultB, isTrue);
      expect(coordinator.state.status, PrayerNotificationStatus.activeExact);
      expect(coordinator.state.acceptedScheduledCount, greaterThan(0));
    });

    test(
      'resume passive reconcile during in-flight permission dialog does not invalidate active enable',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        int permissionPromptCount = 0;
        final enteredPostCompleter = Completer<void>();
        final permissionCompleter = Completer<bool>();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'requestNotificationPermission') {
            permissionPromptCount++;
            if (!enteredPostCompleter.isCompleted) {
              enteredPostCompleter.complete();
            }
            return await permissionCompleter.future;
          }
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'getAuthorizationToken') {
            return <String, dynamic>{'token': 10};
          }
          if (call.method == 'replacePlan') {
            final plan = Map<String, dynamic>.from(call.arguments as Map);
            final events = plan['events'] as List;
            return <String, dynamic>{
              'success': true,
              'token': 11,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': events.length,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم التحديث بنجاح',
            };
          }
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: false,
              generationToken: 10,
              futureEventsCount: 0,
              pendingCleanupCount: 0,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );
        addTearDown(container.dispose);

        await repo.savePreferences(UserPreferences(
          selectedCityId: cairo.id,
          selectedCity: cairo.arabicName!,
          selectedTimezone: cairo.timezone,
          notificationsEnabled: false,
        ));

        await container.read(preferencesControllerProvider.future);
        await container.read(cityRepositoryProvider.future);

        final coordinator =
            container.read(prayerNotificationCoordinatorProvider);

        // 1. Initiate explicit enable
        final enableFuture = coordinator.enableNotifications();

        // 2. Wait until native POST_NOTIFICATIONS permission dialog is entered
        await enteredPostCompleter.future;

        // 3. Simulate AppShell.didChangeAppLifecycleState(resumed) triggering passive reconcile
        await coordinator.reconcile(passive: true);

        // 4. User grants permission
        permissionCompleter.complete(true);

        final result = await enableFuture;

        expect(result, isTrue);
        expect(permissionPromptCount, 1);
        expect(coordinator.state.status, PrayerNotificationStatus.activeExact);
        expect(coordinator.state.acceptedScheduledCount, 50);
      },
    );

    test('transition from Cairo active to polar city confirms native disable before polarDayUnresolved', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(db);
      addTearDown(() => repo.close());

      final cairo = createCairoCity();
      final longyearbyen = createLongyearbyenCity();
      final cityRepo = InMemoryCityRepository([cairo, longyearbyen]);

      int disableCalls = 0;
      bool nativeEnabled = false;
      int currentRegisteredEventsCount = 0;
      final cairoReplacedCompleter = Completer<void>();
      final polarDisabledCompleter = Completer<void>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'requestNotificationPermission') return true;
        if (call.method == 'canScheduleExactAlarms') return true;
        if (call.method == 'getAuthorizationToken') {
          return <String, dynamic>{'token': 10};
        }
        if (call.method == 'replacePlan') {
          nativeEnabled = true;
          final plan = Map<String, dynamic>.from(call.arguments as Map);
          final events = plan['events'] as List;
          currentRegisteredEventsCount = events.length;
          if (!cairoReplacedCompleter.isCompleted) {
            cairoReplacedCompleter.complete();
          }
          return <String, dynamic>{
            'success': true,
            'token': 11,
            'scheduledCount': events.length,
            'attemptedCount': events.length,
            'exactScheduledCount': events.length,
            'companionScheduledCount': events.length,
            'exactAlarmsUsed': true,
            'companionAlarmsUsed': true,
            'messageAr': 'تم التحديث بنجاح',
          };
        }
        if (call.method == 'disableAlarms') {
          disableCalls++;
          nativeEnabled = false;
          currentRegisteredEventsCount = 0;
          if (!polarDisabledCompleter.isCompleted) {
            polarDisabledCompleter.complete();
          }
          return <String, dynamic>{'success': true, 'token': 12};
        }
        if (call.method == 'getState') {
          return buildValidGetStateMap(
            enabled: nativeEnabled,
            generationToken: 12,
            futureEventsCount: nativeEnabled ? currentRegisteredEventsCount : 0,
            pendingCleanupCount: 0,
          );
        }
        return null;
      });

      // Summer clock in Longyearbyen (midnight sun -> polar unresolved)
      final summerClock = DateTime.utc(2026, 6, 21, 12, 0, 0);

      await repo.savePreferences(UserPreferences(
        selectedCityId: cairo.id,
        selectedCity: cairo.arabicName!,
        selectedTimezone: cairo.timezone,
        notificationsEnabled: true,
      ));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          prayerNotificationClockProvider.overrideWithValue(() => summerClock),
        ],
      );
      addTearDown(container.dispose);

      // Hydrate ACTUAL prefs.future AND cityrepo.future before creating/operating coordinator
      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);
      final initialEffective = container.read(effectivePrayerSettingsProvider).requireValue;
      expect(initialEffective.city.id, cairo.id);

      final coordinator =
          container.read(prayerNotificationCoordinatorProvider);

      // 1. Initial plan replaces with Cairo via explicit user enable
      final enableResult = await coordinator.enableNotifications();
      expect(enableResult, isTrue);
      await cairoReplacedCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('Timed out awaiting Cairo replacePlan'),
      );

      expect(coordinator.state.status, PrayerNotificationStatus.activeExact);
      expect(nativeEnabled, isTrue);
      expect(coordinator.state.acceptedScheduledCount, currentRegisteredEventsCount);
      expect(currentRegisteredEventsCount, greaterThan(0));

      // 2. User changes city to Longyearbyen (triggers automatic listener)
      await container
          .read(preferencesControllerProvider.notifier)
          .setSelectedCity(longyearbyen);

      // Flush Riverpod derived listeners
      await container.pump();

      // Assert effective city is updated to Longyearbyen
      final effective =
          container.read(effectivePrayerSettingsProvider).requireValue;
      expect(effective.city.id, longyearbyen.id);
      expect(effective.city.name, longyearbyen.name);

      // 3. Await genuine guarded completion via OS disable and state update
      await polarDisabledCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('Timed out awaiting polar disableAlarms'),
      );
      final sw = Stopwatch()..start();
      while (coordinator.state.status != PrayerNotificationStatus.polarDayUnresolved &&
             sw.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(disableCalls, 1);
      expect(nativeEnabled, isFalse);
      expect(coordinator.state.status,
          PrayerNotificationStatus.polarDayUnresolved);
      expect(coordinator.state.acceptedScheduledCount, isNull);
      expect(coordinator.state.plannedFutureEventsCount, 0);
    });
  });

  group('NativePrayerChannelClient - Strict Native Bridge Codec', () {
    test('getState fails closed on missing, negative, or invalid fields', () async {
      final client = MethodChannelNativePrayerChannelClient();

      // Case 1: Negative generationToken
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'getState') {
          return buildValidGetStateMap(generationToken: -1);
        }
        return null;
      });
      expect(() => client.getState(), throwsA(isA<NativeBridgeException>()));

      // Case 2: Missing required field (cityId missing)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'getState') {
          final map = buildValidGetStateMap();
          map.remove('cityId');
          return map;
        }
        return null;
      });
      expect(() => client.getState(), throwsA(isA<NativeBridgeException>()));

      // Case 3: Non-boolean field
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'getState') {
          final map = buildValidGetStateMap();
          map['notificationsAllowed'] = 'not_a_bool';
          return map;
        }
        return null;
      });
      expect(() => client.getState(), throwsA(isA<NativeBridgeException>()));

      // Case 4: Negative pendingCleanupCount
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'getState') {
          return buildValidGetStateMap(pendingCleanupCount: -5);
        }
        return null;
      });
      expect(() => client.getState(), throwsA(isA<NativeBridgeException>()));
    });

    test('replacePlan returns typed failure on inconsistent or invalid response', () async {
      final client = MethodChannelNativePrayerChannelClient();
      final dummyPlan = <String, dynamic>{
        'expectedToken': 1,
        'cityId': 1,
        'cityNameAr': 'City',
        'timezone': 'UTC',
        'generalVoiceId': 'adam',
        'fajrVoiceId': 'adam',
        'mode': 'full_adhan',
        'coverageHorizonUtc': 1000,
        'events': <Map<String, dynamic>>[],
      };

      // Case 1: Inconsistent error flag with success: true retains actual technical code
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'replacePlan') {
          return <String, dynamic>{
            'success': true,
            'partialFailure': false,
            'errorCode': 'UNEXPECTED_ERROR_FLAG',
            'token': 1,
            'scheduledCount': 10,
            'attemptedCount': 10,
            'exactScheduledCount': 10,
            'companionScheduledCount': 10,
          };
        }
        return null;
      });
      final res1 = await client.replacePlan(dummyPlan);
      expect(res1.success, isFalse);
      expect(res1.errorCode, 'UNEXPECTED_ERROR_FLAG');

      // Case 2: Missing registration metrics on success: true
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'replacePlan') {
          return <String, dynamic>{
            'success': true,
            'token': 1,
          };
        }
        return null;
      });
      final res2 = await client.replacePlan(dummyPlan);
      expect(res2.success, isFalse);
      expect(res2.errorCode, 'INVALID_SUCCESS_METRICS');

      // Case 3: scheduledCount > attemptedCount
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'replacePlan') {
          return <String, dynamic>{
            'success': true,
            'token': 1,
            'scheduledCount': 15,
            'attemptedCount': 10,
            'exactScheduledCount': 10,
            'companionScheduledCount': 10,
            'exactAlarmsUsed': true,
            'companionAlarmsUsed': true,
          };
        }
        return null;
      });
      final res3 = await client.replacePlan(dummyPlan);
      expect(res3.success, isFalse);
      expect(res3.errorCode, 'INVALID_SUCCESS_METRICS');

      // Case 4: Negative scheduledCount
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'replacePlan') {
          return <String, dynamic>{
            'success': true,
            'token': 1,
            'scheduledCount': -1,
            'attemptedCount': 10,
            'exactScheduledCount': 0,
            'companionScheduledCount': 0,
            'exactAlarmsUsed': true,
            'companionAlarmsUsed': true,
          };
        }
        return null;
      });
      final res4 = await client.replacePlan(dummyPlan);
      expect(res4.success, isFalse);
      expect(res4.errorCode, 'INVALID_SUCCESS_METRICS');
    });

    test('disableAlarms and resetAll return typed failure on invalid token', () async {
      final client = MethodChannelNativePrayerChannelClient();

      // Case 1: disableAlarms with negative token
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'disableAlarms') {
          return <String, dynamic>{
            'success': true,
            'token': -5,
          };
        }
        return null;
      });
      final disableRes = await client.disableAlarms();
      expect(disableRes.success, isFalse);
      expect(disableRes.errorCode, 'INVALID_TOKEN');

      // Case 2: resetAll with negative token
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (call) async {
        if (call.method == 'resetAll') {
          return <String, dynamic>{
            'success': true,
            'token': -1,
          };
        }
        return null;
      });
      final resetRes = await client.resetAll();
      expect(resetRes.success, isFalse);
      expect(resetRes.errorCode, 'INVALID_TOKEN');
    });
  });

  group('Compact UI Layout Tests', () {
    testWidgets(
      '320x480 with textScale 2.0 displays SettingsScreen, scrolls to toggle, and handles interaction without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        bool nativeEnabled = false;
        int registeredCount = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: nativeEnabled,
              generationToken: nativeEnabled ? 2 : 1,
              canScheduleExactAlarms: true,
              notificationsAllowed: true,
              futureEventsCount: nativeEnabled ? registeredCount : 0,
              pendingCleanupCount: 0,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          if (call.method == 'requestNotificationPermission') return true;
          if (call.method == 'canScheduleExactAlarms') return true;
          if (call.method == 'getAuthorizationToken') return <String, dynamic>{'token': 1};
          if (call.method == 'replacePlan') {
            nativeEnabled = true;
            final plan = Map<String, dynamic>.from(call.arguments as Map);
            final events = plan['events'] as List;
            registeredCount = events.length;
            return <String, dynamic>{
              'success': true,
              'token': 2,
              'scheduledCount': events.length,
              'attemptedCount': events.length,
              'exactScheduledCount': events.length,
              'companionScheduledCount': events.length,
              'exactAlarmsUsed': true,
              'companionAlarmsUsed': true,
              'messageAr': 'تم التحديث',
            };
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );

        await tester.runAsync(() async {
          await repo.savePreferences(UserPreferences(
            selectedCityId: cairo.id,
            selectedCity: cairo.arabicName!,
            selectedTimezone: cairo.timezone,
            notificationsEnabled: false,
          ));
          await container.read(preferencesControllerProvider.future);
          await container.read(cityRepositoryProvider.future);
          await container.read(prayerNotificationCoordinatorProvider).reconcile(passive: true);
        });

        try {
          await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              home: const SettingsScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Drag to bring notification card into view with bounded loop
        final switchFinder = find.byType(Switch);
        for (int i = 0; i < 15 && switchFinder.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -250));
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(switchFinder, findsOneWidget);
        await tester.ensureVisible(switchFinder);
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(switchFinder);

        // Wait actual operation/authoritative state with tester.runAsync + bounded real Stopwatch deadline + manual pump
        final sw = Stopwatch()..start();
        while (sw.elapsed < const Duration(seconds: 5)) {
          await tester.pump(const Duration(milliseconds: 50));
          bool stateUpdated = false;
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            final prefs = container.read(preferencesControllerProvider).valueOrNull;
            final coord = container.read(prayerNotificationCoordinatorProvider);
            if (prefs?.notificationsEnabled == true &&
                coord.state.status == PrayerNotificationStatus.activeExact &&
                (coord.state.acceptedScheduledCount ?? 0) > 0) {
              stateUpdated = true;
            }
          });
          if (stateUpdated) break;
        }

        final finalPrefs = container.read(preferencesControllerProvider).valueOrNull;
        expect(finalPrefs?.notificationsEnabled, isTrue);
        final finalCoord = container.read(prayerNotificationCoordinatorProvider);
        expect(finalCoord.state.status, PrayerNotificationStatus.activeExact);
        expect(finalCoord.state.acceptedScheduledCount, greaterThan(0));

        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.runAsync(() async {
          await repo.close();
        });
      }
    },
    );

    testWidgets(
      '480x320 landscape with textScale 2.0 displays PrayersScreen and handles gestures without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(480, 320);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(db);

        final cairo = createCairoCity();
        final cityRepo = InMemoryCityRepository([cairo]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName),
                (call) async {
          if (call.method == 'getState') {
            return buildValidGetStateMap(
              enabled: true,
              generationToken: 1,
              canScheduleExactAlarms: true,
              notificationsAllowed: true,
              futureEventsCount: 50,
              pendingCleanupCount: 0,
              cityId: cairo.id,
              cityNameAr: cairo.arabicName!,
              timezone: cairo.timezone,
            );
          }
          return null;
        });

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            prayerNotificationClockProvider.overrideWithValue(() => fixedClock),
          ],
        );

        await tester.runAsync(() async {
          await repo.savePreferences(UserPreferences(
            selectedCityId: cairo.id,
            selectedCity: cairo.arabicName!,
            selectedTimezone: cairo.timezone,
            notificationsEnabled: true,
          ));
          await container.read(preferencesControllerProvider.future);
          await container.read(cityRepositoryProvider.future);
          expect(container.read(effectivePrayerSettingsProvider).requireValue, isNotNull);
          expect(container.read(prayerTimesControllerProvider).requireValue, isNotNull);
          await container.read(prayerNotificationCoordinatorProvider).reconcile(passive: true);
        });

        try {
          await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              home: const PrayersScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Drag CustomScrollView in landscape to test hit testing & scrollability
        final scrollViewFinder = find.byType(CustomScrollView);
        if (scrollViewFinder.evaluate().isNotEmpty) {
          await tester.drag(scrollViewFinder.first, const Offset(0, -150));
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.runAsync(() async {
          await repo.close();
        });
      }
    },
    );
  });
}
