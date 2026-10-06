import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'package:permission_handler/permission_handler.dart';
import 'report_data_service.dart';
import '../models/activity_log_model.dart';

class ReportExportService {

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  Future<Directory> _downloadsDir() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final dir = Directory.systemTemp;
    return dir;
  }

  String _timestampedName(String base, String ext) {
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2,'0')}'
        '${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}'
        '${now.minute.toString().padLeft(2,'0')}';
    return '${base}_$stamp.$ext';
  }

  Future<String> exportPdf(ReportSnapshot snapshot) async {
    final granted = await _ensureStoragePermission();
    if (!granted) {
      throw Exception('Storage permission denied. Cannot save PDF to Downloads.');
    }
    final doc = pw.Document();
    const blue   = PdfColor.fromInt(0xFF667EEA);
    const dark   = PdfColor.fromInt(0xFF1A1F36);
    const grey   = PdfColor.fromInt(0xFF888888);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: blue, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('FabricFlow ERP — Business Report',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: dark)),
              pw.Text(_formatDate(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 10, color: grey)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: grey)),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.SizedBox(height: 8),
          _pdfKpiTable(snapshot, dark),
          pw.SizedBox(height: 20),
          pw.Text('Sales by Status', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.SizedBox(height: 8),
          _pdfStatusTable(snapshot, dark),
          pw.SizedBox(height: 20),
          pw.Text('Top Selling Products', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.SizedBox(height: 8),
          _pdfTopProductsTable(snapshot, dark),
          pw.SizedBox(height: 20),
          pw.Text('Monthly Performance', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.SizedBox(height: 8),
          _pdfMonthlyTable(snapshot, dark),
          pw.SizedBox(height: 20),
          pw.Text('Inventory — Low Stock Alerts', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.SizedBox(height: 8),
          _pdfLowStockTable(snapshot, dark),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir   = await _downloadsDir();
    final name  = _timestampedName('FabricFlow_Report', 'pdf');
    final file  = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  pw.Widget _pdfKpiTable(ReportSnapshot s, PdfColor dark) {
    final rows = [
      ['Total Revenue', 'Rs. ${s.totalRevenue.toStringAsFixed(0)}'],
      ['Total Orders', '${s.totalOrders}'],
      ['Total Products', '${s.totalProducts}'],
      ['Low Stock Items', '${s.lowStockCount}'],
      ['Out of Stock Items', '${s.outOfStockCount}'],
      ['Average Order Value', 'Rs. ${s.averageOrderValue.toStringAsFixed(0)}'],
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
      columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
      children: rows.map((r) => pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r[0], style: pw.TextStyle(color: dark, fontSize: 10))),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r[1], style: pw.TextStyle(color: dark, fontSize: 10, fontWeight: pw.FontWeight.bold))),
      ])).toList(),
    );
  }

  pw.Widget _pdfStatusTable(ReportSnapshot s, PdfColor dark) {
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
          children: ['Status', 'Count', 'Revenue'].map((h) =>
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList(),
        ),
        ...s.statusBreakdown.entries.map((e) => pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.key, style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e.value.count}', style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${e.value.revenue.toStringAsFixed(0)}', style: pw.TextStyle(color: dark, fontSize: 10))),
        ])),
      ],
    );
  }

  pw.Widget _pdfTopProductsTable(ReportSnapshot s, PdfColor dark) {
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
          children: ['Rank', 'Product', 'Units Sold', 'Revenue'].map((h) =>
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList(),
        ),
        ...s.topProducts.asMap().entries.map((e) => pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#${e.key + 1}', style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.value.name, style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e.value.unitsSold}', style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${e.value.revenue.toStringAsFixed(0)}', style: pw.TextStyle(color: dark, fontSize: 10))),
        ])),
      ],
    );
  }

  pw.Widget _pdfMonthlyTable(ReportSnapshot s, PdfColor dark) {
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
          children: ['Month', 'Orders', 'Revenue'].map((h) =>
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList(),
        ),
        ...s.monthlyPerformance.map((m) => pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m.label, style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${m.orderCount}', style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${m.revenue.toStringAsFixed(0)}', style: pw.TextStyle(color: dark, fontSize: 10))),
        ])),
      ],
    );
  }

  pw.Widget _pdfLowStockTable(ReportSnapshot s, PdfColor dark) {
    if (s.lowStockProducts.isEmpty) {
      return pw.Text('No low-stock items — inventory is healthy.',
          style: pw.TextStyle(color: dark, fontSize: 10, fontStyle: pw.FontStyle.italic));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F0F0)),
          children: ['Tag', 'Product', 'Stock', 'Category'].map((h) =>
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList(),
        ),
        ...s.lowStockProducts.map((p) => pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.tagNumber, style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.name, style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${p.stock}', style: pw.TextStyle(color: dark, fontSize: 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.category, style: pw.TextStyle(color: dark, fontSize: 10))),
        ])),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

  Future<String> exportExcel(ReportSnapshot snapshot) async {
    final granted = await _ensureStoragePermission();
    if (!granted) {
      throw Exception('Storage permission denied. Cannot save Excel file to Downloads.');
    }

    final workbook = Excel.createExcel();

    final summary = workbook['Summary'];
    workbook.setDefaultSheet('Summary');
    summary.appendRow([TextCellValue('FabricFlow ERP — Business Report')]);
    summary.appendRow([TextCellValue('Generated'), TextCellValue(_formatDate(DateTime.now()))]);
    summary.appendRow([]);
    summary.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
    summary.appendRow([TextCellValue('Total Revenue'), DoubleCellValue(snapshot.totalRevenue)]);
    summary.appendRow([TextCellValue('Total Orders'), IntCellValue(snapshot.totalOrders)]);
    summary.appendRow([TextCellValue('Total Products'), IntCellValue(snapshot.totalProducts)]);
    summary.appendRow([TextCellValue('Low Stock Items'), IntCellValue(snapshot.lowStockCount)]);
    summary.appendRow([TextCellValue('Out of Stock Items'), IntCellValue(snapshot.outOfStockCount)]);
    summary.appendRow([TextCellValue('Average Order Value'), DoubleCellValue(snapshot.averageOrderValue)]);

    final salesSheet = workbook['Sales by Status'];
    salesSheet.appendRow([TextCellValue('Status'), TextCellValue('Count'), TextCellValue('Revenue')]);
    for (final e in snapshot.statusBreakdown.entries) {
      salesSheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value.count),
        DoubleCellValue(e.value.revenue),
      ]);
    }

    final topSheet = workbook['Top Products'];
    topSheet.appendRow([TextCellValue('Rank'), TextCellValue('Product'), TextCellValue('Units Sold'), TextCellValue('Revenue')]);
    for (var i = 0; i < snapshot.topProducts.length; i++) {
      final p = snapshot.topProducts[i];
      topSheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(p.name),
        IntCellValue(p.unitsSold),
        DoubleCellValue(p.revenue),
      ]);
    }

    final monthlySheet = workbook['Monthly Performance'];
    monthlySheet.appendRow([TextCellValue('Month'), TextCellValue('Orders'), TextCellValue('Revenue')]);
    for (final m in snapshot.monthlyPerformance) {
      monthlySheet.appendRow([
        TextCellValue(m.label),
        IntCellValue(m.orderCount),
        DoubleCellValue(m.revenue),
      ]);
    }

    final invSheet = workbook['Inventory'];
    invSheet.appendRow([
      TextCellValue('Tag Number'), TextCellValue('Name'), TextCellValue('Category'),
      TextCellValue('Price'), TextCellValue('Stock'), TextCellValue('Warehouse'),
    ]);
    for (final p in snapshot.allProducts) {
      invSheet.appendRow([
        TextCellValue(p.tagNumber),
        TextCellValue(p.name),
        TextCellValue(p.category),
        DoubleCellValue(p.price),
        IntCellValue(p.stock),
        TextCellValue(p.warehouse),
      ]);
    }

    if (workbook.sheets.containsKey('Sheet1')) {
      workbook.delete('Sheet1');
    }

    final bytes = workbook.save();
    if (bytes == null) throw Exception('Failed to encode Excel workbook.');

    final dir  = await _downloadsDir();
    final name = _timestampedName('FabricFlow_Report', 'xlsx');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }
  // ── CSV field escaping (RFC 4180) ─────────────────────────────────────────
  // Wraps a value in double quotes and doubles any literal quote character
  // inside it. This is the rule the previous version of this method missed:
  // replacing commas alone is not sufficient — a username or detail value
  // containing a literal " (e.g. an employee named John "JD" Doe, or a
  // product update detail quoting an old name) would otherwise produce a
  // malformed row that breaks column alignment for every field after it.
  String _csvField(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  // ── CSV EXPORT (Activity Log) ─────────────────────────────────────────────
Future<String> exportActivityLogCsv(List<ActivityLogModel> logs) async {
  final granted = await _ensureStoragePermission();
  if (!granted) {
    throw Exception('Storage permission denied. Cannot save CSV to Downloads.');
  }

  final buffer = StringBuffer();
  // Header row
  buffer.writeln('Timestamp,Username,User ID,Action,Entity,Record ID,Details');

  for (final log in logs) {
    final details = log.details.entries
        .map((e) => '${e.key}=${e.value}')
        .join(' | ');
    buffer.writeln([
      _csvField(_formatDate(log.timestamp)),
      _csvField(log.username),
      _csvField(log.userId),
      _csvField(log.action.value),
      _csvField(log.entity.value),
      _csvField(log.recordId),
      _csvField(details),
    ].join(','));
  }

  final dir  = await _downloadsDir();
  final name = _timestampedName('FabricFlow_ActivityLog', 'csv');
      final file = File('${dir.path}/$name');
    await file.writeAsString(buffer.toString());
    return file.path;
  }
}