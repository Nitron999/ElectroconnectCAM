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
  final List<GerberLayerInfo> layers;
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
  GerberAnalysisResult? _analysis;

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _orderNameController = TextEditingController();
  final TextEditingController _widthController = TextEditingController(text: '0.0');
  final TextEditingController _heightController = TextEditingController(text: '0.0');
  final TextEditingController _qtyController = TextEditingController(text: '10');
  final TextEditingController _minTrackController = TextEditingController(text: '0.15');
  final TextEditingController _minHoleController = TextEditingController(text: '0.30');
  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _basePriceDm2Controller = TextEditingController(text: '528.0');
  final TextEditingController _setupFeeController = TextEditingController(text: '2400.0');
  bool _manualPriceOverride = false;

  bool _isFetchingWebPrice = false;
  String? _webPriceResult;
  String? _webPriceDetails;

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

  void _recalculateTariffFromSpecs({bool force = false}) {
    if (_manualPriceOverride && !force) return;

    double dm2Rate;
    double setupFee;
    switch (_layersCount) {
      case 1:
        dm2Rate = 380.0;
        setupFee = 1800.0;
        break;
      case 2:
        dm2Rate = 528.0;
        setupFee = 2400.0;
        break;
      case 4:
        dm2Rate = 1150.0;
        setupFee = 5500.0;
        break;
      case 6:
        dm2Rate = 1750.0;
        setupFee = 8500.0;
        break;
      case 8:
        dm2Rate = 2400.0;
        setupFee = 12000.0;
        break;
      default:
        dm2Rate = 3200.0 + (_layersCount - 10) * 350.0;
        setupFee = 16000.0;
        break;
    }

    if (_material == 'Алюминий') dm2Rate *= 1.35;
    if (_material == 'Rogers') dm2Rate *= 2.80;

    final foilInt = int.tryParse(_foil) ?? 18;
    if (foilInt >= 70) {
      dm2Rate *= 1.30;
    } else if (foilInt >= 35) {
      dm2Rate *= 1.12;
    }

    if (_finish == 'Иммерсионное золото') {
      dm2Rate *= 1.35;
    } else if (_finish == 'Иммерсионное олово') {
      dm2Rate *= 1.15;
    }

    if (_maskColor != 'Зеленая' && _maskSide != 'Без маски') {
      dm2Rate *= 1.08;
    }

    if (_orderType == 'Повтор') {
      setupFee = 0.0;
    }

    _basePriceDm2Controller.text = dm2Rate.toStringAsFixed(1);
    _setupFeeController.text = setupFee.toStringAsFixed(1);
  }

  void _resetAllFieldsToDefault({bool showToast = true}) {
    _analysis = null;
    _manualPriceOverride = false;
    _webPriceResult = null;
    _webPriceDetails = null;
    _customerController.clear();
    _orderNameController.clear();
    _widthController.text = '0.0';
    _heightController.text = '0.0';
    _qtyController.text = '10';
    _minTrackController.text = '0.15';
    _minHoleController.text = '0.30';
    _notesController.clear();
    _orderType = 'Новый';
    _layersCount = 2;
    _material = 'FR4';
    _thickness = '1.5';
    _foil = '18';
    _maskSide = 'С двух сторон';
    _maskColor = 'Зеленая';
    _silkSide = 'С двух сторон';
    _silkColor = 'Белая';
    _finish = 'HAL';
    _contour = 'фрезеровка';
    _electroTest = true;
    _recalculateTariffFromSpecs(force: true);

    if (showToast) {
      _showSnack('Проект очищен. Готово к загрузке нового архива!');
    }
  }

  void _clearCurrentProject() {
    setState(() {
      _resetAllFieldsToDefault(showToast: true);
    });
  }

  Future<void> _openExtractedFile(String? path, String fileName) async {
    if (path == null || !File(path).existsSync()) {
      _showSnack('Файл $fileName недоступен для открытия.');
      return;
    }
    await OpenFilex.open(path);
  }

  String _buildExcelParserPythonCode() {
    final sb = StringBuffer();
    sb.writeln(r'# -*- coding: utf-8 -*-');
    sb.writeln(r'import json, re, subprocess, sys');
    sb.writeln(r'EXCEL_PATH = sys.argv[1]');
    sb.writeln(r'OUT_JSON = sys.argv[2]');
    sb.writeln(r'def ensure_pkg(pkg):');
    sb.writeln(r'    try:');
    sb.writeln(r'        __import__(pkg)');
    sb.writeln(r'    except ImportError:');
    sb.writeln(r'        subprocess.run([sys.executable, "-m", "pip", "install", "-q", pkg], check=False)');
    sb.writeln(r'def read_lib(path):');
    sb.writeln(r'    if path.lower().endswith(".xlsx"):');
    sb.writeln(r'        ensure_pkg("openpyxl")');
    sb.writeln(r'        import openpyxl');
    sb.writeln(r'        wb = openpyxl.load_workbook(path, data_only=True)');
    sb.writeln(r'        ws = wb.active');
    sb.writeln(r'        return [["" if ws.cell(r, c).value is None else str(ws.cell(r, c).value).strip() for c in range(1, 18)] for r in range(1, 55)]');
    sb.writeln(r'    ensure_pkg("xlrd")');
    sb.writeln(r'    import xlrd');
    sb.writeln(r'    wb = xlrd.open_workbook(path)');
    sb.writeln(r'    sh = wb.sheet_by_index(0)');
    sb.writeln(r'    return [[str(sh.cell_value(r, c)).strip() for c in range(min(18, sh.ncols))] for r in range(min(55, sh.nrows))]');
    sb.writeln(r'def main():');
    sb.writeln(r'    try:');
    sb.writeln(r'        rows = read_lib(EXCEL_PATH)');
    sb.writeln(r'    except Exception as e:');
    sb.writeln(r'        open(OUT_JSON, "w", encoding="utf-8").write(json.dumps({"ok": False, "error": str(e)}))');
    sb.writeln(r'        return');
    sb.writeln(r'    data = {"ok": True, "notes": []}');
    sb.writeln(r'    for row in rows:');
    sb.writeln(r'        ne = [x for x in row if x]');
    sb.writeln(r'        if len(ne) < 2: continue');
    sb.writeln(r'        lbl, val = ne[0].lower(), ne[1]');
    sb.writeln(r'        if re.fullmatch(r"\d+\.?", lbl) and len(ne) >= 3:');
    sb.writeln(r'            lbl, val = ne[1].lower(), ne[2]');
    sb.writeln(r'        row_joined = " ".join(ne).lower()');
    sb.writeln(r'        if "заказчик" in lbl and "название" in lbl: data["customer"] = val');
    sb.writeln(r'        elif "тип заказа" in lbl: data["order_type"] = "Повтор" if "повтор" in val.lower() else "Новый"');
    sb.writeln(r'        elif "количество плат" in lbl:');
    sb.writeln(r'            m = re.search(r"(\d+)", val)');
    sb.writeln(r'            if m: data["qty"] = int(m.group(1))');
    sb.writeln(r'        elif "размеры платы" in lbl or "точные размеры" in lbl:');
    sb.writeln(r'            m = re.search(r"(\d+(?:[.,]\d+)?)\s*[xхXХ*]\s*(\d+(?:[.,]\d+)?)", val)');
    sb.writeln(r'            if m:');
    sb.writeln(r'                data["width"] = float(m.group(1).replace(",", "."))');
    sb.writeln(r'                data["height"] = float(m.group(2).replace(",", "."))');
    sb.writeln(r'        elif "количество слоев" in lbl or "количество слоёв" in lbl:');
    sb.writeln(r'            m = re.search(r"(\d+)", val)');
    sb.writeln(r'            if m: data["layers"] = int(m.group(1))');
    sb.writeln(r'        elif "толщина платы" in lbl:');
    sb.writeln(r'            m = re.search(r"(\d+(?:[.,]\d+)?)", val)');
    sb.writeln(r'            if m: data["thickness"] = m.group(1).replace(",", ".")');
    sb.writeln(r'        elif "толщина фольги" in lbl:');
    sb.writeln(r'            m = re.search(r"(\d+)", val)');
    sb.writeln(r'            if m: data["foil"] = m.group(1)');
    sb.writeln(r'        elif "паяльная маска" in lbl: data["mask_side"] = val');
    sb.writeln(r'        elif "маркировка" in lbl: data["silk_side"] = val');
    sb.writeln(r'        elif "покрытие" in lbl and "ножев" not in lbl and "разъем" not in lbl and "разъём" not in lbl:');
    sb.writeln(r'            data["finish"] = val');
    sb.writeln(r'        elif "ножевых" in lbl and val.lower() not in ("нет", "-", "0", ""): data["notes"].append("Покрытие ножевых разъёмов: " + val)');
    sb.writeln(r'        elif "вариант мпп" in lbl and val.lower() not in ("нет", "-", ""): data["notes"].append("Вариант МПП: " + val)');
    sb.writeln(r'        elif "электроконтрол" in lbl: data["electro_test"] = ("нет" not in val.lower())');
    sb.writeln(r'        elif "обработки контура" in lbl: data["contour"] = val.lower()');
    sb.writeln(r'        if "rogers" in row_joined: data["material"] = "Rogers"');
    sb.writeln(r'        elif "алюмин" in row_joined: data["material"] = "Алюминий"');
    sb.writeln(r'    open(OUT_JSON, "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False))');
    sb.writeln(r'if __name__ == "__main__": main()');
    return sb.toString();
  }

  Future<dynamic> _parseElectroconnectExcelBlank(String excelPath) async {
    if (!Platform.isWindows) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final pyFile = File('${tempDir.path}\\parse_ec_blank.py');
      final outJson = File('${tempDir.path}\\ec_blank_parsed.json');
      if (outJson.existsSync()) outJson.deleteSync();

      final cleanXlsPath = '${tempDir.path}\\clean_blank_${DateTime.now().millisecondsSinceEpoch}${excelPath.toLowerCase().endsWith('.xlsx') ? '.xlsx' : '.xls'}';
      await File(excelPath).copy(cleanXlsPath);

      await pyFile.writeAsString(_buildExcelParserPythonCode(), encoding: utf8);
      await Process.run('python', [pyFile.path, cleanXlsPath, outJson.path], runInShell: true);

      if (outJson.existsSync()) {
        final raw = await outJson.readAsString(encoding: utf8);
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        if (parsed['ok'] == true) return parsed;
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
    final sb = StringBuffer();
    sb.writeln(r'# -*- coding: utf-8 -*-');
    sb.writeln(r'import json, re');
    sb.writeln(r'from playwright.sync_api import sync_playwright');
    sb.writeln('WIDTH = "${w.toStringAsFixed(1)}"');
    sb.writeln('HEIGHT = "${h.toStringAsFixed(1)}"');
    sb.writeln('QTY = "$qty"');
    sb.writeln('LAYERS = "$_layersCount"');
    sb.writeln('THICKNESS = "$_thickness"');
    sb.writeln('FOIL = "$_foil"');
    sb.writeln('MASK_SIDE = "$_maskSide"');
    sb.writeln('FINISH = "$_finish"');
    sb.writeln('ORDER_TYPE = "$_orderType"');
    sb.writeln('OUT_JSON = r"$outJsonPath"');
    sb.writeln(r'def fill_ctx(ctx, kws, val):');
    sb.writeln(r'    inputs = ctx.locator("input:not([type=hidden]):not([type=radio]):not([type=checkbox]):not([type=submit]):not([type=button])")');
    sb.writeln(r'    for i in range(inputs.count()):');
    sb.writeln(r'        inp = inputs.nth(i)');
    sb.writeln(r'        try:');
    sb.writeln(r'            if not inp.is_visible() or not inp.is_editable(): continue');
    sb.writeln(r'            attrs = ((inp.get_attribute("name") or "") + " " + (inp.get_attribute("id") or "") + " " + (inp.get_attribute("placeholder") or "") + " " + (inp.get_attribute("aria-label") or "")).lower()');
    sb.writeln(r'            near = ""');
    sb.writeln(r'            for xp in ["xpath=..", "xpath=../..", "xpath=../../.."]:');
    sb.writeln(r'                try:');
    sb.writeln(r'                    t = inp.locator(xp).inner_text().lower()');
    sb.writeln(r'                    if len(t) < 180: near += " " + t');
    sb.writeln(r'                except Exception: pass');
    sb.writeln(r'            if any(k in (attrs + " " + near) for k in kws):');
    sb.writeln(r'                inp.click()');
    sb.writeln(r'                inp.fill("")');
    sb.writeln(r'                inp.type(str(val), delay=30)');
    sb.writeln(r'                inp.dispatch_event("input")');
    sb.writeln(r'                inp.dispatch_event("change")');
    sb.writeln(r'                inp.press("Tab")');
    sb.writeln(r'                return True');
    sb.writeln(r'        except Exception: pass');
    sb.writeln(r'    return False');
    sb.writeln(r'def select_or_click(ctx, variants):');
    sb.writeln(r'    selects = ctx.locator("select")');
    sb.writeln(r'    for s_idx in range(selects.count()):');
    sb.writeln(r'        sel = selects.nth(s_idx)');
    sb.writeln(r'        try:');
    sb.writeln(r'            opts = sel.locator("option")');
    sb.writeln(r'            for o_idx in range(opts.count()):');
    sb.writeln(r'                otxt = opts.nth(o_idx).inner_text().strip()');
    sb.writeln(r'                if any(v.lower() in otxt.lower() for v in variants):');
    sb.writeln(r'                    oval = opts.nth(o_idx).get_attribute("value")');
    sb.writeln(r'                    sel.select_option(value=oval)');
    sb.writeln(r'                    sel.dispatch_event("change")');
    sb.writeln(r'                    return True');
    sb.writeln(r'        except Exception: pass');
    sb.writeln(r'    for txt in variants:');
    sb.writeln(r'        loc = ctx.locator("label, button, span, div, li, a").filter(has_text=re.compile(re.escape(txt), re.I))');
    sb.writeln(r'        for i in range(loc.count()):');
    sb.writeln(r'            el = loc.nth(i)');
    sb.writeln(r'            try:');
    sb.writeln(r'                if el.is_visible() and len(el.inner_text().strip()) < 60:');
    sb.writeln(r'                    el.click(timeout=1000)');
    sb.writeln(r'                    return True');
    sb.writeln(r'            except Exception: pass');
    sb.writeln(r'    return False');
    sb.writeln(r'def main():');
    sb.writeln(r'    res = {"ok": False, "price": "", "raw": "", "error": ""}');
    sb.writeln(r'    try:');
    sb.writeln(r'        with sync_playwright() as p:');
    sb.writeln(r'            browser = p.chromium.launch(headless=False)');
    sb.writeln(r'            page = browser.new_page(viewport={"width": 1400, "height": 950})');
    sb.writeln(r'            page.goto("https://pselectro.ru/calculate-cost/", timeout=60000, wait_until="domcontentloaded")');
    sb.writeln(r'            page.wait_for_timeout(3000)');
    sb.writeln(r'            ctxs = [page] + list(page.frames)');
    sb.writeln(r'            for c in ctxs:');
    sb.writeln(r'                select_or_click(c, ["Принять", "Согласен"])');
    sb.writeln(r'                if LAYERS == "1": select_or_click(c, ["1 слой", "Односторонн"])');
    sb.writeln(r'                elif LAYERS == "2": select_or_click(c, ["2 слоя", "Двухсторонн", "Двусторонн"])');
    sb.writeln(r'                else: select_or_click(c, [LAYERS + " сло"])');
    sb.writeln(r'                fill_ctx(c, ["длина", "width", "x,", "размер x"], WIDTH)');
    sb.writeln(r'                fill_ctx(c, ["ширина", "height", "y,", "размер y"], HEIGHT)');
    sb.writeln(r'                fill_ctx(c, ["количество", "тираж", "qty", "шт"], QTY)');
    sb.writeln(r'                select_or_click(c, [THICKNESS + " мм", THICKNESS])');
    sb.writeln(r'                if ORDER_TYPE == "Повтор": select_or_click(c, ["Повтор"])');
    sb.writeln(r'                if MASK_SIDE == "Без маски": select_or_click(c, ["Без маски"])');
    sb.writeln(r'                if "золото" in FINISH.lower(): select_or_click(c, ["Иммерсионное золото", "Иммерс", "ENIG"])');
    sb.writeln(r'                elif "олово" in FINISH.lower(): select_or_click(c, ["Иммерсионное олово"])');
    sb.writeln(r'            page.wait_for_timeout(1500)');
    sb.writeln(r'            for c in ctxs: select_or_click(c, ["Рассчитать", "Посчитать"])');
    sb.writeln(r'            page.wait_for_timeout(4000)');
    sb.writeln(r'            txt = ""');
    sb.writeln(r'            for c in [page] + list(page.frames):');
    sb.writeln(r'                try:');
    sb.writeln(r'                    txt += "\n" + c.locator("body").inner_text()');
    sb.writeln(r'                    for inp in c.locator("input").all():');
    sb.writeln(r'                        v = inp.input_value()');
    sb.writeln(r'                        if v: txt += "\nVAL: " + v');
    sb.writeln(r'                except Exception: pass');
    sb.writeln(r'            found = []');
    sb.writeln(r'            for m in re.findall(r"(?:итого|стоимость|сумма|цена|всего)[^\d\n]{0,35}(\d[\d\s]{1,12}(?:[.,]\d{1,2})?)", txt, flags=re.I):');
    sb.writeln(r'                cl = re.sub(r"\s+", " ", m).strip()');
    sb.writeln(r'                try:');
    sb.writeln(r'                    v = float(re.sub(r"[^\d.,]", "", cl).replace(",", "."))');
    sb.writeln(r'                    if v >= 200.0: found.append((v, cl))');
    sb.writeln(r'                except Exception: pass');
    sb.writeln(r'            for m in re.findall(r"(\d[\d\s]{1,12}(?:[.,]\d{1,2})?)\s*(?:руб\.?|р\.|₽)", txt, flags=re.I):');
    sb.writeln(r'                cl = re.sub(r"\s+", " ", m).strip()');
    sb.writeln(r'                try:');
    sb.writeln(r'                    v = float(re.sub(r"[^\d.,]", "", cl).replace(",", "."))');
    sb.writeln(r'                    if v >= 200.0: found.append((v, cl))');
    sb.writeln(r'                except Exception: pass');
    sb.writeln(r'            if found:');
    sb.writeln(r'                found.sort(key=lambda x: x[0])');
    sb.writeln(r'                res["ok"] = True');
    sb.writeln(r'                res["price"] = found[-1][1] + " руб."');
    sb.writeln(r'                res["raw"] = "Считано со страницы pselectro.ru"');
    sb.writeln(r'            else:');
    sb.writeln(r'                res["error"] = "Сайт не вернул цифру итога (возможно, расчёт по этой плате идёт через заявку менеджеру)."');
    sb.writeln(r'            page.wait_for_timeout(3000)');
    sb.writeln(r'            browser.close()');
    sb.writeln(r'    except Exception as e:');
    sb.writeln(r'        res["error"] = str(e)');
    sb.writeln(r'    open(OUT_JSON, "w", encoding="utf-8").write(json.dumps(res, ensure_ascii=False))');
    sb.writeln(r'if __name__ == "__main__": main()');
    return sb.toString();
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
      _webPriceDetails = 'Открываю pselectro.ru/calculate-cost/ и заполняю форму...';
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
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
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

  Future<String> _saveTempBytes(Directory dir, String rawFileName, List<int> fileBytes) async {
    final safeName = rawFileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final outFile = File('${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
    await outFile.writeAsBytes(fileBytes);
    return outFile.path;
  }

  Future<void> _pickAndAnalyzeZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'rar'],
    );
    if (result == null || result.files.single.path == null) return;

    final selectedFile = File(result.files.single.path!);
    final archiveName = selectedFile.path.split(Platform.pathSeparator).last;
    final archiveDir = selectedFile.parent.path;

    try {
      final tempRoot = await getTemporaryDirectory();
      final sessionUnpackDir = Directory('${tempRoot.path}${Platform.pathSeparator}cam_session_${DateTime.now().millisecondsSinceEpoch}');
      sessionUnpackDir.createSync(recursive: true);

      final List<dynamic> projectFiles = [];
      bool hasUnpackedNestedArchive = false;

      if (selectedFile.path.toLowerCase().endsWith('.rar')) {
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
          final fileBytes = file.content as List<int>;

          if (low.endsWith('.zip')) {
            try {
              final innerArchive = ZipDecoder().decodeBytes(fileBytes);
              for (final inner in innerArchive.files) {
                if (!inner.isFile) continue;
                final innerName = inner.name.split('/').last.split('\\').last;
                if (innerName.isNotEmpty) {
                  final iBytes = inner.content as List<int>;
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
            final nestedOutDir = Directory('${sessionUnpackDir.path}${Platform.pathSeparator}unpacked_${DateTime.now().millisecondsSinceEpoch}');
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

      final List<GerberLayerInfo> layers = [];
      int copperLayers = 0;
      bool hasTopMask = false;
      bool hasBottomMask = false;
      bool hasTopSilk = false;
      bool hasBottomSilk = false;
      bool hasBinaryBrd = false;
      bool hasCadSourceOnly = false;
      bool hasTextContour = false;
      String? foundExcelPath;

      double? detectedWidth;
      double? detectedHeight;
      double? fallbackCopperWidth;
      double? fallbackCopperHeight;
      double? minTrackMm;
      double? minDrillMm;
      int totalHoles = 0;
      final Map<double, int> drillBreakdown = {};

      for (final item in projectFiles) {
        final pf = item as Map<String, dynamic>;
        final rawName = pf['name'] as String;
        final fileBytes = pf['bytes'] as List<int>;
        final savedPath = pf['savedPath'] as String;
        final upper = rawName.toUpperCase();
        String role = 'Прочий файл проекта';
        bool importantDoc = false;

        if (upper.endsWith('.RAR') || upper.endsWith('.7Z')) {
          role = 'Нераспакованный RAR (установите WinRAR/7-Zip)';
        } else if (upper.endsWith('.XLS') || upper.endsWith('.XLSX')) {
          role = 'Бланк заказа / спецификация (читается автоматически)';
          importantDoc = true;
          foundExcelPath ??= savedPath;
        } else if (upper.endsWith('.PNG') || upper.endsWith('.JPG') || upper.endsWith('.JPEG') || upper.endsWith('.PDF')) {
          role = 'Чертёж / стек слоёв / ламели (кликните для просмотра)';
          importantDoc = true;
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
            upper.endsWith('.TXT') ||
            upper.endsWith('.EXC') ||
            upper.endsWith('.TAP') ||
            upper.contains('DRILL')) {
          role = 'Сверловка (Excellon)';
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
        if (!isLikelyBinary) {
          final textContent = utf8.decode(fileBytes, allowMalformed: true);
          if (role.contains('Сверловка')) {
            final drillStats = _parseExcellonDrill(textContent);
            totalHoles += drillStats['totalHoles'] as int;
            final tools = drillStats['tools'] as Map<double, int>;
            for (final entry in tools.entries) {
              drillBreakdown[entry.key] = (drillBreakdown[entry.key] ?? 0) + entry.value;
              if (minDrillMm == null || entry.key < minDrillMm) minDrillMm = entry.key;
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
          }
        }
      }

      detectedWidth ??= fallbackCopperWidth;
      detectedHeight ??= fallbackCopperHeight;

      Map<String, dynamic>? blankData;
      if (foundExcelPath != null) {
        final rawBlank = await _parseElectroconnectExcelBlank(foundExcelPath);
        if (rawBlank is Map<String, dynamic>) {
          blankData = rawBlank;
        }
      }

      if (blankData != null) {
        if (detectedWidth == null && blankData['width'] != null) {
          detectedWidth = (blankData['width'] as num).toDouble();
        }
        if (detectedHeight == null && blankData['height'] != null) {
          detectedHeight = (blankData['height'] as num).toDouble();
        }
      }

      final int finalLayersCount = (blankData != null && blankData['layers'] != null)
          ? (blankData['layers'] as num).toInt()
          : (copperLayers > 0 ? copperLayers : 2);

      final projectTitle = archiveName.replaceAll(RegExp(r'\.(zip|rar)$', caseSensitive: false), '');

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
        hasCadSourceOnly: hasCadSourceOnly && copperLayers == 0,
        hasNestedArchive: hasUnpackedNestedArchive,
        parsedFromOrderBlank: blankData != null,
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
            : ((hasTopMask || hasBottomMask) ? 'С одной стороны' : 'Без маски');
        _silkSide = (hasTopSilk && hasBottomSilk)
            ? 'С двух сторон'
            : ((hasTopSilk || hasBottomSilk) ? 'С одной стороны' : 'Без маркировки');

        if (blankData != null) {
          if (blankData['customer'] != null && blankData['customer'].toString().isNotEmpty) {
            _customerController.text = blankData['customer'].toString();
          }
          if (blankData['order_type'] != null) {
            _orderType = blankData['order_type'].toString();
          }
          if (blankData['qty'] != null) {
            _qtyController.text = blankData['qty'].toString();
          }
          if (blankData['material'] != null) {
            _material = blankData['material'].toString();
          }
          if (blankData['thickness'] != null) {
            const validThick = ['0.5', '0.8', '1.0', '1.5', '2.0', '2.5', '3.0'];
            final tStr = blankData['thickness'].toString();
            if (validThick.contains(tStr)) _thickness = tStr;
          }
          if (blankData['foil'] != null) {
            const validFoil = ['12', '18', '35', '50', '70', '105'];
            final fStr = blankData['foil'].toString();
            if (validFoil.contains(fStr)) _foil = fStr;
          }
          if (blankData['mask_side'] != null) {
            final ms = blankData['mask_side'].toString().toLowerCase();
            if (ms.contains('двух')) {
              _maskSide = 'С двух сторон';
            } else if (ms.contains('одной')) {
              _maskSide = 'С одной стороны';
            } else if (ms.contains('без')) {
              _maskSide = 'Без маски';
            }
          }
          if (blankData['silk_side'] != null) {
            final ss = blankData['silk_side'].toString().toLowerCase();
            if (ss.contains('двух')) {
              _silkSide = 'С двух сторон';
            } else if (ss.contains('одной')) {
              _silkSide = 'С одной стороны';
            } else if (ss.contains('без')) {
              _silkSide = 'Без маркировки';
            }
          }
          if (blankData['finish'] != null) {
            final fin = blankData['finish'].toString().toLowerCase();
            if (fin.contains('иммерс') || fin.contains('золот') || fin.contains('enig')) {
              _finish = 'Иммерсионное золото';
            } else if (fin.contains('олов')) {
              _finish = 'Иммерсионное олово';
            } else if (fin.contains('без')) {
              _finish = 'Без покрытия';
            } else {
              _finish = 'HAL';
            }
          }
          if (blankData['contour'] != null) {
            final cnt = blankData['contour'].toString().toLowerCase();
            if (cnt.contains('скрайб')) _contour = 'скрайбирование';
          }
          if (blankData['electro_test'] != null) {
            _electroTest = blankData['electro_test'] == true;
          }
          if (blankData['notes'] is List && (blankData['notes'] as List).isNotEmpty) {
            _notesController.text = (blankData['notes'] as List).join('; ');
          }
        }

        _recalculateTariffFromSpecs(force: true);
      });

      if (blankData != null) {
        _showSnack('Данные автоматически загружены из бланка заказа Excel (.XLS)!');
      } else if (hasUnpackedNestedArchive) {
        _showSnack('Не удалось распаковать вложенный .RAR — укажите X и Y вручную.');
      } else if (detectedWidth == null) {
        _showSnack('Архив загружен, но контур не распознан — введите X и Y вручную для расчёта цены.');
      } else {
        _showSnack('Проект $archiveName проанализирован и рассчитан!');
      }
    } catch (e) {
      _showSnack('Ошибка чтения архива: $e');
    }
  }

  Map<String, dynamic> _parseExcellonDrill(String text) {
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
        final diam = toolDiameters[activeTool]!;
        toolCounts[diam] = (toolCounts[diam] ?? 0) + 1;
        total++;
      }
    }
    return {'totalHoles': total, 'tools': toolCounts};
  }

  Map<String, double?> _parseGerberGeometry(String text) {
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
    } else {
      checks.add(DfmCheckItem(
        title: 'Не заданы габариты платы (X × Y = 0)',
        detail: 'Укажите длину X и ширину Y в мм слева (или откройте бланк .XLS / стек в блоке 3 ниже).',
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
    sb.writeln('РАСЧЕТ СТОИМОСТИ:');
    if (_webPriceResult != null) {
      sb.writeln('• Расчет с сайта pselectro.ru: $_webPriceResult');
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
    final priceLine = _webPriceResult != null
        ? '• Стоимость партии по калькулятору сайта: $_webPriceResult'
        : '• Предварительная стоимость партии с учетом НДС 22%: ${totalWithVat.toStringAsFixed(2)} руб.';

    final text = 'Здравствуйте!\n'
        'Благодарим за обращение на завод «ЭЛЕКТРОконнект».\n\n'
        'По результатам проверки производственных файлов проекта «$title» ($qty шт., общая площадь партии: ${totalDm2.toStringAsFixed(2)} дм²):\n'
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
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPriceField = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {
        if (isPriceField) _manualPriceOverride = true;
      }),
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
    final hasValidDimensions = w > 0 && h > 0;
    final singleAreaDm2 = hasValidDimensions ? (w * h) / 10000.0 : 0.0;
    final totalAreaDm2 = singleAreaDm2 * math.max(qty, 1);

    final baseP = double.tryParse(_basePriceDm2Controller.text.replaceAll(',', '.')) ?? 528.0;
    final setupP = double.tryParse(_setupFeeController.text.replaceAll(',', '.')) ?? 2400.0;
    final pureSum = hasValidDimensions ? ((totalAreaDm2 * baseP) + setupP) : 0.0;
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
                Text('Автопарсинг бланков XLS, Gerber, RAR, ZIP, PCB • Расчет цены и ТЗ', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                              _analysis != null ? 'Проект: ${_analysis!.archiveName}' : 'Загрузите архив с файлами платы (.zip / .rar)',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _analysis != null
                                  ? 'Найдено файлов: ${_analysis!.layers.length} • Отверстий: ${_analysis!.totalHoles} • Папка: ${_analysis!.archiveDir}'
                                  : 'Автоматически читает бланки заказов Excel (.XLS/.XLSX), Gerber, P-CAD и вложенные .RAR',
                              style: TextStyle(fontSize: 12.5, color: _subtleText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('НОВЫЙ ПРОЕКТ'),
                        onPressed: _clearCurrentProject,
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.upload_file_rounded, size: 20),
                        label: const Text('ВЫБРАТЬ АРХИВ', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Тип заказа',
                                    value: _orderType,
                                    items: const ['Новый', 'Повтор'],
                                    onChanged: (v) => setState(() {
                                      _orderType = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
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
                                Expanded(child: _inputField(controller: _basePriceDm2Controller, label: 'Цена за 1 дм², руб.', keyboardType: TextInputType.number, isPriceField: true)),
                                const SizedBox(width: 10),
                                Expanded(child: _inputField(controller: _setupFeeController, label: 'Подготовка, руб.', keyboardType: TextInputType.number, isPriceField: true)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: (hasValidDimensions ? const Color(0xFF0284C7) : Colors.amberAccent).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: (hasValidDimensions ? const Color(0xFF0284C7) : Colors.amberAccent).withOpacity(0.35)),
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
                                      Text(
                                        hasValidDimensions ? 'Локальный расчёт с НДС (22%):' : 'Укажите длину X и ширину Y для расчёта цены:',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _subtleText),
                                      ),
                                      Text(
                                        hasValidDimensions ? '${totalSumWithVat.toStringAsFixed(2)} руб.' : '0.00 руб.',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: hasValidDimensions ? const Color(0xFF0284C7) : Colors.amberAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_webPriceResult != null || _webPriceDetails != null) ...[
                                    const Divider(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Цена напрямую с сайта pselectro.ru:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                        Text(
                                          _webPriceResult ?? '...',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                        ),
                                      ],
                                    ),
                                    if (_webPriceDetails != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(_webPriceDetails!, style: TextStyle(fontSize: 11.5, color: _subtleText)),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Слои',
                                    value: '$_layersCount',
                                    items: const ['1', '2', '4', '6', '8', '10', '12', '16'],
                                    onChanged: (v) => setState(() {
                                      _layersCount = int.parse(v!);
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Материал',
                                    value: _material,
                                    items: const ['FR4', 'Алюминий', 'Rogers'],
                                    onChanged: (v) => setState(() {
                                      _material = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownField(label: 'Толщина, мм', value: _thickness, items: const ['0.5', '0.8', '1.0', '1.5', '2.0', '2.5', '3.0'], onChanged: (v) => setState(() => _thickness = v!))),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Фольга, мкм',
                                    value: _foil,
                                    items: const ['12', '18', '35', '50', '70', '105'],
                                    onChanged: (v) => setState(() {
                                      _foil = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Маска',
                                    value: _maskSide,
                                    items: const ['С двух сторон', 'С одной стороны', 'Без маски'],
                                    onChanged: (v) => setState(() {
                                      _maskSide = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Цвет маски',
                                    value: _maskColor,
                                    items: const ['Зеленая', 'Синяя', 'Черная', 'Белая', 'Красная'],
                                    onChanged: (v) => setState(() {
                                      _maskColor = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _dropdownField(
                                    label: 'Покрытие',
                                    value: _finish,
                                    items: const ['HAL', 'Иммерсионное золото', 'Иммерсионное олово', 'Без покрытия'],
                                    onChanged: (v) => setState(() {
                                      _finish = v!;
                                      _recalculateTariffFromSpecs();
                                    }),
                                  ),
                                ),
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
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                                  icon: _isFetchingWebPrice
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.cloud_download_outlined, size: 16),
                                  label: Text(_isFetchingWebPrice ? 'Считаю на сайте...' : 'Запросить цену с сайта'),
                                  onPressed: _isFetchingWebPrice ? null : _fetchPriceFromWebsite,
                                ),
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
                                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                  label: const Text('Открыть сайт вручную'),
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
                                if (_analysis?.parsedFromOrderBlank == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.45)),
                                    ),
                                    child: const Text(
                                      'Параметры (заказчик, размеры X/Y, тираж, слои, толщина, покрытие и примечания) автоматически считаны из бланка заказа Excel!',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                if (_analysis?.hasNestedArchive == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.redAccent.withOpacity(0.45)),
                                    ),
                                    child: const Text(
                                      'Внутри обнаружен .RAR, а WinRAR / 7-Zip не найдены в стандартных папках Program Files — распакуйте его вручную или укажите X/Y слева.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                if (_analysis?.hasCadSourceOnly == true && _analysis?.parsedFromOrderBlank != true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.45)),
                                    ),
                                    child: const Text(
                                      'В архиве исходник платы (.PCB/.LAY) без Gerber-слоёв. Нажмите на бланк .XLS или чертёж стека в списке ниже, чтобы открыть их и посмотреть размеры X/Y.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
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
                                              Text(chk.detail, style: TextStyle(fontSize: 12.5, color: _subtleText)),
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
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('3. Состав архива (${_analysis!.totalHoles} отв.)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      Text('Клик по файлу — открыть', style: TextStyle(fontSize: 11, color: _subtleText)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ..._analysis!.layers.map((l) => InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => _openExtractedFile(l.extractedPath, l.fileName),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: l.isImportantDoc ? accent.withOpacity(0.08) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                l.isImportantDoc ? Icons.open_in_new_rounded : Icons.insert_drive_file_outlined,
                                                size: 15,
                                                color: l.isImportantDoc ? const Color(0xFF38BDF8) : accent,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  l.fileName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: l.isImportantDoc ? const Color(0xFF38BDF8) : null,
                                                  ),
                                                ),
                                              ),
                                              Text(l.role, style: TextStyle(fontSize: 11, color: _subtleText)),
                                            ],
                                          ),
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
