# Contract Shield Release Prep

## Release Positioning

Contract Shield is a bilingual real-estate helper for consumers in Ontario, Quebec, and British Columbia. It helps users estimate seller savings, review buyer closing costs, understand cancellation and rescission workflows, scan contracts for red flags, and generate supporting reports and notices.

## Branding Decision Locked

Primary app name for submission is `Contract Shield`.

FSBO may still appear in descriptive copy as a feature/use-case term, but not as the app name.

## Suggested Store Metadata

### Apple App Store

- App Name: `Contract Shield`
- Subtitle: `Buyer costs, contract scan, and legal help`
- Promotional Text: `Estimate buyer costs, review key contract risks, and generate real-estate reports for Ontario, Quebec, and British Columbia.`

### Google Play

- App Name: `Contract Shield`
- Short Description: `Canadian real-estate helper for buyer costs, contract scans, and legal notice prep.`

### Long Description

Contract Shield helps Canadian consumers handle critical real-estate tasks with more clarity and less guesswork.

The current release focuses on Ontario, Quebec, and British Columbia and supports both first-time and repeat buyers. Users can estimate buyer closing costs, review seller savings, scan contracts for risky language, generate reports, and access province-aware legal information for cancellation and rescission workflows.

Key features:

- buyer closing-cost estimates for ON, QC, and BC
- first-time buyer and repeat buyer support
- seller savings calculator with province-aware defaults
- contract scanner with OCR-powered red-flag detection
- legal-information workflows for cancellation and rescission
- PDF report and notice generation
- English and French support
- premium upgrade options for advanced workflows

Important note: Contract Shield is an informational tool and not a substitute for legal advice, brokerage advice, or tax advice.

## Keywords and Search Terms

Suggested English terms:

- real estate canada
- closing costs calculator
- first time home buyer canada
- fsbo canada
- contract scanner
- rescission notice
- buyer cost calculator

Suggested French terms:

- immobilier canada
- frais de cloture
- premier acheteur maison
- calculatrice immobilier
- analyse contrat

## Screenshot Plan

### Screenshot 1

- Focus: buyer closing-cost calculator
- Message: `Estimate costs before you make an offer`
- Show: province selector, first-time vs repeat buyer, total breakdown card

### Screenshot 2

- Focus: contract scanner
- Message: `Scan agreements for risky language`
- Show: scanner frame and red-flag findings

### Screenshot 3

- Focus: legal rights and notices
- Message: `Review cancellation and rescission guidance`
- Show: province-specific legal rights screen or notice workflow

### Screenshot 4

- Focus: premium reports and exports
- Message: `Save reports and export key records`
- Show: buyer report or history export view

### Screenshot 5

- Focus: bilingual support
- Message: `Use the app in English or French`
- Show: French UI screen with meaningful content rather than settings alone

## Privacy and Support URLs

The current paywall links point to:

- Privacy Policy: `https://bigdavion0824-dot.github.io/contract-shield/legal/privacy.html`
- Terms of Use: `https://bigdavion0824-dot.github.io/contract-shield/legal/terms.html`

Before submission, confirm:

- both pages are publicly reachable without errors
- the content matches the app's actual data collection and purchase flows
- the support email shown in-app is populated and monitored

## Submission Checklist

- Choose final in-app and store-facing brand name
- Populate support email in the app settings used for release QA
- Verify privacy policy and terms URLs are live and final
- Upload production App Store and Google Play purchase products
- Test purchase and restore flows with sandbox accounts
- Complete device QA on the release matrix
- Complete legal review of ON, QC, and BC guidance and templates
- Capture final screenshots in English and French
- Review all store descriptions for consistency with the actual feature set

## Remaining Blockers Outside Code

- legal signoff
- live billing validation
- device QA signoff
- final published store assets and support information

## Code Signing Steps (Required)

## Optional Production Telemetry (Recommended)

- Configure a secure HTTPS endpoint to receive JSON telemetry events/errors
- Build with dart define:
	- `flutter build appbundle --release --dart-define=TELEMETRY_ENDPOINT=https://your-endpoint.example.com/ingest`
	- `flutter build ios --release --no-codesign --dart-define=TELEMETRY_ENDPOINT=https://your-endpoint.example.com/ingest`
- Verify endpoint receives records with `type=event` and `type=error`
- Do not include secrets in the endpoint URL

### Android (Play Store)

- Copy `android/key.properties.example` to `android/key.properties`
- Fill `storePassword`, `keyPassword`, `keyAlias`, and `storeFile`
- Confirm `android/key.properties` is not committed
- Run `flutter build appbundle --release`
- Upload `build/app/outputs/bundle/release/app-release.aab` to Play Console

### iOS (App Store)

- Open `ios/Runner.xcworkspace` in Xcode
- Select the `Runner` target, then `Signing & Capabilities`
- Set your Apple Team and enable automatic signing (or assign a distribution profile)
- Ensure Bundle Identifier and provisioning profile match App Store Connect
- Build archive from Xcode: `Product > Archive`
- Upload to App Store Connect and validate in TestFlight

## Release Recommendation

Treat the current build as a strong beta or release candidate, not a fully public launch build, until the external blockers above are closed.