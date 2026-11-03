import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SketchPage extends StatefulWidget {
  const SketchPage({super.key});
  @override
  State<SketchPage> createState() => _SketchPageState();
}

class _SketchPageState extends State<SketchPage> {
  final canvas = GlobalKey();
  final strokes = <List<Offset>>[];
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sketch 草图'),
      actions: [
        IconButton(
          tooltip: '撤销笔画',
          onPressed: strokes.isEmpty
              ? null
              : () => setState(() => strokes.removeLast()),
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: '清空',
          onPressed: strokes.isEmpty
              ? null
              : () => setState(() => strokes.clear()),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('画出想法后加入附件，不会自动发送。'),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: canvas,
              child: ColoredBox(
                color: Colors.white,
                child: GestureDetector(
                  key: const ValueKey('sketch-pad'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: busy
                      ? null
                      : (e) => setState(() => strokes.add([e.localPosition])),
                  onPanUpdate: busy
                      ? null
                      : (e) => setState(() {
                          if (strokes.isNotEmpty &&
                              strokes.fold<int>(0, (n, s) => n + s.length) <
                                  20000) {
                            strokes.last.add(e.localPosition);
                          }
                        }),
                  child: CustomPaint(
                    painter: _SketchPainter(strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy || strokes.isEmpty
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final image =
                          await (canvas.currentContext!.findRenderObject()
                                  as RenderRepaintBoundary)
                              .toImage(pixelRatio: 1.5);
                      final bytes = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      image.dispose();
                      if (context.mounted && bytes != null) {
                        Navigator.pop<Uint8List>(
                          context,
                          bytes.buffer.asUint8List(),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('加入会话附件'),
          ),
        ),
      ],
    ),
  );
}

class _SketchPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SketchPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint);
        continue;
      }
      final path = Path();
      for (var i = 0; i < stroke.length; i++) {
        i == 0
            ? path.moveTo(stroke[i].dx, stroke[i].dy)
            : path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}
