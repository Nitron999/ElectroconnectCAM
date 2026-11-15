import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ElectroconnectCamApp());
}

class ElectroconnectCamApp extends StatefulWidget {
  const ElectroconnectCamApp({super.key});

  @override
  State<ElectroconnectCamApp> createState() => _ElectroconnectCamAppState();
}

class _ElectroconnectCamAppState extends State<ElectroconnectCamApp> {
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = prefs.getBool('cam_dark_theme') ?? false);
  }

  Future<void> _toggleTheme() async {
    final next = !_isDark;
    setState(() => _isDark = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cam_dark_theme', next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЭЛЕКТРОконнект — CAM & DFM (Кувезенков А.А.)',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF002E63),
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF002E63),
        scaffoldBackgroundColor: const Color(0xFF0A101D),
      ),
      home: CamWorkspaceScreen(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

class GerberLayerInfo {
  final String fileName;
  final String role;
  final int sizeBytes;
  final String? extractedPath;
  final bool isImportantDoc;

  GerberLayerInfo({
    required this.fileName,
    required this.role,
    required this.sizeBytes,
    this.extractedPath,
    this.isImportantDoc = false,
  });
}

class GerberAnalysisResult {
  final String archiveName;
  final String archiveDir;
  final String projectTitle;
  final List layers;
  final List extraProjectDocs;
  final List extraTextAlerts;
  final int detectedLayersCount;
  final bool hasTopMask;
  final bool hasBottomMask;
  final bool hasTopSilk;
  final bool hasBottomSilk;
  final bool hasBinaryBrdOnly;
  final bool hasCadSourceOnly;
  final bool hasNestedArchive;
  final bool parsedFromOrderBlank;
  final double? widthMm;
  final double? heightMm;
  final double? minTrackMm;
  final double? minDrillMm;
  final int totalHoles;
  final Map drillToolsBreakdown;

  GerberAnalysisResult({
    required this.archiveName,
    required this.archiveDir,
    required this.projectTitle,
    required this.layers,
    required this.extraProjectDocs,
    required this.extraTextAlerts,
    required this.detectedLayersCount,
    required this.hasTopMask,
    required this.hasBottomMask,
    required this.hasTopSilk,
    required this.hasBottomSilk,
    required this.hasBinaryBrdOnly,
    required this.hasCadSourceOnly,
    required this.hasNestedArchive,
    required this.parsedFromOrderBlank,
    this.widthMm,
    this.heightMm,
    this.minTrackMm,
    this.minDrillMm,
    required this.totalHoles,
    required this.drillToolsBreakdown,
  });
}

class DfmCheckItem {
  final String title;
  final String detail;
  final String level;

  DfmCheckItem({
    required this.title,
    required this.detail,
    required this.level,
  });
}

class CamWorkspaceScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const CamWorkspaceScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<CamWorkspaceScreen> createState() => _CamWorkspaceScreenState();
}

class _CamWorkspaceScreenState extends State<CamWorkspaceScreen> {
  static const Color ecNavy = Color(0xFF002E63);
  static const Color ecNavyLight = Color(0xFF0D478A);
  static const Color ecOrange = Color(0xFFF56600);

  GerberAnalysisResult? _analysis;
  List _blankBoardsList = [];
  int _selectedBoardIdx = 0;

  Map<String, double> _tariffConfig = {
    'l1': 290.0,
    'l2': 370.0,
    'l4': 650.0,
    'l6': 850.0,
    'l8': 1090.0,
    'l10': 1395.0,
    'l12': 1665.0,
    'l14': 1958.0,
    'l16': 2213.0,
    'l18': 2513.0,
    'al': 465.0,
    'mask2': 49.0,
    'silk1': 20.0,
    'gold': 75.0,
    'tin': 55.0,
    'foil50': 30.0,
    'foil70': 48.0,
    'foil105': 70.0,
    'setupLayer': 300.0,
    'setupSilk': 600.0,
    'colorMaskCoeff': 2.0,
    'expressMult': 1.50,
    'superExpressMult': 2.00,
  };

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _orderNameController = TextEditingController();
  final TextEditingController _widthController = TextEditingController(text: '0.0');
  final TextEditingController _heightController = TextEditingController(text: '0.0');
  final TextEditingController _qtyController = TextEditingController(text: '10');
  final TextEditingController _extraQtysController = TextEditingController();
  final TextEditingController _minTrackController = TextEditingController(text: '0.15');
  final TextEditingController _minHoleController = TextEditingController(text: '0.30');
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _managerController = TextEditingController();

  final TextEditingController _basePriceDm2Controller = TextEditingController(text: '459.0');
  final TextEditingController _setupFeeController = TextEditingController(text: '1800.0');
  bool _manualPriceOverride = false;

  bool _isFetchingWebPrice = false;
  String? _webPriceResult;
  String? _webPriceDetails;

  String _orderType = 'Новый';
  String _urgency = 'Серийный';
  int _layersCount = 2;
  String _material = 'FR4';
  String _thickness = '1.5';
  String _foil = '18';
  String _maskSide = 'С двух сторон';
  String _maskColor = 'Зеленая';
  String _silkSide = 'С двух сторон';
  String _silkColor = 'Белая';
  String _finish = 'HAL (ПОС-63)';
  String _contour = 'фрезеровка';
  bool _electroTest = true;

  Color get _cardBg => widget.isDark ? const Color(0xFF111827) : Colors.white;
  Color get _borderCol => widget.isDark ? const Color(0xFF1F2937) : const Color(0xFFD5DFEC);
  Color get _subtleText => widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  @override
  void initState() {
    super.initState();
    _loadTariffConfig();
  }

  Future<void> _loadTariffConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ec_tariff_config_v1');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map;
        setState(() {
          for (final entry in decoded.entries) {
            final k = entry.key.toString();
            final v = (entry.value as num).toDouble();
            if (_tariffConfig.containsKey(k)) {
              _tariffConfig[k] = v;
            }
          }
          _recalculateTariffFromSpecs(force: true);
        });
      } catch (_) {}
    } else {
      _recalculateTariffFromSpecs(force: true);
    }
  }

  Future<void> _saveTariffConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ec_tariff_config_v1', jsonEncode(_tariffConfig));
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ecNavy,
        content: Text(text, style: const TextStyle(fontSize: 14, color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openTariffEditorDialog() async {
    final Map<String, TextEditingController> ctrls = {};
    for (final entry in _tariffConfig.entries) {
      ctrls[entry.key] = TextEditingController(text: entry.value.toString());
    }

    Widget numBox(String key, String title) {
      return SizedBox(
        width: 190,
        child: TextField(
          controller: ctrls[key],
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: title,
            labelStyle: const TextStyle(fontSize: 12.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: ecNavy, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.price_change_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Настройка тарифов прайса ООО «ЭЛЕКТРОконнект» (без НДС)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 840,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Базовые ставки за 1 дм² по слойности (руб.):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    numBox('l1', '1 слой (ОПП), р/дм²'),
                    numBox('l2', '2 слоя (ДПП), р/дм²'),
                    numBox('l4', '4 слоя (МПП), р/дм²'),
                    numBox('l6', '6 слоёв (МПП), р/дм²'),
                    numBox('l8', '8 слоёв (МПП), р/дм²'),
                    numBox('l10', '10 слоёв (МПП), р/дм²'),
                    numBox('l12', '12 слоёв (МПП), р/дм²'),
                    numBox('l14', '14 слоёв (МПП), р/дм²'),
                    numBox('l16', '16 слоёв (МПП), р/дм²'),
                    numBox('l18', '18 слоёв (МПП), р/дм²'),
                    numBox('al', 'Алюминий (AL), р/дм²'),
                  ],
                ),
                const Divider(height: 24),
                const Text('Доплаты за покрытие, маску, маркировку и фольгу (руб./дм²):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    numBox('mask2', 'Маска 2 стороны, р/дм²'),
                    numBox('silk1', 'Маркировка 1 ст., р/дм²'),
                    numBox('gold', 'Иммерс. золото, р/дм²'),
                    numBox('tin', 'Иммерс. олово, р/дм²'),
                    numBox('foil50', 'Фольга 50 мкм, +р/дм²'),
                    numBox('foil70', 'Фольга 70 мкм, +р/дм²'),
                    numBox('foil105', 'Фольга 105 мкм, +р/дм²'),
                  ],
                ),
                const Divider(height: 24),
                const Text('Подготовка производства и коэффициенты:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    numBox('setupLayer', 'Подготовка 1 слоя, руб.'),
                    numBox('setupSilk', 'Подготовка марк., руб.'),
                    numBox('colorMaskCoeff', 'Коэф. цветной маски'),
                    numBox('expressMult', 'Коэф. Ускоренный (Экспресс)'),
                    numBox('superExpressMult', 'Коэф. Суперэкспресс'),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _tariffConfig = {
                  'l1': 290.0,
                  'l2': 370.0,
                  'l4': 650.0,
                  'l6': 850.0,
                  'l8': 1090.0,
                  'l10': 1395.0,
                  'l12': 1665.0,
                  'l14': 1958.0,
                  'l16': 2213.0,
                  'l18': 2513.0,
                  'al': 465.0,
                  'mask2': 49.0,
                  'silk1': 20.0,
                  'gold': 75.0,
                  'tin': 55.0,
                  'foil50': 30.0,
                  'foil70': 48.0,
                  'foil105': 70.0,
                  'setupLayer': 300.0,
                  'setupSilk': 600.0,
                  'colorMaskCoeff': 2.0,
                  'expressMult': 1.50,
                  'superExpressMult': 2.00,
                };
                _manualPriceOverride = false;
                _recalculateTariffFromSpecs(force: true);
              });
              _saveTariffConfig();
              Navigator.pop(ctx);
              _showSnack('Тарифы сброшены на заводские значения 2026 года.');
            },
            child: const Text('Сбросить по умолчанию'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: ecOrange, foregroundColor: Colors.white),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Применить и сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() {
                for (final entry in ctrls.entries) {
                  final parsed = double.tryParse(entry.value.text.replaceAll(',', '.'));
                  if (parsed != null && parsed >= 0) {
                    _tariffConfig[entry.key] = parsed;
                  }
                }
                _manualPriceOverride = false;
                _recalculateTariffFromSpecs(force: true);
              });
              _saveTariffConfig();
              Navigator.pop(ctx);
              _showSnack('Новые цены прайса применены ко всем расчётам!');
            },
          ),
        ],
      ),
    );
  }

  ({double dm2Rate, double setupFee}) _computeRatesForSpecs({
    required int layers,
    required String material,
    required String foil,
    required String finish,
    required String maskColor,
    required String maskSide,
    required String silkSide,
    required String orderType,
    required String urgency,
    double widthMm = 0,
    double heightMm = 0,
    double minTrackMm = 0.15,
    double minDrillMm = 0.30,
    String notesText = '',
  }) {
    double baseBoardDm2;
    switch (layers) {
      case 1:
        baseBoardDm2 = _tariffConfig['l1'] ?? 290.0;
        break;
      case 2:
        baseBoardDm2 = _tariffConfig['l2'] ?? 370.0;
        break;
      case 4:
        baseBoardDm2 = _tariffConfig['l4'] ?? 650.0;
        break;
      case 6:
        baseBoardDm2 = _tariffConfig['l6'] ?? 850.0;
        break;
      case 8:
        baseBoardDm2 = _tariffConfig['l8'] ?? 1090.0;
        break;
      case 10:
        baseBoardDm2 = _tariffConfig['l10'] ?? 1395.0;
        break;
      case 12:
        baseBoardDm2 = _tariffConfig['l12'] ?? 1665.0;
        break;
      case 14:
        baseBoardDm2 = _tariffConfig['l14'] ?? 1958.0;
        break;
      case 16:
        baseBoardDm2 = _tariffConfig['l16'] ?? 2213.0;
        break;
      default:
        baseBoardDm2 = (_tariffConfig['l18'] ?? 2513.0) + (layers - 18) * 150.0;
        break;
    }

    if (material == 'Алюминий') {
      baseBoardDm2 = _tariffConfig['al'] ?? 465.0;
    } else if (material == 'FR4 Tg170') {
      baseBoardDm2 += 27.0 * layers;
    } else if (material == 'Rogers') {
      baseBoardDm2 *= 2.50;
    }

    final mask2Rate = _tariffConfig['mask2'] ?? 49.0;
    final silk1Rate = _tariffConfig['silk1'] ?? 20.0;

    double dm2Addons = 0.0;
    if (maskSide == 'С двух сторон') {
      dm2Addons += mask2Rate;
    } else if (maskSide.startsWith('С одной стороны')) {
      dm2Addons += (mask2Rate * 0.5);
    }

    if (silkSide == 'С двух сторон') {
      dm2Addons += (silk1Rate * 2.0);
    } else if (silkSide.startsWith('С одной стороны')) {
      dm2Addons += silk1Rate;
    }

    final foilInt = int.tryParse(foil) ?? 18;
    if (foilInt >= 105) {
      dm2Addons += _tariffConfig['foil105'] ?? 70.0;
    } else if (foilInt >= 70) {
      dm2Addons += _tariffConfig['foil70'] ?? 48.0;
    } else if (foilInt >= 50) {
      dm2Addons += _tariffConfig['foil50'] ?? 30.0;
    }

    if (finish == 'Иммерсионное золото') {
      dm2Addons += _tariffConfig['gold'] ?? 75.0;
    } else if (finish == 'Иммерсионное олово') {
      dm2Addons += _tariffConfig['tin'] ?? 55.0;
    }

    final notesLow = notesText.toLowerCase();
    final hasViaMaskPlug = notesLow.contains('забивк') || notesLow.contains('via plugging');
    final hasEpoxyFill = notesLow.contains('смолой') || notesLow.contains('компаунд') || notesLow.contains('ipc 4761');
    final hasBlindVias = notesLow.contains('слеп') || notesLow.contains('глух');
    final hasImpedanceOrPair = notesLow.contains('импеданс') || notesLow.contains('попарн') || notesLow.contains('прессован');

    if (hasViaMaskPlug) {
      dm2Addons += 49.0;
    }

    double maxCoeff = 1.0;
    if (maskColor != 'Зеленая' && maskSide != 'Без маски') {
      maxCoeff = math.max(maxCoeff, _tariffConfig['colorMaskCoeff'] ?? 2.0);
    }
    if (hasEpoxyFill) {
      maxCoeff = math.max(maxCoeff, 1.5);
    }
    if (hasBlindVias) {
      maxCoeff = math.max(maxCoeff, 1.4);
    }
    if ((minTrackMm > 0 && minTrackMm < 0.125) || (minDrillMm > 0 && minDrillMm < 0.30)) {
      maxCoeff = math.max(maxCoeff, 1.25);
    }
    if (hasImpedanceOrPair) {
      maxCoeff = math.max(maxCoeff, 1.2);
    }
    if (widthMm > 0 && heightMm > 0 && ((widthMm * heightMm) / 10000.0) > 5.0) {
      maxCoeff = math.max(maxCoeff, 1.2);
    }

    double dm2Rate = (baseBoardDm2 + dm2Addons) * maxCoeff;

    double setupFee = 0.0;
    if (orderType != 'Повтор') {
      int maskLayers = maskSide == 'С двух сторон' ? 2 : (maskSide.startsWith('С одной стороны') ? 1 : 0);
      setupFee = (layers + maskLayers) * (_tariffConfig['setupLayer'] ?? 300.0);
      if (silkSide != 'Без маркировки') {
        setupFee += (_tariffConfig['setupSilk'] ?? 600.0);
      }
      if (hasViaMaskPlug) {
        setupFee += 500.0;
      }
      if ((minTrackMm > 0 && minTrackMm < 0.125) ||
          (minDrillMm > 0 && minDrillMm < 0.30) ||
          hasImpedanceOrPair ||
          hasEpoxyFill) {
        setupFee *= 1.50;
      }
    }

    if (urgency == 'Экспресс') {
      dm2Rate *= (_tariffConfig['expressMult'] ?? 1.50);
    } else if (urgency == 'СуперЭкспресс') {
      dm2Rate *= (_tariffConfig['superExpressMult'] ?? 2.00);
    }

    return (dm2Rate: dm2Rate, setupFee: setupFee);
  }

  /// Как в КП завода (64x23 мм = 0.1472 -> 0.15 дм² на плату, минимум 0.03 дм²)
  double _calcEffectiveSingleDm2(double w, double h) {
    if (w <= 0 || h <= 0) return 0.0;
    final rawDm2 = (w * h) / 10000.0;
    final roundedUp = (rawDm2 * 100.0).ceil() / 100.0;
    return math.max(roundedUp, 0.03);
  }

  bool _hasCustomStackOrPressing(String notesText, int layers) {
    final low = notesText.toLowerCase();
    return low.contains('попарн') ||
        low.contains('прессован') ||
        low.contains('стек заказчика') ||
        low.contains('между слоями') ||
        low.contains('импеданс') ||
        low.contains('ipc 4761') ||
        low.contains('смолой') ||
        low.contains('глух') ||
        low.contains('слеп');
  }

  void _recalculateTariffFromSpecs({bool force = false}) {
    if (_manualPriceOverride && !force) return;

    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final tr = double.tryParse(_minTrackController.text.replaceAll(',', '.')) ?? 0.15;
    final dr = double.tryParse(_minHoleController.text.replaceAll(',', '.')) ?? 0.30;

    final rates = _computeRatesForSpecs(
      layers: _layersCount,
      material: _material,
      foil: _foil,
      finish: _finish,
      maskColor: _maskColor,
      maskSide: _maskSide,
      silkSide: _silkSide,
      orderType: _orderType,
      urgency: _urgency,
      widthMm: w,
      heightMm: h,
      minTrackMm: tr,
      minDrillMm: dr,
      notesText: _notesController.text,
    );

    _basePriceDm2Controller.text = rates.dm2Rate.toStringAsFixed(1);
    _setupFeeController.text = rates.setupFee.toStringAsFixed(1);
  }

  void _syncCurrentFormBackToBoardList() {
    if (_blankBoardsList.isEmpty || _selectedBoardIdx < 0 || _selectedBoardIdx >= _blankBoardsList.length) {
      return;
    }
    final current = Map<String, dynamic>.from(_blankBoardsList[_selectedBoardIdx] as Map);
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0.0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0.0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;

    if (w > 0) current['width'] = w;
    if (h > 0) current['height'] = h;
    current['qty'] = qty;
    current['layers'] = _layersCount;
    current['material'] = _material;
    current['thickness'] = _thickness;
    current['foil'] = _foil;
    current['finish'] = _finish;
    current['order_type'] = _orderType;
    current['urgency'] = _urgency;
    current['mask_side'] = _maskSide;
    current['mask_color'] = _maskColor;
    current['silk_side'] = _silkSide;
    current['silk_color'] = _silkColor;
    current['contour'] = _contour;
    current['electro_test'] = _electroTest;
    current['customer'] = _customerController.text.trim();
    if (_manualPriceOverride) {
      current['manual_dm2_rate'] = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.'));
      current['manual_setup_fee'] = double.tryParse(_setupFeeController.text.replaceAll(',', '.'));
    }
    _blankBoardsList[_selectedBoardIdx] = current;
  }

  void _resetAllFieldsToDefault({bool showToast = true}) {
    _analysis = null;
    _blankBoardsList = [];
    _selectedBoardIdx = 0;
    _manualPriceOverride = false;
    _webPriceResult = null;
    _webPriceDetails = null;
    _customerController.clear();
    _orderNameController.clear();
    _widthController.text = '0.0';
    _heightController.text = '0.0';
    _qtyController.text = '10';
    _extraQtysController.clear();
    _minTrackController.text = '0.15';
    _minHoleController.text = '0.30';
    _notesController.clear();
    _orderType = 'Новый';
    _urgency = 'Серийный';
    _layersCount = 2;
    _material = 'FR4';
    _thickness = '1.5';
    _foil = '18';
    _maskSide = 'С двух сторон';
    _maskColor = 'Зеленая';
    _silkSide = 'С двух сторон';
    _silkColor = 'Белая';
    _finish = 'HAL (ПОС-63)';
    _contour = 'фрезеровка';
    _electroTest = true;
    _recalculateTariffFromSpecs(force: true);

    if (showToast) {
      _showSnack('Проект очищен. Готово к загрузке нового файла или архива!');
    }
  }

  void _clearCurrentProject() {
    setState(() {
      _resetAllFieldsToDefault(showToast: true);
    });
  }

  String _normalizeUrgency(String? raw) {
    final u = (raw ?? '').toLowerCase();
    if (u.contains('супер')) return 'СуперЭкспресс';
    if (u.contains('экспресс') || u.contains('ускорен') || u.contains('срочн')) return 'Экспресс';
    return 'Серийный';
  }

  String _parseColorFromText(String raw, String fallback) {
    final low = raw.toLowerCase();
    if (low.contains('син')) return 'Синяя';
    if (low.contains('черн') || low.contains('чёрн')) return 'Черная';
    if (low.contains('бел')) return 'Белая';
    if (low.contains('красн')) return 'Красная';
    if (low.contains('зелен') || low.contains('зелён')) return 'Зеленая';
    return fallback;
  }

  void _applyBoardFromBlank(Map board, String baseTitle) {
    if (board['customer'] != null && board['customer'].toString().isNotEmpty) {
      _customerController.text = board['customer'].toString();
    }
    final bName = board['board_name']?.toString().trim() ?? '';
    if (bName.isNotEmpty) {
      final lowBase = baseTitle.toLowerCase();
      final isGenericArchive = lowBase == 'платы' ||
          lowBase == 'gerber' ||
          lowBase == 'заказ' ||
          lowBase.contains('запрос') ||
          baseTitle.isEmpty;
      _orderNameController.text = (isGenericArchive || bName.contains(baseTitle))
          ? bName
          : '$baseTitle ($bName)';
    } else {
      _orderNameController.text = baseTitle;
    }

    if (board['order_type'] != null) {
      _orderType = board['order_type'].toString();
    }
    if (board['urgency'] != null) {
      _urgency = _normalizeUrgency(board['urgency'].toString());
    }
    if (board['width'] != null && board['height'] != null) {
      final wVal = (board['width'] as num).toDouble();
      final hVal = (board['height'] as num).toDouble();
      if (wVal > 0 && hVal > 0) {
        _widthController.text = wVal.toStringAsFixed(1);
        _heightController.text = hVal.toStringAsFixed(1);
      } else {
        _widthController.text = '0.0';
        _heightController.text = '0.0';
      }
    }
    if (board['qty'] != null) {
      _qtyController.text = board['qty'].toString();
    }
    if (board['layers'] != null) {
      _layersCount = (board['layers'] as num).toInt();
    }
    if (board['material'] != null) {
      _material = board['material'].toString();
    }
    if (board['thickness'] != null) {
      const validThick = ['0.5', '0.8', '1.0', '1.5', '1.6', '2.0', '2.5', '3.0'];
      final rawD = double.tryParse(board['thickness'].toString().replaceAll(',', '.'));
      final tStr = rawD != null ? rawD.toStringAsFixed(1) : board['thickness'].toString();
      if (validThick.contains(tStr)) _thickness = tStr;
    }
    if (board['foil'] != null) {
      const validFoil = ['12', '18', '35', '50', '70', '105'];
      final fStr = board['foil'].toString();
      if (validFoil.contains(fStr)) _foil = fStr;
    }
    if (board['mask_side'] != null) {
      final rawMs = board['mask_side'].toString();
      final ms = rawMs.toLowerCase();
      if (ms.contains('двух') || ms.contains('2')) {
        _maskSide = 'С двух сторон';
      } else if (ms.contains('низ') || ms.contains('bot')) {
        _maskSide = 'С одной стороны (низ)';
      } else if (ms.contains('одной') || ms.contains('верх') || ms.contains('top') || ms.contains('1') || ms.contains('только верх')) {
        _maskSide = 'С одной стороны (верх)';
      } else if (ms.contains('без') || ms.contains('нет')) {
        _maskSide = 'Без маски';
      }
      _maskColor = _parseColorFromText(rawMs, _maskColor);
    }
    if (board['mask_color'] != null) {
      _maskColor = _parseColorFromText(board['mask_color'].toString(), _maskColor);
    }
    if (board['silk_side'] != null) {
      final rawSs = board['silk_side'].toString();
      final ss = rawSs.toLowerCase();
      if (ss.contains('двух') || ss.contains('2')) {
        _silkSide = 'С двух сторон';
      } else if (ss.contains('низ') || ss.contains('bot')) {
        _silkSide = 'С одной стороны (низ)';
      } else if (ss.contains('одной') || ss.contains('верх') || ss.contains('top') || ss.contains('1') || ss.contains('только верх')) {
        _silkSide = 'С одной стороны (верх)';
      } else if (ss.contains('без') || ss.contains('нет')) {
        _silkSide = 'Без маркировки';
      }
      _silkColor = _parseColorFromText(rawSs, _silkColor);
    }
    if (board['silk_color'] != null) {
      _silkColor = _parseColorFromText(board['silk_color'].toString(), _silkColor);
    }
    if (board['finish'] != null) {
      final fin = board['finish'].toString().toLowerCase();
      if (fin.contains('иммерс') || fin.contains('золот') || fin.contains('enig')) {
        _finish = 'Иммерсионное золото';
      } else if (fin.contains('олов')) {
        _finish = 'Иммерсионное олово';
      } else if (fin.contains('без')) {
        _finish = 'Без покрытия';
      } else {
        _finish = 'HAL (ПОС-63)';
      }
    }
    if (board['contour'] != null) {
      final cnt = board['contour'].toString().toLowerCase();
      if (cnt.contains('фрез') && (cnt.contains('скрайб') || cnt.contains('v-cut'))) {
        _contour = 'фрезеровка + скрайб';
      } else if (cnt.contains('скрайб') || cnt.contains('v-cut')) {
        _contour = 'скрайбирование';
      } else {
        _contour = 'фрезеровка';
      }
    }
    if (board['electro_test'] != null) {
      _electroTest = board['electro_test'] == true;
    }

    final List combinedNotes = [];
    if (board['notes'] is List) {
      for (final item in (board['notes'] as List)) {
        final n = item.toString();
        if (_layersCount < 4) {
          final nl = n.toLowerCase();
          if (nl.contains('попарн') || nl.contains('вариант мпп') || nl.contains('между слоями') || nl.contains('прессован')) {
            continue;
          }
        }
        combinedNotes.add(n);
      }
    }
    if (_analysis != null && _analysis!.extraTextAlerts.isNotEmpty) {
      for (final alert in _analysis!.extraTextAlerts) {
        if (!combinedNotes.contains(alert.toString())) {
          combinedNotes.add(alert.toString());
        }
      }
    }
    _notesController.text = combinedNotes.join('; ');

    _manualPriceOverride = false;
    _webPriceResult = null;
    _webPriceDetails = null;
    if (board['manual_dm2_rate'] != null) {
      _manualPriceOverride = true;
      _basePriceDm2Controller.text = (board['manual_dm2_rate'] as num).toDouble().toStringAsFixed(1);
      if (board['manual_setup_fee'] != null) {
        _setupFeeController.text = (board['manual_setup_fee'] as num).toDouble().toStringAsFixed(1);
      }
    } else {
      _recalculateTariffFromSpecs(force: true);
    }

    if (board['kp_price_with_vat'] != null) {
      final kpSum = (board['kp_price_with_vat'] as num).toDouble();
      final kpDays = board['kp_days']?.toString() ?? '';
      _webPriceResult = '${kpSum.toStringAsFixed(2)} руб.';
      _webPriceDetails = 'Цена из загруженного КП завода (срок: $kpDays раб. дн.)';
    }
  }

  Future<void> _openExtractedFile(String? path, String fileName) async {
    if (path == null || !File(path).existsSync()) {
      _showSnack('Файл $fileName недоступен для открытия.');
      return;
    }
    await OpenFilex.open(path);
  }

  String _buildDocParserPythonCode() {
    const lines = [
      r'# -*- coding: utf-8 -*-',
      r'import json, re, subprocess, sys',
      r'DOC_PATH = sys.argv[1]',
      r'OUT_JSON = sys.argv[2]',
      r'def ensure_pkg(pkg):',
      r'    try:',
      r'        __import__(pkg)',
      r'    except ImportError:',
      r'        subprocess.run([sys.executable, "-m", "pip", "install", "-q", pkg], check=False)',
      r'def is_reddish_rgb(rgb_str):',
      r'    if not rgb_str: return False',
      r'    s = str(rgb_str).strip().upper()',
      r'    if len(s) == 8: s = s[2:]',
      r'    if len(s) != 6 or not re.fullmatch(r"[0-9A-F]{6}", s): return False',
      r'    r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)',
      r'    return r >= 150 and g <= 95 and b <= 95 and (r - max(g, b)) >= 80',
      r'def is_highlight_fill(rgb_str):',
      r'    if not rgb_str: return False',
      r'    s = str(rgb_str).strip().upper()',
      r'    if len(s) == 8: s = s[2:]',
      r'    if len(s) != 6 or not re.fullmatch(r"[0-9A-F]{6}", s): return False',
      r'    if s in ("FFFFFF", "000000", "D9D9D9", "F2F2F2", "E7E6E6", "EDEDED"): return False',
      r'    r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)',
      r'    return (r >= 200 and g >= 180 and b <= 130) or is_reddish_rgb(s)',
      r'def parse_pdf_tkp(path):',
      r'    ensure_pkg("pypdf")',
      r'    import pypdf',
      r'    reader = pypdf.PdfReader(path)',
      r'    full_text = "\n".join((p.extract_text() or "") for p in reader.pages)',
      r'    customer = ""',
      r'    for line in full_text.splitlines():',
      r'        s = line.strip()',
      r'        if "АО «" in s or "ООО «" in s or "ФГУП" in s or "ПАО" in s or "ЗАО" in s:',
      r'            if "ЭЛЕКТРОКОННЕКТ" not in s.upper():',
      r'                customer = s',
      r'                break',
      r'    boards = []',
      r'    pattern = re.compile(r"^\s*(\d+)\s+([А-ЯA-Z0-9\-\.\s\[\]]+?)\s+(Плата\s+печатная(?:\s+многослойная)?)\s+Шт\.?\s+(\d+)", re.M | re.I)',
      r'    for m in pattern.finditer(full_text):',
      r'        code = re.sub(r"\s+", " ", m.group(2)).strip()',
      r'        kind = m.group(3).lower()',
      r'        qty = int(m.group(4))',
      r'        layers = 4 if "многослой" in kind else 2',
      r'        boards.append({',
      r'            "customer": customer,',
      r'            "board_name": code,',
      r'            "qty": qty,',
      r'            "layers": layers,',
      r'            "order_type": "Новый",',
      r'            "urgency": "Серийный",',
      r'            "finish": "HAL (ПОС-63)",',
      r'            "notes": ["Приёмка: ОТК" if "отк" in full_text.lower() else "Запрос ТКП из PDF"],',
      r'        })',
      r'    if not boards:',
      r'        for line in full_text.splitlines():',
      r'            m2 = re.match(r"^\s*(\d+)\s+(\S+(?:\s+\S+){0,3})\s+Плата\s+печатная", line.strip(), re.I)',
      r'            if m2:',
      r'                q_m = re.search(r"Шт\.?\s*(\d+)", line, re.I)',
      r'                qty = int(q_m.group(1)) if q_m else 10',
      r'                layers = 4 if "многослой" in line.lower() else 2',
      r'                boards.append({',
      r'                    "customer": customer,',
      r'                    "board_name": m2.group(2).strip(),',
      r'                    "qty": qty,',
      r'                    "layers": layers,',
      r'                    "order_type": "Новый",',
      r'                    "urgency": "Серийный",',
      r'                    "finish": "HAL (ПОС-63)",',
      r'                    "notes": ["Запрос ТКП из PDF"],',
      r'                })',
      r'    return boards',
      r'def read_excel_with_colors(path):',
      r'    rows_text = []',
      r'    red_notes = []',
      r'    if path.lower().endswith(".xlsx"):',
      r'        ensure_pkg("openpyxl")',
      r'        import openpyxl',
      r'        wb = openpyxl.load_workbook(path, data_only=True)',
      r'        ws = wb.active',
      r'        for r in range(1, min(90, ws.max_row + 1)):',
      r'            r_vals = []',
      r'            for c in range(1, min(60, ws.max_column + 1)):',
      r'                cell = ws.cell(r, c)',
      r'                val = "" if cell.value is None else str(cell.value).strip()',
      r'                r_vals.append(val)',
      r'                if val and len(val) > 2:',
      r'                    try:',
      r'                        fnt = cell.font',
      r'                        is_b = bool(fnt and fnt.bold)',
      r'                        col = fnt.color if fnt else None',
      r'                        rgb = str(col.rgb) if col and col.rgb else ""',
      r'                        th = col.theme if col and col.theme is not None else -1',
      r'                        fill_rgb = str(cell.fill.start_color.rgb) if cell.fill and cell.fill.fill_type and cell.fill.start_color else ""',
      r'                        if is_reddish_rgb(rgb) or th in (5, 9):',
      r'                            tag = "[ЖИРНЫМ КРАСНЫМ В EXCEL]: " if is_b else "[КРАСНЫМ В EXCEL]: "',
      r'                            red_notes.append(tag + val)',
      r'                        elif is_highlight_fill(fill_rgb):',
      r'                            red_notes.append("[ВЫДЕЛЕНО ЦВЕТОМ В EXCEL]: " + val)',
      r'                        elif is_b and r >= 12 and c >= 6 and len(val) >= 5 and not re.fullmatch(r"[\d.,\s]+", val):',
      r'                            if val.lower() not in ("новый", "повтор", "серийный", "фрезеровка", "с двух сторон", "да", "нет", "любой", "отсутствует", "открыты", "под маской"):',
      r'                                red_notes.append("[ЖИРНЫМ В EXCEL]: " + val)',
      r'                    except Exception:',
      r'                        pass',
      r'            rows_text.append(r_vals)',
      r'        return rows_text, red_notes',
      r'    ensure_pkg("xlrd")',
      r'    import xlrd',
      r'    try:',
      r'        wb = xlrd.open_workbook(path, formatting_info=True)',
      r'        has_fmt = True',
      r'    except Exception:',
      r'        wb = xlrd.open_workbook(path)',
      r'        has_fmt = False',
      r'    sh = wb.sheet_by_index(0)',
      r'    for r in range(min(90, sh.nrows)):',
      r'        r_vals = []',
      r'        for c in range(min(60, sh.ncols)):',
      r'            val = str(sh.cell_value(r, c)).strip()',
      r'            r_vals.append(val)',
      r'            if has_fmt and val and len(val) > 2:',
      r'                try:',
      r'                    xf = wb.xf_list[sh.cell_xf_index(r, c)]',
      r'                    font = wb.font_list[xf.font_index]',
      r'                    is_b = bool(getattr(font, "bold", 0) or getattr(font, "weight", 400) >= 600)',
      r'                    rgb = wb.colour_map.get(font.colour_index)',
      r'                    bg_rgb = wb.colour_map.get(xf.background.pattern_colour_index) if hasattr(xf, "background") else None',
      r'                    is_red = bool(rgb and rgb[0] >= 150 and rgb[1] <= 95 and rgb[2] <= 95 and (rgb[0] - max(rgb[1], rgb[2])) >= 80)',
      r'                    is_bg_warn = bool(bg_rgb and ((bg_rgb[0] >= 200 and bg_rgb[1] >= 180 and bg_rgb[2] <= 130) or (bg_rgb[0] >= 180 and bg_rgb[1] <= 90 and bg_rgb[2] <= 90)))',
      r'                    if is_red:',
      r'                        tag = "[ЖИРНЫМ КРАСНЫМ В EXCEL]: " if is_b else "[КРАСНЫМ В EXCEL]: "',
      r'                        red_notes.append(tag + val)',
      r'                    elif is_bg_warn:',
      r'                        red_notes.append("[ВЫДЕЛЕНО ЦВЕТОМ В EXCEL]: " + val)',
      r'                    elif is_b and r >= 11 and c >= 4 and len(val) >= 5 and not re.fullmatch(r"[\d.,\s]+", val):',
      r'                        if val.lower() not in ("новый", "повтор", "серийный", "фрезеровка", "с двух сторон", "да", "нет", "любой", "отсутствует", "открыты", "под маской"):',
      r'                            red_notes.append("[ЖИРНЫМ В EXCEL]: " + val)',
      r'                except Exception:',
      r'                    pass',
      r'        rows_text.append(r_vals)',
      r'    return rows_text, red_notes',
      r'def clean_num_str(s):',
      r'    return re.sub(r"\.0$", "", s.strip())',
      r'def parse_kp_format(rows):',
      r'    full_txt = "\n".join(" ".join(x for x in r if x) for r in rows)',
      r'    if "коммерческое предложение" not in full_txt.lower():',
      r'        return None',
      r'    customer = ""',
      r'    for r in rows:',
      r'        ne = [x for x in r if x]',
      r'        if len(ne) >= 2 and "заказчик" in ne[0].lower():',
      r'            customer = ne[1]',
      r'            break',
      r'    boards = []',
      r'    for idx, r in enumerate(rows):',
      r'        ne = [x for x in r if x]',
      r'        if len(ne) >= 7 and re.fullmatch(r"\d+(?:\.0)?", ne[0]) and "печатные платы" in ne[1].lower():',
      r'            b_name = ne[1].replace("Печатные платы", "").strip()',
      r'            days = int(float(ne[2])) if re.match(r"^\d+", ne[2]) else 14',
      r'            qty = int(float(ne[5])) if re.match(r"^\d+", ne[5]) else 10',
      r'            sum_vat = float(ne[-1].replace(",", ".")) if re.match(r"^\d", ne[-1]) else 0.0',
      r'            urg = "СуперЭкспресс" if days <= 4 else ("Экспресс" if days <= 8 else "Серийный")',
      r'            b = {"customer": customer, "board_name": f"{b_name} ({days} дн.)", "qty": qty, "urgency": urg, "kp_price_with_vat": sum_vat, "kp_days": days, "notes": []}',
      r'            if idx + 1 < len(rows):',
      r'                spec = " ".join(x for x in rows[idx + 1] if x)',
      r'                b["order_type"] = "Повтор" if "повтор" in spec.lower() else "Новый"',
      r'                m_l = re.search(r"(\d+)\s*сл", spec, re.I)',
      r'                if m_l: b["layers"] = int(m_l.group(1))',
      r'                m_sz = re.search(r"(\d+(?:[.,]\d+)?)\s*[xхXХ*×]\s*(\d+(?:[.,]\d+)?)", spec)',
      r'                if m_sz:',
      r'                    b["width"] = float(m_sz.group(1).replace(",", "."))',
      r'                    b["height"] = float(m_sz.group(2).replace(",", "."))',
      r'                m_th = re.search(r"-(\d+(?:[.,]\d+)?)\s*мм-", spec)',
      r'                if m_th: b["thickness"] = m_th.group(1).replace(",", ".")',
      r'                m_fl = re.search(r"-(\d+)\s*мкм", spec)',
      r'                if m_fl: b["foil"] = m_fl.group(1)',
      r'                if "tg170" in spec.lower(): b["material"] = "FR4 Tg170"',
      r'                elif "rogers" in spec.lower(): b["material"] = "Rogers"',
      r'                elif "алюмин" in spec.lower(): b["material"] = "Алюминий"',
      r'                if "золот" in spec.lower(): b["finish"] = "Иммерсионное золото"',
      r'                elif "олов" in spec.lower(): b["finish"] = "Иммерсионное олово"',
      r'                elif "пос" in spec.lower() or "hal" in spec.lower(): b["finish"] = "HAL (ПОС-63)"',
      r'                b["electro_test"] = ("эл. тест" in spec.lower())',
      r'                if "маркировка: с одной" in spec.lower(): b["silk_side"] = "С одной стороны (верх)"',
      r'                elif "маркировка: без" in spec.lower(): b["silk_side"] = "Без маркировки"',
      r'            boards.append(b)',
      r'    return boards if boards else None',
      r'def main():',
      r'    try:',
      r'        if DOC_PATH.lower().endswith(".pdf"):',
      r'            pdf_boards = parse_pdf_tkp(DOC_PATH)',
      r'            open(OUT_JSON, "w", encoding="utf-8").write(json.dumps({"ok": bool(pdf_boards), "boards": pdf_boards}, ensure_ascii=False))',
      r'            return',
      r'        rows, red_notes = read_excel_with_colors(DOC_PATH)',
      r'    except Exception as e:',
      r'        open(OUT_JSON, "w", encoding="utf-8").write(json.dumps({"ok": False, "error": str(e)}))',
      r'        return',
      r'    kp_boards = parse_kp_format(rows)',
      r'    if kp_boards:',
      r'        open(OUT_JSON, "w", encoding="utf-8").write(json.dumps({"ok": True, "boards": kp_boards}, ensure_ascii=False))',
      r'        return',
      r'    customer = ""',
      r'    global_material = None',
      r'    global_notes = list(red_notes)',
      r'    num_boards = 1',
      r'    for r_i, row in enumerate(rows):',
      r'        ne = [x for x in row if x]',
      r'        if not ne: continue',
      r'        rj = " ".join(ne).lower()',
      r'        if "tg170" in rj or "tg 170" in rj or "htg" in rj: global_material = "FR4 Tg170"',
      r'        elif "rogers" in rj: global_material = "Rogers"',
      r'        elif "алюмин" in rj: global_material = "Алюминий"',
      r'        if "полуотверст" in rj: global_notes.append("Металлизированные полуотверстия")',
      r'        if "зенков" in rj: global_notes.append("Требуется зенковка отверстий")',
      r'        if "импеданс" in rj: global_notes.append("Контроль волнового сопротивления (импеданс)")',
      r'        if "реперн" in rj: global_notes.append("Нанести реперные знаки на полях заготовки")',
      r'        if "отк" in [x.strip().lower() for x in ne]: global_notes.append("Приёмка: ОТК")',
      r'        if "фаска" in rj:',
      r'            for x in ne:',
      r'                if "фаска" in x.lower(): global_notes.append(x)',
      r'        if "иное:" in rj or "иные требован" in rj or rj.startswith("иное") or "дополнительные требован" in rj or "особые требован" in rj:',
      r'            extra = [x for x in ne if not re.match(r"^(иное|иные|примечан|особые|дополнительные)", x.lower())]',
      r'            if extra:',
      r'                global_notes.append("Требование: " + " ".join(extra))',
      r'            elif r_i + 1 < len(rows):',
      r'                next_ne = [x for x in rows[r_i + 1] if x]',
      r'                if next_ne: global_notes.append("Доп. требование: " + " ".join(next_ne))',
      r'        lbl = ne[0].lower()',
      r'        vals = ne[1:]',
      r'        if re.fullmatch(r"\d+\.?", lbl) and len(ne) >= 3:',
      r'            lbl = ne[1].lower()',
      r'            vals = ne[2:]',
      r'        if ("размеры платы" in lbl or "точные размеры" in lbl or "имя файла" in lbl) and len(vals) > num_boards:',
      r'            num_boards = min(len(vals), 12)',
      r'    boards = [{"notes": list(global_notes)} for _ in range(num_boards)]',
      r'    if global_material:',
      r'        for b in boards: b["material"] = global_material',
      r'    for row in rows:',
      r'        ne = [x for x in row if x]',
      r'        if len(ne) < 2: continue',
      r'        lbl, vals = ne[0].lower(), ne[1:]',
      r'        if re.fullmatch(r"\d+\.?", lbl) and len(ne) >= 3:',
      r'            lbl, vals = ne[1].lower(), ne[2:]',
      r'        if ("заказчик" in lbl and "название" in lbl) or lbl in ("заказчик", "организация", "предприятие", "компания"):',
      r'            customer = vals[0]',
      r'            for b in boards: b["customer"] = customer',
      r'            continue',
      r'        for idx in range(num_boards):',
      r'            val = vals[idx] if idx < len(vals) else vals[0]',
      r'            b = boards[idx]',
      r'            if "тип заказа" in lbl: b["order_type"] = "Повтор" if "повтор" in val.lower() else "Новый"',
      r'            elif "срочность" in lbl or "вариант и срочность" in lbl:',
      r'                b["urgency"] = val',
      r'            elif "имя файла" in lbl or "название печатной платы" in lbl or "децимальн" in lbl or "обозначен" in lbl:',
      r'                b["board_name"] = clean_num_str(val)',
      r'            elif "количество плат" in lbl or "тираж" in lbl:',
      r'                m = re.search(r"(\d+)", val)',
      r'                if m: b["qty"] = int(m.group(1))',
      r'            elif "формат поставки" in lbl and val.lower() not in ("нет", "-", ""):',
      r'                b["notes"].append("Формат поставки: " + val)',
      r'            elif "размер единичной платы" in lbl or "размеры платы" in lbl or "точные размеры" in lbl or "габарит" in lbl:',
      r'                if len(vals) >= 4 and vals[0].upper() == "X" and vals[2].upper() == "Y":',
      r'                    b["width"] = float(vals[1].replace(",", "."))',
      r'                    b["height"] = float(vals[3].replace(",", "."))',
      r'                else:',
      r'                    m = re.search(r"(\d+(?:[.,]\d+)?)\s*[xхXХ*×]\s*(\d+(?:[.,]\d+)?)", val)',
      r'                    if m:',
      r'                        b["width"] = float(m.group(1).replace(",", "."))',
      r'                        b["height"] = float(m.group(2).replace(",", "."))',
      r'            elif "количество слоев" in lbl or "количество слоёв" in lbl or "слойност" in lbl:',
      r'                m = re.search(r"(\d+)", val)',
      r'                if m: b["layers"] = int(m.group(1))',
      r'            elif "материал основания" in lbl:',
      r'                vl = val.lower()',
      r'                if "tg170" in vl or "htg" in vl: b["material"] = "FR4 Tg170"',
      r'                elif "rogers" in vl: b["material"] = "Rogers"',
      r'                elif "алюмин" in vl: b["material"] = "Алюминий"',
      r'                else: b["material"] = "FR4"',
      r'            elif "толщина платы" in lbl or "толщина готовой платы" in lbl or "толщина стеклотекстолита" in lbl:',
      r'                m = re.search(r"(\d+(?:[.,]\d+)?)", val)',
      r'                if m: b["thickness"] = m.group(1).replace(",", ".")',
      r'            elif "толщина фольги" in lbl or "толщина меди" in lbl or "фольга" in lbl:',
      r'                nums = [int(x) for x in re.findall(r"(\d+)", val)]',
      r'                if nums: b["foil"] = str(max(nums))',
      r'            elif "цвет маски" in lbl or "цвет паяльной" in lbl: b["mask_color"] = val',
      r'            elif "паяльная маска" in lbl or "наличие маски" in lbl or lbl.startswith("маска"):',
      r'                b["mask_side"] = val',
      r'                for j in range(len(vals) - 1):',
      r'                    if "цвет" in vals[j].lower(): b["mask_color"] = vals[j + 1]',
      r'            elif "маркировка" in lbl or "шелкограф" in lbl: b["silk_side"] = val',
      r'            elif ("финишное покрытие" in lbl or "покрыт" in lbl) and "ножев" not in lbl and "концев" not in lbl and "ламель" not in lbl and "разъем" not in lbl and "разъём" not in lbl:',
      r'                v_low = val.lower()',
      r'                if "иммерс" in v_low or "золот" in v_low or "enig" in v_low:',
      r'                    b["finish"] = "Иммерсионное золото"',
      r'                elif "олов" in v_low:',
      r'                    b["finish"] = "Иммерсионное олово"',
      r'                elif "без" in v_low:',
      r'                    b["finish"] = "Без покрытия"',
      r'                else:',
      r'                    b["finish"] = "HAL (ПОС-63)"',
      r'            elif ("ножевых" in lbl or "концев" in lbl or "ламель" in lbl) and val.lower() not in ("нет", "-", "0", "", "отсутствует", "отсутствуют"):',
      r'                b["notes"].append("Разъёмы/ламели: " + val)',
      r'            elif "вариант мпп" in lbl and val.lower() not in ("нет", "-", "", "отсутствует", "любой"):',
      r'                b["notes"].append("Вариант МПП: " + val)',
      r'            elif ("переходные отверстия" in lbl or "забиванию отверстий" in lbl) and val.lower() not in ("нет", "-", ""):',
      r'                b["notes"].append("Переходные отверстия: " + val)',
      r'            elif "файл сверловки" in lbl and val.lower() not in ("нет", "-", ""):',
      r'                b["notes"].append("Сверловка: " + val)',
      r'            elif "электроконтрол" in lbl or "электротест" in lbl: b["electro_test"] = ("нет" not in val.lower())',
      r'            elif "обработки контура" in lbl or "контур" in lbl: b["contour"] = val.lower()',
      r'    for b in boards:',
      r'        seen = set()',
      r'        u = []',
      r'        for n in b["notes"]:',
      r'            norm = re.sub(r"^\[.*?\]:\s*", "", n).strip()',
      r'            if norm not in seen:',
      r'                seen.add(norm)',
      r'                u.append(n)',
      r'        b["notes"] = u',
      r'    open(OUT_JSON, "w", encoding="utf-8").write(json.dumps({"ok": True, "boards": boards}, ensure_ascii=False))',
      r'if __name__ == "__main__": main()',
    ];
    return lines.join('\n');
  }

  Future<dynamic> _parseDocumentBlank(String docPath) async {
    if (!Platform.isWindows) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final pyFile = File('${tempDir.path}\\parse_ec_doc.py');
      final outJson = File('${tempDir.path}\\ec_doc_parsed.json');
      if (outJson.existsSync()) outJson.deleteSync();

      final ext = docPath.split('.').last.toLowerCase();
      final cleanDocPath = '${tempDir.path}\\clean_doc_${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File(docPath).copy(cleanDocPath);

      await pyFile.writeAsString(_buildDocParserPythonCode(), encoding: utf8);
      await Process.run('python', [pyFile.path, cleanDocPath, outJson.path], runInShell: true);

      if (outJson.existsSync()) {
        final raw = await outJson.readAsString(encoding: utf8);
        final parsed = jsonDecode(raw) as Map;
        if (parsed['ok'] == true && parsed['boards'] is List && (parsed['boards'] as List).isNotEmpty) {
          return parsed['boards'] as List;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _extractExternalArchiveToDir(String archivePath, Directory targetDir) async {
    if (!Platform.isWindows) return false;
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

    const winrarCandidates = [
      r'C:\Program Files\WinRAR\UnRAR.exe',
      r'C:\Program Files\WinRAR\WinRAR.exe',
      r'C:\Program Files (x86)\WinRAR\UnRAR.exe',
      r'C:\Program Files (x86)\WinRAR\WinRAR.exe',
    ];
    for (final exe in winrarCandidates) {
      if (File(exe).existsSync()) {
        final res = await Process.run(exe, ['x', '-o+', '-y', archivePath, '${targetDir.path}\\']);
        if (res.exitCode == 0) return true;
      }
    }

    const sevenZipCandidates = [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];
    for (final exe in sevenZipCandidates) {
      if (File(exe).existsSync()) {
        final res = await Process.run(exe, ['x', '-y', '-o${targetDir.path}', archivePath]);
        if (res.exitCode == 0) return true;
      }
    }

    try {
      final res = await Process.run('tar', ['-xf', archivePath, '-C', targetDir.path]);
      if (res.exitCode == 0) return true;
    } catch (_) {}

    return false;
  }

  String _buildPlaywrightCalcPythonCode(double w, double h, int qty, String outJsonPath) {
    final lines = [
      r'# -*- coding: utf-8 -*-',
      r'import json, re',
      r'from playwright.sync_api import sync_playwright',
      'WIDTH = "${w.toStringAsFixed(1)}"',
      'HEIGHT = "${h.toStringAsFixed(1)}"',
      'QTY = "$qty"',
      'LAYERS = "$_layersCount"',
      'THICKNESS = "$_thickness"',
      'FOIL = "$_foil"',
      'MASK_SIDE = "$_maskSide"',
      'FINISH = "$_finish"',
      'ORDER_TYPE = "$_orderType"',
      'URGENCY = "$_urgency"',
      'OUT_JSON = r"$outJsonPath"',
      r'def fill_ctx(ctx, kws, val):',
      r'    inputs = ctx.locator("input:not([type=hidden]):not([type=radio]):not([type=checkbox]):not([type=submit]):not([type=button])")',
      r'    for i in range(inputs.count()):',
      r'        inp = inputs.nth(i)',
      r'        try:',
      r'            if not inp.is_visible() or not inp.is_editable(): continue',
      r'            attrs = ((inp.get_attribute("name") or "") + " " + (inp.get_attribute("id") or "") + " " + (inp.get_attribute("placeholder") or "") + " " + (inp.get_attribute("aria-label") or "")).lower()',
      r'            near = ""',
      r'            for xp in ["xpath=..", "xpath=../..", "xpath=../../.."]:',
      r'                try:',
      r'                    t = inp.locator(xp).inner_text().lower()',
      r'                    if len(t) < 180: near += " " + t',
      r'                except Exception: pass',
      r'            if any(k in (attrs + " " + near) for k in kws):',
      r'                inp.click()',
      r'                inp.fill("")',
      r'                inp.type(str(val), delay=30)',
      r'                inp.dispatch_event("input")',
      r'                inp.dispatch_event("change")',
      r'                inp.press("Tab")',
      r'                return True',
      r'        except Exception: pass',
      r'    return False',
      r'def select_or_click(ctx, variants):',
      r'    selects = ctx.locator("select")',
      r'    for s_idx in range(selects.count()):',
      r'        sel = selects.nth(s_idx)',
      r'        try:',
      r'            opts = sel.locator("option")',
      r'            for o_idx in range(opts.count()):',
      r'                otxt = opts.nth(o_idx).inner_text().strip()',
      r'                if any(v.lower() in otxt.lower() for v in variants):',
      r'                    oval = opts.nth(o_idx).get_attribute("value")',
      r'                    sel.select_option(value=oval)',
      r'                    sel.dispatch_event("change")',
      r'                    return True',
      r'        except Exception: pass',
      r'    for txt in variants:',
      r'        loc = ctx.locator("label, button, span, div, li, a").filter(has_text=re.compile(re.escape(txt), re.I))',
      r'        for i in range(loc.count()):',
      r'            el = loc.nth(i)',
      r'            try:',
      r'                if el.is_visible() and len(el.inner_text().strip()) < 60:',
      r'                    el.click(timeout=1000)',
      r'                    return True',
      r'            except Exception: pass',
      r'    return False',
      r'def main():',
      r'    res = {"ok": False, "price": "", "raw": "", "error": ""}',
      r'    try:',
      r'        with sync_playwright() as p:',
      r'            browser = p.chromium.launch(headless=False)',
      r'            page = browser.new_page(viewport={"width": 1400, "height": 950})',
      r'            page.goto("https://pselectro.ru/calculate-cost/", timeout=60000, wait_until="domcontentloaded")',
      r'            page.wait_for_timeout(3000)',
      r'            ctxs = [page] + list(page.frames)',
      r'            for c in ctxs:',
      r'                select_or_click(c, ["Принять", "Согласен"])',
      r'                if LAYERS == "1": select_or_click(c, ["1 слой", "Односторонн"])',
      r'                elif LAYERS == "2": select_or_click(c, ["2 слоя", "Двухсторонн", "Двусторонн"])',
      r'                else: select_or_click(c, [LAYERS + " сло"])',
      r'                fill_ctx(c, ["длина", "width", "x,", "размер x"], WIDTH)',
      r'                fill_ctx(c, ["ширина", "height", "y,", "размер y"], HEIGHT)',
      r'                fill_ctx(c, ["количество", "тираж", "qty", "шт"], QTY)',
      r'                select_or_click(c, [THICKNESS + " мм", THICKNESS])',
      r'                if ORDER_TYPE == "Повтор": select_or_click(c, ["Повтор"])',
      r'                if URGENCY == "СуперЭкспресс": select_or_click(c, ["Суперэкспресс", "Супер экспресс", "Экспресс"])',
      r'                elif URGENCY == "Экспресс": select_or_click(c, ["Экспресс", "Срочн"])',
      r'                if MASK_SIDE == "Без маски": select_or_click(c, ["Без маски"])',
      r'                if "золото" in FINISH.lower(): select_or_click(c, ["Иммерсионное золото", "Иммерс", "ENIG"])',
      r'                elif "олово" in FINISH.lower(): select_or_click(c, ["Иммерсионное олово"])',
      r'            page.wait_for_timeout(1500)',
      r'            for c in ctxs: select_or_click(c, ["Рассчитать", "Посчитать"])',
      r'            page.wait_for_timeout(4000)',
      r'            txt = ""',
      r'            for c in [page] + list(page.frames):',
      r'                try:',
      r'                    txt += "\n" + c.locator("body").inner_text()',
      r'                    for inp in c.locator("input").all():',
      r'                        v = inp.input_value()',
      r'                        if v: txt += "\nVAL: " + v',
      r'                except Exception: pass',
      r'            found = []',
      r'            for m in re.findall(r"(?:итого|стоимость|сумма|цена|всего)[^\d\n]{0,35}(\d[\d\s]{1,12}(?:[.,]\d{1,2})?)", txt, flags=re.I):',
      r'                cl = re.sub(r"\s+", " ", m).strip()',
      r'                try:',
      r'                    v = float(re.sub(r"[^\d.,]", "", cl).replace(",", "."))',
      r'                    if v >= 200.0: found.append((v, cl))',
      r'                except Exception: pass',
      r'            for m in re.findall(r"(\d[\d\s]{1,12}(?:[.,]\d{1,2})?)\s*(?:руб\.?|р\.|₽)", txt, flags=re.I):',
      r'                cl = re.sub(r"\s+", " ", m).strip()',
      r'                try:',
      r'                    v = float(re.sub(r"[^\d.,]", "", cl).replace(",", "."))',
      r'                    if v >= 200.0: found.append((v, cl))',
      r'                except Exception: pass',
      r'            if found:',
      r'                found.sort(key=lambda x: x[0])',
      r'                res["ok"] = True',
      r'                res["price"] = found[-1][1] + " руб."',
      r'                res["raw"] = "Считано со страницы pselectro.ru (" + URGENCY + ")"',
      r'            else:',
      r'                res["error"] = "На странице pselectro.ru форма расчёта требует отправки файлов менеджеру (онлайн-цена не отображается)."',
      r'            page.wait_for_timeout(2500)',
      r'            browser.close()',
      r'    except Exception as e:',
      r'        res["error"] = str(e)',
      r'    open(OUT_JSON, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False))',
      r'if __name__ == "__main__": main()',
    ];
    return lines.join('\n');
  }

  Future<void> _fetchPriceFromWebsite() async {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;

    if (w <= 0 || h <= 0) {
      _showSnack('Сначала укажите длину X и ширину Y платы (больше 0)!');
      return;
    }

    if (!Platform.isWindows) {
      _showSnack('Автозапрос с сайта через Playwright работает на Windows.');
      return;
    }

    setState(() {
      _isFetchingWebPrice = true;
      _webPriceResult = null;
      _webPriceDetails = 'Открываю pselectro.ru/calculate-cost/ и заполняю форму ($_urgency)...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}\\pselectro_calc_bot.py');
      final resultFile = File('${tempDir.path}\\pselectro_calc_result.json');
      if (resultFile.existsSync()) resultFile.deleteSync();

      await scriptFile.writeAsString(
        _buildPlaywrightCalcPythonCode(w, h, qty, resultFile.path),
        encoding: utf8,
      );

      final procResult = await Process.run('python', [scriptFile.path], runInShell: true);

      if (resultFile.existsSync()) {
        final jsonStr = await resultFile.readAsString(encoding: utf8);
        final data = jsonDecode(jsonStr) as Map;
        if (data['ok'] == true && (data['price']?.toString().isNotEmpty ?? false)) {
          setState(() {
            _webPriceResult = data['price'].toString();
            _webPriceDetails = data['raw']?.toString() ?? 'Актуальный расчёт с pselectro.ru';
          });
          _showSnack('Цена с сайта получена: $_webPriceResult');
        } else {
          final err = data['error']?.toString() ?? 'Не удалось получить цену';
          setState(() => _webPriceDetails = err);
          _showSnack(err);
        }
      } else {
        final stderrText = procResult.stderr.toString().trim();
        setState(() {
          _webPriceDetails = stderrText.isNotEmpty
              ? 'Python ошибка: $stderrText'
              : 'Скрипт завершился без ответа.';
        });
      }
    } catch (e) {
      setState(() => _webPriceDetails = 'Ошибка запуска: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingWebPrice = false);
      }
    }
  }

  Future<String> _saveTempBytes(Directory dir, String rawFileName, List fileBytes) async {
    final safeName = rawFileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final outFile = File('${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
    await outFile.writeAsBytes(fileBytes.cast<int>());
    return outFile.path;
  }

  Future<void> _pickAndAnalyzeZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'rar', 'xls', 'xlsx', 'pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    final selectedFile = File(result.files.single.path!);
    final archiveName = selectedFile.path.split(Platform.pathSeparator).last;
    final archiveDir = selectedFile.parent.path;
    final lowSelected = selectedFile.path.toLowerCase();

    try {
      final tempRoot = await getTemporaryDirectory();
      final sessionUnpackDir = Directory('${tempRoot.path}${Platform.pathSeparator}cam_session_${DateTime.now().millisecondsSinceEpoch}');
      sessionUnpackDir.createSync(recursive: true);

      final List projectFiles = [];
      bool hasUnpackedNestedArchive = false;

      if (lowSelected.endsWith('.xls') || lowSelected.endsWith('.xlsx') || lowSelected.endsWith('.pdf')) {
        projectFiles.add({
          'name': archiveName,
          'bytes': await selectedFile.readAsBytes(),
          'savedPath': selectedFile.path,
        });
      } else if (lowSelected.endsWith('.rar')) {
        final ok = await _extractExternalArchiveToDir(selectedFile.path, sessionUnpackDir);
        if (ok && sessionUnpackDir.existsSync()) {
          for (final entity in sessionUnpackDir.listSync(recursive: true)) {
            if (entity is File) {
              projectFiles.add({
                'name': entity.path.split(Platform.pathSeparator).last,
                'bytes': await entity.readAsBytes(),
                'savedPath': entity.path,
              });
            }
          }
        } else {
          hasUnpackedNestedArchive = true;
        }
      } else {
        final bytes = await selectedFile.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive.files) {
          if (!file.isFile) continue;
          final rawName = file.name.split('/').last.split('\\').last;
          if (rawName.isEmpty || rawName.startsWith('.')) continue;

          final low = rawName.toLowerCase();
          final fileBytes = file.content as List;

          if (low.endsWith('.zip')) {
            try {
              final innerArchive = ZipDecoder().decodeBytes(fileBytes.cast<int>());
              for (final inner in innerArchive.files) {
                if (!inner.isFile) continue;
                final innerName = inner.name.split('/').last.split('\\').last;
                if (innerName.isNotEmpty) {
                  final iBytes = inner.content as List;
                  final p = await _saveTempBytes(sessionUnpackDir, innerName, iBytes);
                  projectFiles.add({'name': innerName, 'bytes': iBytes, 'savedPath': p});
                }
              }
            } catch (_) {
              final p = await _saveTempBytes(sessionUnpackDir, rawName, fileBytes);
              projectFiles.add({'name': rawName, 'bytes': fileBytes, 'savedPath': p});
            }
          } else if (low.endsWith('.rar') || low.endsWith('.7z')) {
            final tempRarPath = await _saveTempBytes(sessionUnpackDir, 'nested_$rawName', fileBytes);
            final nestedOutDir = Directory('${sessionUnpackDir.path}${Platform.pathSeparator}unpacked_${DateTime.now().microsecondsSinceEpoch}');
            final ok = await _extractExternalArchiveToDir(tempRarPath, nestedOutDir);
            if (ok && nestedOutDir.existsSync()) {
              for (final entity in nestedOutDir.listSync(recursive: true)) {
                if (entity is File) {
                  projectFiles.add({
                    'name': entity.path.split(Platform.pathSeparator).last,
                    'bytes': await entity.readAsBytes(),
                    'savedPath': entity.path,
                  });
                }
              }
            } else {
              hasUnpackedNestedArchive = true;
              final p = await _saveTempBytes(sessionUnpackDir, rawName, fileBytes);
              projectFiles.add({'name': rawName, 'bytes': fileBytes, 'savedPath': p});
            }
          } else {
            final p = await _saveTempBytes(sessionUnpackDir, rawName, fileBytes);
            projectFiles.add({'name': rawName, 'bytes': fileBytes, 'savedPath': p});
          }
        }
      }

      final List layers = [];
      final List extraProjectDocs = [];
      final List extraTextAlerts = [];
      int copperLayers = 0;
      bool hasTopMask = false;
      bool hasBottomMask = false;
      bool hasTopSilk = false;
      bool hasBottomSilk = false;
      bool hasBinaryBrd = false;
      bool hasCadSourceOnly = false;
      bool hasTextContour = false;
      final List foundExcelPaths = [];
      final List foundPdfPaths = [];

      double? detectedWidth;
      double? detectedHeight;
      double? fallbackCopperWidth;
      double? fallbackCopperHeight;
      double? minTrackMm;
      double? minDrillMm;
      int totalHoles = 0;
      final Map drillBreakdown = {};

      for (final item in projectFiles) {
        final pf = item as Map;
        final rawName = pf['name'] as String;
        final fileBytes = (pf['bytes'] as List).cast<int>();
        final savedPath = pf['savedPath'] as String;
        final upper = rawName.toUpperCase();
        String role = 'Прочий файл проекта';
        bool importantDoc = false;

        if (upper.endsWith('.RAR') || upper.endsWith('.7Z')) {
          role = 'Нераспакованный RAR (установите WinRAR/7-Zip)';
        } else if (upper.endsWith('.XLS') || upper.endsWith('.XLSX')) {
          role = 'Бланк заказа / КП (читается автоматически)';
          importantDoc = true;
          foundExcelPaths.add(savedPath);
        } else if (upper.endsWith('.PDF')) {
          role = 'Запрос ТКП / чертёж PDF (читается автоматически)';
          importantDoc = true;
          foundPdfPaths.add(savedPath);
          extraProjectDocs.add(rawName);
        } else if (upper.endsWith('.PNG') || upper.endsWith('.JPG') || upper.endsWith('.JPEG') || upper.endsWith('.BMP')) {
          role = 'Чертёж / стек слоёв / ламели (кликните для просмотра)';
          importantDoc = true;
          extraProjectDocs.add(rawName);
        } else if (upper.endsWith('.DOC') || upper.endsWith('.DOCX') || upper.endsWith('.RTF')) {
          role = 'Текстовое ТЗ / пояснение Word (откройте для проверки)';
          importantDoc = true;
          extraProjectDocs.add(rawName);
        } else if (upper.endsWith('.PCB') || upper.endsWith('.PCBDOC') || upper.endsWith('.LAY') || upper.endsWith('.LAY6')) {
          role = 'Исходник платы CAD (.PCB / .LAY)';
          hasCadSourceOnly = true;
          importantDoc = true;
        } else if (upper.endsWith('.TOP') ||
            upper.endsWith('.GTL') ||
            upper.endsWith('.CMP') ||
            upper.contains('F_CU') ||
            upper.contains('TOP_COPPER') ||
            upper.contains('_TOP.')) {
          role = 'Верхний слой меди (TOP)';
          copperLayers++;
        } else if (upper.endsWith('.BOT') ||
            upper.endsWith('.GBL') ||
            upper.endsWith('.SOL') ||
            upper.contains('B_CU') ||
            upper.contains('BOT_COPPER') ||
            upper.contains('_BOT.')) {
          role = 'Нижний слой меди (BOT)';
          copperLayers++;
        } else if (RegExp(r'\.(G[1-9]|IN[1-9]|L[2-9]|GP[1-9])$').hasMatch(upper)) {
          role = 'Внутренний слой меди';
          copperLayers++;
        } else if (upper.endsWith('.TMS') ||
            upper.endsWith('.GTS') ||
            upper.endsWith('.STC') ||
            upper.contains('F_MASK') ||
            upper.contains('TOPMASK')) {
          role = 'Верхняя паяльная маска';
          hasTopMask = true;
        } else if (upper.endsWith('.BMS') ||
            upper.endsWith('.GBS') ||
            upper.endsWith('.STS') ||
            upper.contains('B_MASK') ||
            upper.contains('BOTMASK')) {
          role = 'Нижняя паяльная маска';
          hasBottomMask = true;
        } else if (upper.endsWith('.GTO') ||
            upper.endsWith('.TSK') ||
            upper.endsWith('.PLC') ||
            upper.contains('F_SILK') ||
            upper.contains('TOPSILK')) {
          role = 'Верхняя маркировка (шелкография)';
          hasTopSilk = true;
        } else if (upper.endsWith('.GBO') ||
            upper.endsWith('.BSK') ||
            upper.endsWith('.PLS') ||
            upper.contains('B_SILK') ||
            upper.contains('BOTSILK')) {
          role = 'Нижняя маркировка (шелкография)';
          hasBottomSilk = true;
        } else if (upper.endsWith('.GKO') ||
            upper.endsWith('.GM1') ||
            upper.endsWith('.GM2') ||
            upper.endsWith('.GBR') ||
            upper.contains('EDGE') ||
            upper.contains('OUTLINE') ||
            upper.contains('BOARD') ||
            upper.contains('KONTUR')) {
          role = 'Контур платы / фрезеровка';
          hasTextContour = true;
        } else if (upper.endsWith('.DRL') ||
            upper.endsWith('.EXC') ||
            upper.endsWith('.TAP') ||
            upper.contains('DRILL') ||
            upper.contains('HOLES') ||
            upper.contains('NC_')) {
          role = 'Сверловка (Excellon)';
        } else if (upper.endsWith('.TXT')) {
          final sampleTxt = utf8.decode(fileBytes.take(400).toList(), allowMalformed: true).toUpperCase();
          if (sampleTxt.contains('M48') || sampleTxt.contains('T01') || sampleTxt.contains('METRIC') || sampleTxt.contains('INCH')) {
            role = 'Сверловка (Excellon)';
          } else {
            role = 'Текстовое примечание / ReadMe';
            importantDoc = true;
            extraProjectDocs.add(rawName);
          }
        } else if (upper.endsWith('.BRD')) {
          role = 'Файл платы P-CAD / CAD (.BRD)';
          hasBinaryBrd = true;
        }

        layers.add(GerberLayerInfo(
          fileName: rawName,
          role: role,
          sizeBytes: fileBytes.length,
          extractedPath: savedPath,
          isImportantDoc: importantDoc,
        ));

        final isLikelyBinary = fileBytes.take(200).where((b) => b == 0).length > 5;
        if (!isLikelyBinary && !upper.endsWith('.PDF')) {
          final textContent = utf8.decode(fileBytes, allowMalformed: true);
          if (role.contains('Сверловка')) {
            final drillStats = _parseExcellonDrill(textContent);
            totalHoles += drillStats['totalHoles'] as int;
            final tools = drillStats['tools'] as Map;
            for (final entry in tools.entries) {
              final k = entry.key as double;
              final v = entry.value as int;
              drillBreakdown[k] = ((drillBreakdown[k] as int?) ?? 0) + v;
              if (minDrillMm == null || k < minDrillMm) minDrillMm = k;
            }
          } else if (role.contains('меди') || role.contains('Контур') || upper.endsWith('.GBR') || upper.endsWith('.PHO')) {
            final gerberStats = _parseGerberGeometry(textContent);
            final gTrack = gerberStats['minTrackMm'];
            final gWidth = gerberStats['widthMm'];
            final gHeight = gerberStats['heightMm'];

            if (gTrack != null && (minTrackMm == null || gTrack < minTrackMm)) {
              minTrackMm = gTrack;
            }
            if (gWidth != null && gHeight != null) {
              if (role.contains('Контур')) {
                detectedWidth = gWidth;
                detectedHeight = gHeight;
              } else if (fallbackCopperWidth == null) {
                fallbackCopperWidth = gWidth;
                fallbackCopperHeight = gHeight;
              }
            }
          } else if (role.contains('ReadMe') && !upper.contains('PICK') && !upper.contains('PLACE') && !upper.contains('BOM')) {
            for (final line in textContent.split(RegExp(r'\r?\n'))) {
              final tr = line.trim();
              if (tr.length >= 4 && tr.length <= 160) {
                extraTextAlerts.add('[$rawName]: $tr');
              }
            }
          }
        }
      }

      detectedWidth ??= fallbackCopperWidth;
      detectedHeight ??= fallbackCopperHeight;

      final List parsedBoards = [];
      final docsToParse = foundExcelPaths.isNotEmpty ? foundExcelPaths : foundPdfPaths;
      for (final docP in docsToParse) {
        final rawBoards = await _parseDocumentBlank(docP.toString());
        if (rawBoards is List) {
          parsedBoards.addAll(rawBoards);
        }
      }

      final Map? firstBoard = parsedBoards.isNotEmpty
          ? (parsedBoards.first as Map)
          : null;

      if (firstBoard != null && firstBoard['width'] != null && firstBoard['height'] != null) {
        detectedWidth = (firstBoard['width'] as num).toDouble();
        detectedHeight = (firstBoard['height'] as num).toDouble();
      }

      final int finalLayersCount = (firstBoard != null && firstBoard['layers'] != null)
          ? (firstBoard['layers'] as num).toInt()
          : (copperLayers > 0 ? copperLayers : 2);

      final projectTitle = archiveName.replaceAll(RegExp(r'\.(zip|rar|xls|xlsx|pdf)$', caseSensitive: false), '');

      final resultObj = GerberAnalysisResult(
        archiveName: archiveName,
        archiveDir: archiveDir,
        projectTitle: projectTitle,
        layers: layers,
        extraProjectDocs: extraProjectDocs,
        extraTextAlerts: extraTextAlerts.take(6).toList(),
        detectedLayersCount: finalLayersCount,
        hasTopMask: hasTopMask,
        hasBottomMask: hasBottomMask,
        hasTopSilk: hasTopSilk,
        hasBottomSilk: hasBottomSilk,
        hasBinaryBrdOnly: hasBinaryBrd && !hasTextContour && detectedWidth == null,
        hasCadSourceOnly: hasCadSourceOnly && copperLayers == 0,
        hasNestedArchive: hasUnpackedNestedArchive,
        parsedFromOrderBlank: firstBoard != null,
        widthMm: detectedWidth,
        heightMm: detectedHeight,
        minTrackMm: minTrackMm,
        minDrillMm: minDrillMm,
        totalHoles: totalHoles,
        drillToolsBreakdown: drillBreakdown,
      );

      setState(() {
        _resetAllFieldsToDefault(showToast: false);

        _analysis = resultObj;
        _blankBoardsList = parsedBoards;
        _selectedBoardIdx = 0;
        _orderNameController.text = projectTitle;
        _layersCount = finalLayersCount;

        if (detectedWidth != null && detectedHeight != null) {
          _widthController.text = detectedWidth.toStringAsFixed(1);
          _heightController.text = detectedHeight.toStringAsFixed(1);
        }

        if (minTrackMm != null) {
          _minTrackController.text = minTrackMm.toStringAsFixed(3);
        }
        if (minDrillMm != null) {
          _minHoleController.text = minDrillMm.toStringAsFixed(2);
        }

        _maskSide = (hasTopMask && hasBottomMask)
            ? 'С двух сторон'
            : (hasTopMask ? 'С одной стороны (верх)' : (hasBottomMask ? 'С одной стороны (низ)' : 'Без маски'));
        _silkSide = (hasTopSilk && hasBottomSilk)
            ? 'С двух сторон'
            : (hasTopSilk ? 'С одной стороны (верх)' : (hasBottomSilk ? 'С одной стороны (низ)' : 'Без маркировки'));

        if (firstBoard != null) {
          _applyBoardFromBlank(firstBoard, projectTitle);
        } else {
          if (extraTextAlerts.isNotEmpty) {
            _notesController.text = extraTextAlerts.take(6).join('; ');
          }
          _recalculateTariffFromSpecs(force: true);
        }
      });

      if (parsedBoards.length > 1) {
        _showSnack('В архиве найдено ${parsedBoards.length} плат! Переключайтесь сверху или жмите «Сформировать КП».');
      } else if (firstBoard != null) {
        _showSnack('Параметры и выделенные пометки загружены из документа!');
      } else if (hasUnpackedNestedArchive) {
        _showSnack('Не удалось распаковать вложенный .RAR — укажите X и Y вручную.');
      } else if (detectedWidth == null) {
        _showSnack('Файл загружен, но контур не распознан — введите X и Y вручную для расчёта цены.');
      } else {
        _showSnack('Проект $archiveName проанализирован и рассчитан!');
      }
    } catch (e) {
      _showSnack('Ошибка чтения файла: $e');
    }
  }

  Map _parseExcellonDrill(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final Map toolDiameters = {};
    final Map toolCounts = {};
    bool isMetric = true;
    String? activeTool;
    int total = 0;

    for (final raw in lines) {
      final line = raw.trim().toUpperCase();
      if (line.isEmpty || line.startsWith(';')) continue;
      if (line.contains('INCH')) isMetric = false;
      if (line.contains('METRIC')) isMetric = true;

      final defMatch = RegExp(r'^(T\d+).*?C([\d.]+)').firstMatch(line);
      if (defMatch != null) {
        final tCode = defMatch.group(1)!;
        double d = double.tryParse(defMatch.group(2)!) ?? 0;
        if (!isMetric) d *= 25.4;
        if (d > 0) toolDiameters[tCode] = double.parse(d.toStringAsFixed(3));
        continue;
      }

      final selMatch = RegExp(r'^(T\d+)$').firstMatch(line);
      if (selMatch != null) {
        activeTool = selMatch.group(1);
        continue;
      }

      if ((line.startsWith('X') || line.startsWith('Y')) && activeTool != null && toolDiameters.containsKey(activeTool)) {
        final diam = toolDiameters[activeTool] as double;
        toolCounts[diam] = ((toolCounts[diam] as int?) ?? 0) + 1;
        total++;
      }
    }
    return {'totalHoles': total, 'tools': toolCounts};
  }

  Map _parseGerberGeometry(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    bool isInch = false;
    int decDigits = 4;
    double? minX, maxX, minY, maxY, minAperture;

    for (final raw in lines) {
      final line = raw.trim().toUpperCase();
      if (line.contains('MOIN')) isInch = true;
      if (line.contains('MOMM')) isInch = false;

      final fsMatch = RegExp(r'FS[LA]AX(\d)(\d)Y(\d)(\d)').firstMatch(line);
      if (fsMatch != null) decDigits = int.tryParse(fsMatch.group(2)!) ?? 4;

      final apMatch = RegExp(r'%ADD\d+[CR],([\d.]+)').firstMatch(line);
      if (apMatch != null) {
        double val = double.tryParse(apMatch.group(1)!) ?? 0;
        if (isInch) val *= 25.4;
        if (val >= 0.05 && val <= 3.0 && (minAperture == null || val < minAperture)) {
          minAperture = val;
        }
      }

      final coordMatch = RegExp(r'X(-?\d+)Y(-?\d+)').firstMatch(line);
      if (coordMatch != null && (line.contains('D01') || line.contains('D02') || line.contains('D1*') || line.contains('D2*'))) {
        final rawX = double.tryParse(coordMatch.group(1)!);
        final rawY = double.tryParse(coordMatch.group(2)!);
        if (rawX != null && rawY != null) {
          final scale = math.pow(10, decDigits).toDouble();
          double x = rawX / scale;
          double y = rawY / scale;
          if (isInch) {
            x *= 25.4;
            y *= 25.4;
          }
          if (x.abs() < 2000 && y.abs() < 2000) {
            minX = minX == null ? x : math.min(minX, x);
            maxX = maxX == null ? x : math.max(maxX, x);
            minY = minY == null ? y : math.min(minY, y);
            maxY = maxY == null ? y : math.max(maxY, y);
          }
        }
      }
    }

    double? width, height;
    if (minX != null && maxX != null && minY != null && maxY != null) {
      final dx = (maxX - minX).abs();
      final dy = (maxY - minY).abs();
      if (dx > 1 && dy > 1) {
        width = dx;
        height = dy;
      }
    }
    return {'widthMm': width, 'heightMm': height, 'minTrackMm': minAperture};
  }

  List _evaluateElectroconnectDfm() {
    final List checks = [];
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final track = double.tryParse(_minTrackController.text.replaceAll(',', '.')) ?? 0;
    final drill = double.tryParse(_minHoleController.text.replaceAll(',', '.')) ?? 0;
    final thick = double.tryParse(_thickness) ?? 1.5;
    final notesText = _notesController.text;
    final notesLow = notesText.toLowerCase();

    final highlightedParts = notesText
        .split(';')
        .map((e) => e.trim())
        .where((e) =>
            e.contains('[КРАСНЫМ') ||
            e.contains('[ЖИРНЫМ') ||
            e.contains('[ВЫДЕЛЕНО'))
        .toList();

    if (highlightedParts.isNotEmpty) {
      checks.add(DfmCheckItem(
        title: 'ВНИМАНИЕ! Выделенные (красным / жирным) требования в заявке (${highlightedParts.length}):',
        detail: highlightedParts.join('\n'),
        level: 'error',
      ));
    }

    if (_analysis != null && _analysis!.extraProjectDocs.isNotEmpty) {
      checks.add(DfmCheckItem(
        title: 'В архиве есть доп. документы/чертежи (${_analysis!.extraProjectDocs.length} шт.) — обязательно проверьте!',
        detail: 'Файлы: ${_analysis!.extraProjectDocs.join(", ")} (кликните по ним в блоке 3 ниже, чтобы открыть).',
        level: 'warn',
      ));
    }

    if (_hasCustomStackOrPressing(_notesController.text, _layersCount)) {
      final pairMatch = RegExp(r'(\d+[.,]\d+)\s*[xхXХ*]\s*2').firstMatch(notesLow);
      String stackDetail = 'По прайсу 2026: заполнение отверстий смолой / слепые / глухие / импеданс требуют спец. техпроцесса (коэф. 1.2–1.5).';
      if (pairMatch != null) {
        final coreMm = double.tryParse(pairMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        if (coreMm > 0) {
          final coresSum = coreMm * 2;
          final prepregRest = thick - coresSum;
          stackDetail = prepregRest > 0.05
              ? 'Ядра ${coreMm.toStringAsFixed(2)}×2 = ${coresSum.toStringAsFixed(2)} мм; остаток на препрег и фольгу: ${prepregRest.toStringAsFixed(2)} мм (при общей толщине ${thick.toStringAsFixed(1)} мм).'
              : 'Внимание: сумма ядер (${coresSum.toStringAsFixed(2)} мм) превышает или равна общей толщине платы (${thick.toStringAsFixed(1)} мм)!';
        }
      }
      checks.add(DfmCheckItem(
        title: 'Спец. техпроцесс / стек МПП (повышенный коэф.)',
        detail: stackDetail,
        level: 'warn',
      ));
    }

    final maxSide = math.max(w, h);
    final minSide = math.min(w, h);
    if (maxSide > 550 || minSide > 450) {
      checks.add(DfmCheckItem(
        title: 'Габариты превышают предел цеха!',
        detail: 'Максимум «ЭЛЕКТРОконнект»: 450×350 мм (Стандарт), 550×450 мм (Предел).',
        level: 'error',
      ));
    } else if (maxSide > 450 || minSide > 350) {
      checks.add(DfmCheckItem(
        title: 'Габариты в зоне «Предел» (> 450×350 мм)',
        detail: 'Изготовление возможно до 550×450 мм по согласованию.',
        level: 'warn',
      ));
    } else if (w > 0 && h > 0) {
      if (w < 25.0 || h < 25.0 || (w * h) < 625.0) {
        checks.add(DfmCheckItem(
          title: 'Мелкая плата (${w.toStringAsFixed(1)}×${h.toStringAsFixed(1)} мм < 25×25 мм)',
          detail: 'По тех. требованиям завода платы менее 25×25 мм (625 мм²) отдаются только в групповом блоке (шаг 2.3 мм при фрезеровке или скрайб).',
          level: 'warn',
        ));
      } else {
        checks.add(DfmCheckItem(
          title: 'Габариты платы в норме (${w.toStringAsFixed(1)}×${h.toStringAsFixed(1)} мм)',
          detail: 'Укладываются в стандартное рабочее поле (до 450×350 мм).',
          level: 'ok',
        ));
      }
    } else {
      checks.add(DfmCheckItem(
        title: 'Не заданы габариты платы (X × Y = 0)',
        detail: 'Укажите длину X и ширину Y в мм слева (или загрузите Gerber-архив для автоопределения габаритов).',
        level: 'warn',
      ));
    }

    const stdTrackMap = {'12': 0.100, '18': 0.125, '35': 0.175, '50': 0.270, '70': 0.300, '105': 0.350};
    const limTrackMap = {'12': 0.075, '18': 0.100, '35': 0.150, '50': 0.270, '70': 0.300, '105': 0.350};
    final stdT = stdTrackMap[_foil] ?? 0.125;
    final limT = limTrackMap[_foil] ?? 0.100;

    if (track > 0) {
      if (track < limT) {
        checks.add(DfmCheckItem(
          title: 'Дорожка $track мм ниже предела для $_foil мкм!',
          detail: 'Для фольги $_foil мкм минимум: $stdT мм (Стандарт) / $limT мм (Предел).',
          level: 'error',
        ));
      } else if (track < stdT) {
        checks.add(DfmCheckItem(
          title: 'Дорожка $track мм попадает в «Предел» (коэф. 1.25)',
          detail: 'Для фольги $_foil мкм стандарт ≥ $stdT мм; при ширине < 0.125 мм применяется коэф. 1.25 и +50% к подготовке.',
          level: 'warn',
        ));
      } else {
        checks.add(DfmCheckItem(
          title: 'Ширина проводников в стандарте ($track ≥ $stdT мм)',
          detail: 'Соответствует нормам «ЭЛЕКТРОконнект» для фольги $_foil мкм.',
          level: 'ok',
        ));
      }
    }

    if (drill > 0) {
      final aspect = thick / drill;
      if (drill < 0.20) {
        checks.add(DfmCheckItem(
          title: 'Отверстие Ø $drill мм меньше технологического предела!',
          detail: 'Минимальное металлизированное отверстие завода: 0.20 мм.',
          level: 'error',
        ));
      } else if (drill < 0.30 || aspect > 2.5) {
        checks.add(DfmCheckItem(
          title: 'Сверловка Ø $drill мм (соотношение ${aspect.toStringAsFixed(1)}:1) — зона «Предел»',
          detail: 'Стандарт: Ø ≥ 0.30 мм и отношение толщины платы к диаметру ≤ 2.5 (при < 0.30 мм коэф. 1.25).',
          level: 'warn',
        ));
      } else {
        checks.add(DfmCheckItem(
          title: 'Сверловка в стандарте (мин. Ø $drill мм ≥ 0.30 мм)',
          detail: 'Соотношение толщины к диаметру ${aspect.toStringAsFixed(1)}:1 (норма ≤ 2.5).',
          level: 'ok',
        ));
      }
    }

    if (_finish.startsWith('HAL') && thick < 1.0) {
      checks.add(DfmCheckItem(
        title: 'HAL (ПОС-63) запрещён для платы $thick мм!',
        detail: 'По тех. возможностям завода HASL не применяется на платах тоньше 1.0 мм.',
        level: 'error',
      ));
    }

    if (thick < 0.5 && _electroTest) {
      checks.add(DfmCheckItem(
        title: 'Толщина $thick мм < 0.5 мм: эл. тест Flying Probe не проводится!',
        detail: 'По требованиям завода платы тоньше 0.5 мм проверяются только оптическим тестером (AOI).',
        level: 'warn',
      ));
    }

    if (_maskColor != 'Зеленая' && _maskSide != 'Без маски') {
      checks.add(DfmCheckItem(
        title: 'Цветная маска ($_maskColor): коэф. ${_tariffConfig['colorMaskCoeff'] ?? 2.0} и перемычка ≥ 150 мкм',
        detail: 'По прайсу 2026 цветная LPI маска имеет повышенный коэффициент; минимальная ширина перемычки маски 0.15 мм.',
        level: 'warn',
      ));
    }

    if (_layersCount > 6) {
      checks.add(DfmCheckItem(
        title: 'Сложность МПП: $_layersCount слоёв (зона «Предел»)',
        detail: 'Стандарт до 6 слоёв; производство до 28 слоёв доступно по регламенту.',
        level: 'warn',
      ));
    }

    return checks;
  }

  String _buildSpecificationLine() {
    final w = _widthController.text.trim().replaceAll('.0', '');
    final h = _heightController.text.trim().replaceAll('.0', '');
    final maskPart = _maskSide == 'Без маски' ? 'Без маски' : '$_maskSide $_maskColor';
    final silkPart = _silkSide == 'Без маркировки' ? 'Без маркировки' : '$_silkSide $_silkColor';
    final testPart = _electroTest ? 'Эл. тест.' : 'Без эл. теста.';
    final finShort = _finish.startsWith('HAL') ? 'HAL' : _finish;

    return '$_orderType; $_layersCount сл; ${w}x${h}мм; $_contour; '
        '$_material-${_thickness}мм-${_foil}мкм; '
        'маска: $maskPart; маркировка: $silkPart; $finShort; $testPart';
  }

  String _fmtRuMoney(double val) {
    final fixed = val.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buf.write(' ');
      }
      buf.write(intPart[i]);
    }
    return '${buf.toString()},$decPart';
  }

  Future<void> _generateOfficialKpDocument({bool saveAsPdf = false}) async {
    _syncCurrentFormBackToBoardList();

    final now = DateTime.now();
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final dateStr = '${now.day} ${months[now.month - 1]} ${now.year} г.';
    final kpNum = '${2000 + (now.millisecondsSinceEpoch % 899)}';
    final customerName = _customerController.text.trim().isEmpty
        ? 'ООО «Заказчик»'
        : _customerController.text.trim();
    final managerName = _managerController.text.trim();

    final List itemsToRender = [];
    bool isMultiQtyVariants = false;

    if (_blankBoardsList.length > 1) {
      for (int i = 0; i < _blankBoardsList.length; i++) {
        final b = _blankBoardsList[i] as Map;
        final bName = b['board_name']?.toString().trim() ?? 'Позиция ${i + 1}';
        final w = (b['width'] as num?)?.toDouble() ?? 0.0;
        final h = (b['height'] as num?)?.toDouble() ?? 0.0;
        final qty = (b['qty'] as num?)?.toInt() ?? 10;
        final layers = (b['layers'] as num?)?.toInt() ?? 2;
        final mat = b['material']?.toString() ?? 'FR4';
        final thick = b['thickness']?.toString() ?? '1.5';
        final foil = b['foil']?.toString() ?? '18';
        final oType = b['order_type']?.toString() ?? 'Новый';
        final urg = _normalizeUrgency(b['urgency']?.toString());
        final fin = b['finish']?.toString() ?? 'HAL (ПОС-63)';
        final rawMs = b['mask_side']?.toString() ?? 'С двух сторон';
        final maskColor = _parseColorFromText(rawMs, b['mask_color']?.toString() ?? 'Зеленая');
        final rawSs = b['silk_side']?.toString() ?? 'С двух сторон';
        final silkColor = _parseColorFromText(rawSs, b['silk_color']?.toString() ?? 'Белая');
        final contour = b['contour']?.toString() ?? 'фрезеровка';
        final eTest = b['electro_test'] != false;
        final notesStr = (b['notes'] is List) ? (b['notes'] as List).join('; ') : '';

        final effW = w > 0 ? w : 50.0;
        final effH = h > 0 ? h : 50.0;

        final autoRates = _computeRatesForSpecs(
          layers: layers,
          material: mat,
          foil: foil,
          finish: fin,
          maskColor: maskColor,
          maskSide: rawMs,
          silkSide: rawSs,
          orderType: oType,
          urgency: urg,
          widthMm: effW,
          heightMm: effH,
          notesText: notesStr,
        );

        final dm2Rate = (b['manual_dm2_rate'] as num?)?.toDouble() ?? autoRates.dm2Rate;
        final setupFee = (b['manual_setup_fee'] as num?)?.toDouble() ?? autoRates.setupFee;

        final singleDm2 = _calcEffectiveSingleDm2(effW, effH);
        final totalDm2 = singleDm2 * math.max(qty, 1);
        final pureSum = (totalDm2 * dm2Rate) + setupFee;
        final unitPriceNoVat = pureSum / math.max(qty, 1);
        final vatSum = pureSum * 0.22;
        final totalWithVat = pureSum + vatSum;

        final int leadDays;
        if (urg == 'СуперЭкспресс') {
          leadDays = layers >= 4 ? 6 : 3;
        } else if (urg == 'Экспресс') {
          leadDays = layers >= 4 ? 12 : 7;
        } else {
          leadDays = layers >= 4 ? 20 : 14;
        }

        final finShort = fin.startsWith('HAL') ? 'HAL' : fin;
        final spec = '$oType; $layers сл; ${effW.toStringAsFixed(0)}x${effH.toStringAsFixed(0)}мм; $contour; '
            '$mat-${thick}мм-${foil}мкм; маска: $rawMs $maskColor; маркировка: $rawSs $silkColor; '
            '$finShort; ${eTest ? "Эл. тест." : "Без эл. теста."}';

        itemsToRender.add({
          'idx': i + 1,
          'name': 'Печатные платы $bName',
          'spec': spec,
          'days': leadDays,
          'area': totalDm2,
          'qty': qty,
          'unitPrice': unitPriceNoVat,
          'sumNoVat': pureSum,
          'vat': vatSum,
          'totalWithVat': totalWithVat,
        });
      }
    } else {
      // Одна плата, но возможно несколько вариантов тиража (например: 10, 20, 30 шт. как в КП-2054 ЦНИИ)
      final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
      final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
      final primaryQty = int.tryParse(_qtyController.text.trim()) ?? 10;

      final List<int> qtyVariants = [primaryQty];
      final extraRaw = _extraQtysController.text.trim();
      if (extraRaw.isNotEmpty) {
        for (final part in extraRaw.split(RegExp(r'[,;\s]+'))) {
          final q = int.tryParse(part.trim());
          if (q != null && q > 0 && !qtyVariants.contains(q)) {
            qtyVariants.add(q);
          }
        }
      }
      isMultiQtyVariants = qtyVariants.length > 1;

      final effW = w > 0 ? w : 50.0;
      final effH = h > 0 ? h : 50.0;
      final singleDm2 = _calcEffectiveSingleDm2(effW, effH);
      final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 459.0;
      final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 1800.0;

      final int leadDays;
      if (_urgency == 'СуперЭкспресс') {
        leadDays = _layersCount >= 4 ? 6 : 3;
      } else if (_urgency == 'Экспресс') {
        leadDays = _layersCount >= 4 ? 12 : 7;
      } else {
        leadDays = _layersCount >= 4 ? 20 : 14;
      }

      final boardTitle = _orderNameController.text.trim().isEmpty ? 'изделие' : _orderNameController.text.trim();
      final spec = _buildSpecificationLine();

      for (int i = 0; i < qtyVariants.length; i++) {
        final q = qtyVariants[i];
        final totalDm2 = singleDm2 * math.max(q, 1);
        final pureSum = (totalDm2 * baseP) + setupP;
        final unitPriceNoVat = pureSum / math.max(q, 1);
        final vatSum = pureSum * 0.22;
        final totalWithVat = pureSum + vatSum;

        itemsToRender.add({
          'idx': i + 1,
          'name': 'Печатные платы $boardTitle',
          'spec': spec,
          'days': leadDays,
          'area': totalDm2,
          'qty': q,
          'unitPrice': unitPriceNoVat,
          'sumNoVat': pureSum,
          'vat': vatSum,
          'totalWithVat': totalWithVat,
        });
      }
    }

    double grandNoVat = 0;
    double grandVat = 0;
    double grandWithVat = 0;
    final rowsHtml = StringBuffer();

    for (final rawItem in itemsToRender) {
      final it = rawItem as Map;
      grandNoVat += it['sumNoVat'] as double;
      grandVat += it['vat'] as double;
      grandWithVat += it['totalWithVat'] as double;

      rowsHtml.writeln('''
        <tr class="item-top">
          <td class="c num-cell" rowspan="2">${it['idx']}</td>
          <td class="item-title">${it['name']}</td>
          <td class="c" rowspan="2">${it['days']}</td>
          <td class="r" rowspan="2">${_fmtRuMoney(it['area'] as double)}</td>
          <td class="c" rowspan="2">шт.</td>
          <td class="r" rowspan="2">${it['qty']}</td>
          <td class="r" rowspan="2">${_fmtRuMoney(it['unitPrice'] as double)}</td>
          <td class="r" rowspan="2">${_fmtRuMoney(it['sumNoVat'] as double)}</td>
          <td class="r" rowspan="2">${_fmtRuMoney(it['vat'] as double)}</td>
          <td class="r" rowspan="2">${_fmtRuMoney(it['totalWithVat'] as double)}</td>
        </tr>
        <tr class="item-bot">
          <td class="spec">${it['spec']}</td>
        </tr>
      ''');
    }

    // Если в КП несколько вариантов тиража одной платы (10, 20, 30 шт. как в КП-2054),
    // общий итог не суммируется, чтобы не складывать 3 альтернативных тиража
    final totalsBlockHtml = isMultiQtyVariants
        ? ''
        : '''
          <table class="totals-box">
            <tr>
              <td class="r">Итого без НДС:</td>
              <td class="r b">${_fmtRuMoney(grandNoVat)} руб.</td>
            </tr>
            <tr>
              <td class="r">НДС 22%:</td>
              <td class="r">${_fmtRuMoney(grandVat)} руб.</td>
            </tr>
            <tr>
              <td class="r b">Итого с НДС:</td>
              <td class="r b">${_fmtRuMoney(grandWithVat)} руб.</td>
            </tr>
          </table>
        ''';

    // Точная копия структуры, цветов (#000080 / #022D60) и шрифтов КП-2054 (формат А4 книжный)
    final htmlDoc = '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>КП № $kpNum — $customerName</title>
<style>
  @page { size: A4 portrait; margin: 12mm 10mm; }
  body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 9pt;
    color: #000000;
    margin: 16px 20px;
    background: #ffffff;
  }
  .top-slogan {
    text-align: center;
    font-size: 8.5pt;
    font-weight: bold;
    color: #000080;
    letter-spacing: 0.4px;
    margin-bottom: 2px;
  }
  .header-table {
    width: 100%;
    border-collapse: collapse;
    border-bottom: 1.2px solid #000080;
    padding-bottom: 4px;
    margin-bottom: 12px;
  }
  .logo-wrap { display: inline-flex; align-items: center; gap: 6px; }
  .logo-circle {
    width: 24px; height: 24px; border-radius: 50%;
    background: radial-gradient(circle at 35% 35%, #fff7cc, #f59e0b 55%, #022D60 85%);
    border: 2px solid #022D60;
    display: inline-block;
  }
  .brand-bold { font-size: 19pt; font-weight: bold; color: #022D60; letter-spacing: -0.4px; }
  .brand-reg { font-size: 19pt; font-weight: normal; color: #000080; letter-spacing: -0.4px; }
  .contacts-row td {
    font-size: 8.5pt;
    color: #000080;
    padding-top: 2px;
    padding-bottom: 4px;
  }
  .site-link {
    font-size: 10.5pt;
    color: #000080;
    text-align: center;
  }
  .customer-line {
    margin: 14px 0 12px 0;
    font-size: 10pt;
    color: #000000;
  }
  .title-kp {
    text-align: center;
    font-size: 11pt;
    font-weight: bold;
    color: #000000;
    margin: 12px 0 12px 0;
  }
  table.main {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 10px;
    font-size: 7.5pt;
    color: #000000;
  }
  table.main th {
    border: 0.8px solid #000000;
    background-color: #ffffff;
    font-weight: normal;
    text-align: center;
    padding: 4px 3px;
    line-height: 1.15;
  }
  table.main th.sm {
    font-size: 6.2pt;
  }
  table.main td {
    border: 0.8px solid #000000;
    padding: 3px 4px;
    vertical-align: middle;
  }
  table.main td.num-cell {
    font-size: 8.5pt;
  }
  table.main tr.item-top td.item-title {
    border-bottom: 0.6px solid #000000;
    font-size: 8pt;
    padding-top: 4px;
    padding-bottom: 3px;
  }
  table.main tr.item-bot td.spec {
    border-top: none;
    font-size: 6.8pt;
    color: #000000;
    line-height: 1.25;
    padding-top: 3px;
    padding-bottom: 4px;
  }
  .c { text-align: center; }
  .r { text-align: right; white-space: nowrap; }
  .b { font-weight: bold; }
  .delivery-row {
    margin: 8px 0 10px 0;
    font-size: 7.5pt;
  }
  .totals-box {
    float: right;
    margin-top: -18px;
    margin-bottom: 8px;
    font-size: 8pt;
    border-collapse: collapse;
  }
  .totals-box td { padding: 1.5px 6px; }
  .clear { clear: both; }
  .notice-box {
    border-top: 1px solid #000000;
    border-bottom: 1px solid #000000;
    text-align: center;
    padding: 3px 0;
    font-weight: bold;
    font-size: 8pt;
    margin: 8px 0 8px 0;
    letter-spacing: 0.3px;
  }
  .terms {
    font-size: 6.8pt;
    line-height: 1.35;
    border-bottom: 1px solid #000000;
    padding-bottom: 6px;
  }
  .footer-sign {
    margin-top: 18px;
    font-size: 7.5pt;
    line-height: 1.4;
  }
  .manager-name {
    font-family: "Times New Roman", Times, serif;
    font-weight: bold;
    font-size: 8pt;
  }
  @media print {
    .no-print { display: none !important; }
    body { margin: 0; }
  }
</style>
</head>
<body>
<div class="no-print" style="background:#eef4fb;padding:10px 14px;border-radius:8px;margin-bottom:14px;border:1px solid #002E63;font-size:12px;color:#002E63;">
  <b>Официальный бланк КП № $kpNum (формат А4, как КП-2054) готов!</b> Нажмите <b>Ctrl + P</b> → <b>«Сохранить как PDF»</b> (книжная ориентация).
</div>

<div class="top-slogan">РОССИЙСКИЙ ЗАВОД ПЕЧАТНЫХ ПЛАТ</div>

<table class="header-table">
  <tr>
    <td colspan="3" style="padding-bottom:2px;">
      <div class="logo-wrap">
        <span class="logo-circle"></span>
        <span><span class="brand-bold">электро</span><span class="brand-reg">коннект</span></span>
      </div>
    </td>
  </tr>
  <tr class="contacts-row">
    <td style="width:36%;">Тел : &nbsp;+ (383) 3361001 , 3361003</td>
    <td class="site-link" style="width:32%;">www.pselectro.ru</td>
    <td style="width:32%;text-align:right;">order@pselectro.ru</td>
  </tr>
</table>

<div class="customer-line">
  Заказчик : &nbsp;$customerName
</div>

<div class="title-kp">
  КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ № $kpNum от $dateStr
</div>

<table class="main">
  <thead>
    <tr>
      <th style="width:20px;">№</th>
      <th>Наименование товара</th>
      <th class="sm" style="width:52px;">Срок<br>изготовления<br>(рабочих дней)</th>
      <th class="sm" style="width:44px;">Площадь<br>(кв.дм.)</th>
      <th style="width:30px;">Ед.и<br>зм</th>
      <th style="width:32px;">Кол-<br>во</th>
      <th style="width:48px;">Цена</th>
      <th style="width:54px;">Сумма</th>
      <th style="width:48px;">НДС 22%</th>
      <th style="width:58px;">Сумма с НДС</th>
    </tr>
  </thead>
  <tbody>
    $rowsHtml
  </tbody>
</table>

<div class="delivery-row">
  Доставка до : &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Самовывоз
</div>

$totalsBlockHtml
<div class="clear"></div>

<div class="notice-box">
  НЕ ЯВЛЯЕТСЯ ОСНОВАНИЕМ ДЛЯ ОПЛАТЫ
</div>

<div class="terms">
  1. &nbsp;Настоящее коммерческое предложение подготовлено на основе предоставленных сведений. В случае внесения изменений в исходные данные, стоимость и сроки изготовления могут быть скорректированы.<br>
  2. Предложение действительно 5 рабочих дней.<br>
  3. Оплата заказа производится на основании счета-договора.<br>
  4. При наличии доставки, она включена в стоимость и указан адрес или город получателя в графе "Доставка до" .
</div>

<div class="footer-sign">
  Менеджер по работе с клиентами<br>
  <span class="manager-name">$managerName</span>
</div>
</body>
</html>''';

    final dirPath = _analysis?.archiveDir ?? (await getApplicationDocumentsDirectory()).path;
    final safeCust = customerName.replaceAll(RegExp(r'[\\/:*?"<>|«»"]'), '_');
    final htmlPath = '$dirPath${Platform.pathSeparator}КП-${kpNum}_$safeCust.html';
    await File(htmlPath).writeAsString(htmlDoc, encoding: utf8);

    if (saveAsPdf && Platform.isWindows) {
      final pdfPath = '$dirPath${Platform.pathSeparator}КП-${kpNum}_$safeCust.pdf';
      const browsers = [
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
      ];
      String? foundBrowser;
      for (final b in browsers) {
        if (File(b).existsSync()) {
          foundBrowser = b;
          break;
        }
      }
      if (foundBrowser != null) {
        final fileUri = Uri.file(htmlPath).toString();
        await Process.run(foundBrowser, [
          '--headless',
          '--disable-gpu',
          '--no-pdf-header-footer',
          '--print-to-pdf=$pdfPath',
          fileUri,
        ]);
        if (File(pdfPath).existsSync()) {
          _showSnack('Официальный PDF-бланк КП № $kpNum сохранён: $pdfPath');
          await OpenFilex.open(pdfPath);
          return;
        }
      }
    }

    _showSnack('Официальное КП № $kpNum сформировано: $htmlPath');
    await OpenFilex.open(htmlPath);
  }

  Future<void> _exportConstructorTzFile() async {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;
    final singleDm2 = _calcEffectiveSingleDm2(w, h);
    final totalDm2 = singleDm2 * math.max(qty, 1);

    final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 459.0;
    final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 1800.0;
    final pureSum = (totalDm2 * baseP) + setupP;
    final vatSum = pureSum * 0.22;
    final totalSumWithVat = pureSum + vatSum;

    final dfm = _evaluateElectroconnectDfm();
    final sb = StringBuffer();
    sb.writeln('====================================================================');
    sb.writeln('ТЕХНИЧЕСКОЕ ЗАДАНИЕ НА ПОДГОТОВКУ ПРОИЗВОДСТВА (ООО «ЭЛЕКТРОконнект»)');
    sb.writeln('Разработчик / автор софта: Кувезенков А.А.');
    sb.writeln('====================================================================');
    sb.writeln('Дата формирования: ${DateTime.now().toString().substring(0, 16)}');
    if (_customerController.text.trim().isNotEmpty) {
      sb.writeln('Заказчик:          ${_customerController.text.trim()}');
    }
    sb.writeln('Обозначение платы: ${_orderNameController.text.trim().isEmpty ? "Без названия" : _orderNameController.text.trim()}');
    sb.writeln('Тип / срочность:   $_orderType • $_urgency');
    sb.writeln('Тираж:             $qty шт. (расч. площадь 1 шт: ${singleDm2.toStringAsFixed(2)} дм², партия: ${totalDm2.toStringAsFixed(2)} дм²)');
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('РАСЧЕТ СТОИМОСТИ:');
    if (_webPriceResult != null) {
      sb.writeln('• Расчет с сайта / КП: $_webPriceResult');
    }
    sb.writeln('• Локально без НДС: ${pureSum.toStringAsFixed(2)} руб.');
    sb.writeln('• НДС (22%):        ${vatSum.toStringAsFixed(2)} руб.');
    sb.writeln('• ИТОГО с НДС:      ${totalSumWithVat.toStringAsFixed(2)} руб.');
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('СПЕЦИФИКАЦИЯ ДЛЯ 1С / КП:');
    sb.writeln(_buildSpecificationLine());
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('ТЕХНОЛОГИЧЕСКИЕ ПАРАМЕТРЫ:');
    sb.writeln('• Количество слоёв:      $_layersCount');
    sb.writeln('• Габариты (X × Y):      ${_widthController.text.trim()} × ${_heightController.text.trim()} мм');
    sb.writeln('• Материал / толщина:    $_material, $_thickness мм, фольга $_foil мкм');
    sb.writeln('• Обработка контура:     $_contour');
    sb.writeln('• Паяльная маска:        $_maskSide ($_maskColor)');
    sb.writeln('• Маркировка:            $_silkSide ($_silkColor)');
    sb.writeln('• Финишное покрытие:     $_finish');
    sb.writeln('• Электроконтроль:       ${_electroTest ? "Да (Flying Probe)" : "Нет"}');
    sb.writeln('• Мин. дорожка / сверло: ${_minTrackController.text.trim()} мм / Ø ${_minHoleController.text.trim()} мм');
    if (_notesController.text.trim().isNotEmpty) {
      sb.writeln('• Примечание / стек:     ${_notesController.text.trim()}');
    }
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('РЕЗУЛЬТАТ DFM-ПРОВЕРКИ (РЕГЛАМЕНТ ЭЛЕКТРОКОННЕКТ):');
    for (final rawC in dfm) {
      final c = rawC as DfmCheckItem;
      final tag = c.level == 'error' ? '[КРИТИЧНО]' : (c.level == 'warn' ? '[ПРЕДЕЛ]' : '[OK]');
      sb.writeln('$tag ${c.title} — ${c.detail}');
    }
    if (_analysis != null) {
      sb.writeln('--------------------------------------------------------------------');
      sb.writeln('СОСТАВ АРХИВА (${_analysis!.archiveName}):');
      for (final rawL in _analysis!.layers) {
        final l = rawL as GerberLayerInfo;
        sb.writeln('• ${l.fileName} -> ${l.role}');
      }
      if (_analysis!.drillToolsBreakdown.isNotEmpty) {
        sb.writeln('Сверловка (всего ${_analysis!.totalHoles} отв.):');
        final sorted = _analysis!.drillToolsBreakdown.entries.toList()..sort((a, b) => (a.key as double).compareTo(b.key as double));
        for (final e in sorted) {
          sb.writeln('  - Ø ${e.key} мм: ${e.value} шт.');
        }
      }
    }

    final dirPath = _analysis?.archiveDir ?? (await getApplicationDocumentsDirectory()).path;
    final safeTitle = (_orderNameController.text.trim().isEmpty ? 'PCB_Order' : _orderNameController.text.trim())
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = '$dirPath${Platform.pathSeparator}ТЗ_$safeTitle.txt';
    await File(outPath).writeAsString(sb.toString(), encoding: utf8);
    _showSnack('ТЗ сохранено: $outPath');
    await OpenFilex.open(outPath);
  }

  Future<void> _exportCombinedAllBoardsTzFile() async {
    if (_blankBoardsList.isEmpty) return;
    _syncCurrentFormBackToBoardList();

    final sb = StringBuffer();
    final baseTitle = _analysis?.projectTitle ?? 'Комплект_плат';
    sb.writeln('====================================================================');
    sb.writeln('СВОДНОЕ ТЗ ПО ВСЕМ ПЛАТАМ ЗАКАЗА (ООО «ЭЛЕКТРОконнект»)');
    sb.writeln('Проект: $baseTitle • Позиций в документе: ${_blankBoardsList.length}');
    sb.writeln('====================================================================');
    sb.writeln('Дата формирования: ${DateTime.now().toString().substring(0, 16)}');
    if (_customerController.text.trim().isNotEmpty) {
      sb.writeln('Заказчик:          ${_customerController.text.trim()}');
    }
    sb.writeln('');

    double grandTotalWithVat = 0.0;
    double grandTotalAreaDm2 = 0.0;

    for (int i = 0; i < _blankBoardsList.length; i++) {
      final b = _blankBoardsList[i] as Map;
      final bName = b['board_name']?.toString().trim() ?? 'Позиция ${i + 1}';
      final w = (b['width'] as num?)?.toDouble() ?? 0.0;
      final h = (b['height'] as num?)?.toDouble() ?? 0.0;
      final qty = (b['qty'] as num?)?.toInt() ?? 10;
      final layers = (b['layers'] as num?)?.toInt() ?? 2;
      final mat = b['material']?.toString() ?? 'FR4';
      final thick = b['thickness']?.toString() ?? '1.5';
      final foil = b['foil']?.toString() ?? '18';
      final oType = b['order_type']?.toString() ?? 'Новый';
      final urg = _normalizeUrgency(b['urgency']?.toString());

      String fin = 'HAL (ПОС-63)';
      final rawFin = (b['finish']?.toString() ?? '').toLowerCase();
      if (rawFin.contains('иммерс') || rawFin.contains('золот') || rawFin.contains('enig')) {
        fin = 'Иммерсионное золото';
      } else if (rawFin.contains('олов')) {
        fin = 'Иммерсионное олово';
      } else if (rawFin.contains('без')) {
        fin = 'Без покрытия';
      }

      final rawMs = b['mask_side']?.toString() ?? 'С двух сторон';
      final maskCol = _parseColorFromText(rawMs, b['mask_color']?.toString() ?? 'Зеленая');
      final rawSs = b['silk_side']?.toString() ?? 'С двух сторон';
      final silkCol = _parseColorFromText(rawSs, b['silk_color']?.toString() ?? 'Белая');

      final notesStr = (b['notes'] is List) ? (b['notes'] as List).join('; ') : '';

      final autoRates = _computeRatesForSpecs(
        layers: layers,
        material: mat,
        foil: foil,
        finish: fin,
        maskColor: maskCol,
        maskSide: rawMs,
        silkSide: rawSs,
        orderType: oType,
        urgency: urg,
        widthMm: w,
        heightMm: h,
        notesText: notesStr,
      );

      final dm2Rate = (b['manual_dm2_rate'] as num?)?.toDouble() ?? autoRates.dm2Rate;
      final setupFee = (b['manual_setup_fee'] as num?)?.toDouble() ?? autoRates.setupFee;

      final singleDm2 = _calcEffectiveSingleDm2(w, h);
      final totalDm2 = singleDm2 * math.max(qty, 1);
      final pureSum = (w > 0 && h > 0) ? ((totalDm2 * dm2Rate) + setupFee) : 0.0;
      final totalWithVat = pureSum * 1.22;

      grandTotalWithVat += totalWithVat;
      grandTotalAreaDm2 += totalDm2;

      sb.writeln('--- ПОЗИЦИЯ ${i + 1}: $bName ---');
      sb.writeln('• Параметры: $oType ($urg); $layers сл; ${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)}мм; $mat-$thickмм-$foilмкм; маска: $rawMs $maskCol; марк: $rawSs $silkCol; $fin');
      sb.writeln('• Тираж:     $qty шт. (расч. площадь партии: ${totalDm2.toStringAsFixed(2)} дм²)');
      sb.writeln('• Стоимость: ${totalWithVat.toStringAsFixed(2)} руб. с НДС (тариф ${dm2Rate.toStringAsFixed(0)} р/дм² + подготовка ${setupFee.toStringAsFixed(0)} р)');
      if (notesStr.isNotEmpty) {
        sb.writeln('• Примечания: $notesStr');
      }
      sb.writeln('');
    }

    sb.writeln('====================================================================');
    sb.writeln('ИТОГО ПО ВСЕМУ КОМПЛЕКТУ (${_blankBoardsList.length} поз.):');
    sb.writeln('• Общая расчётная площадь: ${grandTotalAreaDm2.toStringAsFixed(2)} дм²');
    sb.writeln('• ОБЩАЯ СУММА С НДС (22%): ${grandTotalWithVat.toStringAsFixed(2)} руб.');
    sb.writeln('====================================================================');

    final dirPath = _analysis?.archiveDir ?? (await getApplicationDocumentsDirectory()).path;
    final safeTitle = baseTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = '$dirPath${Platform.pathSeparator}Сводное_ТЗ_$safeTitle.txt';
    await File(outPath).writeAsString(sb.toString(), encoding: utf8);
    _showSnack('Сводное ТЗ по всем платам сохранено: $outPath');
    await OpenFilex.open(outPath);
  }

  void _copyClientEmailTemplate(double totalWithVat, double totalDm2) {
    final title = _orderNameController.text.trim().isEmpty ? 'платы' : _orderNameController.text.trim();
    final qty = _qtyController.text.trim();
    final priceLine = _webPriceResult != null
        ? '• Стоимость партии по расчёту сайта / КП: $_webPriceResult'
        : '• Предварительная стоимость партии с учетом НДС 22% (срочность: $_urgency): ${totalWithVat.toStringAsFixed(2)} руб.';

    final text = 'Здравствуйте!\n'
        'Благодарим за обращение на завод «ЭЛЕКТРОконнект».\n\n'
        'По результатам проверки производственных файлов проекта «$title» ($qty шт., расчётная площадь партии: ${totalDm2.toStringAsFixed(2)} дм²):\n'
        '• Габариты и класс точности соответствуют стандартам технологического регламента.\n'
        '$priceLine\n\n'
        'Ждем ваше подтверждение запуска в производство!\n\n'
        'С уважением,\n'
        'ООО «ЭЛЕКТРОконнект»';

    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Шаблон письма клиенту скопирован в буфер обмена!');
  }

  Future<void> _openPselectroCalculator() async {
    const url = 'https://pselectro.ru/calculate-cost/';
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else {
      await OpenFilex.open(url);
    }
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPriceField = false,
    bool triggerRecalc = false,
    bool boldNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {
        if (isPriceField) _manualPriceOverride = true;
        if (triggerRecalc) _recalculateTariffFromSpecs();
        _syncCurrentFormBackToBoardList();
      }),
      style: TextStyle(
        fontSize: boldNumber ? 16.5 : 15.0,
        fontWeight: boldNumber ? FontWeight.bold : FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(fontSize: 13.5, color: _subtleText, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(fontSize: 13, color: _subtleText.withOpacity(0.6)),
        prefixIcon: icon != null ? Icon(icon, size: 20, color: ecNavyLight) : null,
        filled: true,
        fillColor: widget.isDark ? const Color(0xFF182235) : const Color(0xFFF7FAFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ecNavy, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List items,
    required ValueChanged onChanged,
  }) {
    final strItems = items.map((e) => e.toString()).toList();
    final safeValue = strItems.contains(value) ? value : strItems.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: _subtleText, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: widget.isDark ? const Color(0xFF182235) : const Color(0xFFF7FAFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ecNavy, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      ),
      items: strItems
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) {
        onChanged(v);
        _syncCurrentFormBackToBoardList();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;
    final hasValidDimensions = w > 0 && h > 0;
    final singleAreaDm2 = _calcEffectiveSingleDm2(w, h);
    final totalAreaDm2 = singleAreaDm2 * math.max(qty, 1);

    final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 459.0;
    final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 1800.0;
    final pureSum = hasValidDimensions ? ((totalAreaDm2 * baseP) + setupP) : 0.0;
    final vatSum = pureSum * 0.22;
    final totalSumWithVat = pureSum + vatSum;

    final dfmChecks = _evaluateElectroconnectDfm();
    final specLine = _buildSpecificationLine();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: ecNavy,
        foregroundColor: Colors.white,
        elevation: 2,
        toolbarHeight: 68,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ecOrange, width: 1.5),
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, color: ecOrange, size: 25),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('ЭЛЕКТРО', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.4)),
                    Text('коннект', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Color(0xFF93C5FD), letterSpacing: 0.4)),
                    Text(' — CAM & DFM Контроль (Кувезенков А.А.)', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
                Text('РОССИЙСКИЙ ЗАВОД ПЕЧАТНЫХ ПЛАТ • pselectro.ru • Прайс 2026', style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.price_change_outlined, color: ecOrange, size: 20),
            label: const Text('Цены прайса', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
            onPressed: _openTariffEditorDialog,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: widget.isDark ? 'Светлая тема (как на сайте)' : 'Тёмная тема',
            icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 24, color: Colors.white),
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1780),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderCol),
                    boxShadow: widget.isDark
                        ? null
                        : [BoxShadow(color: ecNavy.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: ecNavy.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.folder_zip_outlined, color: widget.isDark ? const Color(0xFF60A5FA) : ecNavy, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _analysis != null ? 'Проект: ${_analysis!.archiveName}' : 'Загрузите архив (.zip / .rar), бланк Excel (.xls/.xlsx) или запрос ТКП (.pdf)',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _analysis != null
                                  ? 'Найдено файлов: ${_analysis!.layers.length} • Позиций в заказе: ${_blankBoardsList.isEmpty ? 1 : _blankBoardsList.length} • Папка: ${_analysis!.archiveDir}'
                                  : 'Автоматически читает все бланки в архиве, запросы ТКП в PDF, готовые КП и вложенные .RAR',
                              style: TextStyle(fontSize: 13.5, color: _subtleText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isDark ? Colors.white : ecNavy,
                          side: BorderSide(color: widget.isDark ? Colors.white24 : ecNavy, width: 1.4),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('НОВЫЙ ПРОЕКТ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        onPressed: _clearCurrentProject,
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ecOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 22),
                        label: const Text('ВЫБРАТЬ ФАЙЛ / АРХИВ', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                        onPressed: _pickAndAnalyzeZip,
                      ),
                    ],
                  ),
                ),
                if (_blankBoardsList.length > 1) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: ecNavy.withOpacity(widget.isDark ? 0.25 : 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ecNavy.withOpacity(0.35)),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('В архиве ${_blankBoardsList.length} плат:', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                        for (int i = 0; i < _blankBoardsList.length; i++)
                          ChoiceChip(
                            selectedColor: ecOrange,
                            label: Text(
                              'Плата ${i + 1}: ${(_blankBoardsList[i] as Map)['board_name'] ?? 'Позиция ${i + 1}'}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _selectedBoardIdx == i ? Colors.white : null,
                              ),
                            ),
                            selected: _selectedBoardIdx == i,
                            onSelected: (_) {
                              setState(() {
                                _syncCurrentFormBackToBoardList();
                                _selectedBoardIdx = i;
                                _applyBoardFromBlank(
                                  _blankBoardsList[i] as Map,
                                  _analysis?.projectTitle ?? '',
                                );
                              });
                            },
                          ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ecNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          icon: const Icon(Icons.summarize_outlined, size: 18),
                          label: const Text('Сводное ТЗ (все платы)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          onPressed: _exportCombinedAllBoardsTzFile,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _borderCol),
                          boxShadow: widget.isDark
                              ? null
                              : [BoxShadow(color: ecNavy.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '1. Параметры платы и расчет стоимости',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : ecNavy),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: ecOrange),
                                  icon: const Icon(Icons.tune_rounded, size: 18),
                                  label: const Text('Изменить тарифы прайса', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                                  onPressed: _openTariffEditorDialog,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _customerController, label: 'Заказчик', icon: Icons.business_rounded)),
                                const SizedBox(width: 12),
                                Expanded(child: _inputField(controller: _orderNameController, label: 'Децимальный номер', icon: Icons.tag_rounded)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _dropdownField(
                                    label: 'Тип заказа',
                                    value: _orderType,
                                    items: const ['Новый', 'Повтор'],
                                    onChanged: (v) => setState(() {
                                      _orderType = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _dropdownField(
                                    label: 'Срочность',
                                    value: _urgency,
                                    items: const ['Серийный', 'Экспресс', 'СуперЭкспресс'],
                                    onChanged: (v) => setState(() {
                                      _urgency = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _inputField(controller: _qtyController, label: 'Тираж, шт.', keyboardType: TextInputType.number, boldNumber: true),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _inputField(
                                    controller: _extraQtysController,
                                    label: 'Доп. тиражи в КП',
                                    hint: 'напр. 20, 30',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _widthController, label: 'Длина X, мм', keyboardType: TextInputType.number, triggerRecalc: true, boldNumber: true)),
                                const SizedBox(width: 12),
                                Expanded(child: _inputField(controller: _heightController, label: 'Ширина Y, мм', keyboardType: TextInputType.number, triggerRecalc: true, boldNumber: true)),
                                const SizedBox(width: 12),
                                Expanded(child: _inputField(controller: _basePriceDm2Controller, label: 'Цена за 1 дм², руб.', keyboardType: TextInputType.number, isPriceField: true, boldNumber: true)),
                                const SizedBox(width: 12),
                                Expanded(child: _inputField(controller: _setupFeeController, label: 'Подготовка, руб.', keyboardType: TextInputType.number, isPriceField: true, boldNumber: true)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              decoration: BoxDecoration(
                                color: widget.isDark
                                    ? ecNavy.withOpacity(0.35)
                                    : const Color(0xFFEEF4FB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: widget.isDark ? const Color(0xFF3B82F6) : ecNavy.withOpacity(0.35), width: 1.3),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Расч. площадь 1 шт: ${singleAreaDm2.toStringAsFixed(2)} дм²',
                                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Партия: ${totalAreaDm2.toStringAsFixed(2)} дм²',
                                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        hasValidDimensions ? 'Расчёт по прайсу 2026 ($_urgency) с НДС 22%:' : 'Укажите длину X и ширину Y для расчёта цены:',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: widget.isDark ? Colors.white : ecNavy,
                                        ),
                                      ),
                                      Text(
                                        hasValidDimensions ? '${totalSumWithVat.toStringAsFixed(2)} руб.' : '0.00 руб.',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.3,
                                          color: hasValidDimensions ? ecOrange : Colors.amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_webPriceResult != null || _webPriceDetails != null) ...[
                                    const Divider(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Цена с сайта / из КП завода:', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                        Text(
                                          _webPriceResult ?? '...',
                                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                        ),
                                      ],
                                    ),
                                    if (_webPriceDetails != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(_webPriceDetails!, style: TextStyle(fontSize: 13, color: _subtleText)),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Слои',
                                    value: '$_layersCount',
                                    items: const ['1', '2', '4', '6', '8', '10', '12', '14', '16', '18'],
                                    onChanged: (v) => setState(() {
                                      _layersCount = int.parse(v.toString());
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Материал',
                                    value: _material,
                                    items: const ['FR4', 'FR4 Tg170', 'Алюминий', 'Rogers'],
                                    onChanged: (v) => setState(() {
                                      _material = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: _dropdownField(label: 'Толщина, мм', value: _thickness, items: const ['0.5', '0.8', '1.0', '1.5', '1.6', '2.0', '2.5', '3.0'], onChanged: (v) => setState(() => _thickness = v.toString()))),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Фольга, мкм',
                                    value: _foil,
                                    items: const ['12', '18', '35', '50', '70', '105'],
                                    onChanged: (v) => setState(() {
                                      _foil = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _dropdownField(
                                    label: 'Маска',
                                    value: _maskSide,
                                    items: const ['С двух сторон', 'С одной стороны (верх)', 'С одной стороны (низ)', 'Без маски'],
                                    onChanged: (v) => setState(() {
                                      _maskSide = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _dropdownField(
                                    label: 'Цвет маски',
                                    value: _maskColor,
                                    items: const ['Зеленая', 'Синяя', 'Черная', 'Белая', 'Красная'],
                                    onChanged: (v) => setState(() {
                                      _maskColor = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: _dropdownField(
                                    label: 'Покрытие',
                                    value: _finish,
                                    items: const ['HAL (ПОС-63)', 'Иммерсионное золото', 'Иммерсионное олово', 'Без покрытия'],
                                    onChanged: (v) => setState(() {
                                      _finish = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _dropdownField(
                                    label: 'Маркировка',
                                    value: _silkSide,
                                    items: const ['С двух сторон', 'С одной стороны (верх)', 'С одной стороны (низ)', 'Без маркировки'],
                                    onChanged: (v) => setState(() {
                                      _silkSide = v.toString();
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _dropdownField(label: 'Цвет марк.', value: _silkColor, items: const ['Белая', 'Черная'], onChanged: (v) => setState(() => _silkColor = v.toString())),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: _dropdownField(label: 'Контур', value: _contour, items: const ['фрезеровка', 'скрайбирование', 'фрезеровка + скрайб'], onChanged: (v) => setState(() => _contour = v.toString())),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _minTrackController, label: 'Мин. дорожка, мм', keyboardType: TextInputType.number, triggerRecalc: true, boldNumber: true)),
                                const SizedBox(width: 12),
                                Expanded(child: _inputField(controller: _minHoleController, label: 'Мин. сверло, мм', keyboardType: TextInputType.number, triggerRecalc: true, boldNumber: true)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CheckboxListTile(
                                    dense: true,
                                    activeColor: ecOrange,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Электротест', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                    value: _electroTest,
                                    onChanged: (v) => setState(() => _electroTest = v ?? true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _inputField(controller: _notesController, label: 'Примечание для ТЗ (стек, прессование, красные пометки)', icon: Icons.notes_rounded, triggerRecalc: true),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _inputField(
                                    controller: _managerController,
                                    label: 'Менеджер в КП',
                                    hint: 'Необязательно',
                                    icon: Icons.person_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text('Готовая строка спецификации (для 1С / КП):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: widget.isDark ? const Color(0xFF0A0F1A) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _borderCol),
                              ),
                              child: SelectableText(specLine, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ecOrange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                                  label: const Text('Сформировать КП (PDF)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                                  onPressed: () => _generateOfficialKpDocument(saveAsPdf: true),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ecNavy,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.request_quote_rounded, size: 18),
                                  label: const Text('КП (HTML-бланк)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  onPressed: () => _generateOfficialKpDocument(saveAsPdf: false),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ecNavyLight,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: _isFetchingWebPrice
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.cloud_download_outlined, size: 18),
                                  label: Text(_isFetchingWebPrice ? 'Считаю на сайте...' : 'Запросить цену с сайта', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  onPressed: _isFetchingWebPrice ? null : _fetchPriceFromWebsite,
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('Копировать строку КП', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: specLine));
                                    _showSnack('Строка спецификации скопирована!');
                                  },
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E40AF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.description_rounded, size: 18),
                                  label: const Text('Сохранить ТЗ (.TXT)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  onPressed: _exportConstructorTzFile,
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.email_outlined, size: 18),
                                  label: const Text('Шаблон письма клиенту', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  onPressed: () => _copyClientEmailTemplate(totalSumWithVat, totalAreaDm2),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: widget.isDark ? Colors.white : ecNavy,
                                    side: BorderSide(color: widget.isDark ? Colors.white24 : ecNavy),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                  label: const Text('Открыть сайт pselectro.ru', style: TextStyle(fontSize: 14)),
                                  onPressed: _openPselectroCalculator,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _borderCol),
                              boxShadow: widget.isDark
                                  ? null
                                  : [BoxShadow(color: ecNavy.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.verified_user_rounded, color: ecOrange, size: 24),
                                    const SizedBox(width: 10),
                                    Text(
                                      '2. DFM-контроль (ЭЛЕКТРОконнект)',
                                      style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : ecNavy),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (_analysis?.parsedFromOrderBlank == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      _blankBoardsList.length > 1
                                          ? 'Из архива загружено всех позиций: ${_blankBoardsList.length} шт. Переключайтесь между платами сверху и нажмите «Сформировать КП (PDF)»!'
                                          : 'Параметры (срочность «$_urgency», размеры X/Y, тираж, слои, покрытие и примечания) считаны из документа!',
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                if (_analysis?.hasNestedArchive == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: Colors.redAccent.withOpacity(0.45)),
                                    ),
                                    child: const Text(
                                      'Внутри обнаружен .RAR, а WinRAR / 7-Zip не найдены в стандартных папках Program Files — распакуйте его вручную или укажите X/Y слева.',
                                      style: TextStyle(fontSize: 13.5),
                                    ),
                                  ),
                                if (_analysis?.hasCadSourceOnly == true && _analysis?.parsedFromOrderBlank != true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ecNavy.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: ecNavy.withOpacity(0.35)),
                                    ),
                                    child: const Text(
                                      'В архиве исходник платы (.PCB/.LAY) без Gerber-слоёв. Нажмите на бланк .XLS или чертёж стека в списке ниже, чтобы открыть их и посмотреть размеры X/Y.',
                                      style: TextStyle(fontSize: 13.5),
                                    ),
                                  ),
                                if (_analysis?.hasBinaryBrdOnly == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ecOrange.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Text('В архиве бинарный .BRD без контура — укажите X и Y вручную.', style: TextStyle(fontSize: 13.5)),
                                  ),
                                ...dfmChecks.map((rawChk) {
                                  final chk = rawChk as DfmCheckItem;
                                  final col = chk.level == 'error'
                                      ? const Color(0xFFDC2626)
                                      : (chk.level == 'warn' ? ecOrange : const Color(0xFF059669));
                                  final icon = chk.level == 'error'
                                      ? Icons.cancel_rounded
                                      : (chk.level == 'warn' ? Icons.warning_amber_rounded : Icons.check_circle_rounded);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: col.withOpacity(widget.isDark ? 0.14 : 0.08),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: col.withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(icon, color: col, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(chk.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: col)),
                                              const SizedBox(height: 3),
                                              Text(chk.detail, style: TextStyle(fontSize: 13.5, color: _subtleText)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          if (_analysis != null) ...[
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: _cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _borderCol),
                                boxShadow: widget.isDark
                                    ? null
                                    : [BoxShadow(color: ecNavy.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '3. Состав архива (${_analysis!.totalHoles} отв.)',
                                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : ecNavy),
                                      ),
                                      Text('Клик по файлу — открыть', style: TextStyle(fontSize: 12.5, color: _subtleText)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ..._analysis!.layers.map((rawL) {
                                    final l = rawL as GerberLayerInfo;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _openExtractedFile(l.extractedPath, l.fileName),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 3),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: l.isImportantDoc ? ecOrange.withOpacity(0.1) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              l.isImportantDoc ? Icons.open_in_new_rounded : Icons.insert_drive_file_outlined,
                                              size: 17,
                                              color: l.isImportantDoc ? ecOrange : (widget.isDark ? const Color(0xFF60A5FA) : ecNavy),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                l.fileName,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: l.isImportantDoc ? (widget.isDark ? const Color(0xFFFB923C) : ecNavy) : null,
                                                ),
                                              ),
                                            ),
                                            Text(l.role, style: TextStyle(fontSize: 12.5, color: _subtleText)),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                  if (_analysis!.drillToolsBreakdown.isNotEmpty) ...[
                                    const Divider(height: 20),
                                    const Text('Инструменты сверловки (.DRL):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: (_analysis!.drillToolsBreakdown.entries.toList()..sort((a, b) => (a.key as double).compareTo(b.key as double)))
                                          .map((e) => Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: Text('Ø ${e.key} мм — ${e.value} шт.', style: const TextStyle(fontSize: 12.5)),
                                              ))
                                          .toList(),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
