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
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = prefs.getBool('cam_dark_theme') ?? true);
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
        colorSchemeSeed: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF38BDF8),
        scaffoldBackgroundColor: const Color(0xFF090D16),
      ),
      home: CamWorkspaceScreen(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

class GerberLayerInfo {
  final String fileName;
  final String role;
  final int sizeBytes;

  GerberLayerInfo({
    required this.fileName,
    required this.role,
    required this.sizeBytes,
  });
}

class GerberAnalysisResult {
  final String archiveName;
  final String archiveDir;
  final String projectTitle;
  final List<GerberLayerInfo> layers;
  final int detectedLayersCount;
  final bool hasTopMask;
  final bool hasBottomMask;
  final bool hasTopSilk;
  final bool hasBottomSilk;
  final bool hasBinaryBrdOnly;
  final double? widthMm;
  final double? heightMm;
  final double? minTrackMm;
  final double? minDrillMm;
  final int totalHoles;
  final Map<double, int> drillToolsBreakdown;

  GerberAnalysisResult({
    required this.archiveName,
    required this.archiveDir,
    required this.projectTitle,
    required this.layers,
    required this.detectedLayersCount,
    required this.hasTopMask,
    required this.hasBottomMask,
    required this.hasTopSilk,
    required this.hasBottomSilk,
    required this.hasBinaryBrdOnly,
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
  final String level; // 'ok', 'warn', 'error'

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
  GerberAnalysisResult? _analysis;

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _orderNameController = TextEditingController();
  final TextEditingController _widthController = TextEditingController(text: '64');
  final TextEditingController _heightController = TextEditingController(text: '23');
  final TextEditingController _qtyController = TextEditingController(text: '10');
  final TextEditingController _minTrackController = TextEditingController(text: '0.15');
  final TextEditingController _minHoleController = TextEditingController(text: '0.30');
  final TextEditingController _notesController = TextEditingController();

  // Поля прайс-калькулятора
  final TextEditingController _basePriceDm2Controller = TextEditingController(text: '528.0');
  final TextEditingController _setupFeeController = TextEditingController(text: '2400.0');

  String _orderType = 'Новый';
  int _layersCount = 2;
  String _material = 'FR4';
  String _thickness = '1.5';
  String _foil = '18';
  String _maskSide = 'С двух сторон';
  String _maskColor = 'Зеленая';
  String _silkSide = 'С двух сторон';
  String _silkColor = 'Белая';
  String _finish = 'HAL';
  String _contour = 'фрезеровка';
  bool _electroTest = true;

  Color get _cardBg => widget.isDark ? const Color(0xFF111827) : Colors.white;
  Color get _borderCol => widget.isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
  Color get _subtleText => widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _pickAndAnalyzeZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) return;

    final zipFile = File(result.files.single.path!);
    final archiveName = zipFile.path.split(Platform.pathSeparator).last;
    final archiveDir = zipFile.parent.path;

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final List<GerberLayerInfo> layers = [];
      int copperLayers = 0;
      bool hasTopMask = false;
      bool hasBottomMask = false;
      bool hasTopSilk = false;
      bool hasBottomSilk = false;
      bool hasBinaryBrd = false;
      bool hasTextContour = false;

      double? detectedWidth;
      double? detectedHeight;
      double? minTrackMm;
      double? minDrillMm;
      int totalHoles = 0;
      final Map<double, int> drillBreakdown = {};

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final rawName = file.name.split('/').last.split('\\').last;
        if (rawName.isEmpty || rawName.startsWith('.')) continue;

        final upper = rawName.toUpperCase();
        String role = 'Прочий файл проекта';

        if (upper.endsWith('.TOP') || upper.endsWith('.GTL') || upper.contains('F_CU') || upper.contains('TOP_COPPER')) {
          role = 'Верхний слой меди (TOP)';
          copperLayers++;
        } else if (upper.endsWith('.BOT') || upper.endsWith('.GBL') || upper.contains('B_CU') || upper.contains('BOT_COPPER')) {
          role = 'Нижний слой меди (BOT)';
          copperLayers++;
        } else if (RegExp(r'\.(G[1-9]|IN[1-9]|L[2-9])$').hasMatch(upper)) {
          role = 'Внутренний слой меди';
          copperLayers++;
        } else if (upper.endsWith('.TMS') || upper.endsWith('.GTS') || upper.contains('F_MASK')) {
          role = 'Верхняя паяльная маска';
          hasTopMask = true;
        } else if (upper.endsWith('.BMS') || upper.endsWith('.GBS') || upper.contains('B_MASK')) {
          role = 'Нижняя паяльная маска';
          hasBottomMask = true;
        } else if (upper.endsWith('.GTO') || upper.endsWith('.TSK') || upper.contains('F_SILK')) {
          role = 'Верхняя маркировка (шелкография)';
          hasTopSilk = true;
        } else if (upper.endsWith('.GBO') || upper.endsWith('.BSK') || upper.contains('B_SILK')) {
          role = 'Нижняя маркировка (шелкография)';
          hasBottomSilk = true;
        } else if (upper.endsWith('.GKO') || upper.endsWith('.GM1') || upper.contains('EDGE') || upper.contains('OUTLINE') || upper.contains('BOARD')) {
          role = 'Контур платы / фрезеровка';
          hasTextContour = true;
        } else if (upper.endsWith('.DRL') || upper.endsWith('.TXT') || upper.endsWith('.EXC') || upper.contains('DRILL')) {
          role = 'Сверловка (Excellon)';
        } else if (upper.endsWith('.BRD')) {
          role = 'Файл платы P-CAD / CAD (.BRD)';
          hasBinaryBrd = true;
        }

        layers.add(GerberLayerInfo(fileName: rawName, role: role, sizeBytes: file.size));

        final contentBytes = file.content as List<int>;
        final isLikelyBinary = contentBytes.take(200).where((b) => b == 0).length > 5;

        if (!isLikelyBinary) {
          final textContent = utf8.decode(contentBytes, allowMalformed: true);
          if (role.contains('Сверловка')) {
            final drillStats = _parseExcellonDrill(textContent);
            totalHoles += drillStats.totalHoles;
            for (final entry in drillStats.tools.entries) {
              drillBreakdown[entry.key] = (drillBreakdown[entry.key] ?? 0) + entry.value;
              if (minDrillMm == null || entry.key < minDrillMm) minDrillMm = entry.key;
            }
          } else if (role.contains('меди') || role.contains('Контур')) {
            final gerberStats = _parseGerberGeometry(textContent);
            if (gerberStats.minTrackMm != null && (minTrackMm == null || gerberStats.minTrackMm! < minTrackMm)) {
              minTrackMm = gerberStats.minTrackMm;
            }
            if (gerberStats.widthMm != null && gerberStats.heightMm != null && (role.contains('Контур') || detectedWidth == null)) {
              detectedWidth = gerberStats.widthMm;
              detectedHeight = gerberStats.heightMm;
            }
          }
        }
      }

      final finalLayersCount = copperLayers > 0 ? copperLayers : 2;
      final projectTitle = archiveName.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');

      final resultObj = GerberAnalysisResult(
        archiveName: archiveName,
        archiveDir: archiveDir,
        projectTitle: projectTitle,
        layers: layers,
        detectedLayersCount: finalLayersCount,
        hasTopMask: hasTopMask,
        hasBottomMask: hasBottomMask,
        hasTopSilk: hasTopSilk,
        hasBottomSilk: hasBottomSilk,
        hasBinaryBrdOnly: hasBinaryBrd && !hasTextContour && detectedWidth == null,
        widthMm: detectedWidth,
        heightMm: detectedHeight,
        minTrackMm: minTrackMm,
        minDrillMm: minDrillMm,
        totalHoles: totalHoles,
        drillToolsBreakdown: drillBreakdown,
      );

      setState(() {
        _analysis = resultObj;
        _orderNameController.text = projectTitle;
        _layersCount = finalLayersCount;
        if (detectedWidth != null) _widthController.text = detectedWidth.toStringAsFixed(1);
        if (detectedHeight != null) _heightController.text = detectedHeight.toStringAsFixed(1);
        if (minTrackMm != null) _minTrackController.text = minTrackMm.toStringAsFixed(3);
        if (minDrillMm != null) _minHoleController.text = minDrillMm.toStringAsFixed(2);
        _maskSide = (hasTopMask && hasBottomMask)
            ? 'С двух сторон'
            : ((hasTopMask || hasBottomMask) ? 'С одной стороны' : 'Без маски');
        _silkSide = (hasTopSilk && hasBottomSilk)
            ? 'С двух сторон'
            : ((hasTopSilk || hasBottomSilk) ? 'С одной стороны' : 'Без маркировки');
      });

      _showSnack('Проект $archiveName проанализирован!');
    } catch (e) {
      _showSnack('Ошибка чтения архива: $e');
    }
  }

  ({int totalHoles, Map<double, int> tools}) _parseExcellonDrill(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final Map<String, double> toolDiameters = {};
    final Map<double, int> toolCounts = {};
    bool isMetric = true;
    String? activeTool;
    int total = 0;

    for (final raw in lines) {
      final line = raw.trim().toUpperCase();
      if (line.isEmpty || line.startsWith(';')) continue;
      if (line.contains('INCH')) isMetric = false;
      if (line.contains('METRIC')) isMetric = true;

      final defMatch = RegExp(r'^(T\d+)C([\d.]+)').firstMatch(line);
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
        final diam = toolDiameters[activeTool]!;
        toolCounts[diam] = (toolCounts[diam] ?? 0) + 1;
        total++;
      }
    }
    return (totalHoles: total, tools: toolCounts);
  }

  ({double? widthMm, double? heightMm, double? minTrackMm}) _parseGerberGeometry(String text) {
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

      final coordMatch = RegExp(r'X(-?\d+)Y(-?\d+)D0[12]').firstMatch(line);
      if (coordMatch != null) {
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
    return (widthMm: width, heightMm: height, minTrackMm: minAperture);
  }

  List<DfmCheckItem> _evaluateElectroconnectDfm() {
    final List<DfmCheckItem> checks = [];
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final track = double.tryParse(_minTrackController.text.replaceAll(',', '.')) ?? 0;
    final drill = double.tryParse(_minHoleController.text.replaceAll(',', '.')) ?? 0;
    final thick = double.tryParse(_thickness) ?? 1.5;

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
      checks.add(DfmCheckItem(
        title: 'Габариты платы в норме (${w.toStringAsFixed(1)}×${h.toStringAsFixed(1)} мм)',
        detail: 'Укладываются в стандартное рабочее поле (до 450×350 мм).',
        level: 'ok',
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
          title: 'Дорожка $track мм попадает в «Предел»',
          detail: 'Для фольги $_foil мкм стандарт ≥ $stdT мм (повышенный класс точности).',
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
          detail: 'Стандарт: Ø ≥ 0.30 мм и отношение толщины платы к диаметру ≤ 2.5.',
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

    if (_finish == 'HAL' && thick < 1.0) {
      checks.add(DfmCheckItem(
        title: 'HAL (ПОС-63) запрещён для платы $thick мм!',
        detail: 'По тех. возможностям завода HASL не применяется на платах тоньше 1.0 мм.',
        level: 'error',
      ));
    }

    if (_maskColor != 'Зеленая' && _maskSide != 'Без маски') {
      checks.add(DfmCheckItem(
        title: 'Цветная маска ($_maskColor): проверь переходные отверстия',
        detail: 'По регламенту завода для цветной маски отверстия ≤ 0.4 мм рекомендуется закрывать маской.',
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
    final w = _widthController.text.trim();
    final h = _heightController.text.trim();
    final maskPart = _maskSide == 'Без маски' ? 'Без маски' : '$_maskSide $_maskColor';
    final silkPart = _silkSide == 'Без маркировки' ? 'Без маркировки' : '$_silkSide $_silkColor';
    final testPart = _electroTest ? 'Эл. тест.' : 'Без эл. теста.';

    return '$_orderType; $_layersCount сл; ${w}х${h}мм; $_contour; '
        '$_material-${_thickness}мм-${_foil}мкм; '
        'маска: $maskPart; маркировка: $silkPart; $_finish; $testPart';
  }
  Future<void> _exportConstructorTzFile() async {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;
    final singleDm2 = (w * h) / 10000.0;
    final totalDm2 = singleDm2 * math.max(qty, 1);

    final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 528.0;
    final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 2400.0;
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
    sb.writeln('Тип заказа:        $_orderType');
    sb.writeln('Тираж:             $qty шт. (площадь 1 шт: ${singleDm2.toStringAsFixed(3)} дм², партия: ${totalDm2.toStringAsFixed(2)} дм²)');
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('РАСЧЕТ СТОИМОСТИ (ПРЕДВАРИТЕЛЬНЫЙ):');
    sb.writeln('• Сумма без НДС:   ${pureSum.toStringAsFixed(2)} руб.');
    sb.writeln('• НДС (22%):       ${vatSum.toStringAsFixed(2)} руб.');
    sb.writeln('• ИТОГО с НДС:     ${totalSumWithVat.toStringAsFixed(2)} руб.');
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
      sb.writeln('• Примечание менеджера:  ${_notesController.text.trim()}');
    }
    sb.writeln('--------------------------------------------------------------------');
    sb.writeln('РЕЗУЛЬТАТ DFM-ПРОВЕРКИ (РЕГЛАМЕНТ ЭЛЕКТРОКОННЕКТ):');
    for (final c in dfm) {
      final tag = c.level == 'error' ? '[КРИТИЧНО]' : (c.level == 'warn' ? '[ПРЕДЕЛ]' : '[OK]');
      sb.writeln('$tag ${c.title} — ${c.detail}');
    }
    if (_analysis != null) {
      sb.writeln('--------------------------------------------------------------------');
      sb.writeln('СОСТАВ АРХИВА (${_analysis!.archiveName}):');
      for (final l in _analysis!.layers) {
        sb.writeln('• ${l.fileName} -> ${l.role}');
      }
      if (_analysis!.drillToolsBreakdown.isNotEmpty) {
        sb.writeln('Сверловка (всего ${_analysis!.totalHoles} отв.):');
        final sorted = _analysis!.drillToolsBreakdown.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
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

  void _copyClientEmailTemplate(double totalWithVat, double totalDm2) {
    final title = _orderNameController.text.trim().isEmpty ? 'платы' : _orderNameController.text.trim();
    final qty = _qtyController.text.trim();
    final text = '''Здравствуйте!
Благодарим за обращение на завод «ЭЛЕКТРОконнект».

По результатам проверки производственных файлов проекта «$title» ($qty шт., общая площадь партии: ${totalDm2.toStringAsFixed(2)} дм²):
• Габариты и класс точности соответствуют стандартам технологического регламента.
• Предварительная стоимость партии с учетом НДС 22%: ${totalWithVat.toStringAsFixed(2)} руб.

Ждем ваше подтверждение запуска в производство!

С уважением,
ООО «ЭЛЕКТРОконнект»''';

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
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12.5, color: _subtleText),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: widget.isDark ? const Color(0xFF182235) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: _subtleText),
        filled: true,
        fillColor: widget.isDark ? const Color(0xFF182235) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderCol)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0284C7);
    final w = double.tryParse(_widthController.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 10;
    final singleAreaDm2 = (w > 0 && h > 0) ? (w * h) / 10000.0 : null;
    final totalAreaDm2 = singleAreaDm2 != null ? singleAreaDm2 * math.max(qty, 1) : 0.0;

    final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 528.0;
    final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 2400.0;
    final pureSum = (totalAreaDm2 * baseP) + setupP;
    final vatSum = pureSum * 0.22;
    final totalSumWithVat = pureSum + vatSum;

    final dfmChecks = _evaluateElectroconnectDfm();
    final specLine = _buildSpecificationLine();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _cardBg,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ЭЛЕКТРОконнект — CAM & DFM Контроль (Кувезенков А.А.)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Анализ Gerber • Проверка норм завода • Расчет цены и ТЗ', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isDark ? 'Светлая тема' : 'Тёмная тема',
            icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderCol)),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_zip_outlined, color: accent, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _analysis != null ? 'Проект: ${_analysis!.archiveName}' : 'Загрузите архив с файлами платы (.zip)',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _analysis != null
                                  ? 'Найдено файлов: ${_analysis!.layers.length} • Отверстий: ${_analysis!.totalHoles} • Папка: ${_analysis!.archiveDir}'
                                  : 'Поддерживаются P-CAD (.TOP, .BOT, .TMS, .BMS, .DRL, .BRD) и стандартные Gerber (.GTL, .GBL, .GTS, .GBS, .GKO)',
                              style: TextStyle(fontSize: 12.5, color: _subtleText),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 20),
                        label: const Text('ВЫБРАТЬ .ZIP АРХИВ', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _pickAndAnalyzeZip,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderCol)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('1. Параметры платы и расчет стоимости', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _customerController, label: 'Заказчик', icon: Icons.business_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _orderNameController, label: 'Децимальный номер', icon: Icons.tag_rounded)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dropdownField(label: 'Тип заказа', value: _orderType, items: const ['Новый', 'Повтор'], onChanged: (v) => setState(() => _orderType = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _widthController, label: 'Длина X, мм', keyboardType: TextInputType.number)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _heightController, label: 'Ширина Y, мм', keyboardType: TextInputType.number)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _qtyController, label: 'Тираж, шт.', keyboardType: TextInputType.number)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _basePriceDm2Controller, label: 'Цена за 1 дм², руб.', keyboardType: TextInputType.number)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _setupFeeController, label: 'Подготовка, руб.', keyboardType: TextInputType.number)),
                              ],
                            ),
                            if (singleAreaDm2 != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.35)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Площадь 1 шт: ${singleAreaDm2.toStringAsFixed(3)} дм²', style: const TextStyle(fontSize: 12.5)),
                                        Text('Партия: ${totalAreaDm2.toStringAsFixed(2)} дм²', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const Divider(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('ИТОГО с НДС (22%):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _subtleText)),
                                        Text('${totalSumWithVat.toStringAsFixed(2)} руб.', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dropdownField(label: 'Слои', value: '$_layersCount', items: const ['1', '2', '4', '6', '8', '10', '12', '16'], onChanged: (v) => setState(() => _layersCount = int.parse(v!)))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Материал', value: _material, items: const ['FR4', 'Алюминий', 'Rogers'], onChanged: (v) => setState(() => _material = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Толщина, мм', value: _thickness, items: const ['0.5', '0.8', '1.0', '1.5', '2.0', '2.5', '3.0'], onChanged: (v) => setState(() => _thickness = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Фольга, мкм', value: _foil, items: const ['12', '18', '35', '50', '70', '105'], onChanged: (v) => setState(() => _foil = v!))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dropdownField(label: 'Маска', value: _maskSide, items: const ['С двух сторон', 'С одной стороны', 'Без маски'], onChanged: (v) => setState(() => _maskSide = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Цвет маски', value: _maskColor, items: const ['Зеленая', 'Синяя', 'Черная', 'Белая', 'Красная'], onChanged: (v) => setState(() => _maskColor = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Покрытие', value: _finish, items: const ['HAL', 'Иммерсионное золото', 'Иммерсионное олово', 'Без покрытия'], onChanged: (v) => setState(() => _finish = v!))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _dropdownField(label: 'Маркировка', value: _silkSide, items: const ['С двух сторон', 'С одной стороны', 'Без маркировки'], onChanged: (v) => setState(() => _silkSide = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Цвет марк.', value: _silkColor, items: const ['Белая', 'Черная'], onChanged: (v) => setState(() => _silkColor = v!))),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Контур', value: _contour, items: const ['фрезеровка', 'скрайбирование'], onChanged: (v) => setState(() => _contour = v!))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _inputField(controller: _minTrackController, label: 'Мин. дорожка, мм', keyboardType: TextInputType.number)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _minHoleController, label: 'Мин. сверло, мм', keyboardType: TextInputType.number)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Электротест', style: TextStyle(fontSize: 13)),
                                    value: _electroTest,
                                    onChanged: (v) => setState(() => _electroTest = v ?? true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _inputField(controller: _notesController, label: 'Примечание для ТЗ', icon: Icons.notes_rounded),
                            const SizedBox(height: 16),
                            const Text('Готовая строка спецификации (для 1С / КП):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: widget.isDark ? const Color(0xFF0A0F1A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _borderCol),
                              ),
                              child: SelectableText(specLine, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488), foregroundColor: Colors.white),
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  label: const Text('Копировать строку КП'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: specLine));
                                    _showSnack('Строка спецификации скопирована!');
                                  },
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.description_rounded, size: 16),
                                  label: const Text('Сохранить ТЗ (.TXT)'),
                                  onPressed: _exportConstructorTzFile,
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                                  icon: const Icon(Icons.email_outlined, size: 16),
                                  label: const Text('Шаблон письма клиенту'),
                                  onPressed: () => _copyClientEmailTemplate(totalSumWithVat, totalAreaDm2),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.calculate_outlined, size: 16),
                                  label: const Text('Калькулятор сайта'),
                                  onPressed: _openPselectroCalculator,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderCol)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 22),
                                    SizedBox(width: 8),
                                    Text('2. DFM-контроль (ЭЛЕКТРОконнект)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_analysis?.hasBinaryBrdOnly == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text('В архиве бинарный .BRD без контура — укажите X и Y вручную.', style: TextStyle(fontSize: 12)),
                                  ),
                                ...dfmChecks.map((chk) {
                                  final col = chk.level == 'error'
                                      ? Colors.redAccent
                                      : (chk.level == 'warn' ? Colors.amberAccent : const Color(0xFF10B981));
                                  final icon = chk.level == 'error'
                                      ? Icons.cancel_rounded
                                      : (chk.level == 'warn' ? Icons.warning_amber_rounded : Icons.check_circle_rounded);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: col.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: col.withOpacity(0.35)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(icon, color: col, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(chk.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: col)),
                                              const SizedBox(height: 2),
                                              Text(chk.detail, style: TextStyle(fontSize: 11.5, color: _subtleText)),
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
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderCol)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('3. Состав архива и сверловка (${_analysis!.totalHoles} отв.)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  ..._analysis!.layers.map((l) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.insert_drive_file_outlined, size: 15, color: accent),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(l.fileName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                            Text(l.role, style: TextStyle(fontSize: 11, color: _subtleText)),
                                          ],
                                        ),
                                      )),
                                  if (_analysis!.drillToolsBreakdown.isNotEmpty) ...[
                                    const Divider(height: 18),
                                    const Text('Инструменты сверловки (.DRL):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: (_analysis!.drillToolsBreakdown.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
                                          .map((e) => Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: Text('Ø ${e.key} мм — ${e.value} шт.', style: const TextStyle(fontSize: 11)),
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
