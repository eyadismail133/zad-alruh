# Copilot instructions

Follow `AGENTS.md` at the repo root — it is the single source of truth for architecture,
design tokens, content rules, signing and the definition of done. The roadmap is `docs/PLAN.ar.md`.

Key reminders:
- Arabic RTL Flutter app; Android APK (sideload) is the only release target right now.
- Change colors via `lib/src/core/theme/app_colors.dart` values, never new inline `Color(0x…)`.
- Never edit Quran/Hadith/Hisn text or Mushaf images by hand; content is hash-validated.
- Keep test keys stable; run `flutter analyze` and `flutter test`.
