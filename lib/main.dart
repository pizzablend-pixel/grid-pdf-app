import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const GridPdfApp());
}

class GridPdfApp extends StatelessWidget {
  const GridPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grid 3x3 PDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.gridpdf/share');
  final List<File> _images = [];
  bool _isGenerating = false;
  bool _cropSquare = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSharedImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Otomatis cek kiriman foto baru saat aplikasi kembali dibuka dari WA
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSharedImages();
    }
  }

  Future<void> _checkSharedImages() async {
    try {
      final List<dynamic>? sharedPaths =
          await platform.invokeMethod<List<dynamic>>('getSharedImages');
      if (sharedPaths != null && sharedPaths.isNotEmpty) {
        setState(() {
          _images.clear();
          for (var p in sharedPaths) {
            if (p is String && p.isNotEmpty) {
              _images.add(File(p));
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error membaca share intent: $e");
    }
  }

  Future<void> _pickImagesManually() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() {
        _images.addAll(picked.map((x) => File(x.path)));
      });
    }
  }

  Future<void> _generateAndSharePdf() async {
    if (_images.isEmpty) return;

    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();
      const int itemsPerPage = 9;
      final int totalPages = (_images.length / itemsPerPage).ceil();

      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final int startIndex = pageIndex * itemsPerPage;
        final int endIndex = (startIndex + itemsPerPage > _images.length)
            ? _images.length
            : startIndex + itemsPerPage;

        final List<File> pageImages = _images.sublist(startIndex, endIndex);

        final List<pw.MemoryImage> pdfImages = [];
        for (var imgFile in pageImages) {
          final bytes = await imgFile.readAsBytes();
          pdfImages.add(pw.MemoryImage(bytes));
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.Column(
                children: List.generate(3, (rowIndex) {
                  return pw.Expanded(
                    child: pw.Row(
                      children: List.generate(3, (colIndex) {
                        final int itemIndex = rowIndex * 3 + colIndex;
                        if (itemIndex < pdfImages.length) {
                          return pw.Expanded(
                            child: pw.Container(
                              margin: const pw.EdgeInsets.all(4),
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(
                                  color: PdfColors.grey400,
                                  width: 0.5,
                                ),
                              ),
                              child: pw.Image(
                                pdfImages[itemIndex],
                                fit: _cropSquare
                                    ? pw.BoxFit.cover
                                    : pw.BoxFit.contain,
                              ),
                            ),
                          );
                        } else {
                          return pw.Expanded(
                            child: pw.Container(
                              margin: const pw.EdgeInsets.all(4),
                            ),
                          );
                        }
                      }),
                    ),
                  );
                }),
              );
            },
          ),
        );
      }

      final outputDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File pdfFile = File(
          "${outputDir.path}/Grid_3x3_${_images.length}_Foto_$timestamp.pdf");
      await pdfFile.writeAsBytes(await pdf.save());

      setState(() => _isGenerating = false);

      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        text: 'PDF Grid 3x3 (${_images.length} Foto - $totalPages Halaman)',
      );
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int pageCount = (_images.length / 9).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grid 3x3 PDF Maker'),
        actions: [
          if (_images.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Bersihkan Semua',
              onPressed: () => setState(() => _images.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.teal.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_images.length} Foto ($pageCount Hal A4)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    const Text('Penuh Kotak (Crop)'),
                    Switch(
                      value: _cropSquare,
                      onChanged: (val) => setState(() => _cropSquare = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _images.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.collections_outlined,
                              size: 72, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada foto.\n\nPilih banyak foto di WhatsApp lalu klik "Bagikan" -> pilih "Grid 3x3 PDF", atau klik tombol di bawah.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _pickImagesManually,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('Pilih Foto dari Galeri'),
                          ),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.file(
                              _images[index],
                              fit: _cropSquare ? BoxFit.cover : BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${index + 1} (Hal ${(index ~/ 9) + 1})',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _images.removeAt(index)),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.red,
                                child: Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _images.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _pickImagesManually,
                      icon: const Icon(Icons.add_a_photo),
                      tooltip: 'Tambah Foto Lagi',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _isGenerating ? null : _generateAndSharePdf,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(_isGenerating
                            ? 'Menyusun PDF...'
                            : 'Buat PDF & Kirim ke WA'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
