import 'dartd:io';
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
      title: 'Dò Vé Số Chuẩn Đài',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const LotteryScannerScreen(),
    );
  }
}

class LotteryScannerScreen extends StatefulWidget {
  const LotteryScannerScreen({super.key});

  @override
  State<LotteryScannerScreen> createState() => _LotteryScannerScreenState();
}

class _LotteryScannerScreenState extends State<LotteryScannerScreen> {
  File? _selectedImage;
  Size? _imageSize;
  List<MatchedResult> _matchedResults = [];
  Map<String, List<String>> _provinceResults = {};
  bool _isProcessing = false;
  String _statusText = "Đang kết nối lấy KQXS từ MinhChinh.com...";

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _fetchMinhChinhByProvince();
  }

  Future<void> _fetchMinhChinhByProvince() async {
    Map<String, List<String>> fallbackData = {
      "TPHCM": ["22", "55", "114", "884", "2424", "3370", "5681", "4809", "3063", "8431", "9970", "3368", "9212", "296215"],
      "LONG AN": ["48", "548", "9548", "7036", "5125", "5124", "4300", "2045", "6434", "9522", "24610", "53708"],
      "BÌNH PHƯỚC": ["15", "315", "7315", "8812", "9012", "4412", "1102", "5512", "88912"],
      "HẬU GIANG": ["91", "291", "8291", "6612", "7712", "1152", "0012", "9912", "33312"],
    };

    try {
      final url = Uri.parse('https://www.minhchinh.com/truc-tiep-xo-so-mien-nam.html');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        var tables = document.querySelectorAll('table');
        for (var table in tables) {
          String tableText = table.text.toUpperCase();
          String detectedProvince = "";

          if (tableText.contains("TP.HCM") || tableText.contains("TPHCM") || tableText.contains("THÀNH PHỐ")) {
            detectedProvince = "TPHCM";
          } else if (tableText.contains("LONG AN")) {
            detectedProvince = "LONG AN";
          } else if (tableText.contains("BÌNH PHƯỚC")) {
            detectedProvince = "BÌNH PHƯỚC";
          } else if (tableText.contains("HẬU GIANG")) {
            detectedProvince = "HẬU GIANG";
          }

          if (detectedProvince.isNotEmpty) {
            List<String> nums = [];
            RegExp exp = RegExp(r'\b\d{2,6}\b');
            for (var m in exp.allMatches(tableText)) {
              nums.add(m.group(0)!);
            }
            if (nums.isNotEmpty) {
              fallbackData[detectedProvince] = nums.toSet().toList();
            }
          }
        }
      }
    } catch (_) {}

    setState(() {
      _provinceResults = fallbackData;
      _statusText = "Sẵn sàng! Hãy chọn ảnh tập vé để dò số.";
    });
  }

  Future<void> _pickAndProcessImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    File imageFile = File(image.path);
    var decodedImage = await decodeImageFromList(imageFile.readAsBytesSync());

    setState(() {
      _selectedImage = imageFile;
      _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
      _isProcessing = true;
      _statusText = "Đang quét và lọc con số trúng...";
    });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      List<MatchedResult> hits = [];
      RegExp numExp = RegExp(r'\d{2,6}');

      for (var block in recognizedText.blocks) {
        String blockText = block.text.toUpperCase();
        
        String targetProvince = "TPHCM";
        if (blockText.contains("LONG AN")) {
          targetProvince = "LONG AN";
        } else if (blockText.contains("BÌNH PHƯỚC")) {
          targetProvince = "BÌNH PHƯỚC";
        } else if (blockText.contains("HẬU GIANG")) {
          targetProvince = "HẬU GIANG";
        }

        List<String> provinceWinningNumbers = _provinceResults[targetProvince] ?? [];

        for (var line in block.lines) {
          for (var element in line.elements) {
            String rawText = element.text;
            Iterable<RegExpMatch> matches = numExp.allMatches(rawText);

            for (var m in matches) {
              String number = m.group(0)!;
              
              // Tính toán vị trí chính xác của chuỗi số khớp
              MatchMatchInfo? winInfo = _findMatchingSubstringInfo(number, provinceWinningNumbers);

              if (winInfo != null) {
                // Tính khoảng chữ nhật tương đối của các con số trúng
                Rect fullRect = element.boundingBox;
                double charWidth = fullRect.width / number.length;
                
                double matchedLeft = fullRect.left + (winInfo.startIndex * charWidth);
                double matchedRight = matchedLeft + (winInfo.matchedLength * charWidth);

                Rect exactNumberRect = Rect.fromLTRB(
                  matchedLeft,
                  fullRect.top,
                  matchedRight,
                  fullRect.bottom,
                );

                hits.add(MatchedResult(
                  rect: exactNumberRect,
                  matchedText: winInfo.matchedText,
                ));
              }
            }
          }
        }
      }

      setState(() {
        _matchedResults = hits;
        _statusText = hits.isNotEmpty
            ? "Tìm thấy ${hits.length} vị trí số trúng! Đã tô nền XANH LÁ."
            : "Không tìm thấy con số trúng phù hợp.";
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

  MatchMatchInfo? _findMatchingSubstringInfo(String scanned, List<String> winningNumbers) {
    if (scanned.length < 2) return null;

    for (String winNum in winningNumbers) {
      // 1. Kiểm tra trúng >= 2 số đuôi (ngoài cùng bên phải)
      for (int len = scanned.length; len >= 2; len--) {
        String tail = scanned.substring(scanned.length - len);
        if (winNum.endsWith(tail) || winNum == tail) {
          return MatchMatchInfo(
            startIndex: scanned.length - len,
            matchedLength: len,
            matchedText: tail,
          );
        }
      }

      // 2. Kiểm tra trúng >= 3 số liên tiếp ở đầu hoặc giữa
      if (scanned.length >= 3) {
        for (int i = 0; i <= scanned.length - 3; i++) {
          String sub = scanned.substring(i, i + 3);
          if (winNum.contains(sub)) {
            return MatchMatchInfo(
              startIndex: i,
              matchedLength: 3,
              matchedText: sub,
            );
          }
        }
      }
    }

    return null;
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
        title: const Text("Dò Vé Số Tô Nền Xanh"),
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
                        Icon(Icons.style_outlined, size: 80, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Chọn ảnh tập vé số để tô nền xanh con số trúng", style: TextStyle(color: Colors.grey, fontSize: 15)),
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
                              painter: GreenHighlightPainter(
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
            padding: const EdgeInsets.all(14),
            color: Colors.black87,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusText,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickAndProcessImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text("THƯ VIỆN ẢNH"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
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

class MatchMatchInfo {
  final int startIndex;
  final int matchedLength;
  final String matchedText;

  MatchMatchInfo({
    required this.startIndex,
    required this.matchedLength,
    required this.matchedText,
  });
}

class MatchedResult {
  final Rect rect;
  final String matchedText;

  MatchedResult({
    required this.rect,
    required this.matchedText,
  });
}

class GreenHighlightPainter extends CustomPainter {
  final List<MatchedResult> results;
  final Size imageSize;
  final Size containerSize;

  GreenHighlightPainter({
    required this.results,
    required this.imageSize,
    required this.containerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Chỉ tô màu XANH LÁ xuyên thấu lên nền con số trúng
    final Paint greenFillPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.75)
      ..style = PaintingStyle.fill;

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

      // Vẽ duy nhất dải màu nền Xanh Lá
      canvas.drawRect(scaledRect, greenFillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
