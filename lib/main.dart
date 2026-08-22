import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soi Vé Số Ảnh Tĩnh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const ImageScannerScreen(),
    );
  }
}

class ImageScannerScreen extends StatefulWidget {
  const ImageScannerScreen({super.key});

  @override
  State<ImageScannerScreen> createState() => _ImageScannerScreenState();
}

class _ImageScannerScreenState extends State<ImageScannerScreen> {
  File? _selectedImage;
  Size? _imageSize;
  List<MatchedResult> _matchedResults = [];
  List<String> _winningNumbers = [];
  bool _isProcessing = false;
  String _statusText = "Đang tải dữ liệu KQXS MinhChinh.com...";

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _fetchMinhChinhXSMN();
  }

  Future<void> _fetchMinhChinhXSMN() async {
    List<String> numbers = [
      "22", "55", "11", "10", "414", "884", "242", "337",
      "5681", "4809", "3063", "8431", "9970", "3368", "9212", "6731", "1953", "8599", "8848", "6015",
      "4478", "6947", "7955", "6107", "87601", "40205", "16122", "83417", "47612", "49104", "81537",
      "35597", "42245", "33081", "96929", "52774", "83126", "96834", "25917", "48661", "18888", "59389",
      "06303", "63080", "00713", "31872", "28812", "57726", "64245", "32760", "25729", "24903",
      "31471", "78879", "34249", "93143", "93750", "33159", "27551", "97079",
      "97663", "27858", "89704", "75645", "68795", "95423", "83847", "63916",
      "296215", "474160", "094423", "617750"
    ];

    try {
      final url = Uri.parse('https://www.minhchinh.com/truc-tiep-xo-so-mien-nam.html');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        var elements = document.querySelectorAll('td, div, span');
        List<String> parsed = [];
        for (var el in elements) {
          String text = el.text.trim();
          RegExp exp = RegExp(r'\b\d{1,6}\b');
          for (var m in exp.allMatches(text)) {
            parsed.add(m.group(0)!);
          }
        }
        if (parsed.length >= 10) numbers = parsed;
      }
    } catch (_) {}

    setState(() {
      _winningNumbers = numbers.toSet().toList();
      _statusText = "Sẵn sàng! Hãy chọn hình ảnh tập vé số để bắt đầu dò.";
    });
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    File imageFile = File(image.path);
    
    // Lấy kích thước thực của bức ảnh
    var decodedImage = await decodeImageFromList(imageFile.readAsBytesSync());

    setState(() {
      _selectedImage = imageFile;
      _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
      _isProcessing = true;
      _statusText = "Đang quét và lọc dữ liệu trên hình ảnh...";
    });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      List<MatchedResult> hits = [];
      RegExp numExp = RegExp(r'\d{1,6}');

      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          for (var element in line.elements) {
            String rawText = element.text;
            Iterable<RegExpMatch> matches = numExp.allMatches(rawText);

            for (var m in matches) {
              String number = m.group(0)!;
              
              // Điều kiện: Trúng bất kỳ số nào trong danh sách KQXS
              if (_checkMatchAny(number)) {
                hits.add(MatchedResult(
                  rect: element.boundingBox,
                  number: number,
                ));
              }
            }
          }
        }
      }

      setState(() {
        _matchedResults = hits;
        _statusText = hits.isNotEmpty
            ? "Tìm thấy ${hits.length} dãy số trùng khớp! Đã tô vàng trên ảnh."
            : "Không tìm thấy dãy số phù hợp trên hình ảnh.";
      });
    } catch (e) {
      setState(() {
        _statusText = "Lỗi xử lý hình ảnh. Vui lòng thử lại!";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  bool _checkMatchAny(String number) {
    if (_winningNumbers.contains(number)) return true;
    for (int i = 0; i < number.length; i++) {
      for (int j = i + 1; j <= number.length; j++) {
        String sub = number.substring(i, j);
        if (_winningNumbers.contains(sub)) return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dò Vé Số Bằng Hình Ảnh"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _selectedImage == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.image_search, size: 80, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Chưa chọn hình ảnh nào", style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_selectedImage!, fit: BoxFit.contain),
                      if (_selectedImage != null && _imageSize != null)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return CustomPaint(
                              painter: ImageOverlayPainter(
                                results: _matchedResults,
                                imageSize: _imageSize!,
                                containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                              ),
                            );
                          },
                        ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.deepOrange),
                          ),
                        ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusText,
                  style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickAndProcessImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text("CHỌN TỪ THƯ VIỆN"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickAndProcessImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("CHỤP ẢNH MỚI"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchedResult {
  final Rect rect;
  final String number;
  MatchedResult({required this.rect, required this.number});
}

class ImageOverlayPainter extends CustomPainter {
  final List<MatchedResult> results;
  final Size imageSize;
  final Size containerSize;

  ImageOverlayPainter({
    required this.results,
    required this.imageSize,
    required this.containerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Tính toán tỷ lệ hiển thị ảnh BoxFit.contain trên màn hình
    double scale = 1.0;
    double offsetX = 0.0;
    double offsetY = 0.0;

    double imgAspect = imageSize.width / imageSize.height;
    double containerAspect = containerSize.width / containerSize.height;

    if (containerAspect > imgAspect) {
      scale = containerSize.height / imageSize.height;
      offsetX = (containerSize.width - (imageSize.width * scale)) / 2;
    } else {
      scale = containerSize.width / imageSize.width;
      offsetY = (containerSize.height - (imageSize.height * scale)) / 2;
    }

    for (var item in results) {
      Rect r = item.rect;
      Rect scaledRect = Rect.fromLTRB(
        r.left * scale + offsetX,
        r.top * scale + offsetY,
        r.right * scale + offsetX,
        r.bottom * scale + offsetY,
      );

      canvas.drawRect(scaledRect, fillPaint);
      canvas.drawRect(scaledRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
