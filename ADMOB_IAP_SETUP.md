# Google AdMob & In-App Purchase Setup Guide

## 📱 Current Status

✅ **Code Integration Complete**
- Google AdMob package installed and integrated
- In-App Purchase package installed and integrated
- Test ad unit IDs already configured
- Purchase flow implementation complete

❌ **Platform Configuration Needed** (Android & iOS only)
- The packages require native platform setup

---

## 🚨 Why Web Shows Errors

The plugins (Google AdMob & In-App Purchase) **only work on Android/iOS**. They don't have implementations for the web platform, which is why you see these errors when running on Chrome:

```
MissingPluginException(No implementation found for method _init on channel ...)
PlatformException(channel-error, Unable to establish connection ...)
```

**This is expected and normal!** To test locally, use an Android emulator or iOS simulator instead.

---

## 📋 Setup Instructions

### Phase 1: Test with Test Ad IDs (Already Done ✅)

The app already uses Google's test ad unit IDs:
- **Banner Ads**: `ca-app-pub-3940256099942544/6300978111`
- **Interstitial Ads**: `ca-app-pub-3940256099942544/1033173712`
- **Rewarded Ads**: `ca-app-pub-3940256099942544/5224354917`

These are free to use for testing.

---

### Phase 2: Android Setup (Google Mobile Ads)

#### Step 1: Update `android/app/build.gradle`

```gradle
android {
    compileSdkVersion 34

    defaultConfig {
        applicationId "com.contractshield.fsbo"
        minSdkVersion 19
        targetSdkVersion 34
        versionCode 1
        versionName "1.0.0"
        
        // Add manifest placeholders for Google Ad Mob App ID
        manifestPlaceholders = [ADMOB_APP_ID: "ca-app-pub-xxxxxxxxxxxxxxxx~zzzzzzzzzz"]
    }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}

dependencies {
    implementation platform('com.google.firebase:firebase-bom:32.2.0')
    implementation 'com.google.firebase:firebase-analytics-ktx'
    implementation 'com.google.android.gms:play-services-ads:22.6.0'
}
```

#### Step 2: Update `android/app/src/main/AndroidManifest.xml`

Add this inside the `<application>` tag:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-xxxxxxxxxxxxxxxx~zzzzzzzzzz"/>
```

Replace `xxxxxxxxxxxxxxxx~zzzzzzzzzz` with your actual **Google AdMob App ID** (get from AdMob console).

---

### Phase 3: iOS Setup (Google Mobile Ads)

#### Step 1: Update `ios/Podfile`

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
      ]
    end
  end
end
```

#### Step 2: Update `ios/Runner/Info.plist`

Add your Google AdMob App ID:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-xxxxxxxxxxxxxxxx~zzzzzzzzzz</string>
```

---

### Phase 4: In-App Purchase Setup (Android)

#### Step 1: Set Up Google Play Billing Library

The `in_app_purchase_android` package requires:

1. **Update `android/app/build.gradle`**:

```gradle
dependencies {
    implementation 'com.android.billingclient:billing:6.0.1'
}
```

2. **Create Products in Google Play Console**:
   - Go to: https://console.cloud.google.com
   - Navigate to your app → Monetize → Products
   - Create an in-app product:
     - **Product ID**: `com.contractshield.upgrade_premium`
     - **Product Type**: One-time purchase
     - **Price**: $4.99 (or your choice)
     - **Title**: "FSBO Premium Upgrade"
     - **Description**: "Unlimited saved calculations and ad-free experience"

3. **Update Product ID in `lib/main.dart`**:

```dart
class InAppPurchaseHelper {
  static const String oneTimeUpgradeId = 'com.contractshield.upgrade_premium'; // ✅ Already set
}
```

---

### Phase 5: In-App Purchase Setup (iOS)

#### Step 1: Configure App Store Connect

1. Go to: https://appstoreconnect.apple.com
2. Select your app → In-App Purchases
3. Create a non-renewing subscription or consumable:
   - **Product ID**: `com.contractshield.upgrade_premium`
   - **Reference Name**: "FSBO Premium Upgrade"
   - **Pricing Tier**: Choose your price tier
   - **Cleared for Sale**: ✅ Yes

#### Step 2: Update App Bundle ID

Ensure your bundle ID matches across:
- `ios/Runner.xcodeproj`
- `ios/Runner/Info.plist`
- App Store Connect settings

---

### Phase 6: Get Your Ad Unit IDs

1. **Create/Log into AdMob**: https://admob.google.com
2. **Add your app** if not already there
3. **Copy your App ID** (format: `ca-app-pub-xxxxxxxxxxxxxxxx~zzzzzzzzzz`)
4. **Create Ad Units**:
   - Go to Apps → Your App → Ad Units
   - Create Banner, Interstitial, Rewarded ad units

5. **Update `lib/main.dart` with your real IDs**:

```dart
class AdMobHelper {
  static const String bannerAdUnitId = 'ca-app-pub-YOUR_REAL_ID'; // Replace
  static const String interstitialAdUnitId = 'ca-app-pub-YOUR_REAL_ID'; // Replace
  static const String rewardedAdUnitId = 'ca-app-pub-YOUR_REAL_ID'; // Replace
}
```

---

## 🧪 Testing Locally

### Test with Android Emulator

```bash
flutter run -d emulator-5554
```

The app will:
- ✅ Show test ads (from Google's test IDs)
- ✅ Allow you to test premium purchase flow (won't actually charge)

### Test with iOS Simulator

```bash
flutter run -d ios
```

Same as above - test ads will display.

---

## 🎯 Before Submitting to Stores

### Google Play Store (Android)

1. Set up billing account in Google Play Console
2. Replace test ad IDs with production ad IDs
3. Configure product ID `com.contractshield.upgrade_premium` in Play Console
4. Test purchase flow with your Play Console test account
5. Submit app with all features enabled

### Apple App Store (iOS)

1. Set up App Store Connect account
2. Create in-app purchase `com.contractshield.upgrade_premium`
3. Configure pricing tier
4. Test with a sandbox account
5. Submit for review

---

## 📝 Code References

### How Ads Work in the App

```dart
// 1. Banner ad loads on home screen
AdMobHelper.loadBannerAd((ad) => setState(() => bannerAd = ad));

// 2. When user tries to save > 3 times (free limit)
if (!isPremium && calculationCount >= 3) {
  AdMobHelper.showInterstitialAd(); // Shows ad
  _showPremiumDialog(); // Then upgrade prompt
}

// 3. User sees the banner ad at top of screen
if (bannerAd != null)
  SizedBox(height: 50, child: AdWidget(ad: bannerAd!))
```

### How In-App Purchases Work

```dart
// 1. User taps "Upgrade to Premium"
onPressed: () => InAppPurchaseHelper.buyPremium();

// 2. Purchase confirmation is listened to
InAppPurchase.instance.purchaseStream.listen((purchases) {
  if (purchase.status == PurchaseStatus.purchased) {
    // Unlock premium
    _handlePurchaseSuccess();
  }
});

// 3. Premium status is saved locally and persists
SharedPreferences.getInstance()
  .then((prefs) => prefs.setBool('isPremium', true));
```

---

## 🚀 Production Checklist

- [ ] AdMob account created
- [ ] AdMob App ID obtained
- [ ] Banner, Interstitial, Rewarded ad units created
- [ ] Ad unit IDs updated in code
- [ ] Google Play Console app configured
- [ ] In-app product created with ID `com.contractshield.upgrade_premium`
- [ ] App Store Connect app configured
- [ ] In-app purchase created with ID `com.contractshield.upgrade_premium`
- [ ] Pricing set for premium upgrade
- [ ] Tested on real Android device
- [ ] Tested on real iOS device
- [ ] Privacy policy updated to mention ads
- [ ] Terms of Service mention in-app purchases
- [ ] App ready for submission

---

## 💡 Tips

1. **Test Devices**: Register test device IDs in AdMob to see test ads on real devices
2. **Test Purchases**: Use sandbox accounts on iOS and test accounts on Android
3. **Compliance**: Update privacy policy to mention data collection for ads
4. **User Feedback**: Add in-app option to report inappropriate ads
5. **Revenue**: Monitor AdMob earnings and IAP conversion rates

---

## 📞 Support

For issues:
- **AdMob**: https://support.google.com/admob
- **In-App Purchases**: https://pub.dev/packages/in_app_purchase
- **Google Play Billing**: https://developer.android.com/google/play/billing

---

**Version**: 1.0.0
**Status**: ✅ Code Ready | ⏳ Platform Setup Required