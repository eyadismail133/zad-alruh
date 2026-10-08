package dev.zadalruh.zad_alruh.adhan

import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import dev.zadalruh.zad_alruh.alarm.AdhanVoiceRegistry
import dev.zadalruh.zad_alruh.alarm.PrayerAlarmCoordinator
import dev.zadalruh.zad_alruh.notifications.PrayerNotificationHelper
import io.flutter.FlutterInjector

/**
 * Android Foreground Service for playing full adhan audio at scheduled exact prayer times.
 * Complies with Android 15+ foreground service mediaPlayback requirements:
 * - Calls startForeground before requesting audio focus.
 * - Displays silent visible status notification with Stop action.
 * - Rechecks authorization, status channel, and DND/silent immediately before physical play.
 * - Confirms immediate resource release on stop.
 * - START_NOT_STICKY to avoid unwanted restarts.
 */
class AdhanMediaPlaybackService : Service() {

    companion object {
        const val ACTION_START_ADHAN = "dev.zadalruh.zad_alruh.action.START_ADHAN"
        const val ACTION_STOP = "dev.zadalruh.zad_alruh.action.STOP"

        const val EXTRA_EVENT_KEY = "extra_event_key"
        const val EXTRA_GENERATION_TOKEN = "extra_generation_token"

        @Volatile
        private var activeServiceInstance: AdhanMediaPlaybackService? = null

        val isRunning: Boolean
            get() = activeServiceInstance != null

        @Volatile
        var currentEventKey: String? = null
            private set

        @Volatile
        var playerFactory: MediaPlayerAdapterFactory = DefaultMediaPlayerAdapterFactory()

        /**
         * Synchronously stops active playback, releases MediaPlayer and audio focus,
         * removes foreground notification, and calls stopSelf() on the active instance.
         * Guaranteed to execute without starting an unnecessary background service
         * or sleeping on the main thread.
         */
        @Synchronized
        fun stopActiveInstance(): Boolean {
            val instance = activeServiceInstance ?: return true
            return try {
                val stopped = instance.stopPlaybackAndFinish("stop_active_instance_requested")
                if (stopped) {
                    activeServiceInstance = null
                    currentEventKey = null
                    true
                } else {
                    false
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    val session = AdhanPlaybackSession(playerFactory)

    val failedCleanupBarrierCount: Int
        get() = session.failedCleanupBarrierCount

    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var noisyReceiverRegistered = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                stopPlaybackAndFinish("audio_becoming_noisy")
            }
        }
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Focus lost to manual Quran playback, call, or other media: stop immediately, no resume!
                stopPlaybackAndFinish("audio_focus_lost")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeServiceInstance = this
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        try {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            registerReceiver(noisyReceiver, filter)
            noisyReceiverRegistered = true
        } catch (_: Exception) {
            noisyReceiverRegistered = false
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP) {
            stopPlaybackAndFinish("action_stop")
            return START_NOT_STICKY
        }

        val eventKey = intent.getStringExtra(EXTRA_EVENT_KEY)
        val token = intent.getLongExtra(EXTRA_GENERATION_TOKEN, -1L)

        if (eventKey.isNullOrEmpty() || token < 0) {
            stopPlaybackAndFinish("invalid_intent_params")
            return START_NOT_STICKY
        }

        currentEventKey = eventKey

        val coordinator = PrayerAlarmCoordinator.instance
        val store = coordinator.store

        // Authorize strictly against current persisted store
        if (!store.isEnabled() || store.getGenerationToken() != token) {
            stopPlaybackAndFinish("stale_authorization")
            return START_NOT_STICKY
        }

        val plan = store.getActivePlan()
        val event = plan?.events?.firstOrNull { it.eventKey == eventKey }
        if (plan == null || event == null) {
            stopPlaybackAndFinish("event_not_in_plan")
            return START_NOT_STICKY
        }

        // Check manual playback lease: suppress before posting status notification or requesting audio focus
        if (coordinator.isManualPlaybackLeaseActive()) {
            coordinator.handleServicePrestartFailure(token, eventKey, "manual_playback_lease_active")
            stopPlaybackAndFinish("manual_playback_lease_active")
            return START_NOT_STICKY
        }

        // Android 15+: Post valid mediaPlayback foreground notification BEFORE requesting audio focus!
        val statusNotification = PrayerNotificationHelper.buildMediaPlaybackStatusNotification(
            context = this,
            cityNameAr = plan.cityNameAr,
            prayerKey = event.prayerKey
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    PrayerNotificationHelper.NOTIFICATION_ID_MEDIA_PLAYBACK,
                    statusNotification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(
                    PrayerNotificationHelper.NOTIFICATION_ID_MEDIA_PLAYBACK,
                    statusNotification
                )
            }
        } catch (_: Exception) {
            // ForegroundServiceStartNotAllowedException on Android 14+ if exact alarm exemption missing
            coordinator.handleServicePrestartFailure(token, eventKey, "start_foreground_failed")
            stopPlaybackAndFinish("start_foreground_exception")
            return START_NOT_STICKY
        }

        // Conservative Silent / DND / Status Channel Check: Suppress loud full adhan if device is silenced or channel disabled
        if (isSuppressedBySilentOrDnd() || PrayerNotificationHelper.isPlaybackStatusChannelBlocked(this)) {
            coordinator.handleServicePrestartFailure(token, eventKey, "suppressed_by_silent_dnd_or_status_channel")
            stopPlaybackAndFinish("suppressed_by_silent_dnd_or_status_channel")
            return START_NOT_STICKY
        }

        // Request Audio Focus
        val focusGranted = requestSystemAudioFocus()
        if (!focusGranted) {
            coordinator.handleServicePrestartFailure(token, eventKey, "audio_focus_denied")
            stopPlaybackAndFinish("audio_focus_denied")
            return START_NOT_STICKY
        }

        // Prepare MediaPlayer using verified FlutterLoader asset lookup
        val assetPath = AdhanVoiceRegistry.FULL_AUDIO_ASSET_PATHS[event.voiceId]
            ?: AdhanVoiceRegistry.FULL_AUDIO_ASSET_PATHS[AdhanVoiceRegistry.VOICE_ADAM]!!

        val preparedPlayer = prepareMediaPlayer(assetPath)
        if (preparedPlayer == null) {
            coordinator.handleServicePrestartFailure(token, eventKey, "media_player_prepare_failed")
            stopPlaybackAndFinish("media_player_prepare_failed")
            return START_NOT_STICKY
        }

        // Final authorization recheck and physical start under shared coordinator synchronization lock:
        val startResult = coordinator.authorizeAndStartPlayback(
            token = token,
            eventKey = eventKey,
            nowEpochMillis = System.currentTimeMillis(),
            isSuppressed = {
                isSuppressedBySilentOrDnd() || PrayerNotificationHelper.isPlaybackStatusChannelBlocked(this)
            },
            onPhysicalStart = {
                preparedPlayer.start()
                session.setActivePlayer(preparedPlayer)
                true
            }
        )

        if (!startResult.isFullyDurable) {
            if (startResult.isStarted) {
                // Audio physically started, but FULL_CONSUMED persistence failed in durable ledger.
                // Stop service immediately to preserve at-most-once.
                stopPlaybackAndFinish("full_consumed_persistence_failed")
            } else {
                // Denied or aborted before physical start.
                // Retain reference in session barrier so failed cleanup is never a lost reference!
                val cleaned = MediaPlayerLifecycleHelper.resetAndRelease(preparedPlayer)
                if (!cleaned) {
                    session.retainFailedPlayer(preparedPlayer)
                }
                stopPlaybackAndFinish("playback_authorization_denied_or_failed")
            }
            return START_NOT_STICKY
        }

        return START_NOT_STICKY
    }

    private fun isSuppressedBySilentOrDnd(): Boolean {
        return PrayerNotificationHelper.isDndOrSilentActive(this)
    }

    private fun requestSystemAudioFocus(): Boolean {
        val am = audioManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()

            audioFocusRequest = request
            am.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonSystemAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(audioFocusChangeListener)
        }
    }

    fun prepareMediaPlayer(assetPath: String): MediaPlayerLifecycleAdapter? {
        return session.prepareMediaPlayer(
            this,
            assetPath,
            onCompletion = { stopPlaybackAndFinish("completed_naturally") },
            onError = { stopPlaybackAndFinish("media_player_error") }
        )
    }

    /**
     * Attempts cleanup of active playback and all players in the cleanup barrier.
     * Guarantees release is called even if stop or reset throws.
     * Returns true only if all players are successfully released.
     */
    fun stopAndReleasePlayer(): Boolean {
        return session.stopAndReleasePlayer()
    }

    fun stopPlaybackAndFinish(reason: String): Boolean {
        var clean = true
        try {
            val playerClean = stopAndReleasePlayer()
            if (!playerClean) {
                clean = false
            }
        } finally {
            try {
                abandonSystemAudioFocus()
            } catch (_: Exception) {
                clean = false
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Exception) {
                clean = false
            }

            try {
                stopSelf()
            } catch (_: Exception) {
                clean = false
            }
        }
        return clean
    }

    override fun onDestroy() {
        if (noisyReceiverRegistered) {
            try {
                unregisterReceiver(noisyReceiver)
            } catch (_: Exception) {}
            noisyReceiverRegistered = false
        }
        val clean = stopPlaybackAndFinish("service_destroyed")
        if (clean && activeServiceInstance == this) {
            activeServiceInstance = null
        }
        currentEventKey = null
        super.onDestroy()
    }
}

/**
 * Narrow interface isolating the lifecycle operations of MediaPlayer.
 * Enables 100% JVM testing of lifecycle resilience without Android stub mock limitations.
 */
interface MediaPlayerLifecycleAdapter {
    fun isPlaying(): Boolean
    fun start()
    fun stop()
    fun reset()
    fun release()
    fun prepareFromAsset(
        context: Context?,
        assetPath: String,
        onCompletion: () -> Unit,
        onError: () -> Unit
    )
}

/**
 * Production adapter delegating to real android.media.MediaPlayer.
 */
class AndroidMediaPlayerAdapter(val realPlayer: MediaPlayer) : MediaPlayerLifecycleAdapter {
    override fun isPlaying(): Boolean = realPlayer.isPlaying
    override fun start() = realPlayer.start()
    override fun stop() = realPlayer.stop()
    override fun reset() = realPlayer.reset()
    override fun release() = realPlayer.release()

    override fun prepareFromAsset(
        context: Context?,
        assetPath: String,
        onCompletion: () -> Unit,
        onError: () -> Unit
    ) {
        if (context == null) throw IllegalArgumentException("Context required for AndroidMediaPlayerAdapter")
        var afd: AssetFileDescriptor? = null
        try {
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            val lookupKey = flutterLoader.getLookupKeyForAsset(assetPath)
            afd = context.assets.openFd(lookupKey)

            realPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            realPlayer.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            realPlayer.isLooping = false
            realPlayer.setOnCompletionListener { onCompletion() }
            realPlayer.setOnErrorListener { _, _, _ ->
                onError()
                true
            }
            realPlayer.prepare()
        } finally {
            try {
                afd?.close()
            } catch (_: Exception) {}
        }
    }
}

interface MediaPlayerAdapterFactory {
    fun createPlayer(context: Context?): MediaPlayerLifecycleAdapter
}

class DefaultMediaPlayerAdapterFactory : MediaPlayerAdapterFactory {
    override fun createPlayer(context: Context?): MediaPlayerLifecycleAdapter {
        return AndroidMediaPlayerAdapter(MediaPlayer())
    }
}

/**
 * Production playback session and cleanup barrier manager.
 * Tracks active playback adapter and all players whose cleanup has not yet succeeded.
 * Guarantees that any failed cleanup player is retained in the cleanup barrier,
 * propagating unconfirmed stop/cleanup results and preventing false success reports.
 */
class AdhanPlaybackSession(
    var playerFactory: MediaPlayerAdapterFactory = DefaultMediaPlayerAdapterFactory()
) {
    private var activePlayer: MediaPlayerLifecycleAdapter? = null
    private val failedCleanupBarrier = mutableListOf<MediaPlayerLifecycleAdapter>()

    val failedCleanupBarrierCount: Int
        get() = failedCleanupBarrier.size

    val hasActivePlayer: Boolean
        get() = activePlayer != null

    fun setActivePlayer(player: MediaPlayerLifecycleAdapter) {
        activePlayer = player
    }

    fun retainFailedPlayer(player: MediaPlayerLifecycleAdapter) {
        if (!failedCleanupBarrier.contains(player)) {
            failedCleanupBarrier.add(player)
        }
    }

    fun prepareMediaPlayer(
        context: Context?,
        assetPath: String,
        onCompletion: (() -> Unit)? = null,
        onError: (() -> Unit)? = null
    ): MediaPlayerLifecycleAdapter? {
        val adapter = playerFactory.createPlayer(context)
        return try {
            adapter.prepareFromAsset(
                context,
                assetPath,
                onCompletion = { onCompletion?.invoke() },
                onError = { onError?.invoke() }
            )
            adapter
        } catch (_: Exception) {
            val cleaned = MediaPlayerLifecycleHelper.resetAndRelease(adapter)
            if (!cleaned) {
                // Sol Finding: Retain failed cleanup player in production cleanup barrier!
                retainFailedPlayer(adapter)
            }
            null
        }
    }

    fun stopAndReleasePlayer(): Boolean {
        var allClean = true

        val current = activePlayer
        if (current != null) {
            activePlayer = null
            val clean = MediaPlayerLifecycleHelper.stopAndRelease(current)
            if (!clean) {
                allClean = false
                retainFailedPlayer(current)
            }
        }

        val iterator = failedCleanupBarrier.iterator()
        while (iterator.hasNext()) {
            val barrierPlayer = iterator.next()
            if (barrierPlayer === current) {
                continue
            }
            val clean = MediaPlayerLifecycleHelper.stopAndRelease(barrierPlayer)
            if (clean) {
                iterator.remove()
            } else {
                allClean = false
            }
        }

        return allClean && failedCleanupBarrier.isEmpty()
    }

    fun stopPlayback(reason: String): Boolean {
        return stopAndReleasePlayer()
    }
}

/**
 * Pure lifecycle helper executing independent stop, reset, and release operations.
 */
object MediaPlayerLifecycleHelper {
    /**
     * Attempts stop, reset, and release on the player in independent try-catch blocks.
     * Guarantees release is attempted even if stop or reset throws.
     * Returns true only if all attempted operations succeeded without exception.
     */
    fun stopAndRelease(player: MediaPlayerLifecycleAdapter): Boolean {
        var clean = true
        try {
            if (player.isPlaying()) {
                player.stop()
            }
        } catch (_: Exception) {
            clean = false
        }

        try {
            player.reset()
        } catch (_: Exception) {
            clean = false
        }

        try {
            player.release()
        } catch (_: Exception) {
            clean = false
        }

        return clean
    }

    /**
     * Attempts reset and release independently on a prepared or partially prepared player.
     * Guarantees release is attempted even if reset throws.
     * Returns true only if both reset and release succeeded without exception.
     */
    fun resetAndRelease(player: MediaPlayerLifecycleAdapter): Boolean {
        var clean = true
        try {
            player.reset()
        } catch (_: Exception) {
            clean = false
        }

        try {
            player.release()
        } catch (_: Exception) {
            clean = false
        }

        return clean
    }
}
