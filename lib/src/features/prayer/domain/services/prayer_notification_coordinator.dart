import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/native_alarm_reset_boundary.dart';
import '../../../prayers/presentation/controllers/prayers_controller.dart';
import '../../../progress/data/models/user_preferences.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../domain/services/prayer_notification_planner.dart';
import 'native_prayer_channel_client.dart';

/// Operational status of the Android prayer notifications.
enum PrayerNotificationStatus {
  /// Notifications are disabled by user preference.
  disabled,

  /// Active and scheduled with exact OS alarms.
  activeExact,

  /// Active with inexact companion fallback (exact alarm permission denied or restricted).
  activeInexact,

  /// User has enabled in app, but notification permission (POST_NOTIFICATIONS) is denied in OS.
  permissionDenied,

  /// Calculation cannot produce valid canonical prayer times due to polar day conditions.
  polarDayUnresolved,

  /// Inconsistent state detected (e.g. failed reset or pending cleanup latch).
  /// Requires explicit user recovery; never auto-scheduled.
  recoveryRequired,

  /// Native plan was updated, but OS reported incomplete alarm scheduling or cleanup.
  partialFailure,

  /// Currently updating native schedule plan.
  updating,
}

/// Rich immutable state snapshot for prayer notifications UI and status widgets.
@immutable
class PrayerNotificationState {
  final PrayerNotificationStatus status;
  final int plannedFutureEventsCount;
  final int? acceptedScheduledCount;
  final int exactScheduledCount;
  final int companionScheduledCount;
  final int pendingCleanupCount;
  final String cityNameAr;
  final String? errorMessageAr;
  final String? technicalCode;
  final bool canScheduleExactAlarms;
  final bool notificationsAllowed;
  final bool isDndOrSilentActive;
  final bool isPlaybackStatusChannelBlocked;
  final bool isManualPlaybackLeaseActive;
  final int generationToken;
  final int unresolvedDaysCount;
  final int estimatedDaysCount;
  final bool isPartialCoverage;
  final String? coverageExplanation;

  const PrayerNotificationState({
    required this.status,
    this.plannedFutureEventsCount = 0,
    this.acceptedScheduledCount,
    this.exactScheduledCount = 0,
    this.companionScheduledCount = 0,
    this.pendingCleanupCount = 0,
    this.cityNameAr = '',
    this.errorMessageAr,
    this.technicalCode,
    this.canScheduleExactAlarms = false,
    this.notificationsAllowed = false,
    this.isDndOrSilentActive = false,
    this.isPlaybackStatusChannelBlocked = false,
    this.isManualPlaybackLeaseActive = false,
    this.generationToken = 0,
    this.unresolvedDaysCount = 0,
    this.estimatedDaysCount = 0,
    this.isPartialCoverage = false,
    this.coverageExplanation,
  });

  static const PrayerNotificationState initial = PrayerNotificationState(
    status: PrayerNotificationStatus.disabled,
  );

  bool get isEnabled =>
      status == PrayerNotificationStatus.activeExact ||
      status == PrayerNotificationStatus.activeInexact;

  bool get isApproximate => status == PrayerNotificationStatus.activeInexact;

  bool get isRecoveryRequired =>
      status == PrayerNotificationStatus.recoveryRequired;

  PrayerNotificationState copyWith({
    PrayerNotificationStatus? status,
    int? plannedFutureEventsCount,
    int? acceptedScheduledCount,
    bool clearAcceptedScheduledCount = false,
    int? exactScheduledCount,
    int? companionScheduledCount,
    int? pendingCleanupCount,
    String? cityNameAr,
    String? errorMessageAr,
    bool clearError = false,
    String? technicalCode,
    bool clearTechnicalCode = false,
    bool? canScheduleExactAlarms,
    bool? notificationsAllowed,
    bool? isDndOrSilentActive,
    bool? isPlaybackStatusChannelBlocked,
    bool? isManualPlaybackLeaseActive,
    int? generationToken,
    int? unresolvedDaysCount,
    int? estimatedDaysCount,
    bool? isPartialCoverage,
    String? coverageExplanation,
    bool clearCoverageExplanation = false,
  }) {
    return PrayerNotificationState(
      status: status ?? this.status,
      plannedFutureEventsCount:
          plannedFutureEventsCount ?? this.plannedFutureEventsCount,
      acceptedScheduledCount: clearAcceptedScheduledCount
          ? null
          : (acceptedScheduledCount ?? this.acceptedScheduledCount),
      exactScheduledCount: exactScheduledCount ?? this.exactScheduledCount,
      companionScheduledCount:
          companionScheduledCount ?? this.companionScheduledCount,
      pendingCleanupCount: pendingCleanupCount ?? this.pendingCleanupCount,
      cityNameAr: cityNameAr ?? this.cityNameAr,
      errorMessageAr:
          clearError ? null : (errorMessageAr ?? this.errorMessageAr),
      technicalCode:
          clearTechnicalCode ? null : (technicalCode ?? this.technicalCode),
      canScheduleExactAlarms:
          canScheduleExactAlarms ?? this.canScheduleExactAlarms,
      notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
      isDndOrSilentActive: isDndOrSilentActive ?? this.isDndOrSilentActive,
      isPlaybackStatusChannelBlocked:
          isPlaybackStatusChannelBlocked ?? this.isPlaybackStatusChannelBlocked,
      isManualPlaybackLeaseActive:
          isManualPlaybackLeaseActive ?? this.isManualPlaybackLeaseActive,
      generationToken: generationToken ?? this.generationToken,
      unresolvedDaysCount: unresolvedDaysCount ?? this.unresolvedDaysCount,
      estimatedDaysCount: estimatedDaysCount ?? this.estimatedDaysCount,
      isPartialCoverage: isPartialCoverage ?? this.isPartialCoverage,
      coverageExplanation: clearCoverageExplanation
          ? null
          : (coverageExplanation ?? this.coverageExplanation),
    );
  }

  @override
  String toString() =>
      'PrayerNotificationState(status: $status, planned: $plannedFutureEventsCount, '
      'accepted: $acceptedScheduledCount, exact: $exactScheduledCount, pendingCleanup: $pendingCleanupCount)';
}

/// Central Android-only coordinator for prayer notifications.
///
/// Responsibilities:
/// - Reuses approved PrayerNotificationPlanner for 10 consecutive civil dates and canonical prayers.
/// - Enforces CAS generation token checks with native Kotlin coordinator.
/// - Serializes ALL physical OS plan mutations and cleanups on a single coordinator-owned queue.
/// - Houses the durable failed-reset recovery latch.
/// - Supports passive, zero-prompt startup and resume reconciliation.
class PrayerNotificationCoordinator extends ChangeNotifier {
  final Ref _ref;
  final NativePrayerChannelClient _client;
  final PrayerNotificationPlanner _planner;
  final DateTime Function() _clock;

  int _invocationEpoch = 0;
  Future<void> _osQueue = Future<void>.value();
  PrayerNotificationState _state = PrayerNotificationState.initial;
  String? _lastScheduledFingerprint;
  bool _isDisposed = false;
  int? _pendingEnableEpoch;
  int? _pendingDisableEpoch;

  late final ProgressMutationBarrier _cachedBarrier;
  ProviderSubscription<AsyncValue<UserPreferences>>? _prefsSub;
  ProviderSubscription<AsyncValue<EffectivePrayerSettings>>? _settingsSub;

  PrayerNotificationCoordinator({
    required Ref ref,
    NativePrayerChannelClient? client,
    PrayerNotificationPlanner? planner,
    DateTime Function()? clock,
  })  : _ref = ref,
        _client = client ?? ref.read(nativePrayerChannelClientProvider),
        _planner = planner ?? PrayerNotificationPlanner(),
        _clock = clock ?? DateTime.now {
    _cachedBarrier = _ref.read(resetBarrierProvider);
    _cachedBarrier.addListener(_onBarrierChanged);

    // Wire real provider listeners to latest immutable effective + optin + voices
    _prefsSub = _ref.listen<AsyncValue<UserPreferences>>(
      preferencesControllerProvider,
      (previous, next) {
        _onPreferencesChanged(previous?.valueOrNull, next.valueOrNull);
      },
      fireImmediately: false,
    );

    _settingsSub = _ref.listen<AsyncValue<EffectivePrayerSettings>>(
      effectivePrayerSettingsProvider,
      (previous, next) {
        _onSettingsChanged(previous?.valueOrNull, next.valueOrNull);
      },
      fireImmediately: false,
    );
  }

  PrayerNotificationState get state => _state;

  void _onBarrierChanged() {
    if (_cachedBarrier.isResetInProgress) {
      _invocationEpoch++;
      _lastScheduledFingerprint = null;
    }
  }

  void _onPreferencesChanged(UserPreferences? prev, UserPreferences? next) {
    if (_isDisposed || _cachedBarrier.isResetInProgress) return;
    if (_pendingEnableEpoch != null || _pendingDisableEpoch != null) return;
    if (next == null) return;

    final prevEnabled = prev?.notificationsEnabled;
    final nextEnabled = next.notificationsEnabled;
    final prevVoices = '${prev?.generalAdhanVoice}|${prev?.fajrAdhanVoice}';
    final nextVoices = '${next.generalAdhanVoice}|${next.fajrAdhanVoice}';

    if (prevEnabled != nextEnabled || prevVoices != nextVoices || prev == null) {
      _invocationEpoch++;
      reconcile(passive: true);
    }
  }

  void _onSettingsChanged(
    EffectivePrayerSettings? prev,
    EffectivePrayerSettings? next,
  ) {
    if (_isDisposed || _cachedBarrier.isResetInProgress) return;
    if (_pendingEnableEpoch != null || _pendingDisableEpoch != null) return;
    if (next == null) return;

    final prefs = _ref.read(preferencesControllerProvider).valueOrNull;
    if (prefs == null || !prefs.notificationsEnabled) return;

    if (prev?.fingerprint != next.fingerprint) {
      _invocationEpoch++;
      reconcile(passive: true);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _invocationEpoch++;
    _pendingEnableEpoch = null;
    _pendingDisableEpoch = null;
    _lastScheduledFingerprint = null;
    _cachedBarrier.removeListener(_onBarrierChanged);
    _prefsSub?.close();
    _settingsSub?.close();
    super.dispose();
  }

  void _updateState(PrayerNotificationState newState) {
    if (_isDisposed) return;
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  /// Synchronously invalidates any active in-flight scheduling when reset begins.
  void invalidateForReset() {
    _invocationEpoch++;
    _pendingEnableEpoch = null;
    _pendingDisableEpoch = null;
    _lastScheduledFingerprint = null;
  }

  bool _isInvocationValid({
    required int epoch,
    required int barrierGen,
    String? expectedFingerprint,
    bool? expectedOptIn,
    String? expectedVoices,
  }) {
    if (_isDisposed) return false;
    if (_invocationEpoch != epoch) return false;
    if (_cachedBarrier.isResetInProgress) return false;
    if (_cachedBarrier.currentGeneration != barrierGen) return false;

    if (expectedOptIn != null) {
      final currentPrefs = _ref.read(preferencesControllerProvider).valueOrNull;
      if (currentPrefs == null ||
          currentPrefs.notificationsEnabled != expectedOptIn) {
        return false;
      }
    }

    if (expectedVoices != null) {
      final currentPrefs = _ref.read(preferencesControllerProvider).valueOrNull;
      if (currentPrefs == null) return false;
      final currentVoices =
          '${currentPrefs.generalAdhanVoice}|${currentPrefs.fajrAdhanVoice}';
      if (currentVoices != expectedVoices) return false;
    }

    if (expectedFingerprint != null) {
      final currentEffective =
          _ref.read(effectivePrayerSettingsProvider).valueOrNull;
      if (currentEffective == null ||
          currentEffective.fingerprint != expectedFingerprint) {
        return false;
      }
    }

    return true;
  }

  /// Passively reconciles current native state against SQLite preferences.
  /// NEVER triggers permission dialogs.
  Future<void> reconcile({bool passive = true}) async {
    if (_isDisposed || _cachedBarrier.isResetInProgress) return;
    if (passive &&
        (_pendingEnableEpoch != null || _pendingDisableEpoch != null)) {
      return;
    }

    final int epoch = ++_invocationEpoch;
    final int barrierGen = _cachedBarrier.currentGeneration;

    final prefsAsync = _ref.read(preferencesControllerProvider);
    if (prefsAsync.isLoading || prefsAsync.hasError) return;
    final prefs = prefsAsync.valueOrNull;
    if (prefs == null) return;

    final NativeAlarmState nativeState;
    try {
      nativeState = await _client.getState();
    } catch (e) {
      if (_isDisposed ||
          _cachedBarrier.isResetInProgress ||
          _invocationEpoch != epoch) {
        return;
      }
      _updateState(_state.copyWith(
        status: PrayerNotificationStatus.recoveryRequired,
        clearAcceptedScheduledCount: true,
        errorMessageAr: 'تعذر قراءة حالة التنبيهات من النظام.',
        technicalCode: 'GET_STATE_EXCEPTION',
      ));
      return;
    }

    if (!_isInvocationValid(
      epoch: epoch,
      barrierGen: barrierGen,
      expectedOptIn: prefs.notificationsEnabled,
    )) {
      return;
    }

    // 1. Detect Failed-Reset Latch & Inconsistent State:
    // If SQLite opt-in is true BUT native store is disabled, OR pendingCleanupCount > 0:
    // We are in a recoveryRequired state. DO NOT auto-reschedule!
    if (prefs.notificationsEnabled &&
        (!nativeState.enabled || nativeState.pendingCleanupCount > 0)) {
      _updateState(_state.copyWith(
        status: PrayerNotificationStatus.recoveryRequired,
        pendingCleanupCount: nativeState.pendingCleanupCount,
        cityNameAr: nativeState.cityNameAr,
        notificationsAllowed: nativeState.notificationsAllowed,
        canScheduleExactAlarms: nativeState.canScheduleExactAlarms,
        isDndOrSilentActive: nativeState.isDndOrSilentActive,
        isPlaybackStatusChannelBlocked:
            nativeState.isPlaybackStatusChannelBlocked,
        generationToken: nativeState.generationToken,
        clearAcceptedScheduledCount: true,
        errorMessageAr: nativeState.pendingCleanupCount > 0
            ? 'توجد عمليات تنظيف معلقة للتنبيهات السابقة تتطلب التأكيد.'
            : 'تتطلب التنبيهات إعادة التفعيل يدوياً بعد محاولة إعادة ضبط سابقة.',
      ));
      return;
    }

    // 2. User has disabled notifications:
    if (!prefs.notificationsEnabled) {
      if (nativeState.enabled) {
        await _enqueueDisableAlarms(epoch, barrierGen);
      } else {
        _updateState(_state.copyWith(
          status: nativeState.pendingCleanupCount > 0
              ? PrayerNotificationStatus.recoveryRequired
              : PrayerNotificationStatus.disabled,
          pendingCleanupCount: nativeState.pendingCleanupCount,
          clearAcceptedScheduledCount: true,
          plannedFutureEventsCount: 0,
          notificationsAllowed: nativeState.notificationsAllowed,
          canScheduleExactAlarms: nativeState.canScheduleExactAlarms,
          isDndOrSilentActive: nativeState.isDndOrSilentActive,
          isPlaybackStatusChannelBlocked:
              nativeState.isPlaybackStatusChannelBlocked,
          generationToken: nativeState.generationToken,
          clearError: true,
          clearTechnicalCode: true,
        ));
      }
      return;
    }

    // 3. User has enabled notifications:
    // Verify OS notification permission passively:
    if (!nativeState.notificationsAllowed) {
      _updateState(_state.copyWith(
        status: PrayerNotificationStatus.permissionDenied,
        notificationsAllowed: false,
        canScheduleExactAlarms: nativeState.canScheduleExactAlarms,
        pendingCleanupCount: nativeState.pendingCleanupCount,
        generationToken: nativeState.generationToken,
        clearAcceptedScheduledCount: true,
        errorMessageAr: 'إذن إرسال الإشعارات غير مفعل في إعدادات النظام.',
      ));
      return;
    }

    // Check effective settings:
    final effectiveAsync = _ref.read(effectivePrayerSettingsProvider);
    if (effectiveAsync.isLoading) return;
    if (effectiveAsync.hasError) {
      _updateState(_state.copyWith(
        status: PrayerNotificationStatus.recoveryRequired,
        clearAcceptedScheduledCount: true,
        errorMessageAr:
            'تعذر تحديد إعدادات مواقيت الصلاة (خطأ في بيانات المدينة أو الحساب).',
        technicalCode: 'EFFECTIVE_SETTINGS_ERROR',
      ));
      return;
    }
    final effective = effectiveAsync.valueOrNull;
    if (effective == null) return;

    // Check if fingerprint, horizon, capability changed, or expiry requires refreshing plan:
    final fingerprint = _buildPlanFingerprint(effective, prefs);
    final nowMillis = _clock().toUtc().millisecondsSinceEpoch;
    final bool horizonExpired =
        nativeState.coverageHorizonUtc > 0 && nativeState.coverageHorizonUtc <= nowMillis;
    final bool horizonNeedsRefresh =
        nativeState.futureEventsCount < 10 || horizonExpired;
    final bool capabilityChanged =
        nativeState.canScheduleExactAlarms != _state.canScheduleExactAlarms;
    final bool needsFreshPlan = _lastScheduledFingerprint != fingerprint ||
        horizonNeedsRefresh ||
        capabilityChanged ||
        _state.acceptedScheduledCount == null;

    if (needsFreshPlan) {
      await _enqueueReplacePlan(
        epoch: epoch,
        barrierGen: barrierGen,
        effective: effective,
        prefs: prefs,
      );
    }
  }

  /// Explicit user opt-in request.
  /// Requests POST_NOTIFICATIONS permission outside the serialized OS queue.
  Future<bool> enableNotifications() async {
    if (_isDisposed || _cachedBarrier.isResetInProgress) return false;

    final int epoch = ++_invocationEpoch;
    final int barrierGen = _cachedBarrier.currentGeneration;
    _pendingEnableEpoch = epoch;

    try {
      // 1. Request POST_NOTIFICATIONS permission outside serialized OS queue:
      final bool notifGranted = await _client.requestNotificationPermission();

      if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
        return false;
      }

      if (!notifGranted) {
        Object? sqlError;
        try {
          await _ref
              .read(preferencesControllerProvider.notifier)
              .setNotificationsEnabled(false);
        } catch (e) {
          sqlError = e;
        }

        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          return false;
        }

        await _enqueueDisableAlarms(
          epoch,
          barrierGen,
          sqlError: sqlError,
          overrideStatus: PrayerNotificationStatus.permissionDenied,
          overrideMessageAr: 'تم رفض إذن الإشعارات من قِبل المستخدم.',
        );
        return false;
      }

      // Check exact alarm permission:
      final bool canExact = await _client.canScheduleExactAlarms();
      if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
        return false;
      }

      // Persist user opt-in in SQLite:
      try {
        await _ref
            .read(preferencesControllerProvider.notifier)
            .setNotificationsEnabled(true);
      } catch (e) {
        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          return false;
        }
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.recoveryRequired,
          clearAcceptedScheduledCount: true,
          errorMessageAr: 'تعذر حفظ إعدادات تفعيل التنبيهات.',
          technicalCode: 'SQLITE_ENABLE_FAILED',
        ));
        return false;
      }

      if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
        return false;
      }

      // Read effective settings:
      final effectiveAsync = _ref.read(effectivePrayerSettingsProvider);
      final effective = effectiveAsync.valueOrNull;
      if (effective == null) {
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.disabled,
          clearAcceptedScheduledCount: true,
          errorMessageAr: 'تعذر تحديد إعدادات المدينة لحساب مواعيد الأذان.',
        ));
        return false;
      }

      final prefs = _ref.read(preferencesControllerProvider).valueOrNull;
      if (prefs == null) return false;

      _updateState(_state.copyWith(status: PrayerNotificationStatus.updating));
      return await _enqueueReplacePlan(
        epoch: epoch,
        barrierGen: barrierGen,
        effective: effective,
        prefs: prefs,
        canExactOverride: canExact,
      );
    } finally {
      if (_pendingEnableEpoch == epoch) {
        _pendingEnableEpoch = null;
      }
    }
  }

  /// Explicit user opt-out request.
  /// Synchronously invalidates in-flight operations and enqueues native cancellation.
  Future<void> disableNotifications() async {
    final int epoch = ++_invocationEpoch;
    final int barrierGen = _cachedBarrier.currentGeneration;
    _pendingEnableEpoch = null;
    _pendingDisableEpoch = epoch;

    _lastScheduledFingerprint = null;
    _updateState(_state.copyWith(
      status: PrayerNotificationStatus.updating,
      clearAcceptedScheduledCount: true,
    ));

    Object? sqlError;
    try {
      await _ref
          .read(preferencesControllerProvider.notifier)
          .setNotificationsEnabled(false);
    } catch (e) {
      sqlError = e;
    }

    try {
      await _enqueueDisableAlarms(epoch, barrierGen, sqlError: sqlError);
    } finally {
      if (_pendingDisableEpoch == epoch) {
        _pendingDisableEpoch = null;
      }
    }
  }

  /// Explicit user action to recover from a failed-reset latch or retry cleanup.
  /// Executes cleanup on _osQueue FIRST, then enqueues plan replacement OUTSIDE
  /// the cleanup callback to prevent nested deadlock.
  Future<void> recoverFromLatch() async {
    final int epoch = ++_invocationEpoch;
    final int barrierGen = _cachedBarrier.currentGeneration;
    _lastScheduledFingerprint = null;
    _updateState(_state.copyWith(
      status: PrayerNotificationStatus.updating,
      clearAcceptedScheduledCount: true,
    ));

    // Step 1: Finish queued cleanup FIRST on _osQueue
    final cleanupCompleter = Completer<bool>();
    _osQueue = _osQueue.then((_) async {
      if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
        cleanupCompleter.complete(false);
        return;
      }
      try {
        final disableRes = await _client.disableAlarms();
        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          cleanupCompleter.complete(false);
          return;
        }
        if (!disableRes.success || disableRes.partialFailure) {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.recoveryRequired,
            errorMessageAr: disableRes.messageAr ??
                'تعذر إتمام تنظيف التنبيهات في النظام. يرجى إعادة المحاولة.',
            technicalCode: disableRes.errorCode ?? 'RECOVERY_DISABLE_FAILED',
          ));
          cleanupCompleter.complete(false);
          return;
        }

        final nativeState = await _client.getState();
        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          cleanupCompleter.complete(false);
          return;
        }
        if (nativeState.pendingCleanupCount > 0) {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.recoveryRequired,
            pendingCleanupCount: nativeState.pendingCleanupCount,
            errorMessageAr:
                'توجد عمليات تنظيف معلقة للتنبيهات السابقة تتطلب التأكيد.',
            technicalCode: 'PENDING_CLEANUP_REMAINING',
          ));
          cleanupCompleter.complete(false);
          return;
        }

        cleanupCompleter.complete(true);
      } catch (e) {
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.recoveryRequired,
          errorMessageAr: 'حدث خطأ أثناء محاولة استعادة التنبيهات: $e',
          technicalCode: 'RECOVERY_EXCEPTION',
        ));
        cleanupCompleter.complete(false);
      }
    }, onError: (Object err, StackTrace stack) {
      if (!cleanupCompleter.isCompleted) cleanupCompleter.complete(false);
    });

    final bool cleanupSuccess = await cleanupCompleter.future;
    if (!cleanupSuccess) return;

    if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) return;

    // Step 2: Schedule replacement OUTSIDE the cleanup callback (no nested deadlock!)
    final prefs = _ref.read(preferencesControllerProvider).valueOrNull;
    if (prefs != null && prefs.notificationsEnabled) {
      final effective =
          _ref.read(effectivePrayerSettingsProvider).valueOrNull;
      if (effective != null) {
        await _enqueueReplacePlan(
          epoch: epoch,
          barrierGen: barrierGen,
          effective: effective,
          prefs: prefs,
        );
        return;
      }
    }

    _updateState(_state.copyWith(
      status: PrayerNotificationStatus.disabled,
      pendingCleanupCount: 0,
      clearAcceptedScheduledCount: true,
      plannedFutureEventsCount: 0,
      clearError: true,
      clearTechnicalCode: true,
    ));
  }

  /// Requests exact alarm permission from the OS and reconciles state.
  Future<bool> requestExactAlarmPermission() async {
    if (_isDisposed || _cachedBarrier.isResetInProgress) return false;
    final int epoch = ++_invocationEpoch;
    final int barrierGen = _cachedBarrier.currentGeneration;
    final granted = await _client.requestExactAlarmPermission();
    if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
      return false;
    }
    await reconcile(passive: true);
    return granted;
  }

  /// Queries exact alarm capability.
  Future<bool> canScheduleExactAlarms() => _client.canScheduleExactAlarms();

  /// Reset-entry hook: durably disables native alarms before manual SDK cleanup on the same OS queue.
  Future<void> executePrepareReset() {
    _invocationEpoch++;
    _lastScheduledFingerprint = null;
    _updateState(_state.copyWith(status: PrayerNotificationStatus.updating));

    final completer = Completer<void>();
    _osQueue = _osQueue.then((_) async {
      try {
        final disableRes = await _client.disableAlarms();
        final nativeState = await _client.getState();

        final bool isClean = disableRes.success &&
            !disableRes.partialFailure &&
            disableRes.errorCode == null &&
            !nativeState.enabled &&
            nativeState.pendingCleanupCount == 0;

        if (!isClean) {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.recoveryRequired,
            pendingCleanupCount: nativeState.pendingCleanupCount,
            errorMessageAr: disableRes.messageAr ??
                'تعذر تأكيد إلغاء التنبيهات قبل إعادة الضبط.',
            technicalCode: disableRes.errorCode ?? 'PREPARE_RESET_UNCERTAIN',
          ));
          completer.completeError(NativeResetException(
            disableRes.messageAr ??
                'تعذر تأكيد إلغاء التنبيهات قبل إعادة الضبط.',
            disableRes.errorCode ?? 'PREPARE_RESET_UNCERTAIN',
          ));
          return;
        }

        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.disabled,
          pendingCleanupCount: 0,
          clearAcceptedScheduledCount: true,
          plannedFutureEventsCount: 0,
          generationToken: disableRes.token ?? nativeState.generationToken,
          clearError: true,
          clearTechnicalCode: true,
        ));
        completer.complete();
      } on NativeResetException catch (e) {
        completer.completeError(e);
      } catch (e) {
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.recoveryRequired,
          errorMessageAr: 'فشل إلغاء تنبيهات النظام أثناء التحضير لإعادة الضبط.',
          technicalCode: 'PREPARE_RESET_FAILED',
        ));
        completer.completeError(NativeResetException(
          'فشل إلغاء تنبيهات النظام أثناء التحضير لإعادة الضبط.',
          e.toString(),
        ));
      }
    }, onError: (Object err, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(err, stack);
    });
    return completer.future;
  }

  /// Cancels all scheduled native alarms and clears native persistence on the same OS queue.
  Future<void> executeResetAll() {
    final completer = Completer<void>();
    _osQueue = _osQueue.then((_) async {
      try {
        final result = await _client.resetAll();
        if (!result.success ||
            result.partialFailure ||
            result.errorCode != null) {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.recoveryRequired,
            errorMessageAr:
                result.messageAr ?? 'فشلت إعادة ضبط مواعيد الأذان في النظام.',
            technicalCode: result.errorCode ?? 'RESET_ALL_FAILED',
          ));
          completer.completeError(NativeResetException(
            result.messageAr ?? 'فشلت إعادة ضبط مواعيد الأذان في النظام.',
            result.errorCode ?? 'RESET_ALL_FAILED',
          ));
          return;
        }
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.disabled,
          pendingCleanupCount: 0,
          clearAcceptedScheduledCount: true,
          plannedFutureEventsCount: 0,
          generationToken: result.token ?? 0,
          clearError: true,
          clearTechnicalCode: true,
        ));
        completer.complete();
      } on NativeResetException catch (e) {
        completer.completeError(e);
      } catch (e) {
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.recoveryRequired,
          errorMessageAr: 'فشلت إعادة ضبط مواعيد الأذان في النظام.',
          technicalCode: 'RESET_ALL_FAILED',
        ));
        completer.completeError(NativeResetException(
          'فشلت إعادة ضبط مواعيد الأذان في النظام.',
          e.toString(),
        ));
      }
    }, onError: (Object err, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(err, stack);
    });
    return completer.future;
  }

  /// Serialized native disable execution.
  Future<void> _enqueueDisableAlarms(
    int epoch,
    int barrierGen, {
    Object? sqlError,
    PrayerNotificationStatus? overrideStatus,
    String? overrideMessageAr,
  }) {
    final completer = Completer<void>();
    _osQueue = _osQueue.then((_) async {
      if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
        completer.complete();
        return;
      }
      try {
        final result = await _client.disableAlarms();
        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          completer.complete();
          return;
        }

        final nativeState = await _client.getState();
        if (!_isInvocationValid(epoch: epoch, barrierGen: barrierGen)) {
          completer.complete();
          return;
        }

        final bool isClean = result.success &&
            !result.partialFailure &&
            result.errorCode == null &&
            !nativeState.enabled &&
            nativeState.pendingCleanupCount == 0 &&
            sqlError == null;

        if (isClean) {
          _updateState(_state.copyWith(
            status: overrideStatus ?? PrayerNotificationStatus.disabled,
            notificationsAllowed: overrideStatus ==
                    PrayerNotificationStatus.permissionDenied
                ? false
                : _state.notificationsAllowed,
            pendingCleanupCount: 0,
            clearAcceptedScheduledCount: true,
            plannedFutureEventsCount: 0,
            generationToken: result.token ?? nativeState.generationToken,
            errorMessageAr: overrideMessageAr,
            clearError: overrideMessageAr == null,
            clearTechnicalCode: true,
          ));
        } else {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.recoveryRequired,
            pendingCleanupCount: nativeState.pendingCleanupCount,
            clearAcceptedScheduledCount: true,
            plannedFutureEventsCount: 0,
            generationToken: result.token ?? nativeState.generationToken,
            errorMessageAr: result.messageAr ??
                (sqlError != null
                    ? 'تعذر حفظ إعدادات إيقاف التنبيهات في قاعدة البيانات.'
                    : 'تعذر تأكيد إلغاء كافة التنبيهات في النظام. يرجى إعادة المحاولة.'),
            technicalCode: result.errorCode ??
                (sqlError != null
                    ? 'SQLITE_OPT_OUT_FAILED'
                    : 'CLEANUP_UNCERTAIN'),
          ));
        }
        completer.complete();
      } catch (e) {
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.recoveryRequired,
          clearAcceptedScheduledCount: true,
          errorMessageAr: 'تعذر إلغاء التنبيهات في النظام. يرجى إعادة المحاولة.',
          technicalCode: 'DISABLE_ALARMS_EXCEPTION',
        ));
        completer.complete();
      }
    }, onError: (Object err, StackTrace stack) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Serialized native plan replacement execution with CAS validation.
  Future<bool> _enqueueReplacePlan({
    required int epoch,
    required int barrierGen,
    required EffectivePrayerSettings effective,
    required UserPreferences prefs,
    bool? canExactOverride,
  }) {
    final completer = Completer<bool>();
    final snapshotFingerprint = effective.fingerprint;
    final snapshotOptIn = prefs.notificationsEnabled;
    final snapshotVoices =
        '${prefs.generalAdhanVoice}|${prefs.fajrAdhanVoice}';

    _osQueue = _osQueue.then((_) async {
      if (!_isInvocationValid(
        epoch: epoch,
        barrierGen: barrierGen,
        expectedFingerprint: snapshotFingerprint,
        expectedOptIn: snapshotOptIn,
        expectedVoices: snapshotVoices,
      )) {
        completer.complete(false);
        return;
      }

      try {
        // 1. Fetch current authorization token for CAS:
        final currentToken = await _client.getAuthorizationToken();
        if (!_isInvocationValid(
          epoch: epoch,
          barrierGen: barrierGen,
          expectedFingerprint: snapshotFingerprint,
          expectedOptIn: snapshotOptIn,
          expectedVoices: snapshotVoices,
        )) {
          completer.complete(false);
          return;
        }

        if (currentToken == null) {
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.partialFailure,
            clearAcceptedScheduledCount: true,
            errorMessageAr: 'تعذر قراءة رمز التفويض الحالي من النظام.',
            technicalCode: 'NULL_AUTHORIZATION_TOKEN',
          ));
          completer.complete(false);
          return;
        }

        // 2. Build schedule plan using approved PrayerNotificationPlanner:
        final generalVoice = UserPreferences.allowedGeneralAdhanVoices
                .contains(prefs.generalAdhanVoice)
            ? prefs.generalAdhanVoice
            : 'adam';
        final fajrVoice = UserPreferences.allowedFajrAdhanVoices
                .contains(prefs.fajrAdhanVoice)
            ? prefs.fajrAdhanVoice
            : 'malmo_fajr';

        final plan = _planner.build(
          city: effective.city,
          settings: effective.settings,
          nowUtc: _clock().toUtc(),
          generalVoiceId: generalVoice,
          fajrVoiceId: fajrVoice,
          mode: 'full_adhan',
        );

        if (plan.unresolvedDaysCount > 0 && plan.hasZeroScheduledEvents) {
          final disableRes = await _client.disableAlarms();
          final nativeState = await _client.getState();

          final bool isClean = disableRes.success &&
              !disableRes.partialFailure &&
              disableRes.errorCode == null &&
              !nativeState.enabled &&
              nativeState.pendingCleanupCount == 0;

          if (!isClean) {
            _updateState(_state.copyWith(
              status: PrayerNotificationStatus.recoveryRequired,
              pendingCleanupCount: nativeState.pendingCleanupCount,
              errorMessageAr: disableRes.messageAr ??
                  'تعذر إتمام تنظيف التنبيهات السابقة عند الانتقال للمدينة القطبية.',
              technicalCode: disableRes.errorCode ?? 'POLAR_DISABLE_INCOMPLETE',
            ));
            completer.complete(false);
            return;
          }

          final reason = plan.unresolvedReasons.isNotEmpty
              ? plan.unresolvedReasons.first
              : 'تعذر حساب المواقيت الفلكية لتعذر غياب أو شروق الشمس (يوم قطبي).';
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.polarDayUnresolved,
            pendingCleanupCount: 0,
            generationToken: disableRes.token ?? nativeState.generationToken,
            unresolvedDaysCount: plan.unresolvedDaysCount,
            estimatedDaysCount: plan.estimatedDaysCount,
            isPartialCoverage: true,
            coverageExplanation: plan.coverageExplanation,
            clearAcceptedScheduledCount: true,
            plannedFutureEventsCount: 0,
            errorMessageAr: reason,
          ));
          completer.complete(false);
          return;
        }

        final planMap = plan.toNativeMap();
        planMap['expectedToken'] = currentToken;
        final plannedCount = plan.events.length;

        // 3. Invoke native replacePlan:
        final response = await _client.replacePlan(planMap);
        if (!_isInvocationValid(
          epoch: epoch,
          barrierGen: barrierGen,
          expectedFingerprint: snapshotFingerprint,
          expectedOptIn: snapshotOptIn,
          expectedVoices: snapshotVoices,
        )) {
          completer.complete(false);
          return;
        }

        // 4. Handle CAS rejection:
        if (response.isStaleToken) {
          _lastScheduledFingerprint = null;
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.partialFailure,
            technicalCode: 'STALE_AUTHORIZATION_TOKEN',
            clearAcceptedScheduledCount: true,
            errorMessageAr: response.messageAr ??
                'انتهت صلاحية رمز التفويض، يرجى إعادة محاولة جدولة المواعيد.',
          ));
          completer.complete(false);
          return;
        }

        // 5. Handle partial or complete failure:
        if (!response.success || response.partialFailure) {
          _lastScheduledFingerprint = null;
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.partialFailure,
            plannedFutureEventsCount: plannedCount,
            acceptedScheduledCount: response.scheduledCount,
            exactScheduledCount: response.exactScheduledCount ?? 0,
            companionScheduledCount: response.companionScheduledCount ?? 0,
            unresolvedDaysCount: plan.unresolvedDaysCount,
            estimatedDaysCount: plan.estimatedDaysCount,
            isPartialCoverage: plan.isPartialCoverage,
            coverageExplanation: plan.coverageExplanation,
            technicalCode: response.errorCode,
            errorMessageAr: response.messageAr ??
                'تم تحديث الخطة، ولكن تعذر اكتمال جدولة بعض التنبيهات في النظام.',
            generationToken: response.token ?? currentToken,
          ));
          completer.complete(false);
          return;
        }

        // 6. Complete success:
        final acceptedCount = response.scheduledCount;
        if (acceptedCount == null ||
            acceptedCount > plannedCount ||
            (response.exactScheduledCount ?? 0) > plannedCount ||
            (response.companionScheduledCount ?? 0) > plannedCount) {
          _lastScheduledFingerprint = null;
          _updateState(_state.copyWith(
            status: PrayerNotificationStatus.partialFailure,
            plannedFutureEventsCount: plannedCount,
            acceptedScheduledCount:
                acceptedCount != null && acceptedCount <= plannedCount
                    ? acceptedCount
                    : null,
            technicalCode: 'ACCEPTED_EXCEEDS_PLANNED',
            errorMessageAr:
                'استجابة غير متسقة في عدد المواعيد المجدولة من النظام.',
          ));
          completer.complete(false);
          return;
        }

        _lastScheduledFingerprint = _buildPlanFingerprint(effective, prefs);
        final status = response.exactAlarmsUsed
            ? PrayerNotificationStatus.activeExact
            : PrayerNotificationStatus.activeInexact;

        _updateState(_state.copyWith(
          status: status,
          plannedFutureEventsCount: plannedCount,
          acceptedScheduledCount: acceptedCount,
          exactScheduledCount: response.exactScheduledCount ?? 0,
          companionScheduledCount: response.companionScheduledCount ?? 0,
          pendingCleanupCount: 0,
          cityNameAr: effective.city.arabicName ?? effective.city.name,
          notificationsAllowed: true,
          canScheduleExactAlarms: response.exactAlarmsUsed,
          generationToken: response.token ?? currentToken,
          unresolvedDaysCount: plan.unresolvedDaysCount,
          estimatedDaysCount: plan.estimatedDaysCount,
          isPartialCoverage: plan.isPartialCoverage,
          coverageExplanation: plan.coverageExplanation,
          clearError: true,
          clearTechnicalCode: true,
        ));
        completer.complete(true);
      } catch (e) {
        _lastScheduledFingerprint = null;
        _updateState(_state.copyWith(
          status: PrayerNotificationStatus.partialFailure,
          clearAcceptedScheduledCount: true,
          errorMessageAr: 'حدث خطأ غير متوقع أثناء جدولة المواعيد.',
          technicalCode: 'REPLACE_PLAN_EXCEPTION',
        ));
        completer.complete(false);
      }
    }, onError: (Object err, StackTrace stack) {
      completer.complete(false);
    });

    return completer.future;
  }

  String _buildPlanFingerprint(
    EffectivePrayerSettings effective,
    UserPreferences prefs,
  ) {
    return '${effective.fingerprint}|${prefs.generalAdhanVoice}|${prefs.fajrAdhanVoice}';
  }
}

/// Provider delivering the clock for prayer notification coordinator testing and production.
final prayerNotificationClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provider delivering the singleton prayer notification coordinator.
final prayerNotificationCoordinatorProvider =
    ChangeNotifierProvider<PrayerNotificationCoordinator>((ref) {
  final client = ref.watch(nativePrayerChannelClientProvider);
  final clock = ref.watch(prayerNotificationClockProvider);
  return PrayerNotificationCoordinator(
    ref: ref,
    client: client,
    clock: clock,
  );
});

/// Exposes the immutable current state of prayer notifications.
final prayerNotificationStateProvider =
    Provider<PrayerNotificationState>((ref) {
  return ref.watch(prayerNotificationCoordinatorProvider).state;
});
