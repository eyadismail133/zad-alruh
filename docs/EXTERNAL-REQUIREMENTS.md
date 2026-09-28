# External requirements and release blockers

Owner confirmed on 2026-09-27: no licensed adhan recordings, and no Google Play/Apple developer accounts. No Mac is available.

Implementation of local code can continue. Actual publication and some content/device acceptance gates cannot complete with the current resources.

1. **Mushaf Page Images:** 604 high-resolution Medina Mushaf page images (Hafs 1441 AH) have been bundled from King Fahd Glorious Quran Printing Complex (KFQC) digital artwork via the open `quran-ws/quran-svg` CC BY 4.0 conversion. The earlier Quran Foundation developer account prerequisite was superseded by this source substitution. However, upstream structural checks were conducted without independent geometric diffs, so comprehensive visual and religious verification by a qualified human scholar across all 604 pages remains a pending release prerequisite. No claim of official KFQC publisher validation is made for this third-party digital conversion.
2. **Adhan Audio Recordings:** Three adhan recordings, including Fajr form, need explicit permission and licensing for bundling and short notification excerpts (<30s). Do not download unlicensed audio or impersonate a reciter.
3. **Religious Corpus Review:** Hisn al-Muslim digital edition and HadeethEnc Arabic rights are documented for the exact acquired editions. A qualified religious reviewer must inspect and approve the final corpus hashes.
4. **Hardware & Platform Gates:** A macOS host with supported Xcode and a real iPhone are required for iOS build/signing and device tests. Physical Android devices are also required for actual alarm/battery/call validation.
5. **Developer & Store Accounts:** Google Play and Apple owner accounts, identity verification, final application identifiers, signing credentials, public HTTPS privacy/support URLs, and a real support contact are required before submission.
6. **Testing Compliance:** New personal Google Play accounts may require at least 12 continuously opted-in testers for 14 days, followed by production-access approval.

No paid service/account purchase, automated account creation or publication is authorized merely by completing code. Codex should prepare reviewable artifacts, report these blockers accurately, and leave final launch owner-controlled.
