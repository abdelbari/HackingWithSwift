# Submitting Canvia to the App Store

Everything App Store Connect asks for, in one place. The text lives in `metadata/`, in the layout [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) reads, so it can be uploaded with `fastlane deliver` or pasted field by field.

## Ready in the repo

| Item | Where |
| --- | --- |
| App icon, 1024×1024, no transparency | `Canvia/Assets.xcassets/AppIcon.appiconset` |
| Privacy manifest (required for every upload) | `Canvia/PrivacyInfo.xcprivacy` |
| Permission prompts (camera, microphone, speech, photos add-only) | build settings, `INFOPLIST_KEY_*` |
| Export compliance (no non-exempt encryption) | `ITSAppUsesNonExemptEncryption = NO` |
| Version 1.0, bundle ID `com.canvia.app` | project build settings |
| Name, subtitle, description, keywords, promo text, release notes in 8 languages | `metadata/<locale>/` |
| Screenshots, 6.9" iPhone and 13" iPad | `screenshots/<locale>/iphone-6.9/`, `screenshots/<locale>/ipad-13/` |
| Privacy policy, support page | `PRIVACY.md`, `SUPPORT.md` |
| Notes for App Review | `metadata/review_information/notes.txt` |
| Upload to TestFlight from CI | `.github/workflows/canvia-testflight.yml` |

## Before you submit

1. **Fix the launch crash** seen on a real iPhone, and confirm the fix on a device through TestFlight.
2. **Put your support email in `SUPPORT.md`** in place of `SUPPORT_EMAIL`.
3. **Merge this branch into `master`**, so the privacy and support URLs in `metadata/*/privacy_url.txt` and `support_url.txt` resolve. They point at `master`, and App Review opens them.
4. **Check the name is free.** Create the app record in App Store Connect with the name in `metadata/en-US/name.txt`; App Store names must be unique.
5. **Set the copyright holder.** `metadata/copyright.txt` says "2026 Abdelbari"; change it if it should be your full legal name or a company.

## App Store Connect answers

**App information**
- Primary category: Graphics & Design. Secondary: Productivity.
- Content rights: Yes, it contains third-party content. The bundled fonts are under the SIL Open Font License or Apache License, both of which allow this use.
- Age rating: answer **None / No** to every question. There is no violence, mature content, gambling, unrestricted web access, user-to-user messaging or user-generated content shared with others. That gives **4+**.

**App privacy** (the "nutrition label")
- Do you or your third-party partners collect data from this app? **No.** The label then reads "Data Not Collected".
- This matches the privacy manifest: no tracking, no collected data types, no third-party SDKs. Speech recognition falls back to Apple's servers on devices that can't do it on device. Apple's guidance treats that as Apple's processing, not data collected by the app. Re-read Apple's current guidance before answering if you're unsure.

**Pricing and availability**
- Free, all territories, unless you want otherwise.

**Version information**
- Copy each field from `metadata/<locale>/`. App Store Connect locales: English (U.S.), Spanish (Spain), French, German, Portuguese (Brazil), Italian, Japanese, Arabic.
- Support URL and privacy policy URL: from `support_url.txt` and `privacy_url.txt`.
- Screenshots: drag `screenshots/en-US/iphone-6.9/*.jpg` into the 6.9" iPhone slot and `screenshots/en-US/ipad-13/*.jpg` into the 13" iPad slot. App Store Connect scales them down for the smaller sizes. Other languages fall back to English.
- App Review information: no sign-in required; paste `review_information/notes.txt` into Notes.

**Build**
- Upload with the TestFlight workflow (Actions → Canvia TestFlight → Run, or push a `v*` tag), or archive in Xcode and use Organizer → Distribute App.
- Export compliance: answered automatically by `ITSAppUsesNonExemptEncryption = NO`.

## Making new screenshots

Edit `screenshots/shots.json`, then push it. The **Canvia App Store screenshots** workflow runs on that push:
- **Preview:** with `"mode": "preview"`, it commits small images of every shot and candidate to `screenshots/preview/`, to choose from.
- **Final:** with `"mode": "final"`, it commits the framed, full-size screenshots.

Captions for another language: add a key such as `"de-DE"` to each shot's `caption`, then run it again with that locale.

## Review risk to weigh

The name "Canvia" and an icon with a white letter C on a cyan-to-purple gradient are both close to Canva's. App Review can reject an app under guideline 4.1 (copycats) or 5.2 (intellectual property) when its name or icon could be confused with a well-known app. A more distinct name and icon lower that risk. The description and keywords never mention Canva.
