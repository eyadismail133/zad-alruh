# Store Submission Pack & Release Roadmap — Zad Alruh (زادُ الروح)

> **Document Status:** Draft Submission Roadmap — Gated on Technical Implementation & Owner Prerequisites.
> *Last policy recheck date: 2026-10-07.*
> **Strict Reality Check:** The project owner currently has **no Google Play or Apple developer accounts**, no production keystores, no public privacy hosting, and no qualified religious signoff. No build is currently approved or submitted.

---

## 1. Store Pack Index

This submission pack organizes all required artifacts for store submission:

| Document | Purpose & Scope |
|---|---|
| [`docs/store/PLAY-STORE-LISTING.ar.md`](PLAY-STORE-LISTING.ar.md) | Official Arabic Play Store metadata: Title (<=30 chars), Short Description (<=80 chars), Full Description, Categorization, Tags, Reviewer Notes, and IARC Content Rating. |
| [`docs/store/DATA-SAFETY-APP-PRIVACY.md`](DATA-SAFETY-APP-PRIVACY.md) | Google Play Data Safety questionnaire worksheet and Apple App Store Privacy Nutrition Labels decision matrix, with complete permission and CDN transit IP rationales. |
| [`docs/store/SCREENSHOTS-CHECKLIST.md`](SCREENSHOTS-CHECKLIST.md) | Genuine physical device/emulator screenshot capture specifications (8-screen sequence) strictly prohibiting mockups and incomplete corpus advertising. |
| [`docs/store/OWNER-HANDOFF.md`](OWNER-HANDOFF.md) | Actionable handoff blueprint outlining developer account creation, upload keystore generation, public endpoint hosting, and religious review prerequisites. |
| [`docs/store/PRIVACY-DRAFT.ar.md`](PRIVACY-DRAFT.ar.md) | Complete Arabic privacy policy text disclosing offline corpus, on-device SQLite storage, absence of GPS permissions, and optional MP3Quran HTTPS audio streaming. |
| [`docs/ANDROID-ACCEPTANCE.ar.md`](../ANDROID-ACCEPTANCE.ar.md) | Comprehensive manual real-device acceptance testing matrix with 100% unchecked initial status for testing on physical Android hardware. |

---

## 2. Accurate Content Corpus Specifications

Every store claim and listing description must strictly reflect the verified offline corpus:

1. **The Holy Quran Mushaf:**
   - 604 high-resolution page images derived from the King Fahd Glorious Quran Printing Complex (KFQC) Medina Mushaf (Hafs an Asim 1441 AH print edition) via the open `quran-ws/quran-svg` CC BY 4.0 conversion.
   - Pinned lossless WebP assets (1200px width, 91.5 MB total).
   - Tanzil Uthmani v1.1 canonical text (6,236 verses across 114 Surahs) with runtime mapping of all 25 differing page boundary breaks.
   - *Factual Limitation:* Automated conversion without geometric differential tests. Comprehensive visual/religious signoff by a qualified human scholar remains a mandatory pre-release gate. **No claim of official KFQC publisher endorsement is made.**
2. **Prophetic Hadith Corpus:**
   - Exactly **3,213 authentic ("صحيح") records** from the official Arabic HadeethEnc (موسوعة الأحاديث النبوية) export `v1.7.0` (acquired 2026-09-28).
   - Includes authentic grade, full text, takhrij, and direct verification links.
   - *(Corrected from earlier draft mentions of 100 hadiths).*
3. **Hisn al-Muslim (Dhikr & Duas):**
   - Exactly **267 supplication items arranged across 132 chapters plus 300 referenced footnotes**, sourced from the official IslamHouse edition by Dr. Saeed bin Ali bin Wahf Al-Qahtani.
   - Verified single-entry repetition instruction badges for 17 whitelist items only.
4. **Global Cities & Prayer Calculations:**
   - Exactly **34,149 populated places and capitals** from the official GeoNames snapshot (`cities15000.txt`, CC BY 4.0).
   - Fully offline calculation engine (Adhan library with 3 documented patches).
   - **Zero GPS location permissions.** City selection is 100% manual.
   - *Current Implementation Note:* The current settings UI supports 8 legacy cities; the global 34,149 city picker is actively queued in development.
5. **Adhan Audio Recordings:**
   - Three free-licensed adhan recordings:
     1. Adam-synagda (CC0 1.0 Universal) — General adhan.
     2. Atcovi (CC BY-SA 4.0) — General adhan (source filename mentions Aaqib Azeez without independent performer verification).
     3. Islamic Center Malmö (CC BY 3.0) — Fajr adhan from Eid al-Fitr 2012.
   - Three 27-second PCM WAV alert clips for notification sounds.
   - Audio playback preview implemented; background scheduled alarms remain queued in development.

---

## 3. Active Implementation Queue Status (Oct 7, 2026)

To prevent misrepresenting development status to reviewers or users:

- **Quran Full-Surah Audio Streaming (MP3Quran):**
  - *Status:* **Actively queued in Codex implementation lane (NOT yet implemented in code).**
  - *Scope:* User-initiated streaming of 114 surahs recited by Sheikh Mishary Alafasy via HTTPS from `cdn.mp3quran.net`.
  - *Store Implication:* Store listing descriptions referencing this feature represent proposed copy that requires final code verification and passing test suites before publishing.
- **Global City Picker (34,149 Cities):**
  - *Status:* **Actively queued in development.** (Current UI displays 8 legacy settings cities).
- **Scheduled Background Prayer Notifications & Exact Alarms:**
  - *Status:* **Actively queued / blocked on platform verification.**
  - *Store Implication:* Do not advertise scheduled full adhan background alarms or iOS recurring notification schedules until native alarm cancellation, Doze mode recovery, and device reboot handlers pass verification.
- **Platform Builds & Measurement:**
  - Android: Current new debug APK has not been built; older September 29 debug APK transferred via MTP to Samsung A54 was not verified. Final release AAB compressed download size is unmeasured and pending.
  - iOS: Host machine is Windows; no macOS hardware, Xcode, or iPhone is available. iOS IPA generation is completely pending.

---

## 4. Official Store Policy Baseline (Rechecked 2026-10-07)

Prior to submission, verify compliance with the following authoritative developer policies:

1. **Google Play Target API 36 Mandate:**
   Mandatory since **August 31, 2026** for all new apps and updates.
   Official Policy: [Target API Level Requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
2. **Google Play 12-Tester Requirement for Personal Accounts:**
   Requires at least 12 opted-in testers for at least 14 continuous days in closed testing before production access can be requested.
   Official Policy: [Closed Testing Requirements](https://support.google.com/googleplay/android-developer/answer/14151465)
3. **Google Play App Bundle Download Limits:**
   500 MB maximum base module download size limit; 200 MB download size warning threshold. *(Actual release AAB download size is unmeasured and pending measurement).*
   Official Policy: [App Size Guidelines](https://support.google.com/googleplay/android-developer/answer/9859372)
4. **Android 16 KB Page-Size Compatibility:**
   Required for apps with native C/C++ libraries and Android 15/16 environments.
   Official Policy: [Support 16 KB Page Sizes](https://developer.android.com/guide/practices/page-sizes)
5. **Apple iOS SDK 26 Submission Requirement:**
   Mandatory since **April 28, 2026** (apps must be built with iOS 26 SDK). *(Note: SDK 27 will be required in April 2027, not currently).*
   Official Policy: [Apple SDK Submission Requirements](https://developer.apple.com/news/?id=ueeok6yw)

---

## 5. Reviewer Notes for Google Play Console

*(To be copied into Google Play Console App Access section upon final verification):*

```text
1. User Access & Authentication:
This application does not require any user account, registration, login, or credentials. All core features (Holy Quran reader, Hisn al-Muslim supplications, 3,213 Sahih hadiths, offline prayer time calculations, and bundled adhan previews) are immediately and fully functional upon clean launch without network access.

2. Location Privacy:
The application does not request or use Android location permissions (ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION). All prayer times are calculated mathematically without GPS access.

3. Network Usage:
The INTERNET permission declared in AndroidManifest is reserved strictly for optional, user-initiated HTTPS audio streaming of full Quran surahs (Mishary Alafasy) from MP3Quran CDN servers when the user taps play on a surah. All Quran text, page images, hadith, supplications, and adhan preview files are bundled locally. No telemetry, analytics, or background tracking requests exist.
```

---

## 6. Pre-Submission Verification Summary

Do NOT submit or claim submission readiness until all gates pass:
- [ ] Codex implementation queue finishes full-surah MP3Quran audio streaming, global city picker, and scheduled notification mechanics.
- [ ] Automated tests pass (`flutter analyze`, `flutter test`).
- [ ] Fresh release AAB built with valid owner signing credentials from `android/key.properties` and measured for download size.
- [ ] Real-device manual acceptance matrix completed on physical Android phones (`docs/ANDROID-ACCEPTANCE.ar.md`).
- [ ] Qualified human religious review signoff recorded for Quran, Hadith, Hisn, and Adhan audio.
- [ ] Public HTTPS privacy policy hosted at an owner-controlled URL.
- [ ] 12 testers complete 14 continuous days of closed testing on Google Play Console.
