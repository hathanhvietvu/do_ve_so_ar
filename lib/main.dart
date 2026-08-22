import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Dò Vé Số XSMN',
      debugShowCheckedModeBanner: false,
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
  
  List<TextElement> _matchingElements = [];
  List<String> _winningNumbers = [];
  String _statusText = "Đang tải KQXS...";
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _fetchMinhChinhXSMN();
    _initCamera();
  }

  Future<void> _fetchMinhChinhXSMN() async {
    try {
      final url = Uri.parse('https://www.minhchinh.com/truc-tiep-xo-so-mien-nam.html');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        List<String> numbers = [];

        var elements = document.querySelectorAll('.box_kqxs td, .bkqmien .number, .v_giai');
        for (var el in elements) {
          String text = el.text.trim();
          RegExp exp = RegExp(r'\b\d{2,6}\b');
          Iterable<RegExpMatch> matches = exp.allMatches(text);
          for (var m in matches) {
            numbers.add(m.group(0)!);
          }
        }

        setState(() {
          _winningNumbers = numbers.toSet().toList();
          _statusText = "Đã tải ${_winningNumbers.length} số trúng. Đưa camera lại gần vé số!";
        });
      } else {
        setState(() {
          _statusText = "Lỗi tải KQXS (${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "Không thể kết nối mạng.";
      });
    }
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;

    _controller = CameraController(
      _cameras[0],
      ResolutionPreset.medium,
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

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      List<TextElement> matches = [];
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          for (var element in line.elements) {
            String cleanText = element.text.replaceAll(RegExp(r'\D'), '');
            if (cleanText.length >= 2 && _winningNumbers.contains(cleanText)) {
              matches.add(element);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _matchingElements = matches;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameras.isEmpty) return null;
    final camera = _cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation90deg,
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
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          if (_imageSize != null)
            CustomPaint(
              painter: ARHighlightPainter(
                elements: _matchingElements,
                imageSize: _imageSize!,
              ),
            ),
          Positioned(
            bottom: 25,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusText,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ARHighlightPainter extends CustomPainter {
  final List<TextElement> elements;
  final Size imageSize;

  ARHighlightPainter({
    required this.elements,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint highlightPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    double scaleX = size.width / imageSize.height;
    double scaleY = size.height / imageSize.width;

    for (var element in elements) {
      Rect rect = element.boundingBox;

      Rect scaledRect = Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, highlightPaint);
      canvas.drawRect(scaledRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
