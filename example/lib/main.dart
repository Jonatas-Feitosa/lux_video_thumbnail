import 'package:flutter/material.dart';
import 'package:lux_video_thumbnail/lux_video_thumbnail.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  VideoThumbnailData? _selection;
  VideoThumbnailData? _dialogSelection;

  Future<void> _chooseInDialog(BuildContext context) async {
    final selection = await videoThumbnailDialog(context: context);
    if (!mounted || selection == null) return;
    setState(() => _dialogSelection = selection);
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return MaterialApp(
      title: 'Lux Video Thumbnail',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Lux Video Thumbnail')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Select in a dialog'),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) => FilledButton.icon(
                      key: const ValueKey('example-open-thumbnail-dialog'),
                      onPressed: () => _chooseInDialog(context),
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Choose thumbnail in dialog'),
                    ),
                  ),
                  if (_dialogSelection case final selected?) ...[
                    const SizedBox(height: 12),
                    Image.memory(
                      selected.bytes,
                      height: 180,
                      fit: BoxFit.contain,
                    ),
                    Text('Confirmed: ${selected.timestamp.inMilliseconds} ms'),
                  ],
                  const Divider(height: 32),
                  const Text('Select directly on the page'),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a video and move the slider to select a thumbnail.',
                  ),
                  const SizedBox(height: 16),
                  VideoThumbnailPicker(
                    onChanged: (thumbnail) =>
                        setState(() => _selection = thumbnail),
                  ),
                  if (selection != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${selection.width} × ${selection.height} · '
                      '${selection.bytes.length} bytes · ${selection.format.name}',
                    ),
                    const Text(
                      'The image is ready to save or upload from your app.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
