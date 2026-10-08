# Quran Recitation Audio Sources & Licensing — MP3Quran.net

> **Document Status:** Reference documentation for implemented foreground Quran full-surah streaming in Zad Alruh.
> **Status:** Implemented pending independent verification gates and human listening signoff.
> **Date of documentation:** 2026-10-07.

---

## 1. Primary Source & Rights

- **Primary Provider:** MP3Quran ([mp3quran.net](https://www.mp3quran.net)). No external corporate or network affiliation is assumed.
- **Developer API:** [mp3quran.net/ar/api](https://www.mp3quran.net/ar/api)
- **Live Catalog Endpoint:** `https://www.mp3quran.net/api/v3/reciters?language=ar`
- **Permissions Section:** [mp3quran.net/ar/privacy](https://www.mp3quran.net/ar/privacy) (قسم حقوق الاستخدام).
  The published rights section permits all visitors and developers to use the materials, recordings, and direct links to share and disseminate Quranic content. The application chooses to attribute the source clearly in the UI and documentation as a matter of transparency and academic honesty, without assuming attribution to be a restrictive legal condition imposed by the provider.
- **Endorsement & Certification Disclaimer:** No official endorsement, sponsorship, or religious certification is claimed from the source or publisher.

---

## 2. Reciter & Moshaf Metadata

- **Reciter:** الشيخ مشاري بن راشد العفاسي (Mishary Al-Afasy)
  - `reciter_id`: `123`
- **Moshaf / Narration:** حفص عن عاصم - مرتل (Hafs 'an 'Asim - Murattal)
  - `moshaf_id`: `123`
  - `rewaya_id`: `1`
- **Surahs Available:** All 114 chapters (`1..114`), full surah recitations.
- **Server Base URL:** `https://cdn.mp3quran.net/audio/mishary-alafasy/r1/`
- **Filename Convention:** Verified exact 3-digit zero-padded numbers:
  - Surah 1 (الفاتحة): `001.mp3` (`https://cdn.mp3quran.net/audio/mishary-alafasy/r1/001.mp3`)
  - Surah 114 (الناس): `114.mp3` (`https://cdn.mp3quran.net/audio/mishary-alafasy/r1/114.mp3`)
  - Live HEAD inspection confirms HTTP 200 `audio/mpeg` with `Accept-Ranges: bytes`.

---

## 3. Privacy, Network & Logging Disclosures

1. **Explicit User-Initiated Streaming:**
   - Audio is never auto-played or pre-fetched. Playback occurs solely upon explicit user command ("استماع للسورة كاملة").
   - Offline functionality (all 604 mushaf pages, Uthmani text, Hadith, Hisn al-Muslim, adhan previews, and prayer times) remains 100% on-device and network-independent.
2. **Provider Server Logging vs CDN Retention:**
   - The published website privacy policy of MP3Quran confirms that its web servers automatically log standard HTTP request metadata: client IP address, date/time, browser/OS type, country of origin, and referrer.
   - Specific CDN edge applicability and edge server retention durations are **unconfirmed** in the provider's documentation; the application does not claim immediate deletion, ephemeral discard, or knowledge of exact edge server retention periods.
3. **App Privacy Architecture:**
   - Zad Alruh embeds zero third-party advertising, tracking, or analytics SDKs.
   - Outbound requests to `cdn.mp3quran.net` are transmitted securely over HTTPS (`usesCleartextTraffic="false"`).

---

## 4. Architecture, Manual Audio Start Guards & Native OS Stop Integration

1. **Typed OS Boundary (`NativePrayerAudioControl`):**
   - Located at `lib/src/features/prayer/domain/services/native_prayer_audio_control.dart`.
   - Production implementation `MethodChannelNativePrayerAudioControl` invokes `stopActivePlayback` over `MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm')`.
   - On Android, manual playback startup (`playAsset`, `playUrl`, `resume`) must await confirmed native stop response `{"stopped": true}` before OS session activation and physical SDK start.
   - Fail-closed: returns `false` on `null`, missing map, `{"stopped": false}`, `MissingPluginException`, or `PlatformException`, preventing manual audio playback while prayer alarms are active.
   - Non-Android platforms treat `stopActivePlayback()` as a legitimate no-op returning `true`.
   - Exposed as `nativePrayerAudioControlProvider` for reuse by future Dart background/notification coordinators.

2. **Manual Audio Reset Generation Guards:**
   - `JustAudioPlayerClient` integrates with `ProgressMutationBarrier` via injected `isResetBarrierActive` and `getResetGeneration` closures.
   - Provider `adhanAudioPlayerClientProvider` reads `progressRepositoryProvider` closures without watching, avoiding player destruction and recreation when reset fences toggle.
   - At invocation of `playAsset`, `playUrl`, or `resume`, the current reset generation (`initialResetGen`) is captured and active reset barriers reject immediately with user-facing Arabic errors.
   - Across every async suspension point (old player retirement, native stop, URL loading, session activation), generation change `_isResetCancelled` is rechecked.
   - Stale or queued starts are permanently discarded if generation advanced, even after the reset barrier fence drops.

3. **Reader Layout & Footer Confirmation Control Integration:**
   - `QuranPageConfirmationControl(pageNumber: _activePage)` is integrated directly into the normal-flow horizontally-scrolling footer row of `QuranReaderScreen` (`quran_reader_bottom_controls`).
   - Headroom, image viewport bounds, and positive Mushaf geometry are preserved with zero persistent secondary cards and zero overlay obstruction on Medina Mushaf pixels.
   - Reading, page scrolling, and navigation never auto-confirm reading progress; confirmation requires explicit user action.

4. **Bidirectional Exclusivity & Native Manual Playback Lease:**
   - **سياسة التشغيل الحصرية:**
     > "أثناء الاستماع داخل التطبيق يظهر تنبيه الصلاة دون تشغيل صوت ثانٍ؛ عند إيقاف الاستماع أو إيقافه مؤقتاً يعود الصوت للمواعيد القادمة، ولا يعاد أذان موعد مضى."
   - **Process-Local Mutual Exclusion Lease:**
     - Before physical manual audio playback begins (`playAsset`, `playUrl`, or `resume`), the client acquires `acquireManualPlaybackLease(requestId: ...)` under the Android coordinator's lock.
     - While held, native prayer alarms that trigger are durably marked as `MANUAL_SUPPRESSED` and post a single dedicated silent notification (`zad_alruh_prayer_manual_silent`), preventing dual playback. Releasing the lease does not replay past prayer audio.
     - **Confirmed Pause UX:** When manual playback is paused in the foreground, the manual playback lease is confirmed released and audio focus is surrendered so subsequent scheduled prayer times are not silenced indefinitely while paused. On resume, a fresh lease is re-acquired atomically.
     - **Platform Boundary:** Applies on Android via native coordinator channel `dev.zadalruh.zad_alruh/prayer_alarm`. Non-Android platforms treat lease operations as honest no-ops. Zero claim or assumption of iOS full background audio execution is made.
