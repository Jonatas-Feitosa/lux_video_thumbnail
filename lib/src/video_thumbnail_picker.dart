import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lux_video_thumbnail_platform_interface/lux_video_thumbnail_platform_interface.dart';
import 'picking/pick_video.dart' as picking;
import 'picking/picked_video.dart';
import 'thumbnail_data.dart';
import 'thumbnail_session.dart';

/// Selects a video and previews the image at the slider's selected position.
///
/// The widget owns its decoder and resources from the default file picker.
/// An [initialSource] or source supplied by [videoPicker] remains caller-owned.
class VideoThumbnailPicker extends StatefulWidget {
  /// Creates a picker. [onChanged] runs only after the current preview is ready.
  const VideoThumbnailPicker({
    super.key,
    required this.onChanged,
    this.onError,
    this.onReadyChanged,
    this.initialSource,
    this.videoPicker,
    this.width = 320,
    this.height,
    this.format = ThumbnailFormat.jpeg,
    this.quality = 85,
    this.selectVideoLabel = 'Select video',
    this.loadingLabel = 'Generating preview…',
    this.emptyLabel = 'Select a video to preview a thumbnail.',
    this.errorLabel = 'Could not generate a thumbnail.',
    this.previewLabel = 'Preview',
    this.backTenFramesTooltip = 'Back 10 frames',
    this.backOneFrameTooltip = 'Back 1 frame',
    this.forwardOneFrameTooltip = 'Forward 1 frame',
    this.forwardTenFramesTooltip = 'Forward 10 frames',
    this.previewHeight = 180,
    this.frameRate = 30,
    this.previewBuilder,
  }) : assert(frameRate > 0);

  /// Receives encoded image bytes and their requested position.
  final ValueChanged<VideoThumbnailData> onChanged;

  /// Receives decoder or selection errors. The built-in UI displays [errorLabel].
  final ValueChanged<Object>? onError;

  /// Reports whether the displayed image matches the current, completed request.
  /// Initially false. Selection, seeking and errors make confirmation unavailable.
  final ValueChanged<bool>? onReadyChanged;

  /// Optional initial input; changing it replaces the selected video.
  final VideoSource? initialSource;

  /// Optional custom selector. Returning null preserves the current selection.
  final Future<VideoSource?> Function()? videoPicker;

  /// Desired encoded preview width. Null uses the source width.
  final int? width;

  /// Desired encoded preview height. Aspect ratio is preserved.
  final int? height;

  /// Encoded image format.
  final ThumbnailFormat format;

  /// JPEG/WebP quality from 1 to 100.
  final int quality;

  /// Localizable choose-video button text.
  final String selectVideoLabel;

  /// Localizable progress text.
  final String loadingLabel;

  /// Localizable text before the first selection.
  final String emptyLabel;

  /// Localizable error text, without exposing source URLs or local paths.
  final String errorLabel;

  /// Localizable label before the selected preview timestamp.
  final String previewLabel;

  /// Localizable tooltip for the button that jumps back 10 frames.
  final String backTenFramesTooltip;

  /// Localizable tooltip for the button that jumps back 1 frame.
  final String backOneFrameTooltip;

  /// Localizable tooltip for the button that jumps forward 1 frame.
  final String forwardOneFrameTooltip;

  /// Localizable tooltip for the button that jumps forward 10 frames.
  final String forwardTenFramesTooltip;

  /// Height of the preview area.
  final double previewHeight;

  /// Frames per second used by the frame-jump controls.
  ///
  /// Platform decoders do not expose a reliable presentation timestamp for every
  /// video frame, so this controls the requested time step. Provide the source
  /// frame rate when it is known; the default is 30 frames per second.
  final double frameRate;

  /// Optional preview renderer for customizing fit, decoration or image display.
  final Widget Function(BuildContext, VideoThumbnailData)? previewBuilder;

  @override
  State<VideoThumbnailPicker> createState() => _VideoThumbnailPickerState();
}

class _VideoThumbnailPickerState extends State<VideoThumbnailPicker> {
  ThumbnailSession? _session;
  PickedVideo? _picked;
  VideoThumbnailData? _thumbnail;
  Duration _timestamp = Duration.zero;
  Timer? _debounce;
  PickerCancellation? _pickerCancellation;
  int _sourceRevision = 0;
  int _requestRevision = 0;
  bool _selecting = false;
  bool _opening = false;
  bool _generating = false;
  bool _failed = false;
  bool _lastReady = false;

  bool get _ready =>
      _thumbnail != null &&
      _thumbnail!.timestamp == _timestamp &&
      !_selecting &&
      !_opening &&
      !_generating &&
      !_failed;

  void _notifyReady() {
    final ready = _ready;
    if (ready == _lastReady) return;
    _lastReady = ready;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastReady == ready) widget.onReadyChanged?.call(ready);
      });
    } else {
      widget.onReadyChanged?.call(ready);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.frameRate.isFinite || widget.frameRate <= 0) {
      throw ArgumentError.value(
        widget.frameRate,
        'frameRate',
        'must be finite and positive',
      );
    }
    if (widget.initialSource case final source?) {
      unawaited(_replace(PickedVideo(source)));
    }
  }

  @override
  void didUpdateWidget(VideoThumbnailPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSource != oldWidget.initialSource) {
      _pickerCancellation?.cancel();
      if (widget.initialSource case final source?) {
        unawaited(_replace(PickedVideo(source)));
      } else {
        _sourceRevision++;
        _requestRevision++;
        _debounce?.cancel();
        unawaited(_release(_session, _picked));
        _session = null;
        _picked = null;
        _thumbnail = null;
        _timestamp = Duration.zero;
        _opening = _generating = _failed = false;
      }
    } else if (widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.format != oldWidget.format ||
        widget.quality != oldWidget.quality) {
      unawaited(_generate());
    }
    _notifyReady();
  }

  Future<void> _select() async {
    setState(() {
      _selecting = true;
      _failed = false;
    });
    _notifyReady();
    final sourceRevision = _sourceRevision;
    try {
      final custom = widget.videoPicker;
      final PickedVideo? picked;
      if (custom == null) {
        final cancellation = PickerCancellation();
        _pickerCancellation = cancellation;
        picked = await picking.pickVideo(cancellation: cancellation);
      } else {
        final source = await custom();
        picked = source == null ? null : PickedVideo(source);
      }
      if (!mounted || sourceRevision != _sourceRevision) {
        await picked?.dispose();
        return;
      }
      if (picked != null) await _replace(picked);
    } catch (error) {
      if (mounted && sourceRevision == _sourceRevision) _report(error);
    } finally {
      _pickerCancellation = null;
      if (mounted) {
        setState(() => _selecting = false);
        _notifyReady();
      }
    }
  }

  Future<void> _replace(PickedVideo picked) async {
    final revision = ++_sourceRevision;
    ++_requestRevision;
    _debounce?.cancel();
    setState(() {
      _opening = true;
      _generating = false;
      _failed = false;
    });
    _notifyReady();
    ThumbnailSession? opened;
    try {
      opened = await ThumbnailSession.open(picked.source);
      if (!mounted || revision != _sourceRevision) {
        await _release(opened, picked);
        return;
      }
      final previousSession = _session;
      final previousPicked = _picked;
      setState(() {
        _session = opened;
        _picked = picked;
        _timestamp = Duration.zero;
        _thumbnail = null;
        _opening = false;
      });
      unawaited(_release(previousSession, previousPicked));
      await _generate();
    } catch (error) {
      if (opened == null) await picked.dispose();
      if (mounted && revision == _sourceRevision) {
        setState(() => _opening = false);
        _report(error);
      }
    }
  }

  void _seek(double milliseconds) {
    _seekTimestamp(Duration(milliseconds: milliseconds.round()));
  }

  void _seekTimestamp(Duration timestamp) {
    ++_requestRevision; // Immediately invalidate a preview already in flight.
    _debounce?.cancel();
    setState(() {
      _timestamp = timestamp;
      _generating = true;
      _failed = false;
    });
    _notifyReady();
    _debounce = Timer(
      const Duration(milliseconds: 160),
      () => unawaited(_generate()),
    );
  }

  void _jumpFrames(int frames, Duration duration) {
    final delta = (frames * Duration.microsecondsPerSecond / widget.frameRate)
        .round();
    final target = (_timestamp.inMicroseconds + delta).clamp(
      0,
      duration.inMicroseconds,
    );
    _seekTimestamp(Duration(microseconds: target.toInt()));
    unawaited(_generate());
  }

  Future<void> _generate() async {
    _debounce?.cancel();
    final session = _session;
    if (!mounted || session == null || _opening) return;
    final revision = ++_requestRevision;
    final timestamp = _timestamp;
    setState(() {
      _generating = true;
      _failed = false;
    });
    _notifyReady();
    VideoThumbnailData result;
    try {
      if (widget.quality < 1 || widget.quality > 100) {
        throw ArgumentError('Invalid quality');
      }
      result = await session.generate(
        ThumbnailOptions(
          timestamp: timestamp,
          width: widget.width,
          height: widget.height,
          format: widget.format,
          quality: widget.quality,
        ),
        isCurrent: () =>
            mounted &&
            revision == _requestRevision &&
            !_opening &&
            identical(session, _session),
      );
    } catch (error) {
      if (mounted && revision == _requestRevision) {
        setState(() => _generating = false);
        _report(error);
      }
      return;
    }
    if (!mounted || revision != _requestRevision) return;
    setState(() {
      _thumbnail = result;
      _generating = false;
    });
    widget.onChanged(result);
    _notifyReady();
  }

  void _report(Object error) {
    setState(() => _failed = true);
    _notifyReady();
    widget.onError?.call(error);
  }

  Future<void> _release(ThumbnailSession? session, PickedVideo? picked) async {
    try {
      try {
        await session?.close();
      } finally {
        await picked?.dispose();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'lux_video_thumbnail',
          context: ErrorDescription('releasing a video session'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _sourceRevision++;
    _requestRevision++;
    _debounce?.cancel();
    _pickerCancellation?.cancel();
    unawaited(_release(_session, _picked));
    super.dispose();
  }

  String _time(Duration time) {
    final hours = time.inHours.toString().padLeft(2, '0');
    final minutes = time.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = time.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _session?.handle.duration;
    final max = (duration?.inMilliseconds ?? 0).toDouble();
    final thumbnail = _thumbnail;
    final canJump =
        duration != null &&
        duration > Duration.zero &&
        !_opening &&
        !_selecting;
    final canStepBack = canJump && _timestamp.inMicroseconds > 0;
    final canStepForward =
        canJump && _timestamp.inMicroseconds < duration.inMicroseconds;
    return Column(
      spacing: 8,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: OutlinedButton.icon(
            key: const ValueKey('lux-video-select'),
            onPressed: _selecting || _opening ? null : _select,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(widget.selectVideoLabel),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(200, 48),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
        if (_picked != null)
          SizedBox(
            key: const ValueKey('lux-video-preview'),
            width: double.infinity,
            height: widget.previewHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumbnail == null
                    ? Center(child: Text(widget.emptyLabel))
                    : widget.previewBuilder?.call(context, thumbnail) ??
                          Image.memory(
                            thumbnail.bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                if (_opening || _generating || _selecting) ...[
                  ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.48),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ],
            ),
          ),
        if (thumbnail != null)
          Text(
            '${widget.previewLabel}: ${_time(thumbnail.timestamp)} / ${duration == null ? '—' : _time(duration)}',
          ),
        if (_session != null) ...[
          Slider(
            key: const ValueKey('lux-video-timestamp'),
            value: _timestamp.inMilliseconds.toDouble().clamp(
              0,
              max > 0 ? max : 1,
            ),
            min: 0,
            max: max > 0 ? max : 1,
            label: _time(_timestamp),
            onChanged: max > 0 && !_opening && !_selecting ? _seek : null,
            onChangeEnd: (_) => unawaited(_generate()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Tooltip(
                message: widget.backTenFramesTooltip,
                child: IconButton.filled(
                  key: const ValueKey('lux-video-jump-back-10'),
                  onPressed: canStepBack
                      ? () => _jumpFrames(-10, duration)
                      : null,
                  icon: const Icon(Icons.fast_rewind),
                ),
              ),
              Tooltip(
                message: widget.backOneFrameTooltip,
                child: IconButton.filled(
                  key: const ValueKey('lux-video-jump-back-1'),
                  onPressed: canStepBack
                      ? () => _jumpFrames(-1, duration)
                      : null,
                  icon: const Icon(Icons.skip_previous),
                ),
              ),
              Tooltip(
                message: widget.forwardOneFrameTooltip,
                child: IconButton.filled(
                  key: const ValueKey('lux-video-jump-forward-1'),
                  onPressed: canStepForward
                      ? () => _jumpFrames(1, duration)
                      : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ),
              Tooltip(
                message: widget.forwardTenFramesTooltip,
                child: IconButton.filled(
                  key: const ValueKey('lux-video-jump-forward-10'),
                  onPressed: canStepForward
                      ? () => _jumpFrames(10, duration)
                      : null,
                  icon: const Icon(Icons.fast_forward),
                ),
              ),
            ],
          ),
        ],

        if (_failed)
          Text(
            widget.errorLabel,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
