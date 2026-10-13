# Reader and content refresh implementation plan

> For agentic workers: use subagent-driven-development with SOL 6.1 medium only. No commits, pushes, or model changes by implementers or reviewers.

**Goal:** Deliver a tested new Android APK and update the existing public download site with clear duas, ordered hadiths, an image-only Quran reader, and a refreshed Arabic font and reader design.

**Architecture:** Preserve canonical religious assets, stable IDs, SQLite history, bookmarks, and favorites. Add a deterministic invocation catalog over the existing Hisn source. Quran images remain canonical; verse metadata connects selection, navigation, bookmarks, and favorites without a text-reader mode.

**Tech stack:** Flutter, Riverpod, SQLite, local content assets, existing Node download site tooling.

**Approved design:** User approved the four-part design in chat on 2026-10-09, with a request to inspect actual dua content and acquire sourced additions if missing. Inspection found explicit invocations in Hisn entries 120, 121, 123 and others, including original footnote references. Existing corpus can satisfy the requested dua section without fabricated or duplicated religious content.

## Constraints and rulings

- User's current SOL 6.1 medium-only instruction overrides the standing Antigravity/Astra model workflow for this task. All delegated implementation and review use gpt-6.1-sol, medium.
- Work on existing feat/zad-alruh checkout; preserve pre-existing uncommitted iOS, README, hosting, and dist work. Do not reset or stage unrelated work.
- Do not remove source corpus data or change canonical SHA digests; remove Quran text presentation, retain metadata for lookup and existing saved references.
- Existing public deployment is authorized to receive the new APK after verification. Do not change host, access, signing identity, or publish to a store.
- Use Noto Naskh Arabic throughout rendered UI and non-Quran religious text; Quran page images remain visually unchanged. Embed licensed offline fonts.

## Task 1: Hisn invocation catalog and ordered hadith navigation

**Files:** Hisn catalog/model/repository/presentation, daily dua screen, progress confirmation validation, hadith repository/list/detail, their existing tests and source documentation.

- [ ] Add regression tests proving numeric hadith ordering (including IDs with different digit lengths), previous/next boundary behavior, dua filtering, and invalid legacy daily selection handling.
- [ ] Run focused tests before implementation and record the expected failures.
- [ ] Introduce an explicit sourced catalog of genuine supplications (including 120/121/123/124 and clearly identified source items); never infer eligibility from a substring at runtime. Keep situational context and references visible.
- [ ] Add separate duas browsing in Hisn, correct labels across item/chapter/detail views, and restrict daily selection and saved confirmations to this catalog. Preserve legacy history while offering replacement for an old non-dua choice.
- [ ] Sort hadiths numerically by their original source ID, preserve search/source/favorite identity, and add previous/next on details without accumulating a route for each step.
- [ ] Run focused tests and analyze; report changed files and evidence, no commit.

## Task 2: Image-only Quran and refreshed typography/design

**Files:** app theme, font assets/pubspec, Quran reader/index/navigation/dialogs, favorites routes, related layout/navigation tests.

- [ ] Add regressions proving all Quran entry points use page images, verse selection from a multi-surah page validates coordinates, existing favorites/bookmarks reopen the correct image page, and text mode controls disappear.
- [ ] Run focused tests before implementation and record expected failures.
- [ ] Remove text reader and Quran text snippets from visible Quran UI. Keep search as lookup to image pages with reference labels.
- [ ] Add page-scoped verse selection by surah and ayah for exact stop, bookmarks, and verse favorites. Use canonical KFQC page ranges; do not pretend image tap coordinates identify a verse.
- [ ] Keep page navigation, zoom, audio, reading confirmation, local saved progress and retry behavior working. Test first/last and multi-surah pages.
- [ ] Apply offline Noto Naskh Arabic in theme and remove explicit old font overrides. Use ivory/green/gold framing and soft lighting outside unchanged Mushaf images, in both themes, without obscuring page lines.
- [ ] Update actual-font smoke/layout tests and regenerate review screenshots. Run focused tests/analyze.

## Task 3: Independent review and delivery

- [ ] SOL 6.1 medium reviewer inspects actual diff, guards code/tests, independently runs relevant gates, reports APPROVED or CHANGES_REQUESTED. Resume implementer for actionable rework.
- [ ] Run full `flutter analyze`, `flutter test`, `dart run tool/validate_content.dart --development` from D:/tools/zad-alruh-workspace with D:/tools/flutter/bin on PATH.
- [ ] Increment version to 0.3.0+3. Refresh the existing ASCII build snapshot from source, preserving Android signing identity; build `flutter build apk --debug` using environment in docs/BUILD-ENVIRONMENT.md.
- [ ] Verify APK signature/version, packaged canonical images and font files, and SHA256. Document real-device limits accurately.
- [ ] Refresh download site name, SHA, version, screenshots, and size; run Node download tests, package/build, publish to same Sites project using hosting skill.
- [ ] Verify public page, download headers, and full streamed APK SHA match. Deliver new download URL and concise results.

## Execution ledger

- Investigation: Hisn contains explicit supplications and source references; daily dua currently permits every Hisn item. Hadith presentation uses original asset order. Quran text mode and text snippets are currently visible. Working tree contains unrelated pre-existing changes.
- Baseline analysis passed; development content integrity passed; six download-worker tests passed.
- User expanded scope during implementation: add a moderate set of genuinely additional sourced duas and adhkar (target about 24/16, quality and nonduplication determine final count), using source-aware supplemental HadeethEnc collection; add a direct hadith destination to bottom navigation; resume at the next page after explicit read confirmation, clamped to604 and without auto-confirming it. Keep canonical source corpus and attribution intact.
- Tasks 1 and 2 implemented and independently reviewed with SOL 6.1 medium. Added 16 supplications and 8 adhkar contexts, numeric hadith navigation, the bottom hadith destination, image-only Quran features, licensed Noto typography, and next-page persistence. Existing canonical corpora/digests preserved.
- Final review initially requested a stale resume-query fix. A deterministic real-SQLite regression failed before the fix; intent sequencing captured before the first await fixed it. Final reviewer returned APPROVED with clean analysis and 28 independently passing tests (92 earlier integration tests).
- Full app suite: 543 passed. Final affected integration suite after the race delta: 108 passed. Analyzer clean; development source integrity passed 47 checks; verified screenshot capture passed. Strict production religious review remains pending, and no physical device was connected.
- Final debug APK 0.3.0+3 built in the ASCII snapshot; 760 selected files matched source, 619 packaged original assets and 604 Mushaf pages passed checks. New Noto font/license bytes matched. Signature matches the previous APK. Size 281,612,842 bytes; SHA256 0816E22F80ADA6732CC3638D99753289B14CB50663D75DEC86181EB4EA6B8A1B. See ANDROID-0.3.0-VERIFICATION.md.
- Existing public Site source committed/pushed by the hosting helper at f5ba7537c01741f9bbed677afb04a5adbcca881b. Local build/package verified the exact APK. Archive ingestion failed twice with an Azure blob upload timeout at 300 seconds; retained the unchanged local archive and selected remote build fallback from that same verified source. Saved Site version 4 and deployment appgdep_6ac913fa5e108191b2dc84517719fe06 are in progress. No app repository commit/push was performed.
- Delivery completed: Site version 4 deployment succeeded at https://zad-alruh.whiterat16.chatgpt.site. Public page and HEAD returned 200; midpoint range returned 206 and exact bytes; full public download matched size 281,612,842 and SHA256 0816E22F80ADA6732CC3638D99753289B14CB50663D75DEC86181EB4EA6B8A1B. New APK download is zad-alruh-0.3.0+3-debug.apk; public page opened through Codex. All requested implementation, review, build, and publication work is complete; documented production/hardware prerequisites remain.
