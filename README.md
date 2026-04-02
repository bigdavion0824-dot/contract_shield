# Contract Shield

Contract Shield is a bilingual Flutter app focused on consumer real-estate workflows for Ontario, Quebec, and British Columbia. The current build combines seller savings tools, buyer closing-cost estimates, cancellation and rescission guidance, contract scanning, PDF generation, signature capture, premium purchase flows, QA tooling, analytics debugging, and launch-readiness tracking.

## Current Scope

- Provinces: Ontario, Quebec, British Columbia
- Languages: English and French
- Buyer support: first-time and repeat buyers
- Monetization: one-time scan purchase and monthly Pro subscription
- Storage: local persistence with SharedPreferences
- Platforms in active scope: Android, iOS, macOS

## Main Capabilities

- Seller savings calculator with province-aware defaults
- Buyer cost calculator with first-time buyer rebate estimates
- Legal rights and cancellation guidance for ON, QC, and BC
- PDF generation for notices and reports
- Signature capture for legal notice workflows
- Contract scanner with OCR-powered red-flag detection
- Premium paywall with in-app purchase and restore support
- History, QA matrix, analytics debug, and launch-readiness dashboards

## Project Structure

- `lib/main.dart`: primary app implementation
- `APP_FEATURES.md`: feature inventory and product status
- `ADMOB_IAP_SETUP.md`: AdMob and in-app purchase configuration notes
- `RELEASE_PREP.md`: store copy, screenshot plan, and launch checklist

## Development

Install dependencies:

```bash
flutter pub get
```

Run the analyzer:

```bash
flutter analyze
```

Run on macOS:

```bash
flutter run -d macos
```

Run on a connected mobile device:

```bash
flutter run -d <device-id>
```

## Launch Status

The repository contains internal launch tooling, but the app is not fully launch-complete until the remaining operational gates are closed:

- final legal review of province-specific content
- live purchase and restore testing in store sandboxes
- real-device QA across the supported release matrix
- final privacy policy, terms, support contact, and store assets

Use the in-app Launch Readiness screen together with `RELEASE_PREP.md` to track those remaining steps.
