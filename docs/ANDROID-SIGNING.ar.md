# توقيع نسخة أندرويد وتحميلها من GitHub

## ليه التوقيع مهم؟
أندرويد بيسمح بتحديث التطبيق فوق النسخة القديمة **بس لو الاتنين متوقعين بنفس المفتاح**.
لو مفيش مفتاح ثابت، كل نسخة CI هتتوقع بمفتاح مؤقت، والمستخدم هيضطر يمسح التطبيق (وبياناته) عشان ينزل الجديدة.

## مرة واحدة بس: اعمل المفتاح
محتاج Java (JDK 17) على جهازك:

```bash
keytool -genkey -v -keystore zad-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias zad
```
اكتب باسورد قوي واحفظه. **احتفظ بنسخة من `zad-release.jks` والباسورد في مكان آمن (Drive مشفر/مدير باسوردات).** لو ضاع، مفيش تحديثات للمستخدمين الحاليين.

## ضيفه في GitHub Secrets
في الريبو: **Settings → Secrets and variables → Actions → New repository secret**

| الاسم | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | ناتج `base64 -w0 zad-release.jks` (على ويندوز: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("zad-release.jks"))`) |
| `ANDROID_KEYSTORE_PASSWORD` | باسورد الـ keystore |
| `ANDROID_KEY_ALIAS` | `zad` |
| `ANDROID_KEY_PASSWORD` | باسورد المفتاح (غالبًا نفس الأول) |

## البناء على جهازك (اختياري)
انسخ `android/key.properties.example` إلى `android/key.properties` واملا القيم، وحط `zad-release.jks` جوه `android/`. الملفين متجاهلين في git.

```bash
flutter build apk --release --split-per-abi
```

## تحميل النسخة
- **كل push على main:** افتح تبويب **Actions** → آخر تشغيل لـ "Android APK" → قسم **Artifacts** تحت.
- **نسخة رسمية:** أي push على main بيحدّث Release برقم النسخة اللي في `pubspec.yaml` تلقائيًا. لنسخة جديدة غيّر الرقم (مثلاً `0.5.0+5`). وتقدر كمان تعمل tag:
  ```bash
  git tag v0.4.0 && git push origin v0.4.0
  ```
  هتلاقيها في **Releases** برابط ثابت تقدر تبعته لأي حد.

## ملحوظة عن النسخ القديمة
النسخة اللي اتوزعت قبل كده (`0.2.0+2-debug`) متوقعة بمفتاح debug على جهاز المطوّر القديم. أول نسخة بالمفتاح الجديد هتحتاج **إلغاء تثبيت القديمة مرة واحدة**، وبعد كده التحديثات هتنزل فوق بعض عادي.
