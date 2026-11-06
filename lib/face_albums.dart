import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:face_detection_tflite/face_detection_tflite.dart' as face_ml;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// On-device, temporary face-similarity albums.
/// Embeddings are kept in memory only and are discarded when this page closes.
class FaceAlbumsPage extends StatefulWidget {
  const FaceAlbumsPage({
    super.key,
    required this.targetDirectory,
    required this.accent,
  });

  final Directory targetDirectory;
  final Color accent;

  @override
  State<FaceAlbumsPage> createState() => _FaceAlbumsPageState();
}

class _FaceAlbumsPageState extends State<FaceAlbumsPage> {
  static const int _maxImages = 1200;
  static const int _maxDirectories = 5000;
  static const int _maxFileBytes = 12 * 1024 * 1024;
  static const double _matchThreshold = 0.62;
  static const double _minimumMatchMargin = 0.08;

  bool _busy = false;
  String _status = 'Scan your accessible photo folders to create private, on-device people albums.';
  double _progress = 0;
  int _processed = 0;
  int _skipped = 0;
  List<_PersonCluster> _groups = <_PersonCluster>[];
  final List<({ _PersonCluster group, String path })> _undoRemovals = [];

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  bool _skipDirectory(String path) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    return p.contains('/android/data/') ||
        p.contains('/android/obb/') ||
        p.contains('/aqua_encrypted_vault/') ||
        p.contains('/aqua_recycle_bin/') ||
        p.contains('/.thumbnails/') ||
        p.split('/').any((part) => part.startsWith('.') && part.length > 1);
  }

  Future<List<File>> _collectImages() async {
    final queue = <Directory>[];
    final seenDirectories = <String>{};
    final images = <File>[];

    void addRoot(Directory directory) {
      final key = directory.absolute.path;
      if (seenDirectories.add(key)) queue.add(directory);
    }

    addRoot(Directory('/storage/emulated/0'));
    addRoot(widget.targetDirectory);

    // Include mounted removable volumes when Android exposes a filesystem path.
    try {
      final storage = Directory('/storage');
      if (await storage.exists()) {
        await for (final entity in storage.list(followLinks: false)) {
          if (entity is Directory &&
              entity.path != '/storage/emulated' &&
              entity.path != '/storage/self' &&
              !_skipDirectory(entity.path)) {
            addRoot(entity);
          }
        }
      }
    } catch (_) {}

    var cursor = 0;
    while (cursor < queue.length &&
        queue.length <= _maxDirectories &&
        images.length < _maxImages) {
      final directory = queue[cursor++];
      if (_skipDirectory(directory.path)) continue;
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is Directory) {
            if (!_skipDirectory(entity.path) &&
                seenDirectories.add(entity.absolute.path) &&
                queue.length < _maxDirectories) {
              queue.add(entity);
            }
          } else if (entity is File && _isImage(entity.path)) {
            images.add(entity);
            if (images.length >= _maxImages) break;
          }
        }
      } catch (_) {
        // Some Android folders are intentionally inaccessible; continue elsewhere.
      }
    }
    return images;
  }

  double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) return -1;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  Future<void> _startScan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _processed = 0;
      _skipped = 0;
      _groups = <_PersonCluster>[];
      _undoRemovals.clear();
      _status = 'Checking photo access…';
    });

    face_ml.FaceDetector? detector;
    try {
      if (Platform.isAndroid) {
        var permission = await Permission.manageExternalStorage.status;
        if (!permission.isGranted) {
          permission = await Permission.manageExternalStorage.request();
        }
        if (!permission.isGranted) {
          throw StateError('Allow “All files access” in Android Settings, then try again.');
        }
      }

      final images = await _collectImages();
      if (images.isEmpty) {
        throw StateError('No supported photos were found in folders this app can access.');
      }

      if (mounted) {
        setState(() => _status = 'Preparing offline face model…');
      }
      detector = await face_ml.FaceDetector.create(
        model: face_ml.FaceDetectionModel.backCamera,
        minFaceSize: 0.04,
      );
      final clusters = <_PersonCluster>[];

      for (var index = 0; index < images.length; index++) {
        final file = images[index];
        try {
          final stat = await file.stat();
          if (stat.size <= 0 || stat.size > _maxFileBytes) {
            _skipped++;
            continue;
          }
          final bytes = await file.readAsBytes();
          final faces = await detector.detectFacesFromBytes(
            bytes,
            // Full mode provides the eye alignment expected by the embedding model.
            mode: face_ml.FaceDetectionMode.full,
          );

          for (final face in faces.take(5)) {
            try {
              final embedding = await detector.getFaceEmbedding(face, bytes);
              if (embedding.isEmpty) continue;

              var bestIndex = -1;
              var bestScore = -1.0;
              var secondScore = -1.0;
              for (var i = 0; i < clusters.length; i++) {
                final cluster = clusters[i];
                var score = -1.0;
                for (final sample in cluster.samples) {
                  score = math.max(score, _cosine(sample, embedding)).toDouble();
                }
                if (score > bestScore) {
                  secondScore = bestScore;
                  bestScore = score;
                  bestIndex = i;
                } else if (score > secondScore) {
                  secondScore = score;
                }
              }

              if (bestIndex >= 0 &&
                  bestScore >= _matchThreshold &&
                  (secondScore < 0 || bestScore - secondScore >= _minimumMatchMargin)) {
                final cluster = clusters[bestIndex];
                if (cluster.samples.length < 6) {
                  cluster.samples.add(List<double>.from(embedding));
                }
                if (!cluster.paths.contains(file.path)) {
                  cluster.paths.add(file.path);
                }
              } else {
                clusters.add(_PersonCluster(
                  samples: <List<double>>[List<double>.from(embedding)],
                  paths: <String>[file.path],
                ));
              }
            } catch (_) {
              _skipped++;
            }
          }
        } catch (_) {
          _skipped++;
        }

        _processed++;
        if (index % 8 == 0 || index == images.length - 1) {
          if (mounted) {
            setState(() {
              _progress = (index + 1) / images.length;
              _status = 'Analysing photo ${index + 1} of ${images.length}…';
            });
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      clusters.removeWhere((group) => group.paths.isEmpty);
      clusters.sort((a, b) => b.paths.length.compareTo(a.paths.length));
      if (mounted) {
        setState(() {
          _groups = clusters;
          _progress = 1;
          _status = 'Finished: ${clusters.length} possible people groups from ${_processed} photos. Review groups before relying on matches.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Face scan could not finish: $error');
    } finally {
      await detector?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeFromGroup(_PersonCluster group, String path, StateSetter sheetSetState) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from this album?'),
        content: const Text('This only removes the photo from this temporary face group. The original photo will stay on your phone and will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !group.paths.contains(path)) return;
    setState(() {
      _undoRemovals.add((group: group, path: path));
      group.paths.remove(path);
      if (group.paths.isEmpty) _groups.remove(group);
    });
    sheetSetState(() {});
  }

  void _undoLastRemoval() {
    if (_undoRemovals.isEmpty) return;
    final item = _undoRemovals.removeLast();
    if (!item.group.paths.contains(item.path)) {
      item.group.paths.add(item.path);
      item.group.paths.sort();
    }
    if (!_groups.contains(item.group)) _groups.add(item.group);
    _groups.sort((a, b) => b.paths.length.compareTo(a.paths.length));
    setState(() {});
  }

  Future<void> _viewPhoto(String path) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF050B12),
        child: Scaffold(
          backgroundColor: const Color(0xFF050B12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF050B12),
            foregroundColor: Colors.white,
            title: Text(path.split(Platform.pathSeparator).last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Close image',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: .8,
              maxScale: 6,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined, color: Colors.white70, size: 56),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showGroup(_PersonCluster group, int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF102B38),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  'Possible person ${index + 1} • ${group.paths.length} photo(s)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  'These photos look similar to the on-device model. Check them yourself; incorrect matches are possible.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: group.paths.length,
                  itemBuilder: (context, i) {
                    final path = group.paths[i];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        InkWell(
                          onTap: () => _viewPhoto(path),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFF244653),
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Material(
                            color: Colors.black.withValues(alpha: .65),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Remove from this album',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 18, color: Colors.white),
                              onPressed: () => _removeFromGroup(group, path, sheetSetState),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071E2A),
      appBar: AppBar(
        title: const Text('Face Albums'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'On-device Face Albums',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'The app detects faces and compares temporary similarity features on this phone. It does not name people or upload photos. Suggested groups can be wrong, so review them manually. Temporary face features are discarded when you leave this screen.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _startScan,
            icon: const Icon(Icons.face_retouching_natural),
            label: Text(_busy ? 'Scanning photos…' : 'Scan accessible photos'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress, color: widget.accent),
            const SizedBox(height: 6),
            Text('${(_progress * 100).round()}% • $_processed scanned • $_skipped skipped',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (!_busy && _groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Possible people • ${_groups.length}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ..._groups.asMap().entries.map((entry) {
              final index = entry.key;
              final group = entry.value;
              final firstPath = group.paths.first;
              return Card(
                color: const Color(0xFF12313F),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.file(
                        File(firstPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.face, color: widget.accent),
                      ),
                    ),
                  ),
                  title: Text('Person group ${index + 1}'),
                  subtitle: Text('${group.paths.length} photo(s) • Tap to review'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showGroup(group, index),
                ),
              );
            }),
          ],
          if (_undoRemovals.isNotEmpty)
            TextButton.icon(
              onPressed: _busy ? null : _undoLastRemoval,
              icon: const Icon(Icons.undo),
              label: Text('Undo last removal (${_undoRemovals.length})'),
            ),
          if (_groups.isNotEmpty)
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() {
                _groups = <_PersonCluster>[];
                _undoRemovals.clear();
                _status = 'Temporary face groups cleared from memory.';
              }),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear temporary groups'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Accuracy note: lighting, camera angle, age changes, masks and low-resolution images can cause missed or incorrect matches. This is a photo-organising aid, not proof of someone’s identity.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PersonCluster {
  _PersonCluster({required this.samples, required this.paths});

  final List<List<double>> samples;
  final List<String> paths;
}
