import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http' as http;
import 'package:html/parser.dart' as parser;

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Dò Vé Số XSMN',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  List<TextBlock> _detectedBlocks = [];
  List<String> _winningNumbers = [];
  bool _isLoadingResults = true;
  String _statusText = "Đang tải KQXS từ MinhChinh.com...";

  @override
  void initState() {
    super.initState();
    _fetchMinhChinhXSMN();
    _initCamera();
  }

  // 1. Cào dữ liệu từ Minh Chinh
  Future<void> _fetchMinhChinhXSMN() async {
    try {
      final url = Uri.parse('https://www.minhchinh.com/truc-tiep-xo-so-mien-nam.html');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        List<String> numbers = [];

        // Tìm tất cả các thẻ chứa dãy số trúng thưởng trên trang web
        var elements = document.querySelectorAll('.box_kqxs td, .bkqmien .number');
        for (var el in elements) {
          String text = el.text.trim();
          // Lọc lấy các chuỗi chỉ chứa số (từ 2 đến 6 chữ số)
          if (RegExp(r'^\d{2,6}$').hasMatch(text)) {
            numbers.add(text);
          }
        }

        setState(() {
          _winningNumbers = numbers.toSet().toList(); // Loại bỏ số trùng
          _isLoadingResults = false;
          _statusText = "Đã tải ${_winningNumbers.length} số trúng. Hãy đưa vé số vào khung hình!";
        });
      } else {
        setState(() {
          _statusText = "Lỗi kết nối tới MinhChinh.com (${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "Không thể tải KQXS. Vui lòng kiểm tra mạng.";
      });
    }
  }

  // 2. Khởi tạo Camera & luồng xử lý AR
  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;

    _controller = CameraController(
      _cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _controller!.initialize();
    if (!mounted) return;

    _controller!.startImageStream((CameraImage image) {
      if (_isProcessing || _winningNumbers.isEmpty) return;
      _isProcessing = true;
      _processCameraImage(image);
    });

    setState(() {});
  }

  // 3. Xử lý OCR từng khung hình
  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      if (mounted) {
        setState(() {
          _detectedBlocks = recognizedText.blocks;
        });
      }
    } catch (e) {
      // Bỏ qua lỗi khung hình lẻ
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dò Vé Số AR - Minh Chính"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Hiển thị Camera
          CameraPreview(_controller!),

          // Lớp vẽ đè bôi vàng AR (CustomPainter)
          CustomPaint(
            size: Size.infinite,
            painter: ARHighlightPainter(
              blocks: _detectedBlocks,
              winningNumbers: _winningNumbers,
              previewSize: _controller!.value.previewSize!,
            ),
          ),

          // Thanh thông báo trạng thái phía dưới
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black70,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusText,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 4. Lớp vẽ bôi vàng số trúng thưởng
class ARHighlightPainter extends CustomPainter {
  final List<TextBlock> blocks;
  final List<String> winningNumbers;
  final Size previewSize;

  ARHighlightPainter({
    required this.blocks,
    required this.winningNumbers,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint highlightPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.55) // Bôi vàng trong suốt
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var block in blocks) {
      for (var line in block.lines) {
        String cleanText = line.text.replaceAll(RegExp(r'\D'), ''); // Chỉ lấy chữ số

        if (cleanText.length >= 2 && cleanText.length <= 6) {
          // Kiểm tra xem dãy số có nằm trong danh sách trúng thưởng không
          if (winningNumbers.contains(cleanText)) {
            Rect rect = line.boundingBox;

            // Chuyển đổi tọa độ khung hình camera sang tọa độ màn hình
            double scaleX = size.width / previewSize.height;
            double scaleY = size.height / previewSize.width;

            Rect scaledRect = Rect.fromLTRB(
              rect.left * scaleX,
              rect.top * scaleY,
              rect.right * scaleX,
              rect.bottom * scaleY,
            );

            // Vẽ hiệu ứng bôi vàng + viền đỏ quanh số trúng
            canvas.drawRect(scaledRect, highlightPaint);
            canvas.drawRect(scaledRect, borderPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
