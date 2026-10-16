import 'package:flutter/material.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'thumbnail_data.dart';
import 'video_thumbnail_picker.dart';

/// Opens a video selector, timeline and preview in a customizable Material dialog.
///
/// Returns only the confirmed, current image; cancelling, Back or barrier dismissal
/// returns null. Confirmation is disabled during selection, decoding and debounce,
/// or after an error. Sources supplied by the app remain caller-owned.
/// The picker releases its resources when the dialog route is disposed.
Future<VideoThumbnailData?> videoThumbnailDialog({
  required BuildContext context,
  VideoSource? initialSource,
  Future<VideoSource?> Function()? videoPicker,
  ValueChanged<Object>? onError,
  int? width = 320,
  int? height,
  ThumbnailFormat format = ThumbnailFormat.jpeg,
  int quality = 85,
  String title = 'Select thumbnail',
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  String selectVideoLabel = 'Select video',
  String loadingLabel = 'Generating preview…',
  String emptyLabel = 'Select a video to preview a thumbnail.',
  String errorLabel = 'Could not generate a thumbnail.',
  String previewLabel = 'Preview',
  String backTenFramesTooltip = 'Back 10 frames',
  String backOneFrameTooltip = 'Back 1 frame',
  String forwardOneFrameTooltip = 'Forward 1 frame',
  String forwardTenFramesTooltip = 'Forward 10 frames',
  double previewHeight = 180,
  double frameRate = 30,
  double maxWidth = 640,
  Widget Function(BuildContext, VideoThumbnailData)? previewBuilder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  ThumbnailOptions(
    timestamp: Duration.zero,
    width: width,
    height: height,
    format: format,
    quality: quality,
  );
  if (!maxWidth.isFinite ||
      maxWidth <= 0 ||
      !previewHeight.isFinite ||
      previewHeight <= 0 ||
      !frameRate.isFinite ||
      frameRate <= 0) {
    throw ArgumentError(
      'Dialog dimensions and frame rate must be finite and positive',
    );
  }
  return showDialog<VideoThumbnailData>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (_) => _ThumbnailDialog(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      maxWidth: maxWidth,
      backgroundColor: backgroundColor,
      shape: shape,
      pickerBuilder: (onChanged, onReadyChanged) => VideoThumbnailPicker(
        initialSource: initialSource,
        videoPicker: videoPicker,
        onError: onError,
        onChanged: onChanged,
        onReadyChanged: onReadyChanged,
        width: width,
        height: height,
        format: format,
        quality: quality,
        selectVideoLabel: selectVideoLabel,
        loadingLabel: loadingLabel,
        emptyLabel: emptyLabel,
        errorLabel: errorLabel,
        previewLabel: previewLabel,
        backTenFramesTooltip: backTenFramesTooltip,
        backOneFrameTooltip: backOneFrameTooltip,
        forwardOneFrameTooltip: forwardOneFrameTooltip,
        forwardTenFramesTooltip: forwardTenFramesTooltip,
        previewHeight: previewHeight,
        frameRate: frameRate,
        previewBuilder: previewBuilder,
      ),
    ),
  );
}

class _ThumbnailDialog extends StatefulWidget {
  const _ThumbnailDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.maxWidth,
    required this.pickerBuilder,
    this.backgroundColor,
    this.shape,
  });

  final String title, confirmLabel, cancelLabel;
  final double maxWidth;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final VideoThumbnailPicker Function(
    ValueChanged<VideoThumbnailData>,
    ValueChanged<bool>,
  )
  pickerBuilder;

  @override
  State<_ThumbnailDialog> createState() => _ThumbnailDialogState();
}

class _ThumbnailDialogState extends State<_ThumbnailDialog> {
  VideoThumbnailData? _selection;
  bool _ready = false;

  void _changed(VideoThumbnailData selection) {
    if (mounted) setState(() => _selection = selection);
  }

  void _readiness(bool ready) {
    if (mounted && _ready != ready) setState(() => _ready = ready);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    backgroundColor: widget.backgroundColor,
    shape: widget.shape,
    constraints: BoxConstraints(maxWidth: widget.maxWidth),
    scrollable: true,
    content: SizedBox(
      width: widget.maxWidth,
      child: widget.pickerBuilder(_changed, _readiness),
    ),
    actions: [
      TextButton(
        key: const ValueKey('lux-video-dialog-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.cancelLabel),
      ),
      FilledButton(
        key: const ValueKey('lux-video-dialog-confirm'),
        onPressed: _ready && _selection != null
            ? () {
                if (mounted && _ready && _selection != null) {
                  Navigator.of(context).pop(_selection);
                }
              }
            : null,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
