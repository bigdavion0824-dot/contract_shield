import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('Flutter framework error: ${details.exceptionAsString()}');
        unawaited(
          RuntimeDiagnostics.recordError(
            'flutter_framework',
            details.exception,
            details.stack,
          ),
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught async/platform error: $error');
        unawaited(
          RuntimeDiagnostics.recordError('platform_dispatcher', error, stack),
        );
        return true;
      };

      ConnectivityService.init();
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await MobileAds.instance.initialize();
        } catch (e) {
          debugPrint('AdMob initialization failed: $e');
        }
      }
      runApp(const MyApp());
    },
    (error, stackTrace) {
      debugPrint('runZonedGuarded uncaught error: $error');
      unawaited(
        RuntimeDiagnostics.recordError('run_zoned_guarded', error, stackTrace),
      );
    },
  );
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
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('isPremium') ?? false;
    } catch (e) {
      debugPrint('Read premium state failed: $e');
      return false;
    }
  }

  static Future<void> buyPremium() async {
    try {
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
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('buyPremium failed: $e');
    }
  }

  static Future<void> verifyAndUnlockPremium() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isPremium', true);
    } catch (e) {
      debugPrint('verifyAndUnlockPremium failed: $e');
    }
  }
}

class AppAnalytics {
  static Future<void> logEvent(
    String eventName, {
    Map<String, String>? params,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().toIso8601String();
      final encodedParams = (params ?? {}).entries
          .map((e) => '${e.key}=${e.value}')
          .join(',');
      final entry = '$timestamp|$eventName|$encodedParams';

      final events = prefs.getStringList('analytics_events') ?? [];
      events.add(entry);
      if (events.length > 200) {
        events.removeRange(0, events.length - 200);
      }

      await prefs.setStringList('analytics_events', events);
      final countKey = 'analytics_count_$eventName';
      final count = prefs.getInt(countKey) ?? 0;
      await prefs.setInt(countKey, count + 1);

      debugPrint('analytics event: $entry');
      unawaited(TelemetryRelay.sendEvent(eventName, params: params ?? {}));
    } catch (e) {
      debugPrint('logEvent failed: $e');
      unawaited(RuntimeDiagnostics.recordError('analytics_log_event', e));
    }
  }

  static Future<Map<String, int>> getEventCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, int>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('analytics_count_')) {
          final eventName = key.replaceFirst('analytics_count_', '');
          out[eventName] = prefs.getInt(key) ?? 0;
        }
      }
      return out;
    } catch (e) {
      debugPrint('getEventCounts failed: $e');
      unawaited(
        RuntimeDiagnostics.recordError('analytics_get_event_counts', e),
      );
      return {};
    }
  }

  static Future<List<String>> getRecentEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('analytics_events') ?? [];
    } catch (e) {
      debugPrint('getRecentEvents failed: $e');
      unawaited(
        RuntimeDiagnostics.recordError('analytics_get_recent_events', e),
      );
      return [];
    }
  }

  static Future<void> clearEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('analytics_count_')) {
          await prefs.remove(key);
        }
      }
      await prefs.setStringList('analytics_events', []);
    } catch (e) {
      debugPrint('clearEvents failed: $e');
      unawaited(RuntimeDiagnostics.recordError('analytics_clear_events', e));
    }
  }
}

class RuntimeDiagnostics {
  static const String _errorsKey = 'runtime_errors';

  static Future<void> recordError(
    String scope,
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      final stackLine = stackTrace
          ?.toString()
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
          .trim();
      final entry =
          '$now|$scope|$error${stackLine != null && stackLine.isNotEmpty ? '|$stackLine' : ''}';

      final list = prefs.getStringList(_errorsKey) ?? [];
      list.add(entry);
      if (list.length > 120) {
        list.removeRange(0, list.length - 120);
      }
      await prefs.setStringList(_errorsKey, list);
      unawaited(TelemetryRelay.sendError(scope, error, stackTrace));
    } catch (e) {
      debugPrint('recordError failed: $e');
    }
  }

  static Future<List<String>> getRecentErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_errorsKey) ?? [];
    } catch (e) {
      debugPrint('getRecentErrors failed: $e');
      return [];
    }
  }

  static Future<void> clearErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_errorsKey, []);
    } catch (e) {
      debugPrint('clearErrors failed: $e');
    }
  }
}

class TelemetryRelay {
  static const String _endpoint = String.fromEnvironment(
    'TELEMETRY_ENDPOINT',
    defaultValue: '',
  );

  static bool get _enabled => _endpoint.trim().isNotEmpty && !kIsWeb;

  static Future<void> sendEvent(
    String eventName, {
    Map<String, String>? params,
  }) async {
    if (!_enabled) {
      return;
    }

    final payload = <String, Object?>{
      'type': 'event',
      'ts': DateTime.now().toUtc().toIso8601String(),
      'name': eventName,
      'params': params ?? <String, String>{},
      'appVersion': AppMeta.version,
      'buildLabel': AppMeta.buildLabel,
      'platform': defaultTargetPlatform.name,
    };
    await _post(payload);
  }

  static Future<void> sendError(
    String scope,
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    if (!_enabled) {
      return;
    }

    final payload = <String, Object?>{
      'type': 'error',
      'ts': DateTime.now().toUtc().toIso8601String(),
      'scope': scope,
      'error': error.toString(),
      'stack': stackTrace?.toString(),
      'appVersion': AppMeta.version,
      'buildLabel': AppMeta.buildLabel,
      'platform': defaultTargetPlatform.name,
    };
    await _post(payload);
  }

  static Future<void> _post(Map<String, Object?> payload) async {
    HttpClient? client;
    try {
      final uri = Uri.tryParse(_endpoint);
      if (uri == null || !uri.hasScheme) {
        return;
      }

      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode(payload));

      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Telemetry relay non-2xx status: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Telemetry relay send failed: $e');
    } finally {
      client?.close(force: true);
    }
  }
}

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static void init() {
    _checkInitialStatus();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      isOnline.value = online;
      if (online) {
        debugPrint('Network: Online');
      } else {
        debugPrint('Network: Offline');
      }
    });
  }

  static Future<void> _checkInitialStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      isOnline.value = !result.contains(ConnectivityResult.none);
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
    }
  }

  static void dispose() {
    _subscription?.cancel();
  }
}

class AppLinks {
  static const String legalBaseUrl =
      'https://bigdavion0824-dot.github.io/contract_shield/legal';
  static const String privacyUrl = '$legalBaseUrl/privacy.html?v=20260403';
  static const String termsUrl = '$legalBaseUrl/terms.html?v=20260403';
}

class AppMeta {
  static const String version = '1.0.0-beta.1';
  static const String buildLabel = '2026.04-launch';
}

// Simple localization strings
class AppStrings {
  static const Map<String, Map<String, String>> translations = {
    'en': {
      'appTitle': 'Contract Shield',
      'estimatedSalePrice': 'Estimated Sale Price (\$)',
      'closingCosts': 'Estimated Closing Costs (\$)',
      'commissionRate': 'Agent Commission: %s%',
      'commissionSavings': 'Commission Savings: \$%s',
      'closingCostSavings': 'Closing Cost Savings: \$%s',
      'totalSavings': 'Total Potential Savings: \$%s',
      'saveCalculation': 'Save Calculation',
      'viewHistory': 'View History',
      'learnTips': 'Learn How to Cancel a Listing & Tips',
      'tipsTitle': 'Home Selling Tips',
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
      'appTitle': 'Contract Shield',
      'estimatedSalePrice': 'Prix de Vente Estimé (\$)',
      'closingCosts': 'Frais de Clôture Estimés (\$)',
      'commissionRate': 'Commission de l\'Agent: %s%',
      'commissionSavings': 'Économies Commission: \$%s',
      'closingCostSavings': 'Économies Frais Clôture: \$%s',
      'totalSavings': 'Économies Potentielles Totales: \$%s',
      'saveCalculation': 'Sauvegarder le Calcul',
      'viewHistory': 'Voir l\'Historique',
      'learnTips': 'Apprendre à Annuler une Inscription & Conseils',
      'tipsTitle': 'Conseils de vente maison',
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
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _language = prefs.getString('language') ?? 'en';
      });
    } catch (e) {
      debugPrint('Language load failed: $e');
    }
  }

  void _setLanguage(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', lang);
      if (!mounted) return;
      setState(() {
        _language = lang;
      });
    } catch (e) {
      debugPrint('Language save failed: $e');
    }
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
  final TextEditingController _commissionRateController =
      TextEditingController();
  String closingCosts = '';
  String selectedProvince = 'ON';
  bool _hasCalculated = false;
  double _calculatedPropertyValue = 0;
  double _calculatedCommissionRate = 5.0;
  String _calculatedProvince = 'ON';
  double _calculatedProvinceClosingCostRate = 1.5;
  bool _usedManualClosingCosts = false;
  double _calculatedManualClosingCosts = 0;
  bool closingCostsManuallyEdited = false;
  List<String> savedCalculations = [];
  bool isPremium = false;
  int calculationCount = 0;
  final maxFreeCalculations = 3;
  BannerAd? bannerAd;
  DateTime? _ontarioDocsReceivedDate;
  bool _ontarioIsCondo = true;
  DateTime? _quebecBrokerageSignedDate;
  DateTime? _bcContractAcceptedDate;
  bool _releaseSafeMode = true;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    _commissionRateController.text = _formatCommissionRate(commissionRate);
    _loadSavedData();
    _initializeAds();
    _setupInAppPurchaseListeners();
  }

  void _initializeAds() {
    if (kIsWeb) return; // Skip on web
    if (!(Platform.isAndroid || Platform.isIOS)) return; // Ads only on mobile
    try {
      AdMobHelper.loadBannerAd((ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
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
      _purchaseSubscription?.cancel();
      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        (purchases) {
          for (final purchase in purchases) {
            if (purchase.productID == InAppPurchaseHelper.monthlyProProductId) {
              if (purchase.status == PurchaseStatus.purchased) {
                unawaited(_handlePurchaseSuccess());
              }
            }
          }
        },
        onError: (error) {
          debugPrint('Purchase stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('In-App Purchase listener setup skipped: $e');
    }
  }

  Future<void> _handlePurchaseSuccess() async {
    try {
      await InAppPurchaseHelper.verifyAndUnlockPremium();
      if (!mounted) return;
      setState(() => isPremium = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium Unlocked! Enjoy unlimited saves.'),
        ),
      );
    } catch (e) {
      debugPrint('Purchase unlock failed: $e');
    }
  }

  double get commissionSavings {
    return _calculatedPropertyValue * (_calculatedCommissionRate / 100);
  }

  double get autoClosingCosts {
    return _calculatedPropertyValue *
        (_calculatedProvinceClosingCostRate / 100);
  }

  double get closingCostSavings {
    if (_usedManualClosingCosts) {
      return _calculatedManualClosingCosts;
    }
    return autoClosingCosts;
  }

  double get totalSavings => commissionSavings + closingCostSavings;

  double get _estimatedSellerCostsTotal =>
      commissionSavings + closingCostSavings;

  double get _sellerLegalNotaryEstimate {
    final ratio = _calculatedProvince == 'QC' ? 0.35 : 0.28;
    return closingCostSavings * ratio;
  }

  double get _sellerMortgageDischargeEstimate {
    final ratio = _calculatedProvince == 'QC' ? 0.20 : 0.17;
    return closingCostSavings * ratio;
  }

  double get _sellerMovingSetupEstimate {
    final ratio = _calculatedProvince == 'QC' ? 0.25 : 0.30;
    return closingCostSavings * ratio;
  }

  double get _sellerTaxAdjustmentsEstimate {
    return closingCostSavings -
        _sellerLegalNotaryEstimate -
        _sellerMortgageDischargeEstimate -
        _sellerMovingSetupEstimate;
  }

  double get _estimatedSellerNetBeforeMortgage {
    return _calculatedPropertyValue - _estimatedSellerCostsTotal;
  }

  double? _parseLooseNumber(String raw) {
    final cleaned = raw
        .replaceAll(',', '')
        .replaceAll('\$', '')
        .replaceAll('%', '')
        .replaceAll(' ', '')
        .trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double get _liveProvinceClosingCostRate {
    return CanadaProvinceRates.defaults[selectedProvince]?.closingCostRate ??
        1.5;
  }

  double? get _liveAutoClosingCost {
    final salePrice = _parseLooseNumber(propertyValue);
    if (salePrice == null || salePrice <= 0) {
      return null;
    }
    return salePrice * (_liveProvinceClosingCostRate / 100);
  }

  String _formatCommissionRate(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  void _adjustCommissionRate(double delta) {
    final nextRate = (commissionRate + delta).clamp(1.0, 7.0).toDouble();
    setState(() {
      commissionRate = double.parse(nextRate.toStringAsFixed(1));
    });
    _syncCommissionRateField();
  }

  void _syncCommissionRateField() {
    final formatted = _formatCommissionRate(commissionRate);
    if (_commissionRateController.text == formatted) {
      return;
    }
    _commissionRateController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _onCommissionRateChanged(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return;
    }

    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 1.0 || parsed > 7.0) {
      return;
    }

    setState(() {
      commissionRate = double.parse(parsed.toStringAsFixed(1));
    });
  }

  void _commitCommissionRateInput() {
    final value = _commissionRateController.text.trim();
    final parsed = double.tryParse(value);

    if (parsed == null) {
      _syncCommissionRateField();
      return;
    }

    final clamped = parsed.clamp(1.0, 7.0).toDouble();
    setState(() {
      commissionRate = double.parse(clamped.toStringAsFixed(1));
    });
    _syncCommissionRateField();
  }

  void _calculateSavings() {
    final parsedPropertyValue = _parseLooseNumber(propertyValue);
    if (parsedPropertyValue == null || parsedPropertyValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid estimated sale price (numbers only, commas are okay).',
          ),
        ),
      );
      return;
    }

    final provinceRate =
        CanadaProvinceRates.defaults[selectedProvince]?.closingCostRate ?? 1.5;
    final manualClosingCosts = _parseLooseNumber(closingCosts);

    setState(() {
      _hasCalculated = true;
      _calculatedPropertyValue = parsedPropertyValue;
      _calculatedCommissionRate = commissionRate;
      _calculatedProvince = selectedProvince;
      _calculatedProvinceClosingCostRate = provinceRate;
      _usedManualClosingCosts =
          closingCosts.trim().isNotEmpty && manualClosingCosts != null;
      _calculatedManualClosingCosts = manualClosingCosts ?? 0;
    });
  }

  void _saveCalculation() async {
    try {
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

      final prefs = await SharedPreferences.getInstance();
      final provinceName =
          CanadaProvinceRates.labels[selectedProvince] ?? selectedProvince;
      final calc =
          'Province: $provinceName, Property: \$$propertyValue, Commission: ${_formatCommissionRate(commissionRate)}%, Savings: \$${totalSavings.toStringAsFixed(2)}';
      savedCalculations.add(calc);
      calculationCount++;
      await prefs.setStringList('calculations', savedCalculations);
      await prefs.setInt('calculationCount', calculationCount);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get('savedMessage', widget.language)),
        ),
      );
    } catch (e) {
      debugPrint('Save calculation failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'fr'
                ? 'Echec de la sauvegarde. Reessayez.'
                : 'Save failed. Please try again.',
          ),
        ),
      );
    }
  }

  void _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        savedCalculations = prefs.getStringList('calculations') ?? [];
        calculationCount = prefs.getInt('calculationCount') ?? 0;
        isPremium = prefs.getBool('isPremium') ?? false;
        _releaseSafeMode = prefs.getBool('releaseSafeMode') ?? true;
      });
    } catch (e) {
      debugPrint('Saved data load failed: $e');
    }
  }

  Future<T?> _safePush<T>(Route<T> route, String scope) async {
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError(scope, e, st));
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'fr'
                ? 'Navigation indisponible. Réessayez.'
                : 'Navigation unavailable. Please try again.',
          ),
        ),
      );
      return null;
    }
  }

  void _upgradeToPremium() async {
    final unlocked = await _safePush<bool>(
      MaterialPageRoute(
        builder: (context) => PaywallPage(language: widget.language),
      ),
      'upgrade_to_premium_nav',
    );

    if (unlocked == true && mounted) {
      setState(() => isPremium = true);
    }
  }

  void _openPremiumWithFeedback() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          widget.language == 'fr' ? 'Ouverture Premium…' : 'Opening Premium…',
        ),
      ),
    );
    _upgradeToPremium();
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
              _openPremiumWithFeedback();
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
    _safePush<void>(
      MaterialPageRoute(
        builder: (context) => FeaturesOverviewPage(language: widget.language),
      ),
      'navigate_features_overview',
    );
  }

  void _navigateToLegalRights() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LegalRightsPage(language: widget.language),
      ),
    );
  }

  void _navigateToBuyerCosts() {
    if (!isPremium) {
      unawaited(
        AppAnalytics.logEvent(
          'paywall_opened_from_buyer_costs',
          params: {'screen': 'home'},
        ),
      );
      _showPremiumDialog();
      return;
    }

    unawaited(
      AppAnalytics.logEvent(
        'buyer_costs_opened',
        params: {'province': selectedProvince},
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeBuyingCostsPage(
          language: widget.language,
          initialProvince: selectedProvince,
        ),
      ),
    );
  }

  void _navigateToBuyerQaMatrix() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BuyerQaMatrixPage(language: widget.language),
      ),
    );
  }

  void _navigateToAnalyticsDebug() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsDebugPage(language: widget.language),
      ),
    );
  }

  void _navigateToRuntimeDiagnostics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RuntimeDiagnosticsPage(language: widget.language),
      ),
    );
  }

  Future<void> _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(language: widget.language),
      ),
    );
    if (!mounted) return;
    _loadSavedData();
  }

  void _navigateToLaunchReadiness() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LaunchReadinessPage(language: widget.language),
      ),
    );
  }

  void _navigateToStoreSubmissionText() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoreSubmissionPage(language: widget.language),
      ),
    );
  }

  Future<void> _copyLaunchChecklist() async {
    final checklist = _isFr
        ? 'Checklist de lancement (impact eleve > faible)\n'
              '1) Validation juridique ON/QC/BC\n'
              '2) QA des achats et restaurations premium\n'
              '3) Matrice QA premier acheteur vs acheteur repetitif\n'
              '4) Verifier PDF/partage/impression des avis\n'
              '5) Activer suivi analytique + surveillance crash\n'
              '6) Polissage bilingue final (EN/FR)\n'
              '7) Captures magasin + politique + support\n'
              '8) Soft launch + ajustements'
        : 'Launch Checklist (Highest to Lowest Impact)\n'
              '1) Legal validation for ON/QC/BC\n'
              '2) Premium purchase + restore QA\n'
              '3) First-time vs repeat buyer QA matrix\n'
              '4) Verify notice PDF/share/print flows\n'
              '5) Enable analytics + crash monitoring\n'
              '6) Final bilingual polish (EN/FR)\n'
              '7) Store assets + privacy policy + support\n'
              '8) Soft launch + iteration';

    await Clipboard.setData(ClipboardData(text: checklist));
    await AppAnalytics.logEvent('launch_checklist_copied');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr ? 'Checklist de lancement copié.' : 'Launch checklist copied.',
        ),
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

  bool get _isFr => widget.language == 'fr';

  String get _regionalRightsTitle => _isFr
      ? 'Droits de retrait régionaux (au 31 mars 2026)'
      : 'Regional Exit Rights (As of Mar 31, 2026)';

  String get _regionalRightsQcLine => _isFr
      ? 'QC • Retrait 3 jours (OACIQ) • Sortie Courtier: 0 \$.'
      : 'QC • 3-Day Withdrawal (OACIQ) • The Broker Exit: \$0.';

  String get _regionalRightsOnLine => _isFr
      ? 'ON • Délai de réflexion 10 jours (condos) • Sortie Neuf: 0 \$.'
      : 'ON • 10-Day Cooling Off (Condos) • The New-Build Exit: \$0.';

  String get _regionalRightsBcLine => _isFr
      ? 'BC • Rétractation 3 jours (HBRP) • Frais obligatoires de 0,25 %.'
      : 'BC • 3-Day Rescission (HBRP) • Mandatory 0.25% fee.';

  String get _legalInfoOnly => _isFr
      ? 'Information seulement, pas un avis juridique.'
      : 'Informational only, not legal advice.';

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
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
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

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  DateTime _moveDeadlineToMondayIfWeekend(DateTime date) {
    if (date.weekday == DateTime.saturday) {
      return date.add(const Duration(days: 2));
    }
    if (date.weekday == DateTime.sunday) {
      return date.add(const Duration(days: 1));
    }
    return date;
  }

  DateTime _quebecWithdrawalDeadline(DateTime signedDuplicateReceivedDate) {
    // OACIQ rule in app: clock starts the day after receipt.
    final thirdDay = signedDuplicateReceivedDate.add(const Duration(days: 3));
    return _moveDeadlineToMondayIfWeekend(thirdDay);
  }

  DateTime _addBusinessDays(DateTime fromDate, int businessDays) {
    var cursor = fromDate;
    var added = 0;
    while (added < businessDays) {
      cursor = cursor.add(const Duration(days: 1));
      if (cursor.weekday != DateTime.saturday &&
          cursor.weekday != DateTime.sunday) {
        added++;
      }
    }
    return cursor;
  }

  String _buildOntarioCoolingOffMessage(DateTime dateReceivedAllDocs) {
    final now = DateTime.now();
    final deadline = dateReceivedAllDocs.add(const Duration(days: 10));

    if (now.isBefore(deadline)) {
      final hoursLeft = deadline.difference(now).inHours;
      return 'ONTARIO SHIELD ACTIVE: You have $hoursLeft hours to get your deposit back.';
    }

    return '10-day window expired. You are now legally bound to the developer.';
  }

  String _buildQuebecBrokerExitMessage(DateTime brokerageSignedDate) {
    final now = DateTime.now();
    final deadline = _quebecWithdrawalDeadline(brokerageSignedDate);

    if (now.isBefore(deadline)) {
      final hoursLeft = deadline.difference(now).inHours;
      return 'BROKER EXIT ACTIVE: You have $hoursLeft hours left to cancel for \$0. Clock started the day after receipt; if day 3 lands on weekend, deadline moves to Monday.';
    }

    return 'Quebec 3-day brokerage cancellation window has expired.';
  }

  String _buildBcRescissionMessage(
    DateTime contractAcceptedDate,
    double purchasePrice,
  ) {
    final now = DateTime.now();
    final deadline = _addBusinessDays(contractAcceptedDate, 3);
    final rescissionFee = purchasePrice * 0.0025;

    if (now.isBefore(deadline)) {
      final hoursLeft = deadline.difference(now).inHours;
      return '3-DAY RESCISSION ACTIVE: You have $hoursLeft hours left (business-day clock). Fee to cancel now: \$${rescissionFee.toStringAsFixed(2)} (0.25%, mandatory and non-negotiable).';
    }

    return 'BC 3-day rescission window has expired.';
  }

  // Ontario 10-day cooling-off checker
  void checkOntarioStatus(DateTime dateFullyExecuted) {
    final message = _buildOntarioCoolingOffMessage(dateFullyExecuted);
    debugPrint(message);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void checkOntarioCoolingOff(DateTime dateReceivedAllDocs) {
    checkOntarioStatus(dateReceivedAllDocs);
  }

  void checkQuebecBrokerExit(DateTime brokerageSignedDate) {
    final message = _buildQuebecBrokerExitMessage(brokerageSignedDate);
    debugPrint(message);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void checkBcRescission(DateTime contractAcceptedDate, double purchasePrice) {
    final message = _buildBcRescissionMessage(
      contractAcceptedDate,
      purchasePrice,
    );
    debugPrint(message);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String getOntarioAdvice(bool isCondo) {
    if (isCondo) {
      return '10-DAY SHIELD ACTIVE: You have 10 calendar days to cancel this condo purchase for free. Critical gotcha: an amended disclosure may reset the 10-day clock.';
    } else {
      return 'STATUS: DELAYED. The 10-day cooling-off for houses starts Jan 1, 2027. You may be FIRM once you sign!';
    }
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
    _syncCommissionRateField();
  }

  @override
  void dispose() {
    _commissionRateController.dispose();
    _purchaseSubscription?.cancel();
    bannerAd?.dispose();
    AdMobHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOnline,
      builder: (context, isOnline, _) => Scaffold(
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
                        'Welcome to Contract Shield',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Estimate your selling and buying costs with confidence',
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
                      if (value != null) {
                        _setProvinceDefaults(value);
                        FocusScope.of(context).unfocus();
                      }
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      closingCosts.trim().isNotEmpty
                          ? 'Using manual closing costs value.'
                          : (_liveAutoClosingCost == null
                                ? 'Auto-estimated closing cost will appear after entering sale price.'
                                : 'Auto-estimated closing cost: \$${_liveAutoClosingCost!.toStringAsFixed(2)} (${_liveProvinceClosingCostRate.toStringAsFixed(1)}%)'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
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
                            'Agent Commission: ${_formatCommissionRate(commissionRate)}%',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          color: const Color(0xFF1E88E5),
                          onPressed: commissionRate > 1.0
                              ? () => _adjustCommissionRate(-0.5)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          color: const Color(0xFF1E88E5),
                          onPressed: commissionRate < 7.0
                              ? () => _adjustCommissionRate(0.5)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextFormField(
                      controller: _commissionRateController,
                      decoration: const InputDecoration(
                        labelText: 'Enter commission %',
                        hintText: 'e.g., 2.5',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,1}$'),
                        ),
                      ],
                      onChanged: _onCommissionRateChanged,
                      onEditingComplete: _commitCommissionRateInput,
                      onFieldSubmitted: (_) => _commitCommissionRateInput(),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _calculateSavings,
                        icon: const Icon(Icons.calculate),
                        label: const Text('Calculate Savings'),
                      ),
                    ),
                  ),
                ]),

                if (_hasCalculated) ...[
                  // ── Section: Summary ─────────────────────────────────
                  _sectionHeader('Summary'),
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
                      'Estimated real estate agent commission',
                      '\$${commissionSavings.toStringAsFixed(2)}',
                    ),
                    const Divider(height: 1),
                    // Estimated closing costs row
                    _savingsRow(
                      'Estimated closing cost (${(CanadaProvinceRates.defaults[_calculatedProvince]?.closingCostRate ?? 1.5).toStringAsFixed(1)}%)',
                      '\$${autoClosingCosts.toStringAsFixed(2)}',
                    ),
                    if (_usedManualClosingCosts) ...[
                      const Divider(height: 1),
                      _savingsRow(
                        'Closing costs (manual override)',
                        '\$${closingCostSavings.toStringAsFixed(2)}',
                      ),
                    ],
                    const Divider(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'Estimated Seller Cost Breakdown',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _savingsRow(
                      'Legal / notary',
                      '\$${_sellerLegalNotaryEstimate.toStringAsFixed(2)}',
                    ),
                    _savingsRow(
                      'Mortgage discharge / admin',
                      '\$${_sellerMortgageDischargeEstimate.toStringAsFixed(2)}',
                    ),
                    _savingsRow(
                      'Moving / setup buffer',
                      '\$${_sellerMovingSetupEstimate.toStringAsFixed(2)}',
                    ),
                    _savingsRow(
                      'Tax and adjustment buffer',
                      '\$${_sellerTaxAdjustmentsEstimate.toStringAsFixed(2)}',
                    ),
                    const Divider(height: 20),
                    _savingsRow(
                      'Estimated total seller costs',
                      '\$${_estimatedSellerCostsTotal.toStringAsFixed(2)}',
                    ),
                    _savingsRow(
                      'Estimated net before mortgage payoff',
                      '\$${_estimatedSellerNetBeforeMortgage.toStringAsFixed(2)}',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Text(
                        'For buying-cost line items (land transfer tax, legal/notary, inspection, appraisal, insurance, and cash needed), open Down Payment & Buyer Costs.',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _navigateToBuyerCosts,
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          label: const Text('Open Buyer Cost Breakdown'),
                        ),
                      ),
                    ),
                  ]),
                ] else
                  _sectionCard([
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      child: Text(
                        'Enter values above, then tap Calculate Savings to see your summary.',
                        style: TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ),
                  ]),

                // ── Province note ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.grey[600],
                      ),
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

                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _regionalRightsTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _regionalRightsQcLine,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1B5E20),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _regionalRightsOnLine,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1B5E20),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _regionalRightsBcLine,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1B5E20),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _legalInfoOnly,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF33691E),
                        ),
                      ),
                    ],
                  ),
                ),

                if (selectedProvince == 'QC')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00838F).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00838F).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr
                              ? 'Sortie Courtier Québec (droit OACIQ de 3 jours)'
                              : 'Quebec Broker Exit (OACIQ 3-Day Right)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF006064),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isFr
                              ? 'Annulez un contrat de courtage en 3 jours pour 0 \$.'
                              : 'Cancel any brokerage contract in 3 days for \$0.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF006064),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isFr
                              ? 'Gotcha: le delai commence le lendemain de la reception de la copie signee. Si le 3e jour tombe samedi ou dimanche, echeance repoussee au lundi.'
                              : 'Gotcha: clock starts the day after receiving the signed duplicate. If day 3 lands on Saturday/Sunday, deadline moves to Monday.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF006064),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _quebecBrokerageSignedDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );

                            if (picked != null) {
                              setState(
                                () => _quebecBrokerageSignedDate = picked,
                              );
                              checkQuebecBrokerExit(picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _quebecBrokerageSignedDate == null
                                ? (_isFr
                                      ? 'Définir la date du contrat de courtage'
                                      : 'Set Brokerage Contract Date')
                                : (_isFr
                                      ? 'Signé: ${_formatDate(_quebecBrokerageSignedDate!)}'
                                      : 'Signed: ${_formatDate(_quebecBrokerageSignedDate!)}'),
                          ),
                        ),
                        if (_quebecBrokerageSignedDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _buildQuebecBrokerExitMessage(
                              _quebecBrokerageSignedDate!,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF006064),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (selectedProvince == 'BC')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF6A1B9A).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr
                              ? 'Rétractation 3 jours C.-B. (Property Law Act)'
                              : 'BC 3-Day Rescission (Property Law Act)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A148C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isFr
                              ? 'Annulez une transaction résidentielle en 3 jours avec des frais de 0,25 %.'
                              : 'Cancel any residential deal in 3 days for a 0.25% fee.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A148C),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isFr
                              ? 'Gotcha: c\'est 3 jours ouvrables. Les frais de 0,25 % sont obligatoires et non negociables.'
                              : 'Gotcha: this is 3 business days. The 0.25% fee is mandatory and cannot be negotiated away.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4A148C),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _bcContractAcceptedDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );

                            if (picked != null) {
                              final purchasePrice =
                                  double.tryParse(propertyValue) ?? 0;
                              setState(() => _bcContractAcceptedDate = picked);
                              checkBcRescission(picked, purchasePrice);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _bcContractAcceptedDate == null
                                ? (_isFr
                                      ? 'Définir la date d\'acceptation du contrat'
                                      : 'Set Accepted Contract Date')
                                : (_isFr
                                      ? 'Accepté: ${_formatDate(_bcContractAcceptedDate!)}'
                                      : 'Accepted: ${_formatDate(_bcContractAcceptedDate!)}'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (double.tryParse(propertyValue) ?? 0) > 0
                              ? (_isFr
                                    ? 'Estimation actuelle des frais 0,25 %: \$${((double.tryParse(propertyValue) ?? 0) * 0.0025).toStringAsFixed(2)}'
                                    : 'Current 0.25% fee estimate: \$${((double.tryParse(propertyValue) ?? 0) * 0.0025).toStringAsFixed(2)}')
                              : (_isFr
                                    ? 'Entrez le prix de vente ci-dessus pour estimer les frais de rétractation de 0,25 %.'
                                    : 'Enter sale price above to estimate the 0.25% rescission fee.'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4A148C),
                            height: 1.4,
                          ),
                        ),
                        if (_bcContractAcceptedDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _buildBcRescissionMessage(
                              _bcContractAcceptedDate!,
                              double.tryParse(propertyValue) ?? 0,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A148C),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (selectedProvince == 'ON')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ontario 10-Day Cooling-Off Timer',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Property Type:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: const Text('Condo'),
                              selected: _ontarioIsCondo,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() => _ontarioIsCondo = true);
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('House'),
                              selected: !_ontarioIsCondo,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() => _ontarioIsCondo = false);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          getOntarioAdvice(_ontarioIsCondo),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0D47A1),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _ontarioDocsReceivedDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );

                            if (picked != null) {
                              setState(() => _ontarioDocsReceivedDate = picked);
                              checkOntarioCoolingOff(picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            _ontarioDocsReceivedDate == null
                                ? 'Set Date Received (All Docs)'
                                : 'Date Received: ${_formatDate(_ontarioDocsReceivedDate!)}',
                          ),
                        ),
                        if (_ontarioDocsReceivedDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _buildOntarioCoolingOffMessage(
                              _ontarioDocsReceivedDate!,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0D47A1),
                              height: 1.4,
                            ),
                          ),
                        ],
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
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _navigateToLegalRights,
                    icon: const Icon(Icons.gavel),
                    label: Text(
                      _isFr
                          ? 'Droits de retrait par province'
                          : 'Legal Rights by Province',
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _navigateToBuyerCosts,
                    icon: Icon(isPremium ? Icons.home_work : Icons.lock),
                    label: Text(
                      _isFr
                          ? 'Mise de fonds et frais d\'achat'
                          : 'Down Payment & Buyer Costs',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToBuyerQaMatrix,
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: Text(
                      _isFr
                          ? 'Matrice QA acheteur (ON/QC/BC)'
                          : 'Buyer QA Matrix (ON/QC/BC)',
                    ),
                  ),
                ),
                if (!_releaseSafeMode) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _navigateToAnalyticsDebug,
                      icon: const Icon(Icons.analytics_outlined),
                      label: Text(
                        _isFr
                            ? 'Tableau analytique (debug)'
                            : 'Analytics Dashboard (Debug)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _navigateToRuntimeDiagnostics,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: Text(
                        _isFr ? 'Diagnostics runtime' : 'Runtime Diagnostics',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyLaunchChecklist,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: Text(
                      _isFr
                          ? 'Copier checklist lancement'
                          : 'Copy Launch Checklist',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(_isFr ? 'Parametres' : 'Settings'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToLaunchReadiness,
                    icon: const Icon(Icons.task_alt_outlined),
                    label: Text(
                      _isFr
                          ? 'Etat de preparation lancement'
                          : 'Launch Readiness',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToStoreSubmissionText,
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(
                      _isFr
                          ? 'Texte de soumission magasin'
                          : 'Store Submission Text',
                    ),
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
                      onPressed: _openPremiumWithFeedback,
                      icon: const Icon(Icons.star),
                      label: const Text('Unlock Premium'),
                      style: ElevatedButton.styleFrom(
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getString('copyright'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

  void _showTipDetails(BuildContext context, int index, String tip) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          language == 'fr' ? 'Conseil ${index + 1}' : 'Tip ${index + 1}',
        ),
        content: Text(tip),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(language == 'fr' ? 'Fermer' : 'Close'),
          ),
        ],
      ),
    );
  }

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
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showTipDetails(context, index, tips[index]),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
  final GlobalKey<SfSignaturePadState> _signaturePadKey =
      GlobalKey<SfSignaturePadState>();
  final _ownerCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _mlsCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  DateTime _contractDate = DateTime.now();
  bool _generating = false;
  bool _hasSignature = false;
  DateTime? _signatureSignedAt;
  Uint8List? _lastPdfBytes;
  String? _lastPdfPath;
  String? _lastPdfName;

  bool get _isFr => widget.language == 'fr';
  String _pdfText(String en, String fr) => _isFr ? fr : en;

  String _formatSignatureTimestamp(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd $hh:$min';
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _brokerCtrl.dispose();
    _addressCtrl.dispose();
    _mlsCtrl.dispose();
    _purchasePriceCtrl.dispose();
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
    final signatureBytes = await _captureRequiredSignatureBytes();
    if (signatureBytes == null) return;

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
                  _pdfText('NOTICE OF TERMINATION', 'AVIS DE RESILIATION'),
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
                  _pdfText(
                    'Based on OACIQ Clause 2.1 - Contract Resiliation',
                    'Base sur la clause 2.1 de l\'OACIQ - Resiliation du contrat',
                  ),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.Divider(height: 24),
              pw.SizedBox(height: 8),
              _pdfRow(
                _pdfText('Date of Notice:', 'Date de l\'avis :'),
                todayStr,
              ),
              _pdfRow(
                _pdfText('Property Owner:', 'Proprietaire :'),
                _ownerCtrl.text,
              ),
              _pdfRow(_pdfText('Broker:', 'Courtier :'), _brokerCtrl.text),
              _pdfRow(
                _pdfText('Property Address:', 'Adresse de la propriete :'),
                _addressCtrl.text,
              ),
              if (_mlsCtrl.text.trim().isNotEmpty)
                _pdfRow(_pdfText('MLS Number:', 'Numero MLS :'), _mlsCtrl.text),
              _pdfRow(
                _pdfText(
                  'Brokerage Contract Date:',
                  'Date du contrat de courtage :',
                ),
                dateStr,
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  _pdfText(
                    'Pursuant to Clause 2.1 of the brokerage contract, I/we hereby formally notify you of my/our intention to terminate the above-referenced brokerage contract for the sale of the property described herein. This notice is served in accordance with the rights and obligations established under the Real Estate Brokerage Act (REBA) and the OACIQ standard forms.',
                    'En vertu de la clause 2.1 du contrat de courtage, je/nous vous avisons formellement de notre intention de resilier le contrat de courtage susmentionne pour la vente de la propriete decrite ci-dessus.',
                  ),
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
                ),
              ),
              pw.SizedBox(height: 32),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfSignatureSection(signatureBytes),
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
                      pw.Text(
                        _pdfText('Date', 'Date'),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  _pdfText(
                    'Generated by Contract Shield © 2026 - This document is for informational purposes only. Consult a legal professional.',
                    'Genere par Contract Shield © 2026 - Ce document est fourni a titre informatif seulement. Consultez un professionnel du droit.',
                  ),
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

      if (mounted) {
        setState(() {
          _lastPdfBytes = bytes;
          _lastPdfPath = file.path;
          _lastPdfName = 'notice_of_termination_$todayStr.pdf';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF generated. Use Print or Share below.'),
          ),
        );
      }
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

  Future<void> _printLastPdf() async {
    if (_lastPdfBytes == null || _lastPdfName == null) return;
    try {
      final printName = _lastPdfName!;
      await Printing.layoutPdf(
        name: printName,
        onLayout: (format) async => _lastPdfBytes!,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> _shareLastPdf() async {
    if (_lastPdfPath == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_lastPdfPath!)],
          text: 'Notice of Termination - Contract Shield',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<Uint8List?> _captureSignatureBytes() async {
    final signatureState = _signaturePadKey.currentState;
    if (signatureState == null) return null;

    try {
      final signatureImage = await signatureState.toImage(pixelRatio: 3.0);
      final byteData = await signatureImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _captureRequiredSignatureBytes() async {
    if (!_hasSignature) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pdfText(
              'A signature is required before generating or sharing a PDF.',
              'Une signature est requise avant de generer ou partager un PDF.',
            ),
          ),
        ),
      );
      return null;
    }

    _signatureSignedAt ??= DateTime.now();

    return _captureSignatureBytes();
  }

  pw.Widget _buildPdfSignatureSection(Uint8List signatureBytes) {
    final signedAt = _signatureSignedAt ?? DateTime.now();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 24),
        pw.Container(
          width: 180,
          height: 60,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(
            pw.MemoryImage(signatureBytes),
            width: 160,
            height: 50,
            fit: pw.BoxFit.contain,
          ),
        ),
        pw.Container(
          width: 180,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
          ),
          height: 1,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _pdfText('Authorized Signature', 'Signature autorisee'),
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          _pdfText(
            'Signed: ${_formatSignatureTimestamp(signedAt)}',
            'Signe le : ${_formatSignatureTimestamp(signedAt)}',
          ),
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  void _clearSignature() {
    _signaturePadKey.currentState?.clear();
    setState(() {
      _hasSignature = false;
      _signatureSignedAt = null;
    });
  }

  // Builds an Ontario rescission notice PDF and opens the native share menu.
  Future<void> shareOntarioNotice(
    String buyerName,
    String propertyAddress,
  ) async {
    if (buyerName.trim().isEmpty || propertyAddress.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buyer name and property address are required.'),
        ),
      );
      return;
    }

    final signatureBytes = await _captureRequiredSignatureBytes();
    if (signatureBytes == null) return;

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) => pw.Center(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfText('NOTICE OF RESCISSION', 'AVIS DE RESILIATION'),
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  '${_pdfText('Property', 'Propriete')}: $propertyAddress',
                ),
                pw.Text('${_pdfText('Buyer', 'Acheteur')}: $buyerName'),
                pw.SizedBox(height: 20),
                pw.Text(
                  _pdfText(
                    'Pursuant to Section 73 of the Ontario Condominium Act, I hereby exercise my right to rescind this agreement within the applicable cooling-off period. This notice is delivered to formally communicate the rescission decision in writing.',
                    'Conformement a l\'article 73 de la Loi sur les condominiums de l\'Ontario, j\'exerce par les presentes mon droit de resilier cette convention dans le delai de reflexion applicable. Cet avis est transmis afin de communiquer formellement par ecrit la decision de resilier.',
                  ),
                  style: const pw.TextStyle(fontSize: 12, lineSpacing: 3),
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    border: pw.Border.all(color: PdfColors.blue200),
                  ),
                  child: pw.Text(
                    _isFr
                        ? 'Point critique : le delai de reflexion est de 10 jours calendrier, et non de jours ouvrables. Si l\'acheteur recoit une declaration modifiee, l\'horloge de 10 jours peut etre reinitialisee.'
                        : 'Critical gotcha: the cooling-off period is 10 calendar days, not business days. If the buyer receives an amended disclosure statement, the 10-day clock may reset.',
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                  ),
                ),
                _buildPdfSignatureSection(signatureBytes),
              ],
            ),
          ),
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'Ontario_Rescission.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ontario notice share failed: $e')),
      );
    }
  }

  Future<void> shareQuebecNotice(
    String ownerName,
    String propertyAddress,
  ) async {
    if (ownerName.trim().isEmpty || propertyAddress.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Owner name and property address are required.'),
        ),
      );
      return;
    }

    final signatureBytes = await _captureRequiredSignatureBytes();
    if (signatureBytes == null) return;

    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _pdfText(
                  'NOTICE OF BROKERAGE CANCELLATION',
                  'AVIS D\'ANNULATION DU COURTAGE',
                ),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('${_pdfText('Date', 'Date')}: $today'),
              pw.Text('${_pdfText('Property', 'Propriete')}: $propertyAddress'),
              pw.Text('${_pdfText('Owner', 'Proprietaire')}: $ownerName'),
              pw.SizedBox(height: 18),
              pw.Text(
                _pdfText(
                  'I hereby provide written notice that I am cancelling the brokerage contract within the applicable cancellation period under Quebec brokerage rules (OACIQ framework).',
                  'Je donne par la presente un avis ecrit indiquant que j\'annule le contrat de courtage dans le delai de resiliation applicable selon les regles de courtage au Quebec (cadre OACIQ).',
                ),
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 3),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.cyan50,
                  border: pw.Border.all(color: PdfColors.cyan200),
                ),
                child: pw.Text(
                  _isFr
                      ? 'Point critique : le delai de retrait de 3 jours commence le lendemain de la reception de la copie signee. Le samedi compte comme jour non juridique; si le 3e jour tombe un samedi ou un dimanche, l\'echeance est repousse au lundi.'
                      : 'Critical gotcha: the 3-day withdrawal clock starts the day after you receive the signed duplicate. Saturdays count as non-juridical days, so if day 3 falls on Saturday or Sunday, the deadline moves to Monday.',
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                ),
              ),
              _buildPdfSignatureSection(signatureBytes),
            ],
          ),
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'Quebec_Broker_Cancellation.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Quebec notice share failed: $e')));
    }
  }

  Future<void> shareBcNotice(
    String buyerName,
    String propertyAddress,
    double purchasePrice,
  ) async {
    if (buyerName.trim().isEmpty || propertyAddress.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buyer name and property address are required.'),
        ),
      );
      return;
    }

    final signatureBytes = await _captureRequiredSignatureBytes();
    if (signatureBytes == null) return;

    if (purchasePrice <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid purchase price to calculate BC fee.'),
        ),
      );
      return;
    }

    try {
      final fee = purchasePrice * 0.0025;
      final pdf = pw.Document();
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _pdfText(
                  'BC NOTICE OF RESCISSION',
                  'AVIS DE RESILIATION C.-B.',
                ),
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('${_pdfText('Date', 'Date')}: $today'),
              pw.Text('${_pdfText('Property', 'Propriete')}: $propertyAddress'),
              pw.Text('${_pdfText('Buyer', 'Acheteur')}: $buyerName'),
              pw.Text(
                '${_pdfText('Purchase Price', 'Prix d\'achat')}: \$${purchasePrice.toStringAsFixed(2)}',
              ),
              pw.Text(
                '${_pdfText('Rescission Fee (0.25%)', 'Frais de resiliation (0,25 %)')}: \$${fee.toStringAsFixed(2)}',
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                _pdfText(
                  'I hereby exercise my rescission right within the BC statutory rescission period for residential real estate transactions and acknowledge the 0.25% rescission fee.',
                  'J\'exerce par les presentes mon droit de resiliation dans le delai legal applicable en Colombie-Britannique pour les transactions immobilieres residentielles et je reconnais les frais de resiliation de 0,25 %.',
                ),
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 3),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.purple50,
                  border: pw.Border.all(color: PdfColors.purple200),
                ),
                child: pw.Text(
                  _isFr
                      ? 'Point critique : en C.-B., la periode de retractation est de 3 jours ouvrables. Les frais de 0,25 % sont obligatoires et ne peuvent pas etre negocies, meme si le vendeur est d\'accord.'
                      : 'Critical gotcha: the BC rescission period is 3 business days. The 0.25% rescission fee is mandatory and cannot be negotiated away, even if the seller agrees.',
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                ),
              ),
              _buildPdfSignatureSection(signatureBytes),
            ],
          ),
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'BC_Rescission_Notice.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('BC notice share failed: $e')));
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _purchasePriceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Purchase Price (for BC 0.25% fee)',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
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
              const SizedBox(height: 20),
              Text(
                _pdfText('SIGNATURE', 'SIGNATURE'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Listener(
                    onPointerDown: (_) {
                      setState(() {
                        _hasSignature = true;
                        _signatureSignedAt = DateTime.now();
                      });
                    },
                    child: SfSignaturePad(
                      key: _signaturePadKey,
                      backgroundColor: Colors.white,
                      minimumStrokeWidth: 1.5,
                      maximumStrokeWidth: 3.0,
                      strokeColor: const Color(0xFF283593),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pdfText(
                        'Sign below with your finger or stylus. Your signature will be added to the generated PDF.',
                        'Signez ci-dessous avec votre doigt ou un stylet. Votre signature sera ajoutee au PDF genere.',
                      ),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _clearSignature,
                    icon: const Icon(Icons.clear),
                    label: Text(_pdfText('Clear', 'Effacer')),
                  ),
                ],
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_generating || _lastPdfBytes == null)
                          ? null
                          : _printLastPdf,
                      icon: const Icon(Icons.print),
                      label: const Text('Print PDF'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_generating || _lastPdfPath == null)
                          ? null
                          : _shareLastPdf,
                      icon: const Icon(Icons.share),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generating
                      ? null
                      : () => shareOntarioNotice(
                          _ownerCtrl.text,
                          _addressCtrl.text,
                        ),
                  icon: const Icon(Icons.gavel),
                  label: const Text('Share Ontario Rescission Notice'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generating
                      ? null
                      : () => shareQuebecNotice(
                          _ownerCtrl.text,
                          _addressCtrl.text,
                        ),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Share Quebec Broker Cancellation'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generating
                      ? null
                      : () => shareBcNotice(
                          _ownerCtrl.text,
                          _addressCtrl.text,
                          double.tryParse(_purchasePriceCtrl.text) ?? 0,
                        ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Share BC Rescission Notice (0.25% fee)'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Generate first, then tap Print or Share.',
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

  void _showFeatureDetails(
    BuildContext context,
    String title,
    String desc,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(desc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(language == 'fr' ? 'Fermer' : 'Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFr = language == 'fr';

    final localizedFeatures = <({String title, String desc, IconData icon, Color color, bool opensPaywall})>[
      (
        title: isFr ? 'Calculateur d\'économies' : 'Savings Calculator',
        desc: isFr
            ? 'Estimez en temps réel les économies de commission et de frais de clôture.'
            : 'Estimate commission and closing-cost savings in real time.',
        icon: Icons.calculate,
        color: const Color(0xFF2E7D32),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Paramètres provinciaux' : 'Province Defaults',
        desc: isFr
            ? 'Utilise des taux par défaut selon la province au Canada.'
            : 'Uses Canada province-specific default commission and closing-cost rates.',
        icon: Icons.map,
        color: const Color(0xFF1565C0),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Sauvegarde et historique' : 'Save & History',
        desc: isFr
            ? 'Sauvegardez vos calculs et consultez-les dans l\'historique.'
            : 'Save calculations and review them later in the History screen.',
        icon: Icons.history,
        color: const Color(0xFF6A1B9A),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'PDF d\'avis de résiliation' : 'Termination Notice PDF',
        desc: isFr
            ? 'Générez et partagez un PDF officiel d\'avis de résiliation.'
            : 'Generate and share a formal Notice of Termination PDF.',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFFC62828),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Scanner de contrat' : 'Contract Scanner',
        desc: isFr
            ? 'Scannez une image de contrat et détectez des clauses risquées. Caméra sur mobile, galerie sur ordinateur.'
            : 'Scan contract images and flag risky words like irrevocable clauses. Camera on mobile, gallery on desktop.',
        icon: Icons.document_scanner,
        color: const Color(0xFFEF6C00),
        opensPaywall: false,
      ),
      (
        title: isFr
            ? 'Mise de fonds et frais d\'achat'
            : 'Down Payment & Buyer Costs',
        desc: isFr
            ? 'Outil Premium pour estimer la mise de fonds minimale, la cible de 20 % et les frais d\'achat d\'une maison.'
            : 'Premium tool to estimate minimum down payment, the 20% target, and key home-buying expenses.',
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF2E7D32),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Matrice QA acheteur' : 'Buyer QA Matrix',
        desc: isFr
            ? 'Vérification rapide des scénarios premiers acheteurs et acheteurs répétitifs pour ON, QC et BC.'
            : 'Quick validation scenarios for first-time and repeat buyers in ON, QC, and BC.',
        icon: Icons.rule_folder_outlined,
        color: const Color(0xFF455A64),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Conseils vendeur' : 'Home Selling Tips',
        desc: isFr
            ? 'Conseils guidés pour vendre sans courtier inscripteur.'
            : 'Guided tips for selling without a listing agent.',
        icon: Icons.lightbulb,
        color: const Color(0xFFF9A825),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Anglais / Français' : 'English / French',
        desc: isFr
            ? 'Changez la langue depuis le menu de l\'application.'
            : 'Switch language from the app menu.',
        icon: Icons.language,
        color: const Color(0xFF00838F),
        opensPaywall: false,
      ),
      (
        title: isFr ? 'Mise à niveau Premium' : 'Premium Upgrade',
        desc: isFr
            ? 'Le plan gratuit a des limites; Premium débloque les sauvegardes illimitées.'
            : 'Free plan has limits; premium unlocks unlimited saved calculations.',
        icon: Icons.workspace_premium,
        color: const Color(0xFF8D6E63),
        opensPaywall: true,
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
                onTap: feature.opensPaywall
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                PaywallPage(language: language),
                          ),
                        );
                      }
                    : () => _showFeatureDetails(
                        context,
                        feature.title,
                        feature.desc,
                        feature.color,
                      ),
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
                trailing: feature.opensPaywall
                    ? const Icon(Icons.open_in_new, size: 18)
                    : null,
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

class StoreSubmissionPage extends StatelessWidget {
  final String language;

  const StoreSubmissionPage({super.key, this.language = 'en'});

  bool get _isFr => language == 'fr';

  String get _appleEn =>
      'App Name: Contract Shield\n'
      'Subtitle: Buyer costs and contract tools\n\n'
      'Promotional Text:\n'
      'Estimate buyer costs, scan contracts for red flags, and prepare key real-estate documents for Ontario, Quebec, and British Columbia.\n\n'
      'Description:\n'
      'Contract Shield helps Canadian consumers make clearer, more confident real-estate decisions. '
      'Built for Ontario, Quebec, and British Columbia, the app supports both first-time and repeat buyers while also helping sellers estimate potential savings.\n\n'
      'Core Features:\n'
      '- Estimate buyer closing costs in ON, QC, and BC\n'
      '- Compare first-time and repeat buyer scenarios\n'
      '- Estimate seller savings with province-aware defaults\n'
      '- Scan contract images and flag risky language\n'
      '- Generate PDF reports and notice documents\n'
      '- English and French language support\n\n'
      'Keywords:\n'
      'real estate canada,closing costs,buyer calculator,contract scan,first time buyer,fsbo,ontario';

  String get _googleEn =>
      'App Name: Contract Shield\n'
      'Short Description: Buyer costs, contract scans, and legal-info tools for ON, QC, and BC.\n\n'
      'Full Description:\n'
      'Contract Shield is a Canadian real-estate helper for Ontario, Quebec, and British Columbia. '
      'Use it to estimate buyer closing costs, compare first-time and repeat buyer scenarios, and evaluate seller savings with province-aware defaults. '
      'You can also scan contracts for risky language, review cancellation and rescission information workflows, and generate PDF reports and notices.';

  String get _appleFr =>
      'Nom: Contract Shield\n'
      'Sous-titre: Frais d\'achat et outils contrat\n\n'
      'Texte promotionnel:\n'
      'Estimez vos frais d\'achat, analysez des contrats et preparez des documents immobiliers pour l\'Ontario, le Quebec et la Colombie-Britannique.\n\n'
      'Description:\n'
      'Contract Shield aide les consommateurs canadiens a prendre des decisions immobilieres plus claires et plus sures. '
      'L\'application prend en charge les premiers acheteurs et les acheteurs repetitifs tout en aidant aussi les vendeurs a estimer leurs economies potentielles.';

  String get _googleFr =>
      'Nom: Contract Shield\n'
      'Description courte: Frais d\'achat, analyse de contrat et outils d\'info juridique pour ON, QC et BC.\n\n'
      'Description complete:\n'
      'Contract Shield est un outil immobilier canadien pour l\'Ontario, le Quebec et la Colombie-Britannique. '
      'L\'application permet d\'estimer les frais d\'achat, de comparer les scenarios pour premiers acheteurs et acheteurs repetitifs, '
      'et d\'analyser des contrats pour reperer des termes a risque.';

  Future<void> _copyAll(BuildContext context) async {
    final text = _isFr
        ? 'Apple App Store (FR)\n\n$_appleFr\n\nGoogle Play (FR)\n\n$_googleFr'
        : 'Apple App Store (EN)\n\n$_appleEn\n\nGoogle Play (EN)\n\n$_googleEn';

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Texte de soumission copie dans le presse-papiers.'
              : 'Submission text copied to clipboard.',
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            SelectableText(body, style: const TextStyle(height: 1.35)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFr ? 'Texte soumission magasin' : 'Store Submission Text',
        ),
        actions: [
          IconButton(
            onPressed: () => _copyAll(context),
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _isFr ? 'Copier le texte' : 'Copy text',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              _isFr
                  ? 'Utilisez cette page pour copier le texte de soumission App Store et Google Play.'
                  : 'Use this page to copy your App Store and Google Play submission text.',
            ),
          ),
          const SizedBox(height: 12),
          _section(
            _isFr ? 'Apple App Store (FR)' : 'Apple App Store (EN)',
            _isFr ? _appleFr : _appleEn,
          ),
          _section(
            _isFr ? 'Google Play (FR)' : 'Google Play (EN)',
            _isFr ? _googleFr : _googleEn,
          ),
        ],
      ),
    );
  }
}

class HomeBuyingCostsPage extends StatefulWidget {
  final String language;
  final String initialProvince;

  const HomeBuyingCostsPage({
    super.key,
    this.language = 'en',
    required this.initialProvince,
  });

  @override
  State<HomeBuyingCostsPage> createState() => _HomeBuyingCostsPageState();
}

class _HomeBuyingCostsPageState extends State<HomeBuyingCostsPage> {
  final TextEditingController _purchasePriceCtrl = TextEditingController();
  final TextEditingController _customDownPaymentCtrl = TextEditingController();
  static const List<String> _supportedBuyerProvinces = ['ON', 'QC', 'BC'];
  late String _selectedProvince;
  String _buyerProfile = 'repeat';

  bool get _isFirstTimeBuyer => _buyerProfile == 'first';

  bool get _isFr => widget.language == 'fr';

  double get _purchasePrice =>
      double.tryParse(_purchasePriceCtrl.text.replaceAll(',', '').trim()) ?? 0;

  double get _customDownPayment =>
      double.tryParse(_customDownPaymentCtrl.text.replaceAll(',', '').trim()) ??
      0;

  @override
  void initState() {
    super.initState();
    _selectedProvince =
        _supportedBuyerProvinces.contains(widget.initialProvince)
        ? widget.initialProvince
        : 'ON';
    unawaited(
      AppAnalytics.logEvent(
        'buyer_costs_screen_view',
        params: {'province': _selectedProvince, 'lang': widget.language},
      ),
    );
  }

  @override
  void dispose() {
    _purchasePriceCtrl.dispose();
    _customDownPaymentCtrl.dispose();
    super.dispose();
  }

  double _minimumDownPayment(double price) {
    if (price <= 500000) return price * 0.05;
    if (price < 1000000) return 25000 + ((price - 500000) * 0.10);
    return price * 0.20;
  }

  double _targetTwentyPercentDown(double price) => price * 0.20;

  double _estimatedMortgageInsurance(double price, double downPayment) {
    if (price <= 0) return 0;
    final downRatio = downPayment / price;
    if (downRatio >= 0.20) return 0;

    final mortgageAmount = price - downPayment;
    final premiumRate = downRatio >= 0.15
        ? 0.028
        : downRatio >= 0.10
        ? 0.031
        : 0.040;
    return mortgageAmount * premiumRate;
  }

  double _estimateTransferTax(double price, String province) {
    double tiered(List<({double limit, double rate})> brackets) {
      var total = 0.0;
      var lower = 0.0;
      for (final bracket in brackets) {
        if (price <= lower) break;
        final taxable = (price < bracket.limit ? price : bracket.limit) - lower;
        if (taxable > 0) total += taxable * bracket.rate;
        lower = bracket.limit;
      }
      return total;
    }

    switch (province) {
      case 'ON':
        return tiered([
          (limit: 55000, rate: 0.005),
          (limit: 250000, rate: 0.01),
          (limit: 400000, rate: 0.015),
          (limit: 2000000, rate: 0.02),
          (limit: double.infinity, rate: 0.025),
        ]);
      case 'BC':
        return tiered([
          (limit: 200000, rate: 0.01),
          (limit: 2000000, rate: 0.02),
          (limit: 3000000, rate: 0.03),
          (limit: double.infinity, rate: 0.05),
        ]);
      case 'QC':
        return tiered([
          (limit: 55200, rate: 0.005),
          (limit: 276200, rate: 0.01),
          (limit: 500000, rate: 0.015),
          (limit: double.infinity, rate: 0.02),
        ]);
      default:
        final rate =
            (CanadaProvinceRates.defaults[province]?.closingCostRate ?? 1.5) /
            100;
        return price * rate * 0.35;
    }
  }

  double _estimateFirstTimeBuyerRebate(
    double price,
    String province,
    double transferTax,
  ) {
    if (!_isFirstTimeBuyer || price <= 0) return 0;

    switch (province) {
      case 'ON':
        return transferTax < 4000 ? transferTax : 4000;
      case 'BC':
        if (price <= 500000) return transferTax;
        if (price > 525000) return 0;
        final factor = (525000 - price) / 25000;
        return transferTax * factor;
      case 'QC':
        return transferTax < 1500 ? transferTax : 1500;
      default:
        return 0;
    }
  }

  Future<void> _saveBuyerCostReport({
    required double price,
    required double minDown,
    required double selectedDown,
    required double netClosing,
    required double cashNeeded,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('calculations') ?? [];
    final provinceName =
        CanadaProvinceRates.labels[_selectedProvince] ?? _selectedProvince;
    final buyerTypeLabel = _isFirstTimeBuyer
        ? (_isFr ? 'Premier acheteur' : 'First-time buyer')
        : (_isFr ? 'Acheteur repetitif' : 'Repeat buyer');
    final report =
        'Buyer Cost Report [$provinceName][$buyerTypeLabel] - Price: ${_money(price)}, Min Down: ${_money(minDown)}, Selected Down: ${_money(selectedDown)}, Closing: ${_money(netClosing)}, Cash Needed: ${_money(cashNeeded)}';
    list.add(report);
    await prefs.setStringList('calculations', list);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Rapport acheteur sauvegarde dans l\'historique.'
              : 'Buyer cost report saved to History.',
        ),
      ),
    );
  }

  double get _legalNotary => _selectedProvince == 'QC' ? 1900 : 1800;
  double get _inspection => 600;
  double get _appraisal => 450;
  double get _titleInsurance => _selectedProvince == 'QC' ? 0 : 350;
  double get _movingSetup => 1500;
  double get _taxAdjustments => _purchasePrice * 0.0015;

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  Widget _costRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: emphasize ? const Color(0xFF1B5E20) : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = _purchasePrice;
    final minDownPayment = price > 0 ? _minimumDownPayment(price) : 0.0;
    final targetDownPayment = price > 0 ? _targetTwentyPercentDown(price) : 0.0;
    final selectedDownPaymentRaw = _customDownPayment > 0
        ? _customDownPayment
        : minDownPayment;
    final selectedDownPayment = selectedDownPaymentRaw < 0
        ? 0.0
        : (selectedDownPaymentRaw > price ? price : selectedDownPaymentRaw);
    final transferTax = price > 0
        ? _estimateTransferTax(price, _selectedProvince)
        : 0.0;
    final closingCostsGross =
        transferTax +
        _legalNotary +
        _inspection +
        _appraisal +
        _titleInsurance +
        _movingSetup +
        _taxAdjustments;
    final firstTimeBuyerRebate = price > 0
        ? _estimateFirstTimeBuyerRebate(price, _selectedProvince, transferTax)
        : 0.0;
    final closingCosts = (closingCostsGross - firstTimeBuyerRebate) < 0
        ? 0.0
        : (closingCostsGross - firstTimeBuyerRebate);
    final mortgageInsurance = price > 0
        ? _estimatedMortgageInsurance(price, minDownPayment)
        : 0.0;
    final mortgageInsuranceForSelected = price > 0
        ? _estimatedMortgageInsurance(price, selectedDownPayment)
        : 0.0;
    final cashNeededSelected = selectedDownPayment + closingCosts;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFr
              ? 'Mise de fonds et frais d\'achat'
              : 'Down Payment & Buyer Costs',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              _isFr
                  ? 'Outil Premium pour estimer la mise de fonds minimale, l\'objectif de 20 % et les principaux frais a payer pour acheter une maison.'
                  : 'Premium tool to estimate the minimum down payment, the 20% target, and the main costs you may need to pay when buying a home.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedProvince,
            decoration: InputDecoration(
              labelText: _isFr ? 'Province' : 'Province',
              prefixIcon: const Icon(Icons.map),
            ),
            items: _supportedBuyerProvinces
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
              if (value == null) return;
              setState(() => _selectedProvince = value);
              unawaited(
                AppAnalytics.logEvent(
                  'buyer_costs_province_changed',
                  params: {'province': value},
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            _isFr
                ? 'Version de depart ciblee: Ontario, Quebec et Colombie-Britannique.'
                : 'Starter scope: Ontario, Quebec, and British Columbia.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _purchasePriceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _isFr
                  ? 'Prix d\'achat de la propriete'
                  : 'Property purchase price',
              prefixIcon: const Icon(Icons.attach_money),
              hintText: _isFr ? 'Ex. 650000' : 'e.g. 650000',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _customDownPaymentCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _isFr
                  ? 'Mise de fonds personnalisee (optionnel)'
                  : 'Custom down payment (optional)',
              prefixIcon: const Icon(Icons.savings),
              hintText: _isFr ? 'Ex. 120000' : 'e.g. 120000',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            _isFr ? 'Profil acheteur' : 'Buyer profile',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(_isFr ? 'Premier acheteur' : 'First-time buyer'),
                selected: _buyerProfile == 'first',
                onSelected: (_) {
                  setState(() => _buyerProfile = 'first');
                  unawaited(
                    AppAnalytics.logEvent(
                      'buyer_profile_selected',
                      params: {'profile': 'first_time'},
                    ),
                  );
                },
              ),
              ChoiceChip(
                label: Text(_isFr ? 'Acheteur repetitif' : 'Repeat buyer'),
                selected: _buyerProfile == 'repeat',
                onSelected: (_) {
                  setState(() => _buyerProfile = 'repeat');
                  unawaited(
                    AppAnalytics.logEvent(
                      'buyer_profile_selected',
                      params: {'profile': 'repeat'},
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isFirstTimeBuyer
                ? (_isFr
                      ? 'Les rabais estimes pour premiers acheteurs peuvent s\'appliquer selon la province et l\'admissibilite.'
                      : 'Estimated first-time buyer rebates may apply based on province and eligibility.')
                : (_isFr
                      ? 'Mode acheteur repetitif: aucun rabais premier acheteur applique.'
                      : 'Repeat buyer mode: no first-time buyer rebate is applied.'),
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          if (price <= 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _isFr
                      ? 'Entrez un prix d\'achat pour voir la mise de fonds minimale, les frais de transfert, les frais juridiques, l\'inspection, l\'evaluation et le total estime a prevoir.'
                      : 'Enter a purchase price to see the minimum down payment, transfer tax estimate, legal/notary fees, inspection, appraisal, and the total cash you may need.',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFr ? 'Mise de fonds' : 'Down Payment',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _costRow(
                      _isFr
                          ? 'Mise de fonds minimale requise'
                          : 'Minimum down payment required',
                      _money(minDownPayment),
                      emphasize: true,
                    ),
                    _costRow(
                      _isFr
                          ? 'Cible recommandee (20 %)'
                          : 'Recommended target (20%)',
                      _money(targetDownPayment),
                    ),
                    _costRow(
                      _isFr
                          ? 'Prime d\'assurance hypothecaire estimee'
                          : 'Estimated mortgage insurance premium',
                      _money(mortgageInsurance),
                    ),
                    _costRow(
                      _isFr
                          ? 'Mise de fonds utilisee (comparaison)'
                          : 'Selected down payment (comparison)',
                      _money(selectedDownPayment),
                    ),
                    _costRow(
                      _isFr
                          ? 'Prime assurance avec mise perso'
                          : 'Insurance premium with selected down payment',
                      _money(mortgageInsuranceForSelected),
                    ),
                    if (_customDownPayment > 0 &&
                        selectedDownPayment < minDownPayment)
                      Text(
                        _isFr
                            ? 'La mise personnalisee est sous le minimum requis. Le minimum legal est indique ci-dessus.'
                            : 'Custom down payment is below the minimum requirement. Legal minimum is shown above.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFC62828),
                        ),
                      ),
                    Text(
                      _isFr
                          ? 'La prime d\'assurance hypothecaire est souvent ajoutee au pret plutot que payee en entier a la cloture.'
                          : 'Mortgage insurance is often added to the mortgage instead of being paid fully at closing.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFr
                          ? 'Frais d\'achat estimes'
                          : 'Estimated Buying Costs',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _costRow(
                      _isFr
                          ? 'Taxe de transfert / droits'
                          : 'Transfer tax / duties',
                      _money(transferTax),
                    ),
                    if (_isFirstTimeBuyer)
                      _costRow(
                        _isFr
                            ? 'Rabais estime premier acheteur'
                            : 'Estimated first-time buyer rebate',
                        '-${_money(firstTimeBuyerRebate)}',
                      ),
                    _costRow(
                      _isFr
                          ? 'Frais juridiques / notaire'
                          : 'Legal / notary fees',
                      _money(_legalNotary),
                    ),
                    _costRow(
                      _isFr ? 'Inspection de la maison' : 'Home inspection',
                      _money(_inspection),
                    ),
                    _costRow(
                      _isFr ? 'Evaluation bancaire' : 'Appraisal',
                      _money(_appraisal),
                    ),
                    _costRow(
                      _isFr ? 'Assurance titres' : 'Title insurance',
                      _money(_titleInsurance),
                    ),
                    _costRow(
                      _isFr
                          ? 'Deménagement / branchements'
                          : 'Moving / setup buffer',
                      _money(_movingSetup),
                    ),
                    _costRow(
                      _isFr
                          ? 'Ajustements de taxes et services'
                          : 'Tax and utility adjustments',
                      _money(_taxAdjustments),
                    ),
                    const Divider(height: 20),
                    _costRow(
                      _isFr
                          ? 'Total estimatif des frais'
                          : 'Estimated total closing costs',
                      _money(closingCosts),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isFr ? 'Argent a prevoir' : 'Cash You May Need',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _money(cashNeededSelected),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isFr
                        ? _isFirstTimeBuyer
                              ? 'Mise de fonds choisie + frais d\'achat estimes (apres rabais).'
                              : 'Mise de fonds choisie + frais d\'achat estimes.'
                        : _isFirstTimeBuyer
                        ? 'Selected down payment plus estimated closing costs (after rebate).'
                        : 'Selected down payment plus estimated closing costs.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(
                  AppAnalytics.logEvent(
                    'buyer_cost_report_saved',
                    params: {
                      'province': _selectedProvince,
                      'profile': _isFirstTimeBuyer ? 'first_time' : 'repeat',
                    },
                  ),
                );
                _saveBuyerCostReport(
                  price: price,
                  minDown: minDownPayment,
                  selectedDown: selectedDownPayment,
                  netClosing: closingCosts,
                  cashNeeded: cashNeededSelected,
                );
              },
              icon: const Icon(Icons.save),
              label: Text(
                _isFr
                    ? 'Sauvegarder le rapport acheteur'
                    : 'Save Buyer Cost Report',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isFr
                  ? 'Estimation seulement. Les taxes de transfert, rabais pour premiers acheteurs, frais du preteur et ajustements peuvent varier selon la province, la municipalite et l\'immeuble.'
                  : 'Estimate only. Transfer taxes, first-time buyer rebates, lender fees, and adjustments vary by province, municipality, and property type.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }
}

class LegalRightsPage extends StatelessWidget {
  final String language;

  const LegalRightsPage({super.key, this.language = 'en'});

  @override
  Widget build(BuildContext context) {
    final isFr = language == 'fr';

    final cards =
        <
          ({
            String region,
            String law,
            String feature,
            String detail,
            String gotcha,
            Color color,
          })
        >[
          (
            region: isFr ? 'Quebec' : 'Quebec',
            law: isFr
                ? 'Retrait 3 jours (OACIQ) - au 31 mars 2026'
                : '3-Day Withdrawal (OACIQ) - As of Mar 31, 2026',
            feature: isFr ? 'Sortie Courtier' : 'The Broker Exit',
            detail: isFr
                ? 'Annulez un contrat de courtage en 3 jours pour 0 \$.'
                : 'Cancel any brokerage contract in 3 days for \$0.',
            gotcha: isFr
                ? 'Le delai commence le lendemain de la reception de la copie signee. Si le 3e jour est samedi ou dimanche, l\'echeance passe au lundi.'
                : 'Clock starts the day after you receive the signed duplicate. If day 3 falls on Saturday or Sunday, deadline moves to Monday.',
            color: const Color(0xFF00838F),
          ),
          (
            region: isFr ? 'Ontario' : 'Ontario',
            law: isFr
                ? 'Délai de réflexion 10 jours (condos) - au 31 mars 2026'
                : '10-Day Cooling Off (Condos) - As of Mar 31, 2026',
            feature: isFr ? 'Sortie Neuf' : 'The New-Build Exit',
            detail: isFr
                ? '10 jours pour annuler un condo neuf pour 0 \$.'
                : '10 days to walk away from a new condo for \$0.',
            gotcha: isFr
                ? 'C\'est 10 jours calendrier (pas ouvrables). Une divulgation modifiee peut reinitialiser l\'horloge de 10 jours.'
                : 'It is 10 calendar days, not business days. An amended disclosure may reset the 10-day clock.',
            color: const Color(0xFF1565C0),
          ),
          (
            region: isFr ? 'Colombie-Britannique' : 'British Columbia',
            law: isFr
                ? 'Rétractation 3 jours (HBRP) - au 31 mars 2026'
                : '3-Day Rescission (HBRP) - As of Mar 31, 2026',
            feature: isFr
                ? 'Droit de rétractation 3 jours'
                : 'The 3-Day Rescission',
            detail: isFr
                ? 'Annulez une transaction résidentielle avec des frais de 0,25 %.'
                : 'Cancel any residential deal for a 0.25% fee.',
            gotcha: isFr
                ? 'Le delai est de 3 jours ouvrables. Les frais de 0,25 % sont obligatoires et non negociables.'
                : 'It is 3 business days. The 0.25% fee is mandatory and cannot be negotiated away.',
            color: const Color(0xFF6A1B9A),
          ),
        ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isFr ? 'Droits de retrait par province' : 'Legal Rights by Province',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              isFr
                  ? 'Vue rapide des droits de retrait provinciaux inclus dans cette application.'
                  : 'Quick view of provincial walk-away rights included in this app.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          ...cards.map(
            (card) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: card.color,
                          child: const Icon(
                            Icons.gavel,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            card.region,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${isFr ? 'La loi' : 'The Law'}: ${card.law}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: card.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isFr ? 'Fonction' : 'Feature'}: ${card.feature}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(card.detail, style: const TextStyle(height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                      '${isFr ? 'Le point critique' : 'The Critical Gotcha'}: ${card.gotcha}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: card.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFr
                ? 'Astuce: utilisez l\'écran principal pour les minuteurs ON/QC/BC et l\'écran Avis de résiliation pour partager les PDF Ontario, Québec et C.-B.'
                : 'Tip: use the main calculator screen for ON/QC/BC timers and the Termination screen to share Ontario, Quebec, and BC notice PDFs.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Text(
              isFr
                  ? 'Information seulement. Cette application ne constitue pas un avis juridique. Consultez un avocat immobilier ou un notaire autorisé dans votre province.'
                  : 'Informational only. This app does not provide legal advice. Consult a licensed real estate lawyer or notary in your province.',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class BuyerQaMatrixPage extends StatefulWidget {
  final String language;

  const BuyerQaMatrixPage({super.key, this.language = 'en'});

  @override
  State<BuyerQaMatrixPage> createState() => _BuyerQaMatrixPageState();
}

class _BuyerQaMatrixPageState extends State<BuyerQaMatrixPage> {
  bool get _isFr => widget.language == 'fr';

  final List<({String province, String profile, double price})> _scenarios =
      const [
        (province: 'ON', profile: 'first', price: 368000.0),
        (province: 'ON', profile: 'first', price: 500000.0),
        (province: 'ON', profile: 'repeat', price: 500000.0),
        (province: 'ON', profile: 'repeat', price: 950000.0),
        (province: 'QC', profile: 'first', price: 300000.0),
        (province: 'QC', profile: 'first', price: 450000.0),
        (province: 'QC', profile: 'repeat', price: 450000.0),
        (province: 'QC', profile: 'repeat', price: 780000.0),
        (province: 'BC', profile: 'first', price: 500000.0),
        (province: 'BC', profile: 'first', price: 515000.0),
        (province: 'BC', profile: 'first', price: 525000.0),
        (province: 'BC', profile: 'repeat', price: 515000.0),
        (province: 'BC', profile: 'repeat', price: 800000.0),
      ];

  final Map<String, String> _statusByKey = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final TextEditingController _testerNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDefaultTesterName();
    unawaited(
      AppAnalytics.logEvent(
        'buyer_qa_screen_view',
        params: {'lang': widget.language},
      ),
    );
  }

  Future<void> _loadDefaultTesterName() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultName = prefs.getString('defaultTesterName') ?? '';
    if (!mounted) return;
    _testerNameCtrl.text = defaultName;
  }

  String _scenarioKey(String province, String profile, double price) {
    return '$province-$profile-${price.toStringAsFixed(0)}';
  }

  String _statusFor(String key) => _statusByKey[key] ?? 'na';

  TextEditingController _noteControllerFor(String key) {
    return _noteControllers.putIfAbsent(key, () => TextEditingController());
  }

  String get _testerName {
    final value = _testerNameCtrl.text.trim();
    if (value.isEmpty) {
      return _isFr ? 'Non indiqué' : 'Not provided';
    }
    return value;
  }

  String _buildContextLine() {
    final mode = kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug');
    if (kIsWeb) {
      return 'platform=web | mode=$mode';
    }
    final osVersion = Platform.operatingSystemVersion
        .replaceAll('\n', ' ')
        .trim();
    return 'platform=${Platform.operatingSystem} | mode=$mode | os=$osVersion';
  }

  double _estimateTransferTax(double price, String province) {
    double tiered(List<({double limit, double rate})> brackets) {
      var total = 0.0;
      var lower = 0.0;
      for (final bracket in brackets) {
        if (price <= lower) break;
        final taxable = (price < bracket.limit ? price : bracket.limit) - lower;
        if (taxable > 0) total += taxable * bracket.rate;
        lower = bracket.limit;
      }
      return total;
    }

    switch (province) {
      case 'ON':
        return tiered([
          (limit: 55000, rate: 0.005),
          (limit: 250000, rate: 0.01),
          (limit: 400000, rate: 0.015),
          (limit: 2000000, rate: 0.02),
          (limit: double.infinity, rate: 0.025),
        ]);
      case 'BC':
        return tiered([
          (limit: 200000, rate: 0.01),
          (limit: 2000000, rate: 0.02),
          (limit: 3000000, rate: 0.03),
          (limit: double.infinity, rate: 0.05),
        ]);
      case 'QC':
        return tiered([
          (limit: 55200, rate: 0.005),
          (limit: 276200, rate: 0.01),
          (limit: 500000, rate: 0.015),
          (limit: double.infinity, rate: 0.02),
        ]);
      default:
        return 0;
    }
  }

  double _firstTimeRebate(double price, String province, double transferTax) {
    switch (province) {
      case 'ON':
        return transferTax < 4000 ? transferTax : 4000;
      case 'BC':
        if (price <= 500000) return transferTax;
        if (price >= 525000) return 0;
        final factor = (525000 - price) / 25000;
        return transferTax * factor;
      case 'QC':
        return transferTax < 1500 ? transferTax : 1500;
      default:
        return 0;
    }
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  int get _passCount =>
      _statusByKey.values.where((status) => status == 'pass').length;
  int get _failCount =>
      _statusByKey.values.where((status) => status == 'fail').length;

  @override
  void dispose() {
    _testerNameCtrl.dispose();
    for (final ctrl in _noteControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<List<String>> _loadQaHistoryEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final calculations = prefs.getStringList('calculations') ?? [];
    return calculations
        .where((entry) => entry.startsWith('Buyer QA Run'))
        .toList();
  }

  Future<void> _saveQaRunToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final calculations = prefs.getStringList('calculations') ?? [];
    final total = _scenarios.length;
    final failWithNotes = _statusByKey.entries.where((entry) {
      if (entry.value != 'fail') return false;
      final note = _noteControllerFor(entry.key).text.trim();
      return note.isNotEmpty;
    }).length;
    final buildContext = _buildContextLine();
    final timestamp = DateTime.now().toIso8601String();
    final summary =
        'Buyer QA Run [ON/QC/BC] - Tester: $_testerName - Passed: $_passCount/$total - Failed: $_failCount - Fail Notes: $failWithNotes - Date: $timestamp - $buildContext';
    calculations.add(summary);
    await prefs.setStringList('calculations', calculations);
    await AppAnalytics.logEvent(
      'buyer_qa_saved',
      params: {
        'passed': '$_passCount',
        'failed': '$_failCount',
        'total': '$total',
        'tester': _testerName,
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Exécution QA sauvegardée dans l\'historique.'
              : 'QA run saved to History.',
        ),
      ),
    );
  }

  Future<void> _shareQaPdf() async {
    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _isFr
                    ? 'Rapport Matrice QA Acheteur (ON/QC/BC)'
                    : 'Buyer QA Matrix Report (ON/QC/BC)',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_isFr ? 'Date' : 'Date'}: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              ),
              pw.Text(
                _isFr
                    ? 'Résultat: $_passCount/${_scenarios.length} réussis'
                    : 'Result: $_passCount/${_scenarios.length} passed',
              ),
              pw.Text(
                '${_isFr ? 'Testeur' : 'Tester'}: $_testerName',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                _isFr
                    ? 'Contexte appareil/build: ${_buildContextLine()}'
                    : 'Device/build context: ${_buildContextLine()}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 14),
              ..._scenarios.map((scenario) {
                final transferTax = _estimateTransferTax(
                  scenario.price,
                  scenario.province,
                );
                final rebate = scenario.profile == 'first'
                    ? _firstTimeRebate(
                        scenario.price,
                        scenario.province,
                        transferTax,
                      )
                    : 0.0;
                final netTax = (transferTax - rebate) < 0
                    ? 0.0
                    : (transferTax - rebate);
                final key = _scenarioKey(
                  scenario.province,
                  scenario.profile,
                  scenario.price,
                );
                final status = _statusFor(key);
                final note = _noteControllerFor(key).text.trim();

                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(
                    '${scenario.province} | ${scenario.profile} | ${_money(scenario.price)} | tax ${_money(transferTax)} | rebate ${_money(rebate)} | net ${_money(netTax)} | ${status.toUpperCase()}${note.isNotEmpty ? ' | note: $note' : ''}',
                  ),
                );
              }),
            ],
          );
        },
      ),
    );

    await AppAnalytics.logEvent(
      'buyer_qa_pdf_shared',
      params: {
        'passed': '$_passCount',
        'failed': '$_failCount',
        'total': '${_scenarios.length}',
        'tester': _testerName,
      },
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Buyer_QA_ON_QC_BC.pdf',
    );
  }

  Future<void> _exportQaHistoryCsv() async {
    final qaEntries = await _loadQaHistoryEntries();

    String esc(String input) => '"${input.replaceAll('"', '""')}"';

    final rows = <String>['entry'];
    for (final entry in qaEntries) {
      rows.add(esc(entry));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/contract_shield_qa_history.csv');
    await file.writeAsString(rows.join('\n'));

    await AppAnalytics.logEvent(
      'buyer_qa_history_csv_exported',
      params: {'rows': '${qaEntries.length}', 'tester': _testerName},
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: _isFr
            ? 'Export CSV de l\'historique QA acheteur.'
            : 'Buyer QA history CSV export.',
      ),
    );
  }

  Future<void> _shareQaHistoryPdf() async {
    final qaEntries = await _loadQaHistoryEntries();
    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            _isFr
                ? 'Historique des exécutions QA acheteur'
                : 'Buyer QA Run History',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${_isFr ? 'Exporté le' : 'Exported on'}: ${now.toIso8601String()}',
          ),
          pw.Text('${_isFr ? 'Testeur' : 'Tester'}: $_testerName'),
          pw.SizedBox(height: 12),
          ...qaEntries.map(
            (entry) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(entry, style: const pw.TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );

    await AppAnalytics.logEvent(
      'buyer_qa_history_pdf_shared',
      params: {'rows': '${qaEntries.length}', 'tester': _testerName},
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Buyer_QA_History.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFr ? 'Matrice QA acheteur' : 'Buyer QA Matrix'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.22)),
            ),
            child: Text(
              _isFr
                  ? 'Validez les sorties clés pour premiers acheteurs et acheteurs répétitifs dans ON/QC/BC.'
                  : 'Validate key outputs for first-time and repeat buyers across ON/QC/BC.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _testerNameCtrl,
            decoration: InputDecoration(
              labelText: _isFr
                  ? 'Nom du testeur (optionnel)'
                  : 'Tester name (optional)',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ..._scenarios.map((scenario) {
            final transferTax = _estimateTransferTax(
              scenario.price,
              scenario.province,
            );
            final rebate = scenario.profile == 'first'
                ? _firstTimeRebate(
                    scenario.price,
                    scenario.province,
                    transferTax,
                  )
                : 0.0;
            final netTax = (transferTax - rebate) < 0
                ? 0.0
                : (transferTax - rebate);
            final key = _scenarioKey(
              scenario.province,
              scenario.profile,
              scenario.price,
            );
            final status = _statusFor(key);
            final noteCtrl = _noteControllerFor(key);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFr
                          ? '${scenario.profile == 'first' ? 'Premier acheteur' : 'Acheteur repetitif'} • ${scenario.province} • Prix ${_money(scenario.price)}'
                          : '${scenario.profile == 'first' ? 'First-time buyer' : 'Repeat buyer'} • ${scenario.province} • Price ${_money(scenario.price)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isFr
                          ? 'Taxe: ${_money(transferTax)} | Rabais: ${_money(rebate)} | Net: ${_money(netTax)}'
                          : 'Tax: ${_money(transferTax)} | Rebate: ${_money(rebate)} | Net: ${_money(netTax)}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(_isFr ? 'Réussi' : 'Pass'),
                          selected: status == 'pass',
                          onSelected: (_) {
                            setState(() => _statusByKey[key] = 'pass');
                            unawaited(
                              AppAnalytics.logEvent(
                                'buyer_qa_result_marked',
                                params: {
                                  'province': scenario.province,
                                  'profile': scenario.profile,
                                  'status': 'pass',
                                },
                              ),
                            );
                          },
                        ),
                        ChoiceChip(
                          label: Text(_isFr ? 'Échec' : 'Fail'),
                          selected: status == 'fail',
                          onSelected: (_) {
                            setState(() => _statusByKey[key] = 'fail');
                            unawaited(
                              AppAnalytics.logEvent(
                                'buyer_qa_result_marked',
                                params: {
                                  'province': scenario.province,
                                  'profile': scenario.profile,
                                  'status': 'fail',
                                },
                              ),
                            );
                          },
                        ),
                        ChoiceChip(
                          label: Text(_isFr ? 'Non marqué' : 'Not marked'),
                          selected: status == 'na',
                          onSelected: (_) {
                            setState(() => _statusByKey[key] = 'na');
                            unawaited(
                              AppAnalytics.logEvent(
                                'buyer_qa_result_marked',
                                params: {
                                  'province': scenario.province,
                                  'profile': scenario.profile,
                                  'status': 'na',
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (status == 'fail') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: _isFr
                              ? 'Note d\'échec (optionnel)'
                              : 'Fail note (optional)',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          unawaited(
                            AppAnalytics.logEvent(
                              'buyer_qa_fail_note_updated',
                              params: {
                                'province': scenario.province,
                                'profile': scenario.profile,
                                'has_note': value.trim().isNotEmpty
                                    ? 'true'
                                    : 'false',
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              _isFr
                  ? 'Progression QA: $_passCount réussis, $_failCount échecs, ${_scenarios.length - _passCount - _failCount} non marqués.'
                  : 'QA progress: $_passCount passed, $_failCount failed, ${_scenarios.length - _passCount - _failCount} not marked.',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveQaRunToHistory,
                  icon: const Icon(Icons.save),
                  label: Text(_isFr ? 'Sauvegarder QA' : 'Save QA Run'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareQaPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(_isFr ? 'Partager PDF' : 'Share PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportQaHistoryCsv,
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(_isFr ? 'CSV historique QA' : 'QA History CSV'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareQaHistoryPdf,
                  icon: const Icon(Icons.history_edu_outlined),
                  label: Text(_isFr ? 'PDF historique QA' : 'QA History PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String language;

  const SettingsPage({super.key, this.language = 'en'});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _testerDefaultCtrl = TextEditingController();
  final TextEditingController _supportEmailCtrl = TextEditingController();
  bool _legalReviewed = false;
  bool _storeAssetsReady = false;
  bool _supportReady = false;
  bool _purchaseQaReady = false;
  bool _deviceQaReady = false;
  bool _privacyPolicyReady = false;
  bool _releaseSafeMode = true;
  bool get _isFr => widget.language == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _testerDefaultCtrl.text = prefs.getString('defaultTesterName') ?? '';
    _supportEmailCtrl.text = prefs.getString('supportEmail') ?? '';
    _legalReviewed = prefs.getBool('launchLegalReviewed') ?? false;
    _storeAssetsReady = prefs.getBool('launchStoreAssetsReady') ?? false;
    _supportReady = prefs.getBool('launchSupportReady') ?? false;
    _purchaseQaReady = prefs.getBool('launchPurchaseQaReady') ?? false;
    _deviceQaReady = prefs.getBool('launchDeviceQaReady') ?? false;
    _privacyPolicyReady = prefs.getBool('launchPrivacyPolicyReady') ?? false;
    _releaseSafeMode = prefs.getBool('releaseSafeMode') ?? true;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveTesterDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultTesterName', _testerDefaultCtrl.text.trim());
    await prefs.setString('supportEmail', _supportEmailCtrl.text.trim());
    await prefs.setBool('launchLegalReviewed', _legalReviewed);
    await prefs.setBool('launchStoreAssetsReady', _storeAssetsReady);
    await prefs.setBool('launchSupportReady', _supportReady);
    await prefs.setBool('launchPurchaseQaReady', _purchaseQaReady);
    await prefs.setBool('launchDeviceQaReady', _deviceQaReady);
    await prefs.setBool('launchPrivacyPolicyReady', _privacyPolicyReady);
    await prefs.setBool('releaseSafeMode', _releaseSafeMode);
    await AppAnalytics.logEvent(
      'settings_saved',
      params: {
        'has_default_tester': _testerDefaultCtrl.text.trim().isNotEmpty
            ? 'true'
            : 'false',
        'has_support_email': _supportEmailCtrl.text.trim().isNotEmpty
            ? 'true'
            : 'false',
        'legal_reviewed': '$_legalReviewed',
        'store_assets_ready': '$_storeAssetsReady',
        'support_ready': '$_supportReady',
        'purchase_qa_ready': '$_purchaseQaReady',
        'device_qa_ready': '$_deviceQaReady',
        'privacy_policy_ready': '$_privacyPolicyReady',
        'release_safe_mode': '$_releaseSafeMode',
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFr ? 'Paramètres sauvegardés.' : 'Settings saved.'),
      ),
    );
  }

  Future<void> _copyLaunchChecklist() async {
    final checklist = _isFr
        ? 'Checklist de lancement (impact eleve > faible)\n'
              '1) Validation juridique ON/QC/BC\n'
              '2) QA des achats et restaurations premium\n'
              '3) Matrice QA premier acheteur vs acheteur repetitif\n'
              '4) Verifier PDF/partage/impression des avis\n'
              '5) Activer suivi analytique + surveillance crash\n'
              '6) Polissage bilingue final (EN/FR)\n'
              '7) Captures magasin + politique + support\n'
              '8) Soft launch + ajustements'
        : 'Launch Checklist (Highest to Lowest Impact)\n'
              '1) Legal validation for ON/QC/BC\n'
              '2) Premium purchase + restore QA\n'
              '3) First-time vs repeat buyer QA matrix\n'
              '4) Verify notice PDF/share/print flows\n'
              '5) Enable analytics + crash monitoring\n'
              '6) Final bilingual polish (EN/FR)\n'
              '7) Store assets + privacy policy + support\n'
              '8) Soft launch + iteration';
    await Clipboard.setData(ClipboardData(text: checklist));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isFr ? 'Checklist copié.' : 'Checklist copied.')),
    );
  }

  @override
  void dispose() {
    _testerDefaultCtrl.dispose();
    _supportEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isFr ? 'Parametres' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isFr ? 'Préférences QA' : 'QA Preferences',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _testerDefaultCtrl,
                    decoration: InputDecoration(
                      labelText: _isFr
                          ? 'Nom du testeur par défaut'
                          : 'Default tester name',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supportEmailCtrl,
                    decoration: InputDecoration(
                      labelText: _isFr ? 'Email support' : 'Support email',
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _saveTesterDefault,
                      icon: const Icon(Icons.save),
                      label: Text(_isFr ? 'Sauvegarder' : 'Save'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _legalReviewed,
                    onChanged: (value) =>
                        setState(() => _legalReviewed = value),
                    title: Text(
                      _isFr
                          ? 'Validation juridique complétée'
                          : 'Legal review completed',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _storeAssetsReady,
                    onChanged: (value) =>
                        setState(() => _storeAssetsReady = value),
                    title: Text(
                      _isFr ? 'Assets magasin prêts' : 'Store assets ready',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _supportReady,
                    onChanged: (value) => setState(() => _supportReady = value),
                    title: Text(
                      _isFr
                          ? 'Support et contact prêts'
                          : 'Support and contact ready',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _purchaseQaReady,
                    onChanged: (value) =>
                        setState(() => _purchaseQaReady = value),
                    title: Text(
                      _isFr
                          ? 'QA achats/restauration complétée'
                          : 'Purchase/restore QA completed',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _deviceQaReady,
                    onChanged: (value) =>
                        setState(() => _deviceQaReady = value),
                    title: Text(
                      _isFr
                          ? 'QA appareils réels complétée'
                          : 'Real-device QA completed',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _privacyPolicyReady,
                    onChanged: (value) =>
                        setState(() => _privacyPolicyReady = value),
                    title: Text(
                      _isFr
                          ? 'Politique de confidentialité prête'
                          : 'Privacy policy ready',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _releaseSafeMode,
                    onChanged: (value) =>
                        setState(() => _releaseSafeMode = value),
                    title: Text(
                      _isFr
                          ? 'Mode release-safe (masquer debug)'
                          : 'Release-safe mode (hide debug tools)',
                    ),
                    subtitle: Text(
                      _isFr
                          ? 'Masque les boutons Analytics Debug et Diagnostics runtime sur l\'accueil.'
                          : 'Hides Analytics Debug and Runtime Diagnostics buttons on Home.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_isFr ? 'Version de l\'application' : 'App Version'),
              subtitle: Text('${AppMeta.version} (${AppMeta.buildLabel})'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isFr
                        ? 'Outils lancement et export'
                        : 'Launch and Export Tools',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _copyLaunchChecklist,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: Text(
                      _isFr
                          ? 'Copier checklist lancement'
                          : 'Copy Launch Checklist',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_releaseSafeMode) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AnalyticsDebugPage(language: widget.language),
                          ),
                        );
                      },
                      icon: const Icon(Icons.analytics_outlined),
                      label: Text(
                        _isFr
                            ? 'Ouvrir analytics debug'
                            : 'Open Analytics Debug',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RuntimeDiagnosticsPage(
                              language: widget.language,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: Text(
                        _isFr
                            ? 'Ouvrir diagnostics runtime'
                            : 'Open Runtime Diagnostics',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              BuyerQaMatrixPage(language: widget.language),
                        ),
                      );
                    },
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: Text(
                      _isFr ? 'Ouvrir matrice QA' : 'Open Buyer QA Matrix',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              LaunchReadinessPage(language: widget.language),
                        ),
                      );
                    },
                    icon: const Icon(Icons.task_alt_outlined),
                    label: Text(
                      _isFr
                          ? 'Ouvrir état de lancement'
                          : 'Open Launch Readiness',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SystemHealthCheckPage(language: widget.language),
                        ),
                      );
                    },
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: Text(
                      _isFr
                          ? 'Ouvrir vérification système'
                          : 'Open System Health Check',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LaunchReadinessPage extends StatefulWidget {
  final String language;

  const LaunchReadinessPage({super.key, this.language = 'en'});

  @override
  State<LaunchReadinessPage> createState() => _LaunchReadinessPageState();
}

class _LaunchReadinessPageState extends State<LaunchReadinessPage> {
  bool get _isFr => widget.language == 'fr';

  int _historyCount = 0;
  int _buyerReportCount = 0;
  int _qaRunCount = 0;
  int _failedQaRunCount = 0;
  int _analyticsEventCount = 0;
  bool _legalReviewed = false;
  bool _storeAssetsReady = false;
  bool _supportReady = false;
  bool _purchaseQaReady = false;
  bool _deviceQaReady = false;
  bool _privacyPolicyReady = false;
  String _defaultTester = '';
  String _supportEmail = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final calculations = prefs.getStringList('calculations') ?? [];
    final analytics = await AppAnalytics.getRecentEvents();
    if (!mounted) return;
    setState(() {
      _historyCount = calculations.length;
      _buyerReportCount = calculations
          .where((entry) => entry.startsWith('Buyer Cost Report'))
          .length;
      _qaRunCount = calculations
          .where((entry) => entry.startsWith('Buyer QA Run'))
          .length;
      _failedQaRunCount = calculations.where((entry) {
        final match = RegExp(r'Failed:\s*(\d+)').firstMatch(entry);
        final failed = int.tryParse(match?.group(1) ?? '0') ?? 0;
        return entry.startsWith('Buyer QA Run') && failed > 0;
      }).length;
      _analyticsEventCount = analytics.length;
      _legalReviewed = prefs.getBool('launchLegalReviewed') ?? false;
      _storeAssetsReady = prefs.getBool('launchStoreAssetsReady') ?? false;
      _supportReady = prefs.getBool('launchSupportReady') ?? false;
      _purchaseQaReady = prefs.getBool('launchPurchaseQaReady') ?? false;
      _deviceQaReady = prefs.getBool('launchDeviceQaReady') ?? false;
      _privacyPolicyReady = prefs.getBool('launchPrivacyPolicyReady') ?? false;
      _defaultTester = prefs.getString('defaultTesterName') ?? '';
      _supportEmail = prefs.getString('supportEmail') ?? '';
      _loading = false;
    });
  }

  int get _completedGateCount {
    final gates = [
      _legalReviewed,
      _qaRunCount > 0,
      _purchaseQaReady,
      _deviceQaReady,
      _privacyPolicyReady,
      _storeAssetsReady,
      _supportReady,
      _analyticsEventCount > 0,
    ];
    return gates.where((value) => value).length;
  }

  double get _readinessScore => _completedGateCount / 8;

  List<String> get _blockingItems {
    final items = <String>[];
    if (!_legalReviewed) {
      items.add(_isFr ? 'Validation juridique' : 'Legal review');
    }
    if (_qaRunCount == 0) {
      items.add(
        _isFr ? 'Aucune exécution QA enregistrée' : 'No QA runs recorded',
      );
    }
    if (!_purchaseQaReady) {
      items.add(_isFr ? 'QA achats/restauration' : 'Purchase/restore QA');
    }
    if (!_deviceQaReady) {
      items.add(_isFr ? 'QA sur appareils réels' : 'Real-device QA');
    }
    if (!_privacyPolicyReady) {
      items.add(_isFr ? 'Politique de confidentialité' : 'Privacy policy');
    }
    if (!_storeAssetsReady) {
      items.add(_isFr ? 'Assets magasin' : 'Store assets');
    }
    if (!_supportReady) {
      items.add(_isFr ? 'Support/contact' : 'Support/contact');
    }
    return items;
  }

  List<String> get _warningItems {
    final items = <String>[];
    if (_failedQaRunCount > 0) {
      items.add(
        _isFr
            ? 'Certaines exécutions QA contiennent des échecs.'
            : 'Some QA runs still contain failures.',
      );
    }
    if (_analyticsEventCount < 5) {
      items.add(
        _isFr
            ? 'Peu d\'événements analytiques enregistrés pour valider l\'instrumentation.'
            : 'Very few analytics events are stored to validate instrumentation.',
      );
    }
    if (_buyerReportCount == 0) {
      items.add(
        _isFr
            ? 'Aucun rapport acheteur sauvegardé pour validation métier.'
            : 'No buyer reports have been saved for business validation yet.',
      );
    }
    if (_supportEmail.isEmpty) {
      items.add(
        _isFr
            ? 'Aucun email support défini dans Paramètres.'
            : 'No support email is configured in Settings.',
      );
    }
    return items;
  }

  bool get _canLaunch => _blockingItems.isEmpty;

  Future<void> _copyReadinessReport() async {
    final lines = <String>[
      _isFr ? 'Rapport de préparation lancement' : 'Launch Readiness Report',
      'Version: ${AppMeta.version} (${AppMeta.buildLabel})',
      _isFr
          ? 'Score: ${(_readinessScore * 100).round()} %'
          : 'Score: ${(_readinessScore * 100).round()}%',
      _isFr
          ? 'Peut lancer: ${_canLaunch ? 'oui' : 'non'}'
          : 'Can launch: ${_canLaunch ? 'yes' : 'no'}',
      _isFr
          ? 'Support email: ${_supportEmail.isEmpty ? 'Non défini' : _supportEmail}'
          : 'Support email: ${_supportEmail.isEmpty ? 'Not set' : _supportEmail}',
      _isFr
          ? 'Testeur par défaut: ${_defaultTester.isEmpty ? 'Non défini' : _defaultTester}'
          : 'Default tester: ${_defaultTester.isEmpty ? 'Not set' : _defaultTester}',
      _isFr ? 'Bloquants:' : 'Blockers:',
      ...(_blockingItems.isEmpty
          ? [_isFr ? '- Aucun' : '- None']
          : _blockingItems.map((item) => '- $item')),
      _isFr ? 'Avertissements:' : 'Warnings:',
      ...(_warningItems.isEmpty
          ? [_isFr ? '- Aucun' : '- None']
          : _warningItems.map((item) => '- $item')),
    ];

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    await AppAnalytics.logEvent(
      'launch_readiness_report_copied',
      params: {'can_launch': '$_canLaunch'},
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Rapport de préparation copié.'
              : 'Launch readiness report copied.',
        ),
      ),
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Icon(icon, size: 18),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockers = <Widget>[
      _statusTile(
        icon: _legalReviewed ? Icons.check : Icons.gavel,
        title: _isFr ? 'Validation juridique' : 'Legal Review',
        subtitle: _legalReviewed
            ? (_isFr ? 'Marquée comme complétée.' : 'Marked complete.')
            : (_isFr
                  ? 'Encore bloquante avant lancement public.'
                  : 'Still a release blocker before public launch.'),
        color: _legalReviewed
            ? const Color(0xFF2E7D32)
            : const Color(0xFFC62828),
      ),
      _statusTile(
        icon: _qaRunCount > 0
            ? Icons.rule_folder_outlined
            : Icons.warning_amber,
        title: _isFr ? 'Couverture QA' : 'QA Coverage',
        subtitle: _isFr
            ? 'Exécutions QA: $_qaRunCount, avec échecs: $_failedQaRunCount.'
            : 'QA runs: $_qaRunCount, with failures: $_failedQaRunCount.',
        color: _qaRunCount == 0
            ? const Color(0xFFC62828)
            : _failedQaRunCount > 0
            ? const Color(0xFFEF6C00)
            : const Color(0xFF2E7D32),
      ),
      _statusTile(
        icon: _storeAssetsReady
            ? Icons.storefront
            : Icons.photo_library_outlined,
        title: _isFr ? 'Assets magasin' : 'Store Assets',
        subtitle: _storeAssetsReady
            ? (_isFr ? 'Prêts pour soumission.' : 'Ready for submission.')
            : (_isFr
                  ? 'Captures, description et visuels à finir.'
                  : 'Screenshots, description, and visuals still need completion.'),
        color: _storeAssetsReady
            ? const Color(0xFF2E7D32)
            : const Color(0xFFEF6C00),
      ),
      _statusTile(
        icon: _supportReady
            ? Icons.support_agent
            : Icons.mark_email_unread_outlined,
        title: _isFr ? 'Support et contact' : 'Support and Contact',
        subtitle: _supportReady
            ? (_isFr
                  ? 'Flux support marqué prêt.'
                  : 'Support flow marked ready.')
            : (_isFr
                  ? 'Préparer email/support utilisateur.'
                  : 'Prepare user support/contact path.'),
        color: _supportReady
            ? const Color(0xFF2E7D32)
            : const Color(0xFFEF6C00),
      ),
      _statusTile(
        icon: _analyticsEventCount > 0
            ? Icons.analytics
            : Icons.analytics_outlined,
        title: _isFr
            ? 'Instrumentation analytique'
            : 'Analytics Instrumentation',
        subtitle: _isFr
            ? 'Événements stockés: $_analyticsEventCount.'
            : 'Stored analytics events: $_analyticsEventCount.',
        color: _analyticsEventCount > 0
            ? const Color(0xFF2E7D32)
            : const Color(0xFFEF6C00),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFr ? 'Etat de preparation lancement' : 'Launch Readiness',
        ),
        actions: [
          IconButton(
            onPressed: _copyReadinessReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    _isFr
                        ? 'Vue de synthèse des éléments encore bloquants ou à finaliser avant la mise en ligne.'
                        : 'Summary of the items still blocking or needing completion before release.',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr ? 'Score de préparation' : 'Readiness Score',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _readinessScore,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isFr
                              ? '${(_readinessScore * 100).round()} % prêt ($_completedGateCount/8 gates)'
                              : '${(_readinessScore * 100).round()}% ready ($_completedGateCount/8 gates)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _canLaunch
                                ? const Color(
                                    0xFF2E7D32,
                                  ).withValues(alpha: 0.10)
                                : const Color(
                                    0xFFC62828,
                                  ).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _canLaunch
                                  ? const Color(
                                      0xFF2E7D32,
                                    ).withValues(alpha: 0.25)
                                  : const Color(
                                      0xFFC62828,
                                    ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _canLaunch
                                    ? Icons.check_circle_outline
                                    : Icons.block,
                                color: _canLaunch
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _canLaunch
                                      ? (_isFr
                                            ? 'Prêt pour une soumission beta contrôlée.'
                                            : 'Ready for a controlled beta submission.')
                                      : (_isFr
                                            ? 'Ne pas lancer publiquement tant que les bloquants restent ouverts.'
                                            : 'Do not publicly launch while blockers remain open.'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr ? 'Résumé opérationnel' : 'Operational Summary',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isFr
                              ? 'Entrées historique: $_historyCount'
                              : 'History entries: $_historyCount',
                        ),
                        Text(
                          _isFr
                              ? 'Rapports acheteur: $_buyerReportCount'
                              : 'Buyer reports: $_buyerReportCount',
                        ),
                        Text(
                          _isFr
                              ? 'Exécutions QA: $_qaRunCount'
                              : 'QA runs: $_qaRunCount',
                        ),
                        Text(
                          _isFr
                              ? 'Support email: ${_supportEmail.isEmpty ? 'Non défini' : _supportEmail}'
                              : 'Support email: ${_supportEmail.isEmpty ? 'Not set' : _supportEmail}',
                        ),
                        Text(
                          _isFr
                              ? 'Testeur par défaut: ${_defaultTester.isEmpty ? 'Non défini' : _defaultTester}'
                              : 'Default tester: ${_defaultTester.isEmpty ? 'Not set' : _defaultTester}',
                        ),
                        Text(
                          'Version: ${AppMeta.version} (${AppMeta.buildLabel})',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr ? 'Bloquants actuels' : 'Current Blockers',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_blockingItems.isEmpty)
                          Text(
                            _isFr
                                ? 'Aucun bloquant majeur marqué dans l\'application.'
                                : 'No major blockers are currently marked in the app.',
                          )
                        else
                          ..._blockingItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.close,
                                    color: Color(0xFFC62828),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(item)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFr ? 'Avertissements' : 'Warnings',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_warningItems.isEmpty)
                          Text(
                            _isFr
                                ? 'Aucun avertissement supplémentaire.'
                                : 'No additional warnings.',
                          )
                        else
                          ..._warningItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFFEF6C00),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(item)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...blockers,
              ],
            ),
    );
  }
}

class AnalyticsDebugPage extends StatefulWidget {
  final String language;

  const AnalyticsDebugPage({super.key, this.language = 'en'});

  @override
  State<AnalyticsDebugPage> createState() => _AnalyticsDebugPageState();
}

class _AnalyticsDebugPageState extends State<AnalyticsDebugPage> {
  Map<String, int> _counts = {};
  List<String> _events = [];
  bool _loading = true;

  bool get _isFr => widget.language == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await AppAnalytics.getEventCounts();
    final events = await AppAnalytics.getRecentEvents();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _events = events.reversed.take(30).toList();
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await AppAnalytics.clearEvents();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Événements analytiques effacés.'
              : 'Analytics events cleared.',
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final allEvents = await AppAnalytics.getRecentEvents();

    String esc(String input) {
      return '"${input.replaceAll('"', '""')}"';
    }

    final rows = <String>['timestamp,event,params'];
    for (final raw in allEvents) {
      final parts = raw.split('|');
      final timestamp = parts.isNotEmpty ? parts[0] : '';
      final event = parts.length > 1 ? parts[1] : '';
      final params = parts.length > 2 ? parts.sublist(2).join('|') : '';
      rows.add('${esc(timestamp)},${esc(event)},${esc(params)}');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/contract_shield_analytics.csv');
    await file.writeAsString(rows.join('\n'));

    await AppAnalytics.logEvent(
      'analytics_csv_exported',
      params: {'rows': '${allEvents.length}'},
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: _isFr
            ? 'Export CSV des événements analytiques.'
            : 'Analytics events CSV export.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFr ? 'Tableau analytique (debug)' : 'Analytics Dashboard (Debug)',
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _isFr ? 'Compteurs d\'événements' : 'Event Counters',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_counts.isEmpty)
                  Text(
                    _isFr
                        ? 'Aucun événement enregistré.'
                        : 'No events recorded yet.',
                  )
                else
                  ...(_counts.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map(
                        (entry) => Card(
                          child: ListTile(
                            title: Text(entry.key),
                            trailing: Text(
                              '${entry.value}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 14),
                Text(
                  _isFr ? 'Événements récents' : 'Recent Events',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_events.isEmpty)
                  Text(_isFr ? 'Aucun événement récent.' : 'No recent events.')
                else
                  ..._events.map(
                    (event) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          event,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class RuntimeDiagnosticsPage extends StatefulWidget {
  final String language;

  const RuntimeDiagnosticsPage({super.key, this.language = 'en'});

  @override
  State<RuntimeDiagnosticsPage> createState() => _RuntimeDiagnosticsPageState();
}

class _RuntimeDiagnosticsPageState extends State<RuntimeDiagnosticsPage> {
  List<String> _errors = [];
  bool _loading = true;

  bool get _isFr => widget.language == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final errors = await RuntimeDiagnostics.getRecentErrors();
    if (!mounted) return;
    setState(() {
      _errors = errors.reversed.take(60).toList();
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await RuntimeDiagnostics.clearErrors();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Diagnostics runtime effaces.'
              : 'Runtime diagnostics cleared.',
        ),
      ),
    );
  }

  Future<void> _copy() async {
    final body = _errors.isEmpty
        ? (_isFr ? 'Aucune erreur runtime.' : 'No runtime errors recorded.')
        : _errors.join('\n');
    await Clipboard.setData(ClipboardData(text: body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr
              ? 'Diagnostics copies dans le presse-papiers.'
              : 'Diagnostics copied to clipboard.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFr ? 'Diagnostics runtime' : 'Runtime Diagnostics'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _isFr
                        ? 'Cette page affiche les erreurs runtime capturees pour aider au debug post-lancement.'
                        : 'This page shows captured runtime errors to support post-launch debugging.',
                  ),
                ),
                const SizedBox(height: 12),
                if (_errors.isEmpty)
                  Text(
                    _isFr
                        ? 'Aucune erreur runtime enregistree.'
                        : 'No runtime errors recorded.',
                  )
                else
                  ..._errors.map(
                    (error) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          error,
                          style: const TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SystemHealthCheckPage extends StatefulWidget {
  final String language;

  const SystemHealthCheckPage({super.key, this.language = 'en'});

  @override
  State<SystemHealthCheckPage> createState() => _SystemHealthCheckPageState();
}

class _SystemHealthCheckPageState extends State<SystemHealthCheckPage> {
  bool _loading = true;
  bool _storageOk = false;
  bool _purchaseAvailable = false;
  bool _privacyLinkAvailable = false;
  bool _termsLinkAvailable = false;
  bool _releaseSafeMode = true;
  int _runtimeErrorCount = 0;
  int _analyticsCount = 0;

  bool get _isFr => widget.language == 'fr';

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    var storageOk = false;
    var purchaseAvailable = false;
    var privacyLinkAvailable = false;
    var termsLinkAvailable = false;
    var releaseSafeMode = false;
    var runtimeErrorCount = 0;
    var analyticsCount = 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      const key = '__health_check_tmp__';
      await prefs.setString(key, 'ok');
      await prefs.remove(key);
      storageOk = true;
      releaseSafeMode = prefs.getBool('releaseSafeMode') ?? true;
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('health_check_storage', e, st));
    }

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        purchaseAvailable = await InAppPurchase.instance.isAvailable();
      }
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('health_check_purchase', e, st));
    }

    try {
      privacyLinkAvailable = await canLaunchUrl(Uri.parse(AppLinks.privacyUrl));
      termsLinkAvailable = await canLaunchUrl(Uri.parse(AppLinks.termsUrl));
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('health_check_links', e, st));
    }

    final runtimeErrors = await RuntimeDiagnostics.getRecentErrors();
    final analyticsEvents = await AppAnalytics.getRecentEvents();
    runtimeErrorCount = runtimeErrors.length;
    analyticsCount = analyticsEvents.length;

    if (!mounted) return;
    setState(() {
      _storageOk = storageOk;
      _purchaseAvailable = purchaseAvailable;
      _privacyLinkAvailable = privacyLinkAvailable;
      _termsLinkAvailable = termsLinkAvailable;
      _releaseSafeMode = releaseSafeMode;
      _runtimeErrorCount = runtimeErrorCount;
      _analyticsCount = analyticsCount;
      _loading = false;
    });
  }

  Future<void> _copyReport() async {
    final lines = [
      'Contract Shield System Health',
      'Storage: ${_storageOk ? 'OK' : 'FAIL'}',
      'Purchase availability: ${_purchaseAvailable ? 'AVAILABLE' : 'UNAVAILABLE'}',
      'Privacy link: ${_privacyLinkAvailable ? 'OK' : 'UNAVAILABLE'}',
      'Terms link: ${_termsLinkAvailable ? 'OK' : 'UNAVAILABLE'}',
      'Release-safe mode: ${_releaseSafeMode ? 'ON' : 'OFF'}',
      'Runtime errors stored: $_runtimeErrorCount',
      'Analytics events stored: $_analyticsCount',
      'App version: ${AppMeta.version} (${AppMeta.buildLabel})',
      'Timestamp: ${DateTime.now().toIso8601String()}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFr ? 'Rapport système copié.' : 'System health report copied.',
        ),
      ),
    );
  }

  String _buildOperationsReport() {
    final now = DateTime.now().toIso8601String();
    final crashGuard = _runtimeErrorCount == 0
        ? 'GREEN'
        : (_runtimeErrorCount < 20 ? 'YELLOW' : 'RED');
    final purchaseGuard = (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
        ? (_purchaseAvailable ? 'GREEN' : 'RED')
        : 'N/A';
    final linksGuard = (_privacyLinkAvailable && _termsLinkAvailable)
        ? 'GREEN'
        : 'RED';

    return [
      'Contract Shield Release Operations Snapshot',
      'Timestamp: $now',
      'Version: ${AppMeta.version} (${AppMeta.buildLabel})',
      '',
      'Health Status',
      '- Storage: ${_storageOk ? 'OK' : 'FAIL'}',
      '- Purchase availability: ${_purchaseAvailable ? 'AVAILABLE' : 'UNAVAILABLE'}',
      '- Privacy link: ${_privacyLinkAvailable ? 'OK' : 'UNAVAILABLE'}',
      '- Terms link: ${_termsLinkAvailable ? 'OK' : 'UNAVAILABLE'}',
      '- Release-safe mode: ${_releaseSafeMode ? 'ON' : 'OFF'}',
      '- Runtime errors stored: $_runtimeErrorCount',
      '- Analytics events stored: $_analyticsCount',
      '',
      'Rollout Guardrail Snapshot',
      '- Crash guard: $crashGuard',
      '- Purchase guard: $purchaseGuard',
      '- Legal links guard: $linksGuard',
      '',
      'Go/No-Go Quick Checks',
      '1) Crash trend stable in last 24h',
      '2) Purchase + restore path healthy',
      '3) Privacy + Terms links reachable',
      '4) No new high-volume runtime error cluster',
      '',
      'Incident Response Quick Steps',
      '1) Pause rollout if guardrail is RED',
      '2) Capture version/device/repro steps',
      '3) Patch minimal fix and validate analyze + tests',
      '4) Resume rollout gradually after metrics recover',
    ].join('\n');
  }

  Future<void> _exportOpsReport() async {
    try {
      final report = _buildOperationsReport();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/contract_shield_ops_report.txt');
      await file.writeAsString(report);

      await AppAnalytics.logEvent('ops_report_exported');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: _isFr
              ? 'Rapport opérations exporté.'
              : 'Operations report export.',
        ),
      );
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('ops_report_export', e, st));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr
                ? 'Impossible d\'exporter le rapport opérations.'
                : 'Unable to export operations report.',
          ),
        ),
      );
    }
  }

  Widget _statusTile(String label, bool ok) {
    return Card(
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        ),
        title: Text(label),
        trailing: Text(
          ok ? 'OK' : 'Check',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFr ? 'Vérification système' : 'System Health Check'),
        actions: [
          IconButton(onPressed: _runChecks, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            onPressed: _exportOpsReport,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusTile(
                  _isFr
                      ? 'Stockage local (SharedPreferences)'
                      : 'Local storage (SharedPreferences)',
                  _storageOk,
                ),
                _statusTile(
                  _isFr
                      ? 'Liens politique de confidentialité'
                      : 'Privacy policy link',
                  _privacyLinkAvailable,
                ),
                _statusTile(
                  _isFr ? 'Liens conditions d\'utilisation' : 'Terms link',
                  _termsLinkAvailable,
                ),
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                  _statusTile(
                    _isFr
                        ? 'Disponibilité achats intégrés'
                        : 'In-app purchase availability',
                    _purchaseAvailable,
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(
                        _isFr
                            ? 'Achats intégrés non applicables sur cette plateforme'
                            : 'In-app purchases are not applicable on this platform',
                      ),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(
                      _isFr ? 'Mode release-safe' : 'Release-safe mode',
                    ),
                    trailing: Text(_releaseSafeMode ? 'ON' : 'OFF'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(
                      _isFr
                          ? 'Erreurs runtime enregistrées'
                          : 'Stored runtime errors',
                    ),
                    trailing: Text('$_runtimeErrorCount'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.analytics_outlined),
                    title: Text(
                      _isFr
                          ? 'Événements analytiques stockés'
                          : 'Stored analytics events',
                    ),
                    trailing: Text('$_analyticsCount'),
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
    unawaited(
      AppAnalytics.logEvent(
        'paywall_screen_view',
        params: {'lang': widget.language},
      ),
    );
    _purchaseSubscription = _iap.purchaseStream.listen(_handlePurchases);
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) {
        if (!mounted) return;
        setState(() {
          _products = [];
          _loadingProducts = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFr
                  ? 'Achats intégrés indisponibles sur cet appareil.'
                  : 'In-app purchases are unavailable on this device.',
            ),
          ),
        );
        return;
      }

      ProductDetailsResponse response = await _iap.queryProductDetails(
        _productOrder.toSet(),
      );

      if (response.error != null && response.productDetails.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        response = await _iap.queryProductDetails(_productOrder.toSet());
      }

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
        unawaited(
          RuntimeDiagnostics.recordError(
            'paywall_load_products',
            response.error!,
          ),
        );
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
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('paywall_load_products', e, st));
      if (!mounted) return;
      setState(() => _loadingProducts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr
                ? 'Erreur de chargement des offres.'
                : 'Failed to load plans.',
          ),
        ),
      );
    }
  }

  Future<void> _buy(ProductDetails product) async {
    try {
      final storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFr
                  ? 'Achats intégrés indisponibles pour le moment.'
                  : 'In-app purchases are unavailable right now.',
            ),
          ),
        );
        return;
      }

      setState(() => _purchasing = true);
      unawaited(
        AppAnalytics.logEvent(
          'purchase_attempt',
          params: {'product_id': product.id},
        ),
      );
      final param = PurchaseParam(productDetails: product);

      if (product.id == InAppPurchaseHelper.singleScanProductId) {
        await _iap.buyConsumable(purchaseParam: param);
      } else {
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('paywall_buy', e, st));
      if (!mounted) return;
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr
                ? 'Achat indisponible pour le moment.'
                : 'Purchase is unavailable right now.',
          ),
        ),
      );
    }
  }

  Future<void> _restorePurchases() async {
    try {
      final storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFr
                  ? 'Restauration indisponible sur cet appareil.'
                  : 'Restore is unavailable on this device.',
            ),
          ),
        );
        return;
      }

      setState(() => _restoring = true);
      await _iap.restorePurchases();
      if (!mounted) return;
      setState(() => _restoring = false);
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('paywall_restore', e, st));
      if (!mounted) return;
      setState(() => _restoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFr
                ? 'Restauration indisponible pour le moment.'
                : 'Restore is unavailable right now.',
          ),
        ),
      );
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        unawaited(
          AppAnalytics.logEvent(
            'purchase_failed',
            params: {'product_id': purchase.productID},
          ),
        );
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
        unawaited(
          AppAnalytics.logEvent(
            'purchase_success',
            params: {'product_id': purchase.productID},
          ),
        );
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
    try {
      final uri = Uri.parse(url);
      final canOpen = await canLaunchUrl(uri);
      if (!canOpen) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isFr
                    ? 'Lien indisponible sur cet appareil.'
                    : 'This link is unavailable on this device.',
              ),
            ),
          );
        }
        return;
      }

      var opened = false;
      for (var attempt = 0; attempt < 3 && !opened; attempt++) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened && attempt < 2) {
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        }
      }

      if (!opened && mounted) {
        unawaited(
          RuntimeDiagnostics.recordError(
            'open_external_url',
            'launch failed for $url',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFr ? 'Impossible d\'ouvrir le lien.' : 'Unable to open link.',
            ),
          ),
        );
      }
    } catch (e, st) {
      unawaited(RuntimeDiagnostics.recordError('open_external_url', e, st));
      if (!mounted) return;
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
    if (product.id == InAppPurchaseHelper.monthlyProProductId) {
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
                onPressed: () => _openExternalUrl(AppLinks.privacyUrl),
                child: Text(
                  _isFr ? 'Politique de confidentialité' : 'Privacy Policy',
                ),
              ),
              TextButton(
                onPressed: () => _openExternalUrl(AppLinks.termsUrl),
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

class HistoryPage extends StatefulWidget {
  final List<String> calculations;
  final String language;

  const HistoryPage(this.calculations, {super.key, this.language = 'en'});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _filter = 'all';

  bool get _isFr => widget.language == 'fr';

  bool _isBuyerReport(String entry) {
    return entry.startsWith('Buyer Cost Report');
  }

  bool _isQaRun(String entry) {
    return entry.startsWith('Buyer QA Run');
  }

  bool _isFailedQaRun(String entry) {
    if (!_isQaRun(entry)) return false;
    final match = RegExp(r'Failed:\s*(\d+)').firstMatch(entry);
    if (match == null) return false;
    final failed = int.tryParse(match.group(1) ?? '0') ?? 0;
    return failed > 0;
  }

  bool _isQaRunWithNotes(String entry) {
    if (!_isQaRun(entry)) return false;
    final match = RegExp(r'Fail Notes:\s*(\d+)').firstMatch(entry);
    if (match == null) return false;
    final noted = int.tryParse(match.group(1) ?? '0') ?? 0;
    return noted > 0;
  }

  bool _isFirstTimeBuyerReport(String entry) {
    if (!_isBuyerReport(entry)) return false;
    return entry.contains('[First-time buyer]') ||
        entry.contains('[Premier acheteur]');
  }

  bool _isRepeatBuyerReport(String entry) {
    if (!_isBuyerReport(entry)) return false;
    return entry.contains('[Repeat buyer]') ||
        entry.contains('[Acheteur repetitif]');
  }

  String _buyerTag(String entry) {
    if (_isFirstTimeBuyerReport(entry)) {
      return _isFr ? 'Premier acheteur' : 'First-time buyer';
    }
    if (_isRepeatBuyerReport(entry)) {
      return _isFr ? 'Acheteur repetitif' : 'Repeat buyer';
    }
    return _isFr ? 'Rapport acheteur' : 'Buyer Cost Report';
  }

  String _historyTag(String entry) {
    if (_isBuyerReport(entry)) return _buyerTag(entry);
    if (_isQaRun(entry)) {
      return _isFr ? 'Execution QA acheteur' : 'Buyer QA Run';
    }
    return _isFr ? 'Calcul economie' : 'Savings Calculation';
  }

  List<String> get _filteredCalculations {
    if (_filter == 'buyer') {
      return widget.calculations.where(_isBuyerReport).toList();
    }
    if (_filter == 'qa') {
      return widget.calculations.where(_isQaRun).toList();
    }
    if (_filter == 'qa_failed') {
      return widget.calculations.where(_isFailedQaRun).toList();
    }
    if (_filter == 'qa_notes') {
      return widget.calculations.where(_isQaRunWithNotes).toList();
    }
    if (_filter == 'buyer_first') {
      return widget.calculations.where(_isFirstTimeBuyerReport).toList();
    }
    if (_filter == 'buyer_repeat') {
      return widget.calculations.where(_isRepeatBuyerReport).toList();
    }
    if (_filter == 'savings') {
      return widget.calculations
          .where((entry) => !_isBuyerReport(entry) && !_isQaRun(entry))
          .toList();
    }
    return widget.calculations;
  }

  Future<void> _exportHistoryCsv() async {
    String esc(String input) => '"${input.replaceAll('"', '""')}"';

    final rows = <String>['entry'];
    for (final entry in widget.calculations) {
      rows.add(esc(entry));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/contract_shield_history.csv');
    await file.writeAsString(rows.join('\n'));

    await AppAnalytics.logEvent(
      'history_csv_exported',
      params: {'rows': '${widget.calculations.length}'},
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: _isFr ? 'Export CSV de l\'historique.' : 'History CSV export.',
      ),
    );
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isFr ? 'Vider l\'historique' : 'Clear history'),
        content: Text(
          _isFr
              ? 'Supprimer toutes les entrées de l\'historique ?'
              : 'Remove all history entries?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isFr ? 'Annuler' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isFr ? 'Vider' : 'Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      widget.calculations.clear();
    });
    await prefs.setStringList('calculations', []);
    await AppAnalytics.logEvent('history_cleared');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isFr ? 'Historique vidé.' : 'History cleared.')),
    );
  }

  Future<void> _deleteEntry(String entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isFr ? 'Supprimer l\'entrée' : 'Delete entry'),
        content: Text(
          _isFr
              ? 'Voulez-vous vraiment supprimer cet élément de l\'historique ?'
              : 'Do you want to permanently remove this history item?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isFr ? 'Annuler' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isFr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      widget.calculations.remove(entry);
    });
    await prefs.setStringList('calculations', widget.calculations);
    await AppAnalytics.logEvent(
      'history_entry_deleted',
      params: {
        'type': _isBuyerReport(entry)
            ? 'buyer_report'
            : _isQaRun(entry)
            ? 'qa_run'
            : 'savings',
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isFr ? 'Entrée supprimée.' : 'Entry deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filteredCalculations;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('viewHistory', widget.language)),
        actions: [
          IconButton(
            onPressed: widget.calculations.isEmpty ? null : _exportHistoryCsv,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: widget.calculations.isEmpty ? null : _clearAllHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: widget.calculations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _isFr
                        ? 'Aucun calcul sauvegardé pour le moment'
                        : 'No saved calculations yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: shown.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(_isFr ? 'Tous' : 'All'),
                          selected: _filter == 'all',
                          onSelected: (_) => setState(() => _filter = 'all'),
                        ),
                        ChoiceChip(
                          label: Text(_isFr ? 'Economies' : 'Savings'),
                          selected: _filter == 'savings',
                          onSelected: (_) =>
                              setState(() => _filter = 'savings'),
                        ),
                        ChoiceChip(
                          label: Text(
                            _isFr ? 'Rapports acheteur' : 'Buyer Reports',
                          ),
                          selected: _filter == 'buyer',
                          onSelected: (_) => setState(() => _filter = 'buyer'),
                        ),
                        ChoiceChip(
                          label: Text(_isFr ? 'Executions QA' : 'QA Runs'),
                          selected: _filter == 'qa',
                          onSelected: (_) => setState(() => _filter = 'qa'),
                        ),
                        ChoiceChip(
                          label: Text(
                            _isFr ? 'QA avec echecs' : 'Failed QA Runs',
                          ),
                          selected: _filter == 'qa_failed',
                          onSelected: (_) =>
                              setState(() => _filter = 'qa_failed'),
                        ),
                        ChoiceChip(
                          label: Text(
                            _isFr ? 'QA avec notes' : 'QA Runs With Notes',
                          ),
                          selected: _filter == 'qa_notes',
                          onSelected: (_) =>
                              setState(() => _filter = 'qa_notes'),
                        ),
                        ChoiceChip(
                          label: Text(
                            _isFr ? 'Premiers acheteurs' : 'First-time Reports',
                          ),
                          selected: _filter == 'buyer_first',
                          onSelected: (_) =>
                              setState(() => _filter = 'buyer_first'),
                        ),
                        ChoiceChip(
                          label: Text(
                            _isFr ? 'Acheteurs repetitifs' : 'Repeat Reports',
                          ),
                          selected: _filter == 'buyer_repeat',
                          onSelected: (_) =>
                              setState(() => _filter = 'buyer_repeat'),
                        ),
                      ],
                    ),
                  );
                }

                final item = shown[index - 1];
                final isBuyer = _isBuyerReport(item);
                final isQa = _isQaRun(item);

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
                        color: isBuyer
                            ? const Color(0xFF2E7D32)
                            : isQa
                            ? const Color(0xFFEF6C00)
                            : const Color(0xFF1E88E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(item),
                    subtitle: (isBuyer || isQa)
                        ? Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              _historyTag(item),
                              style: TextStyle(
                                fontSize: 12,
                                color: isQa
                                    ? const Color(0xFFEF6C00)
                                    : const Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Color(0xFFF44336)),
                      onPressed: () => _deleteEntry(item),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
