import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_metadata/media_metadata.dart';

/// Lightweight file-list preview. Metadata is read once per visible tile and
/// the plugin's native media retriever supplies embedded art/video frames.
class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    required this.accent,
    this.size = 48,
  });

  final String path;
  final Color accent;
  final double size;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<Metadata?>? _metadataFuture;

  String get _extension {
    final name = widget.path.split(Platform.pathSeparator).last.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  bool get _isAudio => const {
    'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'wma',
  }.contains(_extension);

  bool get _isVideo => const {
    'mp4', 'mkv', 'mov', 'webm', '3gp', '3gpp', 'avi', 'm4v',
  }.contains(_extension);

  bool get _isImage => const {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
    'tif', 'tiff',
  }.contains(_extension);

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _loadMetadata();
  }

  void _loadMetadata() {
    if (_isAudio || _isVideo) {
      _metadataFuture = MediaMetadata.read(
        widget.path,
        createThumbnail: _isVideo,
      );
    } else {
      _metadataFuture = null;
    }
  }

  Widget _fallback(IconData icon) => Container(
    width: widget.size,
    height: widget.size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(13),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          widget.accent.withOpacity(.30),
          const Color(0xFF102B38),
        ],
      ),
      border: Border.all(color: widget.accent.withOpacity(.28)),
    ),
    child: Icon(icon, color: widget.accent, size: widget.size * .48),
  );

  Widget _image(Uint8List bytes, {bool video = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(13),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(
              video ? Icons.movie_rounded : Icons.music_note_rounded,
            )),
          if (video)
            Container(
              color: Colors.black.withOpacity(.16),
              alignment: Alignment.center,
              child: const Icon(Icons.play_circle_fill_rounded,
                color: Colors.white, size: 23),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.cover,
            cacheWidth: (widget.size * 2).round(),
            cacheHeight: (widget.size * 2).round(),
            errorBuilder: (_, __, ___) => _fallback(Icons.image_rounded),
          ),
        ),
      );
    }

    if (_metadataFuture == null) {
      return _fallback(Icons.insert_drive_file_rounded);
    }

    return FutureBuilder<Metadata?>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        final art = snapshot.data?.imageMetadata?.data;
        if (art != null && art.isNotEmpty) {
          return _image(art, video: _isVideo);
        }
        return _fallback(
          _isVideo ? Icons.movie_rounded :
          (_isAudio ? Icons.music_note_rounded : Icons.insert_drive_file_rounded),
        );
      },
    );
  }
}
