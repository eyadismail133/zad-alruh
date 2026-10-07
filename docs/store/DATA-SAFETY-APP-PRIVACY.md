# Data Safety & Apple App Privacy Decision Worksheet — Zad Alruh (زادُ الروح)

> **Document Status:** Conditional Decision Worksheet Pending Provider Evidence & Code Verification.
> *Last policy recheck date: 2026-10-07.*
> *Google Play User Data Policy Reference:* [Google Play Data Safety Help Center (answer/10787469)](https://support.google.com/googleplay/android-developer/answer/10787469)
> *Apple App Store Privacy Details Reference:* [App Privacy Details on App Store](https://developer.apple.com/app-store/app-privacy-details/)
> *MP3Quran Published Privacy Policy:* [سياسة الخصوصية لشبكة طريق الإسلام / MP3Quran](https://www.mp3quran.net/ar/privacy)

---

## 1. Executive Technical Architecture

| Architectural Area | Implemented Technical Reality |
|---|---|
| **User Accounts & Authentication** | **None.** No login, registration, account creation, or user identifiers. |
| **App Proprietary Backend** | **None.** No app server, no developer API, and no proprietary database backend. |
| **Advertising & Analytics SDKs** | **Zero advertising SDKs and zero analytics / crash telemetry SDKs.** *(Local functional libraries exist: `sqflite`, `just_audio`, `audio_session`, `adhan`, `timezone`, `flutter_riverpod`, `intl`, `xml`, `crypto`, `path`, `hijri`).* |
| **Local Device Persistence** | **100% On-Device SQLite (`zad_alruh.db`).** Reading bookmark, reading page, favorites, dhikr session history, daily tasks, and local settings are stored in private app storage. |
| **Network & Outbound Traffic** | `android.permission.INTERNET` declared in manifest with `android:usesCleartextTraffic="false"`. Network is planned exclusively for optional, user-initiated HTTPS Quran audio streaming (surahs 001..114, Mishary Alafasy) from `https://cdn.mp3quran.net`. *(Feature queued in development).* |
| **Location Services (GPS)** | **Zero location permissions.** Neither `ACCESS_FINE_LOCATION` nor `ACCESS_COARSE_LOCATION` is declared or requested. City selection uses an offline dataset. *(Note: Outbound IP address during media streaming can expose coarse network-derived location to the receiving CDN server).* |
| **Data Deletion Scope** | In-app "مسح كافة البيانات المحلية" (Reset) clears the local SQLite database and preferences on device. **It does NOT contact external CDNs or delete server access logs.** |

---

## 2. Documented MP3Quran Logging vs. CDN Unknowns

The primary published privacy policy of MP3Quran ([mp3quran.net/ar/privacy](https://www.mp3quran.net/ar/privacy)) provides the following verified facts:

1. **Documented Website Logging (Section: المعلومات المجمعة آلياً):**
   The published policy explicitly states that when interacting with its web services, the infrastructure automatically collects and logs:
   - Client IP Address (عنوان بروتوكول شبكة الإنترنت).
   - Date and Time of access (تاريخ ووقت الدخول).
   - Browser type and Operating System (نوع المتصفح ونظام التشغيل).
   - Country of origin (الدولة التي يتم الدخول منها).
   - Referring URL (عنوان موقع الويب المحيل).
2. **CDN Endpoint Applicability (Unconfirmed):**
   While website portal visits log the metadata above, the exact logging behavior, retention duration, and analytics processing applied to raw media CDN edge endpoints (`cdn.mp3quran.net`) are **not explicitly specified** in published documentation.
3. **No Assumed Ephemeral Processing:**
   Because logging is publicly acknowledged for MP3Quran services, the app developer **must not assume ephemeral processing** (in-memory discard) or claim provider confirmation without written technical documentation.
4. **Third-Party App SDK Distinction:**
   Any analytics or tracking SDKs that MP3Quran may deploy within its own standalone mobile applications belong strictly to their apps; **Zad Alruh bundles zero analytics or advertising SDKs**.
5. **Developer Content Rights (Section 66):**
   The terms state that users and developers are permitted to benefit from the materials, links, and audio on the site to disseminate Quranic content, with attribution. The terms do not state an explicit "non-commercial only" contractual restriction.

---

## 3. Google Play Data Safety Decision Framework

### 3.1 Policy Rule on Off-Device Data Transmission

Under Google Play's User Data policy ([Data collection and ephemeral processing](https://support.google.com/googleplay/android-developer/answer/10787469)):
- Any data sent off the user's device must be disclosed in the Data Safety form in Google Play Console.
- Ephemeral processing (data processed in memory and discarded) does not excuse the developer from completing the questionnaire; it is declared within the form fields.
- Consequently, if the release build includes user-initiated streaming to `cdn.mp3quran.net`, the resulting IP transmission must be evaluated for disclosure.

### 3.2 Evaluation of Data Categories

Google Play defines specific standard data categories. Developers must classify data based on **documented actual use**:

| Potential Play Category | Applicability to User-Initiated Audio Stream | Evaluation Criteria |
|---|---|---|
| **Device or other IDs** | May apply if IP address is retained or processed by the server as a network identifier. | Standard Google Play category for persistent device/network identifiers. |
| **Location (Approximate Location)** | May apply if the receiving CDN uses the client IP to determine and log the user's country or coarse city. | MP3Quran's stated policy logs "الدولة التي يتم الدخول منها" (Country). If the CDN performs coarse geo-lookup from IP, this may constitute coarse location processing. |
| **App Activity / Product Interaction** | May apply if streaming requests are aggregated by the provider to tally surah listen counts. | Subject to whether the provider aggregates request URLs per IP. |

*(Note: Google Play Data Safety does NOT have a category called "Network info" or "Network ID"; IP addresses are evaluated under "Device or other IDs" or "Location").*

### 3.3 Evaluation of "Data Sharing" vs. Policy Exceptions

In Google Play Console, whether transmitting an IP address to `cdn.mp3quran.net` is declared as **"Shared"** must be evaluated against Google's formal definitions:
- **General Rule:** Data transfer to an external third-party server is classified as sharing unless an explicit Google Play exception applies.
- **Potential Exceptions to Evaluate:**
  1. *Service Provider Exception:* Applies when the third party processes data solely on behalf of the developer under strict contractual terms. (Because the app has no direct service contract with MP3Quran, this exception may not apply).
  2. *Specific User-Initiated Disclosure:* Applies when the user explicitly triggers an interaction that inherently connects to a third-party service to deliver requested content.
- **Owner Action:** The owner must evaluate whether Google Play's User-Initiated interaction guidance applies or whether conservative disclosure ("Shared = Yes") is required, based on current Google Play Console guidance at submission time.

---

## 4. Specific Category Evaluation Matrix

| Data Category | Stored Locally in SQLite? | Transmitted Off-Device? | Status & Analysis |
|---|---|---|---|
| **Location (GPS / Precise)** | No | No | No location permissions declared (`ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`). GPS hardware is never accessed. |
| **Location (Coarse / IP-Derived)** | No | Subject to Provider Handling | Manually selected city stays strictly on-device in SQLite. However, when user streams audio, the receiving CDN receives the IP address (from which country/coarse location can be derived per MP3Quran's policy). Cannot claim blanket non-transmission during streaming. |
| **Personal Info (Name, Email, Phone)** | No | No | No user profiles, accounts, or forms. |
| **Financial / Payment Info** | No | No | Completely free, no billing libraries. |
| **Contacts & Calendar** | No | No | No permissions requested. |
| **Photos, Videos, Files** | No | No | Private app sandbox only. |
| **Diagnostics & Telemetry** | No | No | No Crashlytics, Firebase, or Sentry SDKs bundled in app. |
| **Device or other IDs (IP Address)** | No | Yes (Upon User Play) | Transmitted over HTTPS to `cdn.mp3quran.net` when user streams a surah. MP3Quran website policy acknowledges logging IP and country; CDN retention duration is unconfirmed. |

---

## 5. Apple App Store Privacy Details Framework

Under Apple's App Store Review Guidelines ([Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)):

1. **Non-Disclosure Exception Strictness:**
   Data collection is exempt from the on-store Privacy Nutrition Label **ONLY IF BOTH conditions are met**:
   - The data is not used for tracking or advertising.
   - The data is processed ephemerally and discarded immediately by the app **AND by third-party partners/service providers**.
2. **Impact of MP3Quran Stated Policy:**
   Because MP3Quran's published policy states that incoming requests log IP addresses and country data, the owner **cannot claim an automatic non-disclosure exception** without specific evidence that raw CDN audio endpoints discard connection logs immediately.
3. **Data Classification on Apple:**
   If disclosed, IP transmission during audio streaming may be declared under:
   - *Diagnostics* (if retained in web server access logs).
   - *Coarse Location* (if used for country-level routing/logging).
   - *Usage Data (Product Interaction)* (if used for surah stream metrics).
4. **No Premature Defaults:**
   The owner must not default to "Data Not Collected" or "Unlinked" without verifying provider handling.

---

## 6. Permissions & Security Rationale

### 6.1 `android.permission.INTERNET`
- **Current Declaration:** Declared in `AndroidManifest.xml` with `android:usesCleartextTraffic="false"`.
- **Enforcement:** Enforces TLS encryption for all outbound connections.
- **Scope:** Reserved strictly for user-initiated HTTPS Quran audio streaming from MP3Quran CDN. Core reading (604 pages, 3,213 hadiths, 267 Hisn items, offline prayer calculations) operates 100% offline.

### 6.2 Omitted Permissions
- **Location:** Omitted. Prayer times are calculated locally using city coordinates from GeoNames.
- **Storage:** Omitted. Persistent SQLite database resides in private app storage.

### 6.3 Local Reset Limitation Notice
- In-app "مسح كافة البيانات المحلية" resets on-device SQLite tables (`zad_alruh.db`) and stored preferences.
- **It is not an API call or deletion mechanism for external CDN server logs.**
