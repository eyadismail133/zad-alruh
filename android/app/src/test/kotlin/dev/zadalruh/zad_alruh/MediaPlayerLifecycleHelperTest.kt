package dev.zadalruh.zad_alruh

import android.content.Context
import dev.zadalruh.zad_alruh.adhan.AdhanPlaybackSession
import dev.zadalruh.zad_alruh.adhan.MediaPlayerAdapterFactory
import dev.zadalruh.zad_alruh.adhan.MediaPlayerLifecycleAdapter
import dev.zadalruh.zad_alruh.adhan.MediaPlayerLifecycleHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FakeMediaPlayerAdapter : MediaPlayerLifecycleAdapter {
    var isCurrentlyPlaying: Boolean = false
    var stopCount: Int = 0
    var resetCount: Int = 0
    var releaseCount: Int = 0
    var startCount: Int = 0
    var prepareCount: Int = 0

    var throwOnStop: Boolean = false
    var throwOnReset: Boolean = false
    var throwOnRelease: Boolean = false
    var throwOnStart: Boolean = false
    var throwOnPrepare: Boolean = false

    override fun isPlaying(): Boolean = isCurrentlyPlaying

    override fun start() {
        startCount++
        if (throwOnStart) throw RuntimeException("Simulated start error")
        isCurrentlyPlaying = true
    }

    override fun stop() {
        stopCount++
        if (throwOnStop) throw RuntimeException("Simulated stop error")
        isCurrentlyPlaying = false
    }

    override fun reset() {
        resetCount++
        if (throwOnReset) throw RuntimeException("Simulated reset error")
    }

    override fun release() {
        releaseCount++
        if (throwOnRelease) throw RuntimeException("Simulated release error")
    }

    override fun prepareFromAsset(
        context: Context?,
        assetPath: String,
        onCompletion: () -> Unit,
        onError: () -> Unit
    ) {
        prepareCount++
        if (throwOnPrepare) throw RuntimeException("Simulated prepare error")
    }
}

class FakeMediaPlayerAdapterFactory(
    private val supplier: () -> FakeMediaPlayerAdapter
) : MediaPlayerAdapterFactory {
    override fun createPlayer(context: Context?): MediaPlayerLifecycleAdapter {
        return supplier()
    }
}

class MediaPlayerLifecycleHelperTest {

    @Test
    fun testStopAndReleaseAttemptsAllOperationsIndependentlyWhenStopThrows() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.isCurrentlyPlaying = true
        adapter.throwOnStop = true

        val clean = MediaPlayerLifecycleHelper.stopAndRelease(adapter)

        // Must report false because stop threw
        assertFalse(clean)
        assertEquals(1, adapter.stopCount)
        // Invariant: reset and release were NOT skipped!
        assertEquals(1, adapter.resetCount)
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testStopAndReleaseAttemptsAllOperationsIndependentlyWhenResetThrows() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.isCurrentlyPlaying = true
        adapter.throwOnReset = true

        val clean = MediaPlayerLifecycleHelper.stopAndRelease(adapter)

        assertFalse(clean)
        assertEquals(1, adapter.stopCount)
        assertEquals(1, adapter.resetCount)
        // Invariant: release was NOT skipped!
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testStopAndReleaseAttemptsAllOperationsIndependentlyWhenReleaseThrows() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.isCurrentlyPlaying = true
        adapter.throwOnRelease = true

        val clean = MediaPlayerLifecycleHelper.stopAndRelease(adapter)

        assertFalse(clean)
        assertEquals(1, adapter.stopCount)
        assertEquals(1, adapter.resetCount)
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testStopAndReleaseCleanSuccessWhenNoExceptions() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.isCurrentlyPlaying = true

        val clean = MediaPlayerLifecycleHelper.stopAndRelease(adapter)

        assertTrue(clean)
        assertEquals(1, adapter.stopCount)
        assertEquals(1, adapter.resetCount)
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testStopNotCalledWhenPlayerNotPlaying() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.isCurrentlyPlaying = false

        val clean = MediaPlayerLifecycleHelper.stopAndRelease(adapter)

        assertTrue(clean)
        assertEquals(0, adapter.stopCount)
        assertEquals(1, adapter.resetCount)
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testResetAndReleaseAttemptsReleaseEvenWhenResetThrows() {
        val adapter = FakeMediaPlayerAdapter()
        adapter.throwOnReset = true

        val clean = MediaPlayerLifecycleHelper.resetAndRelease(adapter)

        // Must report false
        assertFalse(clean)
        assertEquals(1, adapter.resetCount)
        // Invariant: release was NOT skipped!
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testResetAndReleaseCleanSuccessWhenNoExceptions() {
        val adapter = FakeMediaPlayerAdapter()

        val clean = MediaPlayerLifecycleHelper.resetAndRelease(adapter)

        assertTrue(clean)
        assertEquals(1, adapter.resetCount)
        assertEquals(1, adapter.releaseCount)
    }

    @Test
    fun testPrepareFailureFollowedByReleaseFailureRetainsPlayerAndPropagatesUnconfirmedResult() {
        val fakePlayer = FakeMediaPlayerAdapter()
        fakePlayer.throwOnPrepare = true
        fakePlayer.throwOnRelease = true

        val factory = FakeMediaPlayerAdapterFactory { fakePlayer }
        val session = AdhanPlaybackSession(factory)

        // 1. Prepare fails, release cleanup fails
        val prepared = session.prepareMediaPlayer(
            context = null,
            assetPath = "assets/audio/fajr.mp3"
        )

        // Player could not be prepared, returns null
        assertNull(prepared)
        assertEquals(1, fakePlayer.prepareCount)
        assertEquals(1, fakePlayer.resetCount)
        assertEquals(1, fakePlayer.releaseCount)

        // INVARIANT: Failed player reference was NOT lost; retained in cleanup barrier!
        assertEquals(1, session.failedCleanupBarrierCount)
        assertFalse(session.hasActivePlayer)

        // 2. Attempt stop/cleanup while player still failing release: must report false (unconfirmed stop)
        val initialStop = session.stopAndReleasePlayer()
        assertFalse("Must NOT falsely confirm clean stop when barrier player release fails", initialStop)
        assertEquals(1, session.failedCleanupBarrierCount)

        // 3. Resolve release failure on underlying player
        fakePlayer.throwOnRelease = false

        // 4. Retry stop/cleanup: barrier player successfully releases and is removed from barrier
        val retryStop = session.stopAndReleasePlayer()
        assertTrue("Must confirm clean stop once barrier player release succeeds", retryStop)
        assertEquals(0, session.failedCleanupBarrierCount)
    }

    @Test
    fun testStartDeniedFollowedByReleaseFailureRetainsPlayerInBarrierAndPropagatesUnconfirmedResult() {
        val fakePlayer = FakeMediaPlayerAdapter()
        fakePlayer.throwOnRelease = true

        val factory = FakeMediaPlayerAdapterFactory { fakePlayer }
        val session = AdhanPlaybackSession(factory)

        // 1. Prepare succeeds
        val prepared = session.prepareMediaPlayer(
            context = null,
            assetPath = "assets/audio/fajr.mp3"
        )
        assertNotNull(prepared)
        val nonNullPrepared = requireNotNull(prepared)
        assertEquals(0, session.failedCleanupBarrierCount)

        // 2. Authorization denied before start: cleanup attempted on preparedPlayer, but release throws
        val cleanReset = MediaPlayerLifecycleHelper.resetAndRelease(nonNullPrepared)
        assertFalse(cleanReset)
        if (!cleanReset) {
            session.retainFailedPlayer(nonNullPrepared)
        }

        // INVARIANT: Retained in barrier, not lost!
        assertEquals(1, session.failedCleanupBarrierCount)

        // 3. Stop attempt reports false
        val stopResult = session.stopAndReleasePlayer()
        assertFalse(stopResult)
        assertEquals(1, session.failedCleanupBarrierCount)

        // 4. Resolve release failure
        fakePlayer.throwOnRelease = false
        val recoveredStop = session.stopAndReleasePlayer()
        assertTrue(recoveredStop)
        assertEquals(0, session.failedCleanupBarrierCount)
    }

    @Test
    fun testActivePlayerReleaseFailureRetainsPlayerInBarrierAndPropagatesUnconfirmedResult() {
        val fakePlayer = FakeMediaPlayerAdapter()
        fakePlayer.isCurrentlyPlaying = true
        fakePlayer.throwOnRelease = true

        val factory = FakeMediaPlayerAdapterFactory { fakePlayer }
        val session = AdhanPlaybackSession(factory)
        session.setActivePlayer(fakePlayer)

        val stopResult = session.stopAndReleasePlayer()
        assertFalse(stopResult)
        assertFalse(session.hasActivePlayer)
        assertEquals(1, session.failedCleanupBarrierCount)

        // Subsequent retry with resolved release clears barrier
        fakePlayer.throwOnRelease = false
        val retryResult = session.stopAndReleasePlayer()
        assertTrue(retryResult)
        assertFalse(session.hasActivePlayer)
        assertEquals(0, session.failedCleanupBarrierCount)
    }

    @Test
    fun testPrepareSuccessDoesNotAddToCleanupBarrier() {
        val fakePlayer = FakeMediaPlayerAdapter()
        val factory = FakeMediaPlayerAdapterFactory { fakePlayer }
        val session = AdhanPlaybackSession(factory)

        val prepared = session.prepareMediaPlayer(
            context = null,
            assetPath = "assets/audio/fajr.mp3"
        )

        assertNotNull(prepared)
        assertEquals(0, session.failedCleanupBarrierCount)
        assertEquals(1, fakePlayer.prepareCount)
    }
}
