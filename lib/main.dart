import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMob initialization failed: $e');
    }
  }
  runApp(MyApp());
}

// AdMob Ad Unit IDs (Replace with your real IDs)
class AdMobHelper {
  static const String bannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111'; // Test ID
  static const String interstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712'; // Test ID
  static const String rewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917'; // Test ID

  static BannerAd? _bannerAd;
  static InterstitialAd? _interstitialAd;

  static Future<void> loadBannerAd(Function(BannerAd) onAdLoaded) async {
    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => onAdLoaded(ad as BannerAd),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner ad failed to load: $error');
        },
      ),
    );
    await _bannerAd?.load();
  }

  static Future<void> loadInterstitialAd() async {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('Interstitial ad failed to load: $error');
        },
      ),
    );
  }

  static void showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    }
  }

  static void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
  }
}

// In-App Purchase Product IDs
class InAppPurchaseHelper {
  static const String singleScanProductId = 'com.contractshield.scan_single';
  static const String monthlyProProductId = 'com.contractshield.pro_monthly';

  static final InAppPurchase _iap = InAppPurchase.instance;

  static Future<bool> isPremiumActive() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isPremium') ?? false;
  }

  static Future<void> buyPremium() async {
    final ProductDetailsResponse response = await _iap.queryProductDetails({
      monthlyProProductId,
    });

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Product ID not found: ${response.notFoundIDs}');
      return;
    }

    if (response.productDetails.isEmpty) {
      debugPrint('No product details available');
      return;
    }

    final ProductDetails product = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  static Future<void> verifyAndUnlockPremium() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPremium', true);
  }
}

// Simple localization strings
class AppStrings {
  static const Map<String, Map<String, String>> translations = {
    'en': {
      'appTitle': 'FSBO Helper',
      'estimatedSalePrice': 'Estimated Sale Price (\$)',
      'closingCosts': 'Estimated Closing Costs (\$)',
      'commissionRate': 'Agent Commission: %s%',
      'commissionSavings': 'Commission Savings: \$%s',
      'closingCostSavings': 'Closing Cost Savings: \$%s',
      'totalSavings': 'Total Potential Savings: \$%s',
      'saveCalculation': 'Save Calculation',
      'viewHistory': 'View History',
      'learnTips': 'Learn How to Cancel a Listing & Tips',
      'tipsTitle': 'FSBO Tips',
      'savedMessage': 'Calculation saved!',
      'disclaimer':
          'Disclaimer: This is an estimate. Consult professionals for accurate advice.',
      'copyright': '© 2026 Contract Shield. All rights reserved.',
      'premiumFeature': 'Premium Feature',
      'upgradeToPremium':
          'Upgrade to Premium to unlock unlimited saved calculations.',
      'tap1': 'Price your home competitively using local market data.',
      'tap2': 'Market your property online and through local networks.',
      'tap3': 'Understand legal requirements for disclosures.',
      'tap4': 'Prepare for the paperwork and closing process.',
      'tap5': 'Consider hiring a real estate attorney for guidance.',
      'province': 'Province',
      'defaultRatesApplied': 'Default rates applied for %s',
      'autoClosingCosts': 'Auto-estimated closing costs (%s): \$%s',
    },
    'fr': {
      'appTitle': 'Assistant Vente Maison',
      'estimatedSalePrice': 'Prix de Vente Estimé (\$)',
      'closingCosts': 'Frais de Clôture Estimés (\$)',
      'commissionRate': 'Commission de l\'Agent: %s%',
      'commissionSavings': 'Économies Commission: \$%s',
      'closingCostSavings': 'Économies Frais Clôture: \$%s',
      'totalSavings': 'Économies Potentielles Totales: \$%s',
      'saveCalculation': 'Sauvegarder le Calcul',
      'viewHistory': 'Voir l\'Historique',
      'learnTips': 'Apprendre à Annuler une Inscription & Conseils',
      'tipsTitle': 'Conseils Vente Maison',
      'savedMessage': 'Calcul sauvegardé!',
      'disclaimer':
          'Avis de non-responsabilité: Ceci est une estimation. Consultez des professionnels pour des conseils précis.',
      'copyright': '© 2026 Contract Shield. Tous droits réservés.',
      'premiumFeature': 'Fonctionnalité Premium',
      'upgradeToPremium':
          'Passez à Premium pour débloquer les calculs illimités.',
      'tap1':
          'Évaluez votre maison de manière compétitive en utilisant les données du marché local.',
      'tap2':
          'Commercialisez votre propriété en ligne et via les réseaux locaux.',
      'tap3': 'Comprenez les exigences légales pour les divulgations.',
      'tap4': 'Préparez-vous au processus administratif et de clôture.',
      'tap5': 'Envisagez d\'embaucher un avocat immobilier pour vous guider.',
      'province': 'Province',
      'defaultRatesApplied': 'Taux par défaut appliqués pour %s',
      'autoClosingCosts': 'Frais de clôture estimés automatiquement (%s): \$%s',
    },
  };

  static String get(String key, String language) {
    return translations[language]?[key] ?? translations['en']?[key] ?? key;
  }
}

class ProvinceRateDefaults {
  final double commissionRate;
  final double closingCostRate;

  const ProvinceRateDefaults({
    required this.commissionRate,
    required this.closingCostRate,
  });
}

class CanadaProvinceRates {
  static const Map<String, ProvinceRateDefaults> defaults = {
    'AB': ProvinceRateDefaults(commissionRate: 4.0, closingCostRate: 1.2),
    'BC': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.8),
    'MB': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.3),
    'NB': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.6),
    'NL': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.7),
    'NS': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.6),
    'NT': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.9),
    'NU': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 2.0),
    'ON': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.5),
    'PE': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.6),
    'QC': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.7),
    'SK': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.3),
    'YT': ProvinceRateDefaults(commissionRate: 5.0, closingCostRate: 1.9),
  };

  static const List<String> orderedCodes = [
    'AB',
    'BC',
    'MB',
    'NB',
    'NL',
    'NS',
    'NT',
    'NU',
    'ON',
    'PE',
    'QC',
    'SK',
    'YT',
  ];

  static const Map<String, String> labels = {
    'AB': 'Alberta',
    'BC': 'British Columbia',
    'MB': 'Manitoba',
    'NB': 'New Brunswick',
    'NL': 'Newfoundland and Labrador',
    'NS': 'Nova Scotia',
    'NT': 'Northwest Territories',
    'NU': 'Nunavut',
    'ON': 'Ontario',
    'PE': 'Prince Edward Island',
    'QC': 'Quebec',
    'SK': 'Saskatchewan',
    'YT': 'Yukon',
  };

  static const Map<String, String> notes = {
    'AB':
        'Alberta: legal fees and land title charges are usually the main closing-cost items.',
    'BC':
        'British Columbia: transfer-tax and legal fees can materially affect closing estimates.',
    'MB':
        'Manitoba: land transfer tax and registration fees should be reviewed with your lawyer.',
    'NB':
        'New Brunswick: legal and land transfer charges may vary by municipality and property value.',
    'NL':
        'Newfoundland and Labrador: legal and registration costs are commonly included in closing costs.',
    'NS':
        'Nova Scotia: deed transfer tax can vary by municipality and should be confirmed locally.',
    'NT':
        'Northwest Territories: legal and land-title processing costs may be higher in remote areas.',
    'NU':
        'Nunavut: legal and registration costs can vary; local legal advice is recommended.',
    'ON':
        'Ontario: land transfer tax, legal fees, and adjustments often form the largest closing costs.',
    'PE':
        'Prince Edward Island: legal fees and deed transfer costs should be confirmed before listing.',
    'QC':
        'Quebec: notary fees and transfer duties are common components of closing costs.',
    'SK':
        'Saskatchewan: legal fees and title registration are key contributors to closing costs.',
    'YT':
        'Yukon: legal and title-related fees can vary with property location and complexity.',
  };
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  void _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _language = prefs.getString('language') ?? 'en';
    });
  }

  void _setLanguage(String lang) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    setState(() {
      _language = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.get('appTitle', _language),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E88E5),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          prefixIconColor: const Color(0xFF1E88E5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E88E5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
          ),
        ),
      ),
      home: HomePage(language: _language, onLanguageChanged: _setLanguage),
    );
  }
}

class HomePage extends StatefulWidget {
  final String language;
  final Function(String) onLanguageChanged;

  const HomePage({
    super.key,
    this.language = 'en',
    required this.onLanguageChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String propertyValue = '';
  double commissionRate = 5.0;
  String closingCosts = '';
  String selectedProvince = 'ON';
  bool closingCostsManuallyEdited = false;
  List<String> savedCalculations = [];
  bool isPremium = false;
  int calculationCount = 0;
  final maxFreeCalculations = 3;
  BannerAd? bannerAd;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _initializeAds();
    _setupInAppPurchaseListeners();
  }

  void _initializeAds() {
    if (kIsWeb) return; // Skip on web
    if (!(Platform.isAndroid || Platform.isIOS)) return; // Ads only on mobile
    try {
      AdMobHelper.loadBannerAd((ad) {
        setState(() => bannerAd = ad);
      });
      AdMobHelper.loadInterstitialAd();
    } catch (e) {
      debugPrint('Ad initialization skipped: $e');
    }
  }

  void _setupInAppPurchaseListeners() {
    if (kIsWeb) return; // Skip on web
    try {
      InAppPurchase.instance.purchaseStream.listen((purchases) {
        for (var purchase in purchases) {
          if (purchase.productID == InAppPurchaseHelper.monthlyProProductId) {
            if (purchase.status == PurchaseStatus.purchased) {
              _handlePurchaseSuccess();
            }
          }
        }
      });
    } catch (e) {
      debugPrint('In-App Purchase listener setup skipped: $e');
    }
  }

  void _handlePurchaseSuccess() async {
    await InAppPurchaseHelper.verifyAndUnlockPremium();
    setState(() => isPremium = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium Unlocked! Enjoy unlimited saves.'),
        ),
      );
    }
  }

  double get commissionSavings {
    double value = double.tryParse(propertyValue) ?? 0;
    return value * (commissionRate / 100);
  }

  double get autoClosingCosts {
    final value = double.tryParse(propertyValue) ?? 0;
    final provinceRate =
        CanadaProvinceRates.defaults[selectedProvince]?.closingCostRate ?? 1.5;
    return value * (provinceRate / 100);
  }

  double get closingCostSavings {
    if (closingCosts.trim().isNotEmpty) {
      return double.tryParse(closingCosts) ?? 0;
    }
    return autoClosingCosts;
  }

  double get totalSavings => commissionSavings + closingCostSavings;

  void _saveCalculation() async {
    if (!isPremium && calculationCount >= maxFreeCalculations) {
      // Show interstitial ad before showing upgrade dialog
      if (!kIsWeb) {
        try {
          AdMobHelper.showInterstitialAd();
        } catch (e) {
          debugPrint('Interstitial ad failed: $e');
        }
      }
      _showPremiumDialog();
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    final provinceName =
        CanadaProvinceRates.labels[selectedProvince] ?? selectedProvince;
    String calc =
        'Province: $provinceName, Property: \$$propertyValue, Commission: ${commissionRate.toStringAsFixed(1)}%, Savings: \$${totalSavings.toStringAsFixed(2)}';
    savedCalculations.add(calc);
    calculationCount++;
    await prefs.setStringList('calculations', savedCalculations);
    await prefs.setInt('calculationCount', calculationCount);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('savedMessage', widget.language)),
        ),
      );
    }
  }

  void _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      savedCalculations = prefs.getStringList('calculations') ?? [];
      calculationCount = prefs.getInt('calculationCount') ?? 0;
      isPremium = prefs.getBool('isPremium') ?? false;
    });
  }

  void _upgradeToPremium() async {
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PaywallPage(language: widget.language),
      ),
    );

    if (unlocked == true && mounted) {
      setState(() => isPremium = true);
    }
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.get('premiumFeature', widget.language)),
        content: Text(AppStrings.get('upgradeToPremium', widget.language)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _upgradeToPremium();
            },
            child: const Text('View Plans'),
          ),
        ],
      ),
    );
  }

  void _navigateToTips() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TipsPage(language: widget.language),
      ),
    );
  }

  void _navigateToTermination() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TerminationPage(language: widget.language),
      ),
    );
  }

  void _navigateToContractScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ContractScannerPage()),
    );
  }

  void _navigateToFeaturesOverview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeaturesOverviewPage(language: widget.language),
      ),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            HistoryPage(savedCalculations, language: widget.language),
      ),
    );
  }

  String _getString(String key) {
    return AppStrings.get(key, widget.language);
  }

  String _format(String template, List<String> values) {
    var result = template;
    for (final value in values) {
      result = result.replaceFirst('%s', value);
    }
    return result;
  }

  String get _selectedProvinceName {
    return CanadaProvinceRates.labels[selectedProvince] ?? selectedProvince;
  }

  String get _selectedProvinceNote {
    return CanadaProvinceRates.notes[selectedProvince] ??
        'Closing-cost structures vary by province and municipality.';
  }

  // ── SwiftUI-style Form section helpers ──────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _savingsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  void _setProvinceDefaults(String provinceCode) {
    final defaults = CanadaProvinceRates.defaults[provinceCode];
    if (defaults == null) {
      return;
    }

    setState(() {
      selectedProvince = provinceCode;
      commissionRate = defaults.commissionRate;
      if (!closingCostsManuallyEdited) {
        closingCosts = '';
      }
    });
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    AdMobHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getString('appTitle')),
        elevation: 0,
        actions: [
          if (isPremium)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('English'),
                onTap: () => widget.onLanguageChanged('en'),
              ),
              PopupMenuItem(
                child: const Text('Français'),
                onTap: () => widget.onLanguageChanged('fr'),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFF5F7FA), Colors.grey[100]!],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome to FSBO Helper',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Calculate your potential savings as a For Sale By Owner',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Banner Ad
              if (bannerAd != null)
                SizedBox(height: 50, child: AdWidget(ad: bannerAd!))
              else
                Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Text('Advertisement Space')),
                ),
              const SizedBox(height: 24),

              // ── Section: Property Details ──────────────────────────
              _sectionHeader('Property Details'),
              _sectionCard([
                // Province picker
                DropdownButtonFormField<String>(
                  initialValue: selectedProvince,
                  decoration: const InputDecoration(
                    labelText: 'Province',
                    prefixIcon: Icon(Icons.map),
                    border: InputBorder.none,
                    filled: false,
                  ),
                  items: CanadaProvinceRates.orderedCodes
                      .map(
                        (code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text(
                            '${CanadaProvinceRates.labels[code] ?? code} ($code)',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _setProvinceDefaults(value);
                  },
                ),
                const Divider(height: 1),
                // Sale price
                TextFormField(
                  decoration: InputDecoration(
                    labelText: _getString('estimatedSalePrice'),
                    prefixIcon: const Icon(Icons.home),
                    hintText: 'e.g., 500000',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() => propertyValue = value),
                ),
                const Divider(height: 1),
                // Closing costs
                TextFormField(
                  decoration: InputDecoration(
                    labelText: _getString('closingCosts'),
                    prefixIcon: const Icon(Icons.attach_money),
                    hintText: 'Leave blank to auto-estimate',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() {
                    closingCosts = value;
                    closingCostsManuallyEdited = value.trim().isNotEmpty;
                  }),
                ),
                const Divider(height: 1),
                // Stepper row — matches SwiftUI Stepper
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.percent,
                        size: 20,
                        color: Color(0xFF1E88E5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Agent Commission: ${commissionRate.toInt()}%',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: const Color(0xFF1E88E5),
                        onPressed: commissionRate > 1
                            ? () => setState(() => commissionRate--)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        color: const Color(0xFF1E88E5),
                        onPressed: commissionRate < 7
                            ? () => setState(() => commissionRate++)
                            : null,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    _format(_getString('defaultRatesApplied'), [
                      CanadaProvinceRates.labels[selectedProvince] ??
                          selectedProvince,
                    ]),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ]),

              // ── Section: Your Potential Savings ────────────────────
              _sectionHeader('Your Potential Savings'),
              _sectionCard([
                // Total — big green bold number matching SwiftUI
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  child: Center(
                    child: Text(
                      '\$${totalSavings.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                // Commission row
                _savingsRow(
                  'Commission savings',
                  '\$${commissionSavings.toStringAsFixed(2)}',
                ),
                const Divider(height: 1),
                // Closing costs row
                _savingsRow(
                  closingCosts.trim().isNotEmpty
                      ? 'Closing cost savings'
                      : 'Est. closing costs (${(CanadaProvinceRates.defaults[selectedProvince]?.closingCostRate ?? 1.5).toStringAsFixed(1)}%)',
                  '\$${closingCostSavings.toStringAsFixed(2)}',
                ),
              ]),

              // ── Province note ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$_selectedProvinceName: $_selectedProvinceNote',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Free Trial Counter ─────────────────────────────────
              if (!isPremium)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                    border: Border.all(color: const Color(0xFFFF9800)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Color(0xFFFF9800)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Free Trial: $calculationCount/$maxFreeCalculations saved',
                          style: const TextStyle(
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Action Buttons ─────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveCalculation,
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _navigateToHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('History'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Learn How to Cancel a Listing — matches SwiftUI Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToTips,
                  icon: const Icon(Icons.lightbulb),
                  label: Text(_getString('learnTips')),
                ),
              ),
              const SizedBox(height: 12),

              // ── Generate Notice of Termination ─────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToTermination,
                  icon: const Icon(Icons.description),
                  label: const Text('Generate Notice of Termination'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToContractScanner,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scan Contract for Red Flags'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToFeaturesOverview,
                  icon: const Icon(Icons.apps),
                  label: const Text('What This App Includes'),
                ),
              ),

              // ── Premium Upgrade ────────────────────────────────────
              if (!isPremium) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB300), Color(0xFFFFA000)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _upgradeToPremium,
                    icon: const Icon(Icons.star),
                    label: const Text('Unlock Premium'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Footer
              Center(
                child: Column(
                  children: [
                    Text(
                      '${_getString('disclaimer')} Canada note: tax and transfer-fee rules vary by province; confirm figures with a local real estate lawyer or notary.',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getString('copyright'),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TipsPage extends StatelessWidget {
  final String language;

  const TipsPage({super.key, this.language = 'en'});

  String _getString(String key) => AppStrings.get(key, language);

  @override
  Widget build(BuildContext context) {
    final tips = [
      _getString('tap1'),
      _getString('tap2'),
      _getString('tap3'),
      _getString('tap4'),
      _getString('tap5'),
    ];

    final icons = [
      Icons.trending_up,
      Icons.public,
      Icons.gavel,
      Icons.description,
      Icons.verified_user,
    ];

    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFFF44336),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_getString('tipsTitle'))),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFF5F7FA), Colors.grey[100]!],
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tips.length,
          itemBuilder: (context, index) {
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(color: colors[index], width: 5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors[index].withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icons[index],
                          color: colors[index],
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tip ${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colors[index],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tips[index],
                              style: const TextStyle(fontSize: 14, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Notice of Termination ─────────────────────────────────────────────────
class TerminationPage extends StatefulWidget {
  final String language;
  const TerminationPage({super.key, this.language = 'en'});

  @override
  State<TerminationPage> createState() => _TerminationPageState();
}

class _TerminationPageState extends State<TerminationPage> {
  final _formKey = GlobalKey<FormState>();
  final _ownerCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _mlsCtrl = TextEditingController();
  DateTime _contractDate = DateTime.now();
  bool _generating = false;

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _brokerCtrl.dispose();
    _addressCtrl.dispose();
    _mlsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _contractDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _contractDate = picked);
  }

  Future<void> _generatePDF() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _generating = true);

    try {
      final pdf = pw.Document();
      final dateStr =
          '${_contractDate.year}-${_contractDate.month.toString().padLeft(2, '0')}-${_contractDate.day.toString().padLeft(2, '0')}';
      final todayStr = () {
        final n = DateTime.now();
        return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
      }();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(48),
          build: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'NOTICE OF TERMINATION / AVIS DE RÉSILIATION',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'Based on OACIQ Clause 2.1 — Contract Resiliation',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Divider(height: 24),
              pw.SizedBox(height: 8),
              _pdfRow('Date of Notice:', todayStr),
              _pdfRow('Property Owner / Vendeur:', _ownerCtrl.text),
              _pdfRow('Broker / Courtier:', _brokerCtrl.text),
              _pdfRow('Property Address / Adresse:', _addressCtrl.text),
              if (_mlsCtrl.text.trim().isNotEmpty)
                _pdfRow('MLS® Number:', _mlsCtrl.text),
              _pdfRow('Brokerage Contract Date:', dateStr),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'Pursuant to Clause 2.1 of the brokerage contract, I/we hereby '
                  'formally notify you of my/our intention to terminate the above-referenced '
                  'brokerage contract for the sale of the property described herein. '
                  'This notice is served in accordance with the rights and obligations '
                  'established under the Real Estate Brokerage Act (REBA) and the '
                  'OACIQ standard forms.\n\n'
                  'En vertu de la clause 2.1 du contrat de courtage, je/nous vous '
                  'avisons formellement de notre intention de résilier le contrat '
                  'de courtage susmentionné pour la vente de la propriété décrite ci-dessus.',
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
                ),
              ),
              pw.SizedBox(height: 32),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 180,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(color: PdfColors.black),
                          ),
                        ),
                        height: 30,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Owner Signature / Signature du propriétaire',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 160,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(color: PdfColors.black),
                          ),
                        ),
                        height: 30,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Date', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  'Generated by Contract Shield © 2026 — This document is for informational purposes only. Consult a legal professional.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                    fontStyle: pw.FontStyle.italic,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/notice_of_termination_$todayStr.pdf');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Notice of Termination — Contract Shield');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 160,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notice of Termination')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This generates a formal Notice of Termination based on OACIQ Clause 2.1. '
                        'Always consult a real estate lawyer or notary before filing.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'PROPERTY DETAILS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ownerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Property Owner Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Property Address',
                  prefixIcon: Icon(Icons.home),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mlsCtrl,
                decoration: const InputDecoration(
                  labelText: 'MLS® Number (optional)',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'BROKER DETAILS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _brokerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Broker / Agency Name',
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Brokerage Contract Date',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${_contractDate.year}-${_contractDate.month.toString().padLeft(2, '0')}-${_contractDate.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _generating ? null : _generatePDF,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(
                    _generating
                        ? 'Generating…'
                        : 'Generate Notice of Termination',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'The PDF will open in your share sheet so you can save, email, or print it.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContractScannerPage extends StatefulWidget {
  const ContractScannerPage({super.key});

  @override
  State<ContractScannerPage> createState() => _ContractScannerPageState();
}

enum RiskStatus { pending, low, high }

class _ContractScannerPageState extends State<ContractScannerPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  final List<String> _redFlags = const [
    'non-cancellable',
    'irrevocable',
    'irrevocable period',
    'irrevocable offer',
    'exclusivite',
    'exclusivite de',
    'sans annulation',
    'without cancellation',
  ];

  late final AnimationController _scanController;

  bool _isScanning = false;
  String _scannedText = '';
  List<String> _foundFlags = [];
  RiskStatus _riskLevel = RiskStatus.pending;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _scanFromCamera() async {
    if (Platform.isMacOS) {
      await _scanFromGallery();
      return;
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file != null) {
      await _processImage(file.path);
    }
  }

  Future<void> _scanFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null) {
      await _processImage(file.path);
    }
  }

  Future<void> _startScan() async {
    // On macOS, camera is not supported by image_picker, so use gallery instead
    if (Platform.isMacOS) {
      await _scanFromGallery();
    } else {
      await _scanFromCamera();
    }
  }

  Future<void> _processImage(String path) async {
    setState(() {
      _isScanning = true;
      _riskLevel = RiskStatus.pending;
      _foundFlags = [];
      _scannedText = '';
    });
    _scanController.repeat(reverse: true);

    try {
      final image = InputImage.fromFilePath(path);
      final recognizedText = await _textRecognizer.processImage(image);
      final normalized = recognizedText.text.toLowerCase();

      final matches = _redFlags
          .where((flag) => normalized.contains(flag))
          .toList();

      setState(() {
        _scannedText = recognizedText.text;
        _foundFlags = matches;
        _riskLevel = matches.isNotEmpty ? RiskStatus.high : RiskStatus.low;
      });

      if (mounted && matches.isNotEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Alert: Red Flags Found'),
            content: Text(
              'Potentially risky terms detected:\n\n${matches.join('\n')}\n\nPlease review with a legal professional.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    } finally {
      _scanController.stop();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contract Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 4),
            const Text(
              'Contract Shield',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              "Scan your brokerage agreement for 'traps'",
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),

            // Scanner window with animated scan line.
            SizedBox(
              height: 350,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DashedBorderPainter(
                        color: _isScanning ? Colors.blue : Colors.grey,
                        strokeWidth: 4,
                        borderRadius: 20,
                        dashLength: 10,
                        gapLength: 8,
                      ),
                    ),
                  ),
                  if (_isScanning)
                    AnimatedBuilder(
                      animation: _scanController,
                      builder: (context, child) {
                        final y = -150 + (300 * _scanController.value);
                        return Positioned(
                          left: 18,
                          right: 18,
                          top: 175 + y,
                          child: Container(
                            height: 2,
                            color: Colors.blue.withValues(alpha: 0.35),
                          ),
                        );
                      },
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.document_scanner_outlined,
                        size: 60,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_riskLevel == RiskStatus.high)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _foundFlags.isEmpty
                            ? "TRAP DETECTED: 'Non-Cancellable' clause found."
                            : 'TRAP DETECTED: ${_foundFlags.first}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_riskLevel == RiskStatus.low)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No trap words found in this scan.',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isScanning ? null : _startScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  _isScanning ? 'Analyzing Clauses...' : 'Scan Contract',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isScanning || Platform.isMacOS)
                        ? null
                        : _scanFromCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(Platform.isMacOS ? 'Camera N/A' : 'Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanning ? null : _scanFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),

            if (Platform.isMacOS) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Desktop tip: use Gallery to scan contract photos. Camera scanning is available on mobile devices.',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_scannedText.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(_scannedText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double borderRadius;
  final double dashLength;
  final double gapLength;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class FeaturesOverviewPage extends StatelessWidget {
  final String language;

  const FeaturesOverviewPage({super.key, this.language = 'en'});

  @override
  Widget build(BuildContext context) {
    final isFr = language == 'fr';

    final localizedFeatures = <({String title, String desc, IconData icon, Color color})>[
      (
        title: isFr ? 'Calculateur d\'économies' : 'Savings Calculator',
        desc: isFr
            ? 'Estimez en temps réel les économies de commission et de frais de clôture.'
            : 'Estimate commission and closing-cost savings in real time.',
        icon: Icons.calculate,
        color: const Color(0xFF2E7D32),
      ),
      (
        title: isFr ? 'Paramètres provinciaux' : 'Province Defaults',
        desc: isFr
            ? 'Utilise des taux par défaut selon la province au Canada.'
            : 'Uses Canada province-specific default commission and closing-cost rates.',
        icon: Icons.map,
        color: const Color(0xFF1565C0),
      ),
      (
        title: isFr ? 'Sauvegarde et historique' : 'Save & History',
        desc: isFr
            ? 'Sauvegardez vos calculs et consultez-les dans l\'historique.'
            : 'Save calculations and review them later in the History screen.',
        icon: Icons.history,
        color: const Color(0xFF6A1B9A),
      ),
      (
        title: isFr ? 'PDF d\'avis de résiliation' : 'Termination Notice PDF',
        desc: isFr
            ? 'Générez et partagez un PDF officiel d\'avis de résiliation.'
            : 'Generate and share a formal Notice of Termination PDF.',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFFC62828),
      ),
      (
        title: isFr ? 'Scanner de contrat' : 'Contract Scanner',
        desc: isFr
            ? 'Scannez une image de contrat et détectez des clauses risquées. Caméra sur mobile, galerie sur ordinateur.'
            : 'Scan contract images and flag risky words like irrevocable clauses. Camera on mobile, gallery on desktop.',
        icon: Icons.document_scanner,
        color: const Color(0xFFEF6C00),
      ),
      (
        title: isFr ? 'Conseils FSBO' : 'FSBO Tips',
        desc: isFr
            ? 'Conseils guidés pour vendre sans courtier inscripteur.'
            : 'Guided tips for selling without a listing agent.',
        icon: Icons.lightbulb,
        color: const Color(0xFFF9A825),
      ),
      (
        title: isFr ? 'Anglais / Français' : 'English / French',
        desc: isFr
            ? 'Changez la langue depuis le menu de l\'application.'
            : 'Switch language from the app menu.',
        icon: Icons.language,
        color: const Color(0xFF00838F),
      ),
      (
        title: isFr ? 'Mise à niveau Premium' : 'Premium Upgrade',
        desc: isFr
            ? 'Le plan gratuit a des limites; Premium débloque les sauvegardes illimitées.'
            : 'Free plan has limits; premium unlocks unlimited saved calculations.',
        icon: Icons.workspace_premium,
        color: const Color(0xFF8D6E63),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isFr ? 'Ce que cette application inclut' : 'What This App Includes',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              isFr
                  ? 'Tout ce qui suit est inclus dans cette application. Utilisez cette page pour comprendre rapidement les outils disponibles avant de commencer.'
                  : 'Everything below is included in this app. Use this page to quickly understand what tools are available before starting.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),

          ...localizedFeatures.map(
            (feature) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: feature.color,
                  foregroundColor: Colors.white,
                  child: Icon(feature.icon, size: 18),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        feature.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF2E7D32),
                      size: 18,
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(feature.desc),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),
          Text(
            isFr ? 'Démarrage rapide (3 étapes)' : 'Quick Start (3 Steps)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFr
                        ? '1. Entrez les détails de la propriété et choisissez votre province.'
                        : '1. Enter property details and pick your province.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isFr
                        ? '2. Vérifiez les économies, puis sauvegardez ou générez le PDF d\'avis de résiliation.'
                        : '2. Review savings, then save or generate your termination notice PDF.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isFr
                        ? '3. Utilisez le scanner de contrat pour vérifier les clauses risquées avant de signer.'
                        : '3. Use Contract Scanner to check for risky wording before signing.',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Text(
              isFr
                  ? 'Compatibilité scanner : appareil photo disponible sur iPhone/Android. Sur macOS/ordinateur, utilisez la galerie.'
                  : 'Scanner compatibility: Camera is available on iPhone/Android. On macOS/desktop, use Gallery.',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: Text(
              isFr
                  ? 'Note juridique (Canada/Québec) : Cette application fournit uniquement des estimations et des modèles de documents à titre informatif. '
                        'Pour des conseils juridiques applicables, consultez un avocat immobilier ou un notaire autorisé dans votre province.'
                  : 'Legal note (Canada/Quebec): This app provides informational estimates and document templates only. '
                        'For enforceable legal advice, consult a licensed real estate lawyer or notary in your province.',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class PaywallPage extends StatefulWidget {
  final String language;

  const PaywallPage({super.key, this.language = 'en'});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  final InAppPurchase _iap = InAppPurchase.instance;

  // Replace this base URL after publishing legal pages (e.g. GitHub Pages).
  static const String _legalBaseUrl =
      'https://bigdavion0824-dot.github.io/contract-shield/legal';
  static const String _privacyUrl = '$_legalBaseUrl/privacy.html';
  static const String _termsUrl = '$_legalBaseUrl/terms.html';

  List<ProductDetails> _products = [];
  bool _loadingProducts = true;
  bool _purchasing = false;
  bool _restoring = false;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool get _isFr => widget.language == 'fr';

  static const _productOrder = [
    InAppPurchaseHelper.singleScanProductId,
    InAppPurchaseHelper.monthlyProProductId,
  ];

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = _iap.purchaseStream.listen(_handlePurchases);
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final response = await _iap.queryProductDetails(_productOrder.toSet());
    if (!mounted) return;

    final products = response.productDetails.toList();
    products.sort((a, b) {
      final left = _productOrder.indexOf(a.id);
      final right = _productOrder.indexOf(b.id);
      return left.compareTo(right);
    });

    setState(() {
      _products = products;
      _loadingProducts = false;
    });

    if (response.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr
                ? 'Impossible de charger les offres pour le moment.'
                : 'Unable to load plans right now.',
          ),
        ),
      );
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() => _purchasing = true);
    final param = PurchaseParam(productDetails: product);

    if (product.id == InAppPurchaseHelper.singleScanProductId) {
      await _iap.buyConsumable(purchaseParam: param);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _restoring = true);
    await _iap.restorePurchases();
    if (!mounted) return;
    setState(() => _restoring = false);
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() => _purchasing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isFr
                    ? 'Achat échoué. Veuillez réessayer.'
                    : 'Purchase failed. Please try again.',
              ),
            ),
          );
        }
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (purchase.productID == InAppPurchaseHelper.monthlyProProductId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isPremium', true);
          if (mounted) {
            setState(() {
              _purchasing = false;
              _restoring = false;
            });
            Navigator.pop(context, true);
          }
        } else if (purchase.productID ==
            InAppPurchaseHelper.singleScanProductId) {
          if (mounted) {
            setState(() => _purchasing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isFr
                      ? 'Scan unique acheté avec succès.'
                      : 'Single scan purchased successfully.',
                ),
              ),
            );
          }
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr ? 'Impossible d\'ouvrir le lien.' : 'Unable to open link.',
          ),
        ),
      );
    }
  }

  IconData _iconForProduct(String id) {
    if (id == InAppPurchaseHelper.singleScanProductId) {
      return Icons.document_scanner;
    }
    return Icons.shield;
  }

  String _descriptionForProduct(ProductDetails product) {
    if (product.id == InAppPurchaseHelper.singleScanProductId) {
      return _isFr
          ? '1 analyse de contrat. Idéal pour un besoin ponctuel.'
          : 'One contract scan. Great for one-off usage.';
    }
    if (product.id == InAppPurchaseHelper.monthlyProProductId ||
        product.id == InAppPurchaseHelper.monthlyProProductId) {
      return _isFr
          ? 'Premium mensuel avec calculs illimités et accès complet.'
          : 'Monthly Pro with unlimited saves and full access.';
    }
    return product.description;
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFr ? 'Passer à Premium' : 'Upgrade to Premium'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield, color: Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    Text(
                      _isFr ? 'Plans Contract Shield' : 'Contract Shield Plans',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isFr
                      ? 'Choisissez un achat unique ou l\'abonnement mensuel Pro.'
                      : 'Choose a one-time scan or monthly Pro subscription.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingProducts)
            const Center(child: CircularProgressIndicator())
          else if (_products.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _isFr
                      ? 'Aucune offre disponible pour ce compte pour le moment.'
                      : 'No purchase options are available for this account yet.',
                ),
              ),
            )
          else
            ..._products.map((product) {
              final isPro =
                  product.id == InAppPurchaseHelper.monthlyProProductId;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isPro
                                ? const Color(0xFF1565C0)
                                : const Color(0xFFEF6C00),
                            child: Icon(
                              _iconForProduct(product.id),
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _descriptionForProduct(product),
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            product.price,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: _purchasing ? null : () => _buy(product),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E88E5),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_isFr ? 'Acheter' : 'Buy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _restoring ? null : _restorePurchases,
            icon: const Icon(Icons.restore),
            label: Text(
              _restoring
                  ? (_isFr ? 'Restauration…' : 'Restoring...')
                  : (_isFr ? 'Restaurer les achats' : 'Restore Purchases'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _openExternalUrl(_privacyUrl),
                child: Text(
                  _isFr ? 'Politique de confidentialité' : 'Privacy Policy',
                ),
              ),
              TextButton(
                onPressed: () => _openExternalUrl(_termsUrl),
                child: Text(
                  _isFr ? 'Conditions d\'utilisation' : 'Terms of Use',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  final List<String> calculations;
  final String language;

  const HistoryPage(this.calculations, {super.key, this.language = 'en'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.get('viewHistory', language))),
      body: calculations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No saved calculations yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: calculations.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(calculations[index]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Color(0xFFF44336)),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Delete coming soon')),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
