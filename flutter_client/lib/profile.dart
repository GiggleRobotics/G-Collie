import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

String previewWorkspaceName = '我的工作台';
const profileStorage = FlutterSecureStorage();
Future<void> restoreProfile() async {
  try {
    final raw = await profileStorage.read(key: 'workspace-profile');
    if (raw != null) {
      final d = jsonDecode(raw);
      previewWorkspaceName = d['name'];
      previewAvatar = d['avatar'] == null ? null : base64Decode(d['avatar']);
    }
  } catch (_) {}
}

Future<void> persistProfile() async => profileStorage.write(
  key: 'workspace-profile',
  value: jsonEncode({
    'name': previewWorkspaceName,
    'avatar': previewAvatar == null ? null : base64Encode(previewAvatar!),
  }),
);

Uint8List? previewAvatar;

Widget workspaceAvatar({double size = 40}) => ClipOval(
  child: previewAvatar == null
      ? Image.asset(
          'assets/collie-mark-v2.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.pets),
        )
      : Image.memory(
          previewAvatar!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.pets),
        ),
);

Future<void> editPreviewWorkspace(
  BuildContext context, {
  bool first = false,
}) async {
  final name = TextEditingController(text: previewWorkspaceName);
  Uint8List? avatar = previewAvatar;
  String error = '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, change) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                first ? '设置你的工作台' : '工作台资料',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ClipOval(
                child: avatar == null
                    ? Image.asset(
                        'assets/collie-mark-v2.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Image.memory(
                        avatar!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () async {
                      final file = await openFile(
                        acceptedTypeGroups: [
                          const XTypeGroup(
                            label: '头像',
                            extensions: ['png', 'jpg', 'jpeg', 'webp'],
                          ),
                        ],
                      );
                      if (file == null) return;
                      try {
                        final bytes = await file.readAsBytes();
                        if (bytes.length > 5 * 1024 * 1024) {
                          throw Exception('请选择不超过 5 MB 的图片');
                        }
                        final codec = await ui.instantiateImageCodec(
                          bytes,
                          targetWidth: 512,
                        );
                        final image = (await codec.getNextFrame()).image;
                        final side = math
                            .min(image.width, image.height)
                            .toDouble();
                        final recorder = ui.PictureRecorder();
                        final canvas = Canvas(recorder);
                        canvas.drawImageRect(
                          image,
                          Rect.fromLTWH(
                            (image.width - side) / 2,
                            (image.height - side) / 2,
                            side,
                            side,
                          ),
                          const Rect.fromLTWH(0, 0, 256, 256),
                          Paint(),
                        );
                        final picture = recorder.endRecording();
                        final cropped = await picture.toImage(256, 256);
                        final data = await cropped.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        image.dispose();
                        codec.dispose();
                        cropped.dispose();
                        picture.dispose();
                        if (ctx.mounted) {
                          change(() {
                            avatar = data!.buffer.asUint8List();
                            error = '';
                          });
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          change(() => error = '图片无法读取，请选择有效且不超过 5 MB 的图片');
                        }
                      }
                    },
                    child: const Text('更换头像'),
                  ),
                  TextButton(
                    onPressed: () => change(() => avatar = null),
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              TextField(
                controller: name,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '工作台名称',
                  hintText: '我的工作台',
                ),
              ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Colors.red)),
              const Text(
                '资料保存在本手机，切换电脑不影响。头像将居中裁切为圆形。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(first ? '暂时跳过' : '取消'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        previewWorkspaceName = name.text.trim().isEmpty
                            ? '我的工作台'
                            : name.text.trim();
                        previewAvatar = avatar;
                        Navigator.pop(ctx);
                      },
                      child: Text(first ? '进入工作台' : '保存'),
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
  await persistProfile();
  // Let the closing route release its text field before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  name.dispose();
}
