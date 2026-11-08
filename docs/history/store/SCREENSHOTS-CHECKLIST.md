# Genuine Screenshot & Visual Asset Checklist — Zad Alruh (زادُ الروح)

> **Document Status:** Reviewable Checklist for Physical Device / Emulator Visual Capture.
> *Last verified on 2026-10-07.*
> *Store Policy Reference: Google Play Graphic Assets Guidelines & Apple App Store Screenshot Specifications.*

---

## 1. Core Principles & Truth-in-Advertising Rules

To ensure strict compliance with Google Play Developer Program Policies ([Google Play Graphic Assets](https://support.google.com/googleplay/android-developer/answer/9866130)) and Apple App Store Review Guidelines (Guideline 2.3 — Accurate Metadata):

1. **Genuine Application Screens Only:**
   Every screenshot must be captured directly from the actual running application build (running on a real Android device or official emulator). **Zero synthetic mockups, generic stock templates, or Photoshop concept designs are permitted.**
2. **Real Bundled Corpus Displayed:**
   No screen may display "Lorem Ipsum", placeholder dummy text, or unverified draft verses.
   - Quran screens must display authentic pages from the **604 Medina Mushaf Hafs 1441 AH** corpus.
   - Hadith screens must display verified records from the **3,213 Sahih HadeethEnc v1.7.0** database.
   - Supplication screens must show real chapters from **Hisn al-Muslim (267 items plus 300 footnotes)**.
   - City screens must show authentic records from the **34,149 GeoNames** database (using current available cities, noting global picker is queued).
3. **Never Advertise Unimplemented Features:**
   Screenshots must reflect features actively implemented in the build. Since full-surah MP3Quran streaming and background notification alarms are actively queued in development, screenshots must not depict mock UI claiming completed background features until verified.
4. **Authentic RTL & Typography:**
   Screens must showcase the authentic Arabic right-to-left layout, IBM Plex Sans Arabic typography, and warm cream/forest green/gold visual design (`design/zad-alruh-light.html`). Page images must never be inverted or distorted.

---

## 2. Store Graphic Specifications

### 2.1 Google Play Store Requirements

| Asset Type | Dimension / Ratio | Format | Requirements & Best Practices |
|---|---|---|---|
| **App Icon** | 512 x 512 px (1:1) | 32-bit PNG | Supplied Zad Alruh logo; no transparent background, max 1024 KB. |
| **Feature Graphic** | 1024 x 500 px | JPEG or 24-bit PNG | High-quality visual banner, no promotional text like "Best App" or download badges. |
| **Phone Screenshots** | Min 2, Max 8 screenshots<br>Min dimension: 1080 x 1920 px (16:9) or 1080 x 2400 px (20:9) | JPEG or 24-bit PNG (no alpha) | Captured in portrait orientation; crisp Arabic text; status bar clean. |
| **7-Inch Tablet (Optional)** | 1200 x 1920 px or equivalent | JPEG or 24-bit PNG | Required only if targeting 7-inch tablet layout specifically. |
| **10-Inch Tablet (Optional)** | 1600 x 2560 px or equivalent | JPEG or 24-bit PNG | Required only if targeting 10-inch tablet layout specifically. |

---

### 2.2 Apple App Store Requirements (When Packaging for iOS)

| Device Category | Display Resolution | Status |
|---|---|---|
| **iPhone 6.7" Display** (iPhone 16 Pro Max / 15 Pro Max) | 1290 x 2796 px (Portrait) | **Mandatory** for modern iOS releases. |
| **iPhone 6.5" Display** (iPhone 11 Pro Max / XS Max) | 1242 x 2688 px (Portrait) | Required for older display coverage. |
| **iPad Pro 12.9" Display** (6th Generation) | 2048 x 2732 px (Portrait) | Required if universal iPad binary is supported. |

---

## 3. Recommended 8-Screenshot Sequence & Capture Checklist

The following 8 screenshots constitute the visual submission pack:

### Screenshot 1: Home Dashboard (الشاشة الرئيسية)
- **Objective:** Introduce the core daily companion experience.
- **Content to Display:**
  - Next prayer card showing active countdown to prayer and sunrise timing.
  - Daily progress cards: Quran daily goal (2 pages default), morning/evening dhikr, dua of the day.
  - Clean Islamic warm palette, authentic branding.
- **Verification Check:** [ ] Next prayer calculation is accurate; countdown timer is valid; no overflow on small screen heights.

---

### Screenshot 2: The Holy Quran Reader (المصحف الشريف)
- **Objective:** Demonstrate authentic 604-page Medina Mushaf reading.
- **Content to Display:**
  - Full authentic page view (e.g., Page 1 Al-Fatihah, Page 2 Al-Baqarah opening, or Page 3).
  - Crisp 1200px lossless WebP rendering with first-line comfort zoom.
  - Page header showing Surah name, Juz number, and page number in Arabic.
  - Reader controls: bookmark toggle and switch to Quran text view mode («نص القرآن»).
- **Verification Check:** [ ] Page boundary matches printed Hafs 1441 AH; pure white background; no text distortion or blurriness.

---

### Screenshot 3: Quran Index & Search (فهرس السور والبحث القرآني)
- **Objective:** Show ease of Quran navigation and offline search.
- **Content to Display:**
  - Surah list showing chapter number, revelation type (Makki/Madani), and ayah counts.
  - Search tab showing an active search query (e.g., "الرحمن") returning instant offline verse matches with highlighted snippets.
- **Verification Check:** [ ] Search results show verse references correctly; keyboard does not obscure results; RTL alignment intact.

---

### Screenshot 4: Hisn al-Muslim Supplications & Tasbeeh (أذكار حصن المسلم والتسبيح)
- **Objective:** Highlight the documented supplications and repetition badges.
- **Content to Display:**
  - An authentic chapter view (e.g., "أذكار الصباح والمساء" أو "دعاء الركوع").
  - Item card displaying the full Arabic supplication, repetition instruction badge (e.g. 3x for Item 76), and clear reference footnote.
  - Separate view of the dedicated personal tasbeeh counter.
- **Verification Check:** [ ] Repetition badge strictly adheres to the 17 verified items whitelist; scholarly footnotes are displayed; personal tasbeeh counter operates independently.

---

### Screenshot 5: Sahih Hadith Collection (صحيح الحديث النبوي)
- **Objective:** Showcase the 3,213 authentic hadiths from HadeethEnc.
- **Content to Display:**
  - Hadith detail card displaying title, authentic grade badge ("صحيح"), full Prophetic text, and takhrij reference.
  - Source attribution badge acknowledging HadeethEnc.com v1.7.0.
- **Verification Check:** [ ] Hadith grade displays "صحيح"; full text is formatted legibly; source link icon visible.

---

### Screenshot 6: Prayer Times & Manual City Selection (مواقيت الصلاة واختيار المدن)
- **Objective:** Showcase the offline calculation and privacy (no GPS).
- **Content to Display:**
  - Detailed prayer times table for the day: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha.
  - City selection sheet showing available cities without requesting GPS permissions.
  - Visual indication that city selection is 100% manual with zero location permissions required.
- **Verification Check:** [ ] Calculation method clearly displayed; all 5 prayer times and sunrise rendered; no location permission prompts.

---

### Screenshot 7: Adhan Audio & Settings (أصوات الأذان والإعدادات)
- **Objective:** Display audio preview and customization.
- **Content to Display:**
  - Adhan voice picker showing the three bundled licensed recordings:
    1. أذان عام (المصدر: Adam-synagda - رخصة CC0 1.0)
    2. أذان عام (المصدر: Atcovi - رخصة CC BY-SA 4.0، اسم الملف يشير إلى Aaqib Azeez دون إثبات مستقل لهوية المؤدي)
    3. أذان الفجر (المصدر: المركز الإسلامي في مالمو - رخصة CC BY 3.0)
  - Audio playback preview bar with stop button.
- **Verification Check:** [ ] Real audio preview functions; honest attribution of performer and uploader; stop button halts sound immediately.

---

### Screenshot 8: Transparency, Sources & Privacy (المصادر والخصوصية)
- **Objective:** Reassure users and reviewers of ethical, open, and private design.
- **Content to Display:**
  - "المصادر والتراخيص" (Sources & Licenses) screen.
  - Direct attribution cards for Tanzil, KFQC (quran-ws), HadeethEnc, IslamHouse, GeoNames, and Wikimedia Adhan sources.
  - Prominent notice of zero advertising, zero accounts, zero analytics, and local-only data retention.
- **Verification Check:** [ ] All source names, versions, and license types clearly readable; external links open system browser correctly.

---

## 4. Pre-Capture Environment Checklist

Before capturing store screenshots on the tester device or emulator:

- [ ] **Clean Status Bar:** Ensure system clock is set to an appropriate time (e.g., `12:00` or `7:00`), battery indicator is 100%, and Wi-Fi / cellular icons are clean.
- [ ] **No Notification Clutter:** Clear all notification icons from the notification shade.
- [ ] **No Debug Banner:** Confirm screenshots are captured from a `profile` or `release` build where the Flutter debug banner (`DEBUG`) is completely disabled.
- [ ] **Font & Display Scaling:** Capture at standard 100% system display scale and standard font scale to ensure layout symmetry.
- [ ] **True Theme Verification:** Capture the primary light theme (`design/zad-alruh-light.html` warm cream/forest green palette). If providing dark mode screenshots, verify that Quran page images are displayed on a clean white sheet without color inversion.
