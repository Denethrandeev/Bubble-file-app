import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'advanced_tools.dart';
import 'media_thumbnail.dart';
import 'location_albums.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const AquaApp());

const List<Color> aquaAccents = <Color>[
  Color(0xFF20E4E8),
  Color(0xFFAA8BFF),
  Color(0xFF4DE0A5),
  Color(0xFFFFC15A),
  Color(0xFFFF83C5),
];


class _LiquidSurfacePainter extends CustomPainter {
  const _LiquidSurfacePainter({required this.accent, required this.tilt, required this.enabled});
  final Color accent;
  final Offset tilt;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !enabled) return;
    final slope = enabled ? (tilt.dx * .12).clamp(-.13, .13) : 0.0;
    final base = size.height * .91;
    final path = Path()..moveTo(0, base + slope * size.height);
    for (var i = 0; i <= 24; i++) {
      final x = size.width * i / 24;
      final wave = math.sin(i / 24 * math.pi * 2) * size.height * .009;
      path.lineTo(x, base + slope * (x - size.width / 2) + wave);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent.withOpacity(.16), accent.withOpacity(.30)],
      ).createShader(Offset.zero & size));
    final shine = Paint()
      ..color = accent.withOpacity(.52)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final surface = Path()..moveTo(0, base + slope * size.height);
    for (var i = 0; i <= 24; i++) {
      final x = size.width * i / 24;
      final wave = math.sin(i / 24 * math.pi * 2) * size.height * .009;
      surface.lineTo(x, base + slope * (x - size.width / 2) + wave);
    }
    canvas.drawPath(surface, shine);
    for (var i = 0; i < 2; i++) {
      final x = size.width * (.28 + i * .43) + (enabled ? tilt.dx * 3 : 0);
      final y = size.height * (.955 - i * .018) + (enabled ? tilt.dy * 2 : 0);
      canvas.drawCircle(Offset(x, y), size.width * (.009 + i * .003),
        Paint()..color = Colors.white.withOpacity(.36));
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidSurfacePainter old) =>
      old.accent != accent || old.tilt != tilt || old.enabled != enabled;
}

class _StorageDropPainter extends CustomPainter {
  const _StorageDropPainter({
    required this.fraction,
    required this.color,
    required this.active,
  });

  final double fraction;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .5, size.height * .04)
      ..cubicTo(size.width * .40, size.height * .22, size.width * .08,
          size.height * .48, size.width * .08, size.height * .68)
      ..cubicTo(size.width * .08, size.height * .91, size.width * .25,
          size.height * .99, size.width * .5, size.height * .99)
      ..cubicTo(size.width * .75, size.height * .99, size.width * .92,
          size.height * .91, size.width * .92, size.height * .68)
      ..cubicTo(size.width * .92, size.height * .48, size.width * .60,
          size.height * .22, size.width * .5, size.height * .04)
      ..close();

    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(.10)
      ..style = PaintingStyle.fill);
    canvas.save();
    canvas.clipPath(path);
    if (active) {
      final top = size.height * (1 - fraction.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, size.height),
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(.55), color],
        ).createShader(Offset.zero & size));
    }
    canvas.restore();
    canvas.drawPath(path, Paint()
      ..color = color.withOpacity(.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7);
    canvas.drawCircle(Offset(size.width * .35, size.height * .45),
      size.width * .055, Paint()..color = Colors.white.withOpacity(.65));
  }

  @override
  bool shouldRepaint(covariant _StorageDropPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.active != active;
}

class AquaApp extends StatefulWidget {
  const AquaApp({super.key});
  @override
  State<AquaApp> createState() => _AquaAppState();
}

class _AquaAppState extends State<AquaApp> with WidgetsBindingObserver {
  int _tab = 0;
  int _theme = 0;
  bool _gravity = true;
  bool _waterEnabled = true;
  Offset _waterTilt = Offset.zero;
  Offset? _waterBaseline;
  StreamSubscription<AccelerometerEvent>? _waterSensor;
  bool _animations = true;
  bool _performance = true;
  double _bubbleSpeed = 1.0;
  bool _light = false;
  bool _checkingPermission = false;
  bool _hasStorage = false;
  int _storageTotalBytes = 0;
  int _storageFreeBytes = 0;
  List<Map<String, dynamic>> _storageVolumes = <Map<String, dynamic>>[];
  String _storageMessage = 'Allow access to browse your phone storage.';
  Directory _root = Directory('/storage/emulated/0');
  Directory _current = Directory('/storage/emulated/0');
  List<FileSystemEntity> _items = <FileSystemEntity>[];
  String _search = '';
  bool _foldersFirst = true;
  bool _showHidden = false;
  bool _scanningDuplicates = false;
  String _fileCategory = 'All files';
  String _sortMode = 'Name';
  String _viewMode = 'List';
  bool _sortDescending = false;
  bool _categoryScanBusy = false;
  List<FileSystemEntity> _categoryFiles = <FileSystemEntity>[];
  Directory? _recycleDirectory;
  File? _recycleIndex;
  List<Map<String, dynamic>> _recycleRecords = <Map<String, dynamic>>[];
  FileSystemEntity? _clipboardEntity;
  bool _clipboardMove = false;
  Timer? _recycleTimer;
  List<String> _storageRoots = <String>['/storage/emulated/0'];
  static const FlutterSecureStorage _folderPinStore = FlutterSecureStorage();
  final AudioPlayer _mediaAudioPlayer = AudioPlayer();

  Color get _accent => aquaAccents[_theme];

  bool _showSplash = true;
  final GlobalKey<_BubbleFieldState> _bubbleFieldKey = GlobalKey<_BubbleFieldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waterSensor = accelerometerEventStream().listen((event) {
      _waterBaseline ??= Offset(event.x, event.y);
      final next = Offset(
        ((event.x - _waterBaseline!.dx) / 9.8).clamp(-1.0, 1.0).toDouble(),
        ((event.y - _waterBaseline!.dy) / 9.8).clamp(-1.0, 1.0).toDouble(),
      );
      if ((next - _waterTilt).distance > .045 && mounted) {
        setState(() => _waterTilt = next);
      }
    }, onError: (_) {});
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _showSplash = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestStorage();
      _initializeRecycleBin();
    });
  }

  Future<void> _requestStorage() async {
    if (!Platform.isAndroid) {
      setState(() => _storageMessage = 'This build currently targets Android storage.');
      return;
    }
    if (mounted) setState(() => _checkingPermission = true);
    try {
      // Android 11+ uses a special All files access setting. A legacy
      // media permission is NOT enough to browse the whole shared-storage tree.
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!mounted) return;
      setState(() {
        _hasStorage = status.isGranted;
        _checkingPermission = false;
        _storageMessage = status.isGranted
            ? 'All files access is enabled.'
            : 'Android requires All files access. The system may open a Settings page; enable “Allow access to manage all files”, return to Aqua, then tap Check permission.';
      });
      if (status.isGranted) {
        await _loadStorageInfo();
        await _discoverStorageRoots();
        await _loadStorageVolumes();
        await _loadDirectory(_root);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingPermission = false;
        _storageMessage = 'Could not request storage access: ' + e.toString();
      });
    }
  }

  Future<void> _loadStorageInfo() async {
    try {
      final info = await const MethodChannel('aqua/storage')
          .invokeMapMethod<String, int>('storageInfo');
      if (!mounted || info == null) return;
      setState(() {
        _storageTotalBytes = info['total'] ?? 0;
        _storageFreeBytes = info['free'] ?? 0;
      });
    } catch (_) {
      // Keep the storage card usable even if a device blocks the native stat call.
    }
  }

  Future<void> _loadStorageVolumes() async {
    try {
      final values = await const MethodChannel('aqua/storage')
          .invokeListMethod<dynamic>('storageVolumes');
      if (!mounted || values == null) return;
      final volumes = values.whereType<Map>().map((value) =>
          Map<String, dynamic>.from(value)).where((value) =>
          value['path'] is String && (value['total'] as num? ?? 0) > 0).toList();
      if (!mounted) return;
      setState(() => _storageVolumes = volumes);
    } catch (_) {
      // Keep the existing internal-storage indicator if this device lacks volume stats.
    }
  }

  Future<void> _refreshStorageVolumes() async {
    await _discoverStorageRoots();
    await _loadStorageInfo();
    await _loadStorageVolumes();
  }

  Color _volumeStatusColor(double used) {
    if (used >= .90) return const Color(0xFFFF5268);
    if (used >= .70) return const Color(0xFFFFC15A);
    return const Color(0xFF35D6B0);
  }

  Widget _storageVolumeDrop(Map<String, dynamic> volume) {
    final path = volume['path'] as String? ?? '';
    final total = (volume['total'] as num?)?.toInt() ?? 0;
    final free = (volume['free'] as num?)?.toInt() ?? 0;
    final used = total <= 0 ? 0.0 : ((total - free) / total).clamp(0.0, 1.0).toDouble();
    final removable = volume['removable'] == true;
    final label = removable ? 'EXTERNAL' : 'INTERNAL';
    final selected = _root.path == path;
    final color = _volumeStatusColor(used);
    return InkWell(
      onTap: path.isEmpty ? null : () {
        final directory = Directory(path);
        setState(() => _root = directory);
        _loadDirectory(directory);
        setState(() => _tab = 1);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 142,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(.12) : Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _accent.withOpacity(.65) : Colors.white.withOpacity(.10)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(
            size: const Size(48, 58),
            painter: _StorageDropPainter(
              fraction: used,
              color: color,
              active: total > 0,
            ),
          ),
          const SizedBox(height: 7),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, letterSpacing: 1.1, color: color, fontWeight: FontWeight.w800)),
          Text('${(used * 100).round()}% used',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          Text('${_formatBytes(total - free)} / ${_formatBytes(total)}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: Colors.white60)),
          Text(removable ? 'SD / USB' : 'Phone',
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
        ]),
      ),
    );
  }

  double get _storageUsedFraction {
    if (_storageTotalBytes <= 0) return 0;
    return ((_storageTotalBytes - _storageFreeBytes) / _storageTotalBytes)
        .clamp(0.0, 1.0);
  }

  Color get _storageStatusColor {
    final used = _storageUsedFraction;
    if (used >= .90) return const Color(0xFFFF5268);
    if (used >= .70) return const Color(0xFFFFC15A);
    return const Color(0xFF35D6B0);
  }

  Future<void> _initializeRecycleBin() async {
    try {
      final support = await getApplicationSupportDirectory();
      final folder = Directory('${support.path}/aqua_recycle_bin');
      await folder.create(recursive: true);
      final index = File('${support.path}/aqua_recycle_bin.json');
      var records = <Map<String, dynamic>>[];
      if (await index.exists()) {
        final decoded = jsonDecode(await index.readAsString());
        if (decoded is List) {
          records = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _recycleDirectory = folder;
        _recycleIndex = index;
        _recycleRecords = records;
      });
      await _expireRecycleRecords();
      _recycleTimer?.cancel();
      _recycleTimer = Timer.periodic(const Duration(minutes: 1), (_) => _expireRecycleRecords());
    } catch (e) {
      _message('Recycle Bin could not be initialized: ' + e.toString());
    }
  }

  Future<void> _saveRecycleRecords() async {
    final index = _recycleIndex;
    if (index == null) return;
    await index.writeAsString(jsonEncode(_recycleRecords), flush: true);
  }

  Future<void> _deleteEntityPermanently(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  bool _isExpiringRecycleRecords = false;

  Future<void> _expireRecycleRecords() async {
    if (_isExpiringRecycleRecords) return;
    _isExpiringRecycleRecords = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final keep = <Map<String, dynamic>>[];
      var changed = false;
      for (final record in List<Map<String, dynamic>>.from(_recycleRecords)) {
        final stage = record['stage'] as String? ?? 'bin';
        final started = (record['stageStartedAt'] as num?)?.toInt() ?? now;
        final lifetime = stage == 'shred'
            ? const Duration(hours: 2).inMilliseconds
            : const Duration(days: 30).inMilliseconds;
        if (now - started >= lifetime) {
          try {
            await _deleteEntityPermanently(record['storedPath'] as String);
            changed = true;
          } catch (_) {
            // Keep recovery metadata so a failed deletion can be retried.
            keep.add(record);
          }
        } else {
          keep.add(record);
        }
      }
      if (changed || keep.length != _recycleRecords.length) {
        if (mounted) {
          setState(() => _recycleRecords = keep);
        } else {
          _recycleRecords = keep;
        }
        await _saveRecycleRecords();
      }
    } finally {
      _isExpiringRecycleRecords = false;
    }
  }

  Future<void> _copyEntityRecursively(FileSystemEntity source, String targetPath) async {
    if (source is File) {
      await source.copy(targetPath);
      return;
    }
    if (source is Directory) {
      final target = Directory(targetPath);
      await target.create(recursive: true);
      await for (final child in source.list(followLinks: false)) {
        final childName = _nameOf(child);
        await _copyEntityRecursively(child, '${target.path}/$childName');
      }
      return;
    }
    throw FileSystemException('Unsupported file-system item', source.path);
  }

  Future<void> _moveEntityToClipboard(FileSystemEntity entity, {required bool move}) async {
    setState(() {
      _clipboardEntity = entity;
      _clipboardMove = move;
    });
    _message(move ? 'Cut: ${_nameOf(entity)}' : 'Copied: ${_nameOf(entity)}');
  }

  Future<void> _pasteClipboard() async {
    final source = _clipboardEntity;
    if (source == null) return;
    final target = '${_current.path}/${_nameOf(source)}';
    if (source.path == target) {
      _message('This item is already in the current folder.');
      return;
    }
    final wasMove = _clipboardMove;
    try {
      await _copyEntityRecursively(source, target);
      if (wasMove) await _deleteEntityPermanently(source.path);
      if (mounted) setState(() { _clipboardEntity = null; _clipboardMove = false; });
      await _loadDirectory(_current);
      _message(wasMove ? 'Moved successfully.' : 'Copied successfully.');
    } catch (e) {
      _message('Copy or move failed: ' + e.toString());
    }
  }

  Future<void> _sendToRecycleBin(FileSystemEntity entity) async {
    final folder = _recycleDirectory;
    if (folder == null) {
      _message('Recycle Bin is not ready yet.');
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storedPath = '${folder.path}/${id}_${_nameOf(entity)}';
    final record = <String, dynamic>{
      'id': id,
      'name': _nameOf(entity),
      'originalPath': entity.path,
      'storedPath': storedPath,
      'stage': 'bin',
      'stageStartedAt': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      // Complete and persist the recovery copy before removing the original.
      await _copyEntityRecursively(entity, storedPath);
      if (await FileSystemEntity.type(storedPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        throw FileSystemException('Recycle copy was not created', storedPath);
      }
      _recycleRecords.add(record);
      try {
        await _saveRecycleRecords();
      } catch (_) {
        _recycleRecords.removeWhere((item) => item['id'] == id);
        rethrow;
      }

      try {
        await _deleteEntityPermanently(entity.path);
        await _loadDirectory(_current);
        _message('Moved to Recycle Bin for 30 days.');
      } catch (deleteError) {
        // The recovery copy is retained and can still be restored.
        await _loadDirectory(_current);
        _message('A recovery copy was saved in Recycle Bin, but the original could not be fully removed: $deleteError');
      }
    } catch (e) {
      final recorded = _recycleRecords.any((item) => item['id'] == id);
      if (!recorded) {
        try {
          await _deleteEntityPermanently(storedPath);
        } catch (_) {}
      }
      _message('Could not safely move item to Recycle Bin: $e');
    }
  }

  Future<void> _restoreRecycleRecord(Map<String, dynamic> record) async {
    try {
      var destination = record['originalPath'] as String;
      final parent = Directory(File(destination).parent.path);
      await parent.create(recursive: true);
      if (await FileSystemEntity.type(destination) != FileSystemEntityType.notFound) {
        final base = destination;
        var suffix = 1;
        do {
          destination = '$base (restored $suffix)';
          suffix++;
        } while (await FileSystemEntity.type(destination) != FileSystemEntityType.notFound);
      }
      final sourcePath = record['storedPath'] as String;
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _copyEntityRecursively(Directory(sourcePath), destination);
      } else {
        await File(sourcePath).copy(destination);
      }
      await _deleteEntityPermanently(sourcePath);
      setState(() => _recycleRecords.removeWhere((item) => item['id'] == record['id']));
      await _saveRecycleRecords();
      _message('File restored.');
      if (_hasStorage) await _loadDirectory(_current);
    } catch (e) {
      _message('Restore failed: ' + e.toString());
    }
  }

  Future<void> _deleteAgainForTwoHours(Map<String, dynamic> record) async {
    final oldStage = record['stage'];
    final oldStarted = record['stageStartedAt'];
    setState(() {
      record['stage'] = 'shred';
      record['stageStartedAt'] = DateTime.now().millisecondsSinceEpoch;
    });
    try {
      await _saveRecycleRecords();
      _message('Moved to 2-hour temporary recovery stage.');
    } catch (e) {
      setState(() {
        record['stage'] = oldStage;
        record['stageStartedAt'] = oldStarted;
      });
      _message('Could not save the recovery timer; item remains in Recycle Bin: $e');
    }
  }

  String _remainingTime(Map<String, dynamic> record) {
    final started = (record['stageStartedAt'] as num?)?.toInt() ?? 0;
    final stage = record['stage'] as String? ?? 'bin';
    final duration = stage == 'shred' ? const Duration(hours: 2) : const Duration(days: 30);
    final remaining = duration - DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(started));
    if (remaining.isNegative) return 'Expiring…';
    if (stage == 'shred') return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
    return '${remaining.inDays}d ${remaining.inHours.remainder(24)}h left';
  }

  Future<void> _discoverStorageRoots() async {
    final found = <String>{'/storage/emulated/0'};
    for (final mountPath in <String>['/storage', '/mnt/media_rw']) {
      try {
        final mount = Directory(mountPath);
        if (!await mount.exists()) continue;
        await for (final entry in mount.list(followLinks: false)) {
          if (entry is! Directory) continue;
          if (entry.path == '/storage/emulated') {
            final internal = Directory('/storage/emulated/0');
            if (await internal.exists()) found.add(internal.path);
          } else if (!entry.path.endsWith('/self') && !entry.path.endsWith('/emulated')) {
            found.add(entry.path);
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _storageRoots = found.toList()..sort());
  }

  Future<void> _loadDirectory(Directory directory) async {
    if (!_hasStorage && !await Permission.manageExternalStorage.isGranted) return;
    try {
      // Read directory entries once; the visible list applies the selected
      // sort once when the Files view is built (avoids sorting twice).
      final entries = await directory.list(followLinks: false).toList();
      if (!mounted) return;
      setState(() {
        _current = directory;
        _items = entries;
        _hasStorage = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _storageMessage = 'Cannot open this folder: ' + e.toString());
    }
  }

  String _nameOf(FileSystemEntity entity) =>
      entity.path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;

  String _extensionOf(FileSystemEntity entity) {
    final name = _nameOf(entity);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Future<void> _loadCategoryFiles(String category) async {
    if (!_hasStorage) return;
    setState(() {
      _fileCategory = category;
      _search = '';
      _categoryScanBusy = true;
      _categoryFiles = <FileSystemEntity>[];
    });
    final found = <FileSystemEntity>[];
    final pending = <Directory>[];
    final seen = <String>{};
    for (final path in _storageRoots) {
      if (await Directory(path).exists()) pending.add(Directory(path));
    }
    if (pending.isEmpty && await _root.exists()) pending.add(_root);
    var visited = 0;
    while (pending.isNotEmpty && visited < 20000) {
      final directory = pending.removeLast();
      final normalized = directory.path.toLowerCase();
      if (!seen.add(normalized)) continue;
      if (normalized.contains('/android/data') ||
          normalized.contains('/android/obb') ||
          normalized.contains('/.') ||
          normalized.contains('/aqua_recycle_bin') ||
          normalized.contains('/vault')) continue;
      try {
        await for (final entity in directory.list(followLinks: false)) {
          visited++;
          if (entity is Directory) {
            final name = _nameOf(entity);
            if (!name.startsWith('.') && !entity.path.toLowerCase().contains('/android/data') &&
                !entity.path.toLowerCase().contains('/android/obb')) {
              pending.add(entity);
            }
          } else if (entity is File && _matchesCategory(entity)) {
            found.add(entity);
          }
          if (visited >= 20000) break;
        }
      } catch (_) {
        // Ignore folders Android or the storage provider does not expose.
      }
    }
    if (!mounted) return;
    setState(() {
      _categoryFiles = found;
      _categoryScanBusy = false;
      _tab = 1;
    });
  }

  bool _matchesCategory(FileSystemEntity item) {
    if (_fileCategory == 'All files') return true;
    if (item is Directory) return false;
    final ext = _extensionOf(item);
    switch (_fileCategory) {
      case 'Images':
        return <String>{'jpg','jpeg','png','gif','webp','bmp','heic','heif','tif','tiff'}.contains(ext);
      case 'Videos':
        return <String>{'mp4','mkv','mov','webm','3gp','avi','m4v'}.contains(ext);
      case 'Audio':
        return <String>{'mp3','wav','m4a','aac','flac','ogg','opus','wma'}.contains(ext);
      case 'Documents':
        return <String>{'pdf','doc','docx','txt','rtf','xls','xlsx','ppt','pptx','csv'}.contains(ext);
      case 'APKs':
        return ext == 'apk';
      case 'Downloads':
        return item.path.toLowerCase().contains('/download');
      default:
        return true;
    }
  }

  List<FileSystemEntity> get _visibleItems {
    final source = _fileCategory == 'All files' ? _items : _categoryFiles;
    final items = source.where((item) =>
      (_showHidden || !_nameOf(item).startsWith('.')) &&
      _nameOf(item).toLowerCase().contains(_search.toLowerCase()) &&
      _matchesCategory(item)).toList();
    items.sort((a, b) {
      int result;
      switch (_sortMode) {
        case 'Size':
          int sizeOf(FileSystemEntity item) {
            try { return item is File ? item.lengthSync() : 0; } catch (_) { return 0; }
          }
          result = sizeOf(a).compareTo(sizeOf(b));
          break;
        case 'Date':
          DateTime dateOf(FileSystemEntity item) {
            try { return item.statSync().modified; } catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
          }
          result = dateOf(a).compareTo(dateOf(b));
          break;
        case 'Type':
          result = _extensionOf(a).compareTo(_extensionOf(b));
          break;
        default:
          result = _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      }
      if (_fileCategory == 'All files' && _foldersFirst && a is Directory != (b is Directory)) {
        result = a is Directory ? -1 : 1;
      }
      return _sortDescending ? -result : result;
    });
    return items;
  }

  Future<void> _findDuplicates() async {
    if (_scanningDuplicates || !_hasStorage) return;
    setState(() => _scanningDuplicates = true);
    _message('Scanning storage for identical files…');
    try {
      final bySize = <int, List<File>>{};
      // Search every discovered mounted volume, not only the currently open
      // folder. This makes duplicates on an SD card visible alongside phone
      // storage while keeping the scan bounded for low-memory devices.
      final pending = <Directory>[
        for (final path in _storageRoots) Directory(path),
      ];
      if (pending.isEmpty) pending.add(_root);
      final seenDirectories = <String>{};
      var visited = 0;
      while (pending.isNotEmpty && visited < 15000) {
        final directory = pending.removeLast();
        if (!seenDirectories.add(directory.path)) continue;
        try {
          await for (final entity in directory.list(followLinks: false)) {
            if (entity is Directory) {
              final path = entity.path.replaceAll('\\\\', '/');
              final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
              if (!name.startsWith('.') &&
                  !path.contains('/Android/data/') &&
                  !path.contains('/Android/obb/') &&
                  !path.contains('/aqua_recycle_bin/') &&
                  !path.contains('/aqua_encrypted_vault/')) {
                pending.add(entity);
              }
            } else if (entity is File) {
              visited++;
              try {
                final size = await entity.length();
                if (size > 0) (bySize[size] ??= <File>[]).add(entity);
              } catch (_) {}
            }
            if (visited >= 15000) break;
          }
        } catch (_) {
          // A removable volume can disappear or contain folders Android
          // does not expose; continue scanning the remaining directories.
        }
      }
      final byHash = <String, List<File>>{};
      for (final candidates in bySize.values.where((items) => items.length > 1)) {
        for (final file in candidates) {
          try {
            final digest = await sha256.bind(file.openRead()).first;
            (byHash[digest.toString()] ??= <File>[]).add(file);
          } catch (_) {}
        }
      }
      final groups = byHash.values.where((items) => items.length > 1).toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF102B38),
          title: const Text('Identical files'),
          content: SizedBox(
            width: double.maxFinite,
            child: groups.isEmpty
              ? Text('No byte-identical duplicate files found in the scanned area. Scanned up to $visited files.')
              : ListView(
                  shrinkWrap: true,
                  children: groups.map((group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${group.length} identical copies',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        ...group.map((file) => Text(file.path,
                          style: const TextStyle(fontSize: 11, color: Colors.white70))),
                      ],
                    ),
                  )).toList(),
                ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      _message('Duplicate scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanningDuplicates = false);
    }
  }

  Future<void> _openAdvancedTools({bool openVaultOnStart = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AquaAdvancedTools(
        targetDirectory: _current,
        accent: _accent,
        openVaultOnStart: openVaultOnStart,
      ),
    ));
    if (_hasStorage) await _loadDirectory(_current);
  }

  int? _secretGesturePointer;
  final List<Offset> _secretGesturePoints = <Offset>[];
  int _secretBubbleTapCount = 0;
  Timer? _secretBubbleTapTimer;

  void _onSecretBubbleTap() {
    if (_tab != 0 || !mounted) return;
    _secretBubbleTapCount++;
    _secretBubbleTapTimer?.cancel();
    _secretBubbleTapTimer = Timer(const Duration(milliseconds: 1400), () {
      _secretBubbleTapCount = 0;
    });
    if (_secretBubbleTapCount >= 3) {
      _secretBubbleTapCount = 0;
      _secretBubbleTapTimer?.cancel();
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_openAdvancedTools(openVaultOnStart: true));
    }
  }

  void _onSecretGestureDown(PointerDownEvent event) {
    if (_tab != 0 || _secretGesturePointer != null) return;
    _secretGesturePointer = event.pointer;
    _secretGesturePoints
      ..clear()
      ..add(event.localPosition);
    setState(() {});
  }

  void _onSecretGestureMove(PointerMoveEvent event) {
    if (event.pointer != _secretGesturePointer) return;
    final last = _secretGesturePoints.isEmpty ? null : _secretGesturePoints.last;
    if (last == null || (event.localPosition - last).distance >= 3) {
      _secretGesturePoints.add(event.localPosition);
      if (mounted) setState(() {});
    }
  }

  Future<void> _onSecretGestureUp(PointerUpEvent event) async {
    if (event.pointer != _secretGesturePointer) return;
    _secretGesturePoints.add(event.localPosition);
    final accepted = _isFreehandBox(_secretGesturePoints);
    _secretGesturePointer = null;
    _secretGesturePoints.clear();
    if (mounted) setState(() {});
    if (!accepted || _tab != 0 || !mounted) return;
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    await _openAdvancedTools(openVaultOnStart: true);
  }

  void _onSecretGestureCancel(PointerCancelEvent event) {
    if (event.pointer != _secretGesturePointer) return;
    _secretGesturePointer = null;
    _secretGesturePoints.clear();
    if (mounted) setState(() {});
  }

  bool _isFreehandBox(List<Offset> points) {
    if (points.length < 12) return false;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var pathLength = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
      if (i > 0) pathLength += (p - points[i - 1]).distance;
    }
    final width = maxX - minX;
    final height = maxY - minY;
    final side = math.max(width, height);
    if (math.min(width, height) < 56 || side == 0) return false;
    final ratio = width / height;
    if (ratio < .62 || ratio > 1.6) return false;
    final startGap = (points.first - points.last).distance;
    if (startGap > math.max(30.0, side * .28)) return false;
    if (pathLength < (width + height) * 1.25) return false;

    final cornerRadius = side * .38;
    final corners = <Offset>[
      Offset(minX, minY), Offset(maxX, minY),
      Offset(maxX, maxY), Offset(minX, maxY),
    ];
    for (final corner in corners) {
      if (!points.any((p) => (p - corner).distance <= cornerRadius)) return false;
    }
    return true;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF102B38),
        title: const Text('New folder'),
        content: TextField(controller: controller, autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Directory(_current.path + Platform.pathSeparator + name).create();
      await _loadDirectory(_current);
    } catch (e) {
      _message('Could not create folder: ' + e.toString());
    }
  }

  Future<void> _rename(FileSystemEntity entity) async {
    final controller = TextEditingController(text: _nameOf(entity));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF102B38),
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _nameOf(entity)) return;
    try {
      final target = entity.parent.path + Platform.pathSeparator + name;
      if (entity is File) {
        await entity.rename(target);
      } else if (entity is Directory) {
        await entity.rename(target);
      }
      await _loadDirectory(_current);
    } catch (e) {
      _message('Rename failed: ' + e.toString());
    }
  }

  Future<void> _shareEntity(FileSystemEntity entity) async {
    if (entity is! File) {
      _message('Sharing folders is not supported yet. Select an individual file.');
      return;
    }
    try {
      await Share.shareXFiles([XFile(entity.path)], text: _nameOf(entity));
    } catch (e) {
      _message('Could not share this file: ' + e.toString());
    }
  }

  Future<void> _showDetails(FileSystemEntity entity) async {
    var size = 'Folder';
    if (entity is File) {
      try { size = _formatBytes(await entity.length()); } catch (_) { size = 'Unavailable'; }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF102B38),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_nameOf(entity), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(entity.path, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 8),
          Text('Size: ' + size),
          const SizedBox(height: 18),
        ]),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2) + ' GB';
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<bool> _unlockFolderIfNeeded(Directory directory) async {
    final key = 'aqua_folder_pin_${sha256.convert(utf8.encode(directory.path))}';
    final stored = await _folderPinStore.read(key: key);
    if (stored == null) return true;
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlock ${_nameOf(directory)}'),
        content: TextField(controller: controller, obscureText: true,
          keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Folder PIN')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    if (pin == null) return false;
    final digest = sha256.convert(utf8.encode('${directory.path}:$pin')).toString();
    if (digest != stored) { _message('Incorrect folder PIN.'); return false; }
    return true;
  }

  Future<void> _setFolderPin(Directory directory) async {
    final key = 'aqua_folder_pin_${sha256.convert(utf8.encode(directory.path))}';
    final stored = await _folderPinStore.read(key: key);
    if (stored != null) {
      final controller = TextEditingController();
      final pin = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove PIN • ${_nameOf(directory)}'),
          content: TextField(controller: controller, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Current PIN')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Remove lock')),
          ],
        ),
      );
      if (pin == null) return;
      if (sha256.convert(utf8.encode('${directory.path}:$pin')).toString() != stored) {
        _message('Incorrect folder PIN.'); return;
      }
      await _folderPinStore.delete(key: key);
      _message('Folder PIN removed.');
      return;
    }
    final first = TextEditingController();
    final second = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Protect ${_nameOf(directory)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: first, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Create PIN (6+ digits)')),
          TextField(controller: second, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confirm PIN')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, first.text), child: const Text('Protect')),
        ],
      ),
    );
    if (pin == null) return;
    if (pin.length < 6 || pin != second.text) {
      _message('PINs must match and contain at least 6 characters.'); return;
    }
    await _folderPinStore.write(key: key,
      value: sha256.convert(utf8.encode('${directory.path}:$pin')).toString());
    _message('In-app PIN gate enabled. This does not encrypt the folder or block access from other apps.');
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      if (await _unlockFolderIfNeeded(entity)) await _loadDirectory(entity);
      return;
    }
    if (entity is! File) {
      await _showDetails(entity);
      return;
    }
    final ext = _extensionOf(entity);
    const images = <String>{'jpg','jpeg','png','gif','webp','bmp','heic','heif','tif','tiff'};
    if (images.contains(ext)) {
      await _viewImageFile(entity);
      return;
    }
    const audio = <String>{'mp3','wav','m4a','aac','flac','ogg','opus','wma'};
    const video = <String>{'mp4','mkv','mov','webm','3gp','avi','m4v'};
    if (audio.contains(ext)) {
      await _playAudioFile(entity);
      return;
    }
    if (video.contains(ext)) {
      await _playVideoFile(entity);
      return;
    }
    try {
      final result = await OpenFilex.open(entity.path);
      if (result.type != ResultType.done) {
        _message(result.message.isNotEmpty
            ? result.message
            : 'No compatible document viewer is installed for this file.');
        await _showDetails(entity);
      }
    } catch (e) {
      _message('Could not open file: $e');
      await _showDetails(entity);
    }
  }

  Future<void> _viewImageFile(File file) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF050B12),
        child: Scaffold(
          backgroundColor: const Color(0xFF050B12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF050B12),
            foregroundColor: Colors.white,
            title: Text(
              file.uri.pathSegments.isEmpty ? 'Image' : file.uri.pathSegments.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Close image',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 6.0,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56),
                      SizedBox(height: 12),
                      Text(
                        'This image could not be displayed.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playAudioFile(File file) async {
    try {
      await _mediaAudioPlayer.stop();
      await _mediaAudioPlayer.setSourceDeviceFile(file.path);
      await _mediaAudioPlayer.resume();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF102B38),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: StreamBuilder<PlayerState>(
              stream: _mediaAudioPlayer.onPlayerStateChanged,
              initialData: PlayerState.playing,
              builder: (context, snapshot) {
                final playing = snapshot.data == PlayerState.playing;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.graphic_eq_rounded, color: _accent, size: 44),
                  const SizedBox(height: 10),
                  Text(_nameOf(file), maxLines: 2, textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                      iconSize: 38,
                      onPressed: () async {
                        if (playing) {
                          await _mediaAudioPlayer.pause();
                        } else {
                          await _mediaAudioPlayer.resume();
                        }
                      },
                      icon: Icon(playing ? Icons.pause_circle : Icons.play_circle,
                        color: _accent),
                    ),
                    IconButton(
                      iconSize: 30,
                      onPressed: () async {
                        await _mediaAudioPlayer.stop();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  ]),
                ]);
              },
            ),
          ),
        ),
      );
    } catch (e) {
      _message('Audio playback failed: $e');
    }
  }

  Future<void> _playVideoFile(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.play();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF102B38),
          title: Text(_nameOf(file), maxLines: 1, overflow: TextOverflow.ellipsis),
          content: AspectRatio(
            aspectRatio: controller.value.aspectRatio > 0
                ? controller.value.aspectRatio : 16 / 9,
            child: VideoPlayer(controller),
          ),
          actions: [
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextButton.icon(
                onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(value.isPlaying ? 'Pause' : 'Play'),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      _message('Video playback failed: $e');
    } finally {
      await controller.dispose();
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android 11+ sends the user to a special Settings screen for
      // MANAGE_EXTERNAL_STORAGE. On the first launch _hasStorage is false,
      // so checking only when it is already true leaves the app stuck after
      // the user grants access. Re-check the permission whenever we resume.
      unawaited(_syncStoragePermissionAfterResume());
    }
  }

  Future<void> _syncStoragePermissionAfterResume() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.manageExternalStorage.status;
      if (!mounted) return;
      if (status.isGranted) {
        final newlyGranted = !_hasStorage;
        if (newlyGranted) {
          setState(() {
            _hasStorage = true;
            _storageMessage = 'All files access is enabled.';
          });
        }
        await _loadStorageInfo();
        await _discoverStorageRoots();
        await _loadStorageVolumes();
        if (newlyGranted) {
          await _loadDirectory(_root);
        } else {
          await _refreshStorageVolumes();
        }
      } else if (_hasStorage) {
        setState(() {
          _hasStorage = false;
          _storageMessage = 'Storage access is not enabled. Tap Check permission to grant access again.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _storageMessage = 'Could not re-check storage access: $error');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waterSensor?.cancel();
    _recycleTimer?.cancel();
    _secretBubbleTapTimer?.cancel();
    _mediaAudioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _light ? const Color(0xFFEAF5F7) : const Color(0xFF04141E);
    final foreground = _light ? const Color(0xFF102B38) : Colors.white;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _light ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: base,
        colorScheme: ColorScheme.fromSeed(seedColor: _accent,
          brightness: _light ? Brightness.light : Brightness.dark),
      ),
      home: _showSplash
          ? const BubbleSplashScreen()
          : Scaffold(
        body: Listener(
          onPointerDown: (event) {
            _bubbleFieldKey.currentState?.handlePointerDown(event.localPosition);
            _onSecretGestureDown(event);
          },
          onPointerMove: (event) {
            _bubbleFieldKey.currentState?.handlePointerMove(event.localPosition);
            _onSecretGestureMove(event);
          },
          onPointerUp: (event) {
            _bubbleFieldKey.currentState?.handlePointerUp();
            _onSecretGestureUp(event);
          },
          onPointerCancel: (event) {
            _bubbleFieldKey.currentState?.handlePointerUp();
            _onSecretGestureCancel(event);
          },
          child: Stack(children: [
          Positioned.fill(child: AquaBackdrop(reduced: _performance)),
          if (_animations)
            Positioned.fill(child: BubbleField(
              key: _bubbleFieldKey,
              accent: _accent,
              gravityEnabled: _gravity,
              reduced: _performance,
              speed: _bubbleSpeed,
              onBubbleTap: _onSecretBubbleTap,
            )),
          SafeArea(child: Column(children: [
            _header(foreground),
            Expanded(child: IndexedStack(index: _tab, children: [
              _home(foreground),
              _files(foreground),
              _settings(foreground),
              _recycleBin(foreground),
            ])),
            _bottomNav(foreground),
          ])),
          if (_secretGesturePoints.length > 1)
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: _SecretBoxGesturePainter(_secretGesturePoints),
            ))),
        ])),
      ),
    );
  }

  Widget _header(Color foreground) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 18, 10),
    child: Row(children: [
      Container(width: 43, height: 43,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(colors: [_accent.withOpacity(.9), _accent.withOpacity(.35)]),
          boxShadow: [BoxShadow(color: _accent.withOpacity(.22), blurRadius: 18)],
        ),
        child: const Icon(Icons.water_drop_rounded, color: Color(0xFF06202A))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BUBBLE', style: TextStyle(color: foreground, fontSize: 18,
          fontWeight: FontWeight.w900, letterSpacing: 3)),
        Text('FILE MANAGER', style: TextStyle(color: foreground.withOpacity(.55),
          fontSize: 9, letterSpacing: 2.4)),
      ])),
      IconButton(onPressed: () => setState(() => _tab = 2),
        icon: Icon(Icons.tune_rounded, color: foreground.withOpacity(.8))),
    ]),
  );

  Widget _home(Color foreground) => ListView(
    padding: const EdgeInsets.fromLTRB(19, 8, 19, 22),
    children: [
      const SizedBox(height: 10),
      Text('Your space,', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w300, color: foreground)),
      Text('beautifully organized.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: foreground)),
      const SizedBox(height: 20),
      _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('STORAGE DROPS', style: TextStyle(fontSize: 10, letterSpacing: 1.7, color: Colors.white60))),
          IconButton(
            tooltip: 'Refresh connected storage',
            visualDensity: VisualDensity.compact,
            onPressed: _hasStorage ? _refreshStorageVolumes : _requestStorage,
            icon: Icon(Icons.refresh_rounded, color: _accent, size: 19),
          ),
        ]),
        if (!_hasStorage)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Allow storage access to show your storage drops.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
          )
        else if (_storageVolumes.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _storageVolumes.map((volume) => Padding(
                padding: const EdgeInsets.only(right: 9),
                child: _storageVolumeDrop(volume),
              )).toList(),
            ),
          )
        else
          Row(children: [
            CustomPaint(
              size: const Size(48, 58),
              painter: _StorageDropPainter(
                fraction: _storageUsedFraction,
                color: _storageStatusColor,
                active: _storageTotalBytes > 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _storageTotalBytes > 0
                ? '${_formatBytes(_storageTotalBytes - _storageFreeBytes)} used • ${_formatBytes(_storageTotalBytes)} total'
                : 'Internal storage is connected',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            )),
          ]),
      ])),
      const SizedBox(height: 20),
      const Text('EXPLORE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white60)),
      const SizedBox(height: 11),
      GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 11, mainAxisSpacing: 11,
        childAspectRatio: 1.65,
        children: [
          _category('All files', Icons.folder_copy_rounded),
          _category('Images', Icons.image_rounded),
          _category('Videos', Icons.movie_rounded),
          _category('Audio', Icons.headphones_rounded),
          _category('Documents', Icons.description_rounded),
          _category('Downloads', Icons.download_rounded),
          _category('Places', Icons.location_on_rounded),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openAdvancedTools(openVaultOnStart: true),
            child: _glass(child: Row(children: [
              Icon(Icons.lock_rounded, color: _accent, size: 25),
              const SizedBox(width: 10),
              const Expanded(child: Text('Secret Vault', style: TextStyle(fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
            ])),
          ),
        ],
      ),
      const SizedBox(height: 14),
      InkWell(onTap: _openAdvancedTools, borderRadius: BorderRadius.circular(22),
        child: _glass(child: Row(children: [
          Icon(Icons.auto_awesome_rounded, color: _accent, size: 27),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Advanced tools', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Vault • ZIP • GPS maps • Smart Cleanup • SD / USB', style: TextStyle(fontSize: 10, color: Colors.white60)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        ]))),
      const SizedBox(height: 17),
      _glass(child: Row(children: [
        Icon(Icons.bubble_chart_rounded, color: _accent, size: 28),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Living water bubbles', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Touch the open background to pop a bubble',
            style: TextStyle(fontSize: 11, color: Colors.white60)),
        ])),
      ])),
    ],
  );

  Widget _category(String title, IconData icon) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () {
      if (title == 'Places') {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LocationAlbumsPage(
            targetDirectory: _root,
            accent: _accent,
          ),
        ));
      } else if (title == 'All files') {
        setState(() { _fileCategory = title; _search = ''; _tab = 1; });
        _loadDirectory(_root);
      } else {
        _loadCategoryFiles(title);
      }
    },
    child: _glass(child: Row(children: [
      Icon(icon, color: _accent, size: 25),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
    ])),
  );

  Widget _files(Color foreground) {
    final visibleItems = _visibleItems;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(19, 8, 19, 10),
        child: Row(children: [
          Expanded(child: Text(_fileCategory, style: TextStyle(fontSize: 27,
            fontWeight: FontWeight.w800, color: foreground))),
          IconButton(onPressed: _scanningDuplicates ? null : _findDuplicates, tooltip: 'Find identical files', icon: Icon(Icons.copy_all_rounded, color: _accent)),
          if (_clipboardEntity != null)
            IconButton(onPressed: _pasteClipboard, tooltip: 'Paste', icon: Icon(Icons.content_paste_rounded, color: _accent)),
          IconButton(onPressed: _createFolder, tooltip: 'New folder', icon: Icon(Icons.create_new_folder_rounded, color: _accent)),
          IconButton(onPressed: () => _loadDirectory(_root), tooltip: 'Home folder', icon: Icon(Icons.home_rounded, color: _accent)),
        ]),
      ),
      if (!_hasStorage)
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: _glass(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_off_rounded, color: _accent, size: 42),
            const SizedBox(height: 12),
            const Text('Storage permission needed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_storageMessage, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _checkingPermission ? null : _requestStorage,
              icon: const Icon(Icons.security_rounded),
              label: Text(_checkingPermission ? 'Checking…' : 'Allow storage access')),
          ])),
        )))
      else ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 19), child: _glass(
          child: Column(children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search this folder', prefixIcon: Icon(Icons.search_rounded),
                border: InputBorder.none, isDense: true),
              onChanged: (value) => setState(() => _search = value),
            ),
            Row(children: [
              IconButton(onPressed: () {
                if (_current.path != _root.path) _loadDirectory(_current.parent);
              }, icon: const Icon(Icons.arrow_back_rounded, size: 19)),
              Expanded(child: Text(_current.path, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white60))),
              PopupMenuButton<String>(
                tooltip: 'Switch storage volume',
                icon: Icon(Icons.sd_storage_rounded, color: _accent, size: 19),
                onSelected: (path) {
                  final volume = Directory(path);
                  setState(() => _root = volume);
                  _loadDirectory(volume);
                },
                itemBuilder: (context) => _storageRoots.map((path) =>
                  PopupMenuItem(value: path, child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              ),
              PopupMenuButton<String>(
                tooltip: 'File display method',
                onSelected: (value) => setState(() => _viewMode = value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'List', child: Text('List view')),
                  PopupMenuItem(value: 'Compact', child: Text('Compact view')),
                  PopupMenuItem(value: 'Grid', child: Text('Grid view')),
                  PopupMenuItem(value: 'Large thumbnails', child: Text('Large thumbnails')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                  child: Icon(Icons.grid_view_rounded, color: _accent, size: 19),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort files',
                onSelected: (value) => setState(() {
                  if (value == 'Folders first' || value == 'No folder priority') {
                    _foldersFirst = value == 'Folders first';
                  } else if (value == 'Ascending' || value == 'Descending') {
                    _sortDescending = value == 'Descending';
                  } else {
                    _sortMode = value;
                  }
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Name', child: Text('Sort by name')),
                  PopupMenuItem(value: 'Size', child: Text('Sort by size')),
                  PopupMenuItem(value: 'Date', child: Text('Sort by date')),
                  PopupMenuItem(value: 'Type', child: Text('Sort by type')),
                  PopupMenuItem(value: 'Ascending', child: Text('Ascending')),
                  PopupMenuItem(value: 'Descending', child: Text('Descending')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'Folders first', child: Text('Folders first')),
                  PopupMenuItem(value: 'No folder priority', child: Text('No folder priority')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('Sort: $_sortMode ${_sortDescending ? '↓' : '↑'}', style: TextStyle(fontSize: 10, color: _accent)),
                ),
              ),
            ]),
          ]),
        )),
        const SizedBox(height: 8),
        Expanded(child: _categoryScanBusy
          ? const Center(child: CircularProgressIndicator())
          : visibleItems.isEmpty
          ? const Center(child: Text('No matching files found', style: TextStyle(color: Colors.white54)))
          : _viewMode == 'Grid' || _viewMode == 'Large thumbnails'
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _viewMode == 'Large thumbnails' ? 2 : 3,
                crossAxisSpacing: 9, mainAxisSpacing: 9,
                childAspectRatio: _viewMode == 'Large thumbnails' ? .82 : .88,
              ),
              itemCount: visibleItems.length,
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                final isFolder = item is Directory;
                return InkWell(
                  onTap: () => _openEntity(item),
                  borderRadius: BorderRadius.circular(17),
                  child: _glass(child: Column(children: [
                    Expanded(child: isFolder
                      ? Icon(Icons.folder_rounded, color: _accent, size: 54)
                      : MediaThumbnail(key: ValueKey(item.path), path: item.path, accent: _accent, size: _viewMode == 'Large thumbnails' ? 126 : 88)),
                    Padding(padding: const EdgeInsets.fromLTRB(6, 5, 6, 7),
                      child: Text(_nameOf(item), maxLines: 2, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                  ])),
                );
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              itemCount: visibleItems.length,
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                final isFolder = item is Directory;
                return Padding(
                  padding: EdgeInsets.only(bottom: _viewMode == 'Compact' ? 3 : 7),
                  child: _glass(child: Row(children: [
                    isFolder
                      ? Icon(Icons.folder_rounded, color: _accent, size: 25)
                      : InkWell(
                          onTap: () => _openEntity(item),
                          child: MediaThumbnail(
                            key: ValueKey(item.path),
                            path: item.path,
                            accent: _accent,
                            size: _viewMode == 'Compact' ? 34 : 50,
                          ),
                        ),
                    SizedBox(width: _viewMode == 'Compact' ? 7 : 11),
                    Expanded(child: InkWell(
                      onTap: () => _openEntity(item),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_nameOf(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(isFolder ? 'Folder' : 'File',
                          style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      ]),
                    )),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') _rename(item);
                        if (value == 'details') _showDetails(item);
                        if (value == 'copy') _moveEntityToClipboard(item, move: false);
                        if (value == 'cut') _moveEntityToClipboard(item, move: true);
                        if (value == 'delete') _sendToRecycleBin(item);
                        if (value == 'share') _shareEntity(item);
                        if (value == 'folder_pin' && item is Directory) _setFolderPin(item);
                      },
                      itemBuilder: (context) => [
                        if (item is Directory) const PopupMenuItem(value: 'folder_pin', child: Text('Set / remove in-app Folder PIN')),
                        const PopupMenuItem(value: 'copy', child: Text('Copy')),
                        PopupMenuItem(value: 'cut', child: Text('Cut')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Move to Recycle Bin')),
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuItem(value: 'details', child: Text('Properties')),
                      ],
                    ),
                  ])),
                );
              },
            )),
      ],
    ]);
  }

  Widget _recycleBin(Color foreground) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(19, 10, 19, 22),
      children: [
        Text('Recycle Bin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: foreground)),
        const SizedBox(height: 8),
        const Text('Items stay here for 30 days. Choosing Delete again starts a separate 2-hour recovery period.',
          style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.4)),
        const SizedBox(height: 14),
        if (_recycleRecords.isEmpty)
          _glass(child: const Text('Recycle Bin is empty.', style: TextStyle(color: Colors.white70)))
        else ..._recycleRecords.map((record) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record['name'] as String? ?? 'File', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text((record['stage'] == 'shred' ? 'Temporary recovery • ' : 'Recycle Bin • ') + _remainingTime(record),
              style: TextStyle(fontSize: 11, color: _accent)),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () => _restoreRecycleRecord(record), child: const Text('Restore')),
              const Spacer(),
              if (record['stage'] != 'shred')
                TextButton(onPressed: () => _deleteAgainForTwoHours(record), child: const Text('Delete again')),
            ]),
          ])),
        )),
      ],
    );
  }

  Widget _settings(Color foreground) => ListView(
    padding: const EdgeInsets.fromLTRB(19, 10, 19, 22),
    children: [
      Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: foreground)),
      const SizedBox(height: 17),
      _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ACCENT COLOR', style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: Colors.white60)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(aquaAccents.length, (i) =>
          GestureDetector(onTap: () => setState(() => _theme = i),
            child: AnimatedContainer(duration: const Duration(milliseconds: 180),
              width: 43, height: 43,
              decoration: BoxDecoration(shape: BoxShape.circle, color: aquaAccents[i],
                border: Border.all(color: _theme == i ? Colors.white : Colors.transparent, width: 3),
                boxShadow: [BoxShadow(color: aquaAccents[i].withOpacity(.25), blurRadius: 13)]),
              child: _theme == i ? const Icon(Icons.check_rounded, color: Color(0xFF06202A)) : null))),
        ),
      ])),
      const SizedBox(height: 12),
      _switchTile('Show hidden files', 'Include dot-prefixed files and folders', _showHidden,
        (v) => setState(() => _showHidden = v)),
      _switchTile('Gravity bubbles', 'Move with your phone tilt sensor', _gravity,
        (v) => setState(() => _gravity = v)),
      _switchTile('Bubbles', 'Show or hide floating bubbles and bubble effects', _animations,
        (v) => setState(() => _animations = v)),
      _switchTile('Water', 'Show or hide the liquid layer inside every glass card', _waterEnabled,
        (v) => setState(() => _waterEnabled = v)),
      _switchTile('Performance mode', 'Use fewer bubbles and less motion work', _performance,
        (v) => setState(() => _performance = v)),
      const SizedBox(height: 10),
      _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('BUBBLE MOVEMENT SPEED',
            style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white60))),
          Text('${_bubbleSpeed.toStringAsFixed(1)}×',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
        ]),
        Slider(
          value: _bubbleSpeed.clamp(.1, 3.0),
          min: .1,
          max: 3.0,
          // Continuous slider: users can choose any speed, not fixed steps.
          activeColor: _accent,
          onChanged: (value) => setState(() => _bubbleSpeed = value),
        ),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0.1×  Very slow', style: TextStyle(fontSize: 10, color: Colors.white54)),
          Text('3.0×  Very fast', style: TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
      ])),
      _switchTile('Light appearance', 'Switch the interface brightness', _light,
        (v) => setState(() => _light = v)),
      const SizedBox(height: 12),
      _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('STORAGE ACCESS', style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: Colors.white60)),
        const SizedBox(height: 8),
        Text(_storageMessage, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Align(alignment: Alignment.centerRight,
          child: TextButton(onPressed: _requestStorage, child: const Text('Check permission'))),
      ])),
      const SizedBox(height: 12),
      _glass(child: const Text(
        'Bubble File Manager • Development build\n'
        'Includes storage browsing, file operations, bubble physics, two-stage Recycle Bin, hidden files and SHA-256 duplicate scanning. '
        'Advanced Tools add encrypted Vault, ZIP, selected-photo GPS maps, removable-storage file import and cleanup suggestions. '
        'Automatic face similarity albums still require a bundled offline embedding model and validation on real devices.',
        style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.55))),
    ],
  );

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
    Padding(padding: const EdgeInsets.only(bottom: 9), child: _glass(child: SwitchListTile(
      contentPadding: EdgeInsets.zero, value: value, onChanged: onChanged,
      activeColor: _accent, title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white54)),
    )));

  Widget _glass({required Widget child}) {
    final radius = BorderRadius.circular(23);
    final content = Stack(
      children: [
        Padding(padding: const EdgeInsets.all(15), child: Material(
          color: Colors.transparent, child: child)),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(
          painter: _LiquidSurfacePainter(
            accent: _accent,
            tilt: _waterTilt,
            enabled: _gravity && _waterEnabled,
          ),
        ))),
      ],
    );
    // Keep the water layer lightweight in Performance mode; blur is optional.
    if (_performance) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.075),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withOpacity(.15), width: 1),
          ),
          child: content,
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(.14), Colors.white.withOpacity(.045)]),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withOpacity(.17), width: 1),
            boxShadow: [BoxShadow(color: _accent.withOpacity(.055), blurRadius: 24)],
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _bottomNav(Color foreground) => Padding(
    padding: const EdgeInsets.fromLTRB(19, 7, 19, 11),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: _performance ? 0 : 22, sigmaY: _performance ? 0 : 22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xCC0C2835),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(.15)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _navItem('Home', Icons.water_drop_rounded, 0),
            _navItem('Files', Icons.folder_rounded, 1),
            _navItem('Settings', Icons.settings_rounded, 2),
            _navItem('Bin', Icons.delete_outline_rounded, 3),
          ]),
        ),
      ),
    ),
  );

  Widget _navItem(String label, IconData icon, int index) => InkWell(
    onTap: () => setState(() => _tab = index),
    borderRadius: BorderRadius.circular(17),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _tab == index ? _accent : Colors.white54),
        Text(label, style: TextStyle(fontSize: 10,
          color: _tab == index ? _accent : Colors.white54, fontWeight: FontWeight.w600)),
      ])),
  );
}

class BubbleSplashScreen extends StatefulWidget {
  const BubbleSplashScreen({super.key});

  @override
  State<BubbleSplashScreen> createState() => _BubbleSplashScreenState();
}

class _BubbleSplashScreenState extends State<BubbleSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF041C25),
      body: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) {
          final t = _motion.value * math.pi * 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -.12),
                    radius: 1.15,
                    colors: [Color(0xFF0B4650), Color(0xFF062A34), Color(0xFF03151E)],
                  ),
                ),
              ),
              for (var i = 0; i < 9; i++)
                Positioned(
                  left: (i * 47.0 + 18) % MediaQuery.sizeOf(context).width,
                  top: (MediaQuery.sizeOf(context).height *
                          ((i / 9 + _motion.value * (i.isEven ? 1 : -1)) % 1))
                      .clamp(0.0, MediaQuery.sizeOf(context).height),
                  child: Transform.translate(
                    offset: Offset(math.sin(t + i) * 13, 0),
                    child: Container(
                      width: 9 + (i % 4) * 7,
                      height: 9 + (i % 4) * 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF9CFFF4).withOpacity(.10 + (i % 3) * .035),
                        border: Border.all(color: const Color(0xFF9CFFF4).withOpacity(.34)),
                        boxShadow: [BoxShadow(color: const Color(0xFF54F5E7).withOpacity(.15), blurRadius: 12)],
                      ),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: Offset(0, math.sin(t) * 7),
                      child: Transform.scale(
                        scale: 1 + math.sin(t * .5) * .025,
                        child: SizedBox(
                          width: 230,
                          height: 205,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 196,
                                height: 145,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(0xFFB9FFF5).withOpacity(.46),
                                      const Color(0xFF4DDDD5).withOpacity(.16),
                                      const Color(0xFFB9FFF5).withOpacity(.30),
                                    ],
                                  ),
                                  border: Border.all(color: const Color(0xFF8DFFF4), width: 3),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF36F5E6).withOpacity(.34), blurRadius: 35, spreadRadius: 3),
                                    BoxShadow(color: Colors.white.withOpacity(.10), blurRadius: 9, spreadRadius: -2),
                                  ],
                                ),
                                child: Icon(Icons.folder_rounded, size: 112,
                                  color: const Color(0xFFD6FFFA).withOpacity(.82)),
                              ),
                              for (var i = 0; i < 6; i++)
                                Positioned(
                                  left: 18 + (i * 31.0) % 190,
                                  top: 10 + ((i * 43.0 + t * 12) % 170),
                                  child: Container(
                                    width: 10 + (i % 3) * 8,
                                    height: 10 + (i % 3) * 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(colors: [
                                        Colors.white.withOpacity(.95),
                                        const Color(0xFF7CFFF2).withOpacity(.20),
                                      ]),
                                      border: Border.all(color: Colors.white.withOpacity(.65)),
                                      boxShadow: [BoxShadow(color: const Color(0xFF70FFF2).withOpacity(.4), blurRadius: 10)],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 23),
                    const Text('BUBBLE',
                      style: TextStyle(fontSize: 43, fontWeight: FontWeight.w900,
                        letterSpacing: 3.5, color: Color(0xFF9CFFF0),
                        shadows: [Shadow(color: Color(0xFF36DCCF), blurRadius: 22)])),
                    const SizedBox(height: 2),
                    const Text('FILE MANAGER',
                      style: TextStyle(fontSize: 19, letterSpacing: 4.0,
                        fontWeight: FontWeight.w300, color: Color(0xFFE3FFFC))),
                    const SizedBox(height: 22),
                    Text('Safety and Relax File Management System',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, letterSpacing: .6,
                        color: Colors.white.withOpacity(.72))),
                    const SizedBox(height: 7),
                    Text('Created by H.G.Aluthge',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.1,
                        color: Colors.white.withOpacity(.52))),
                  ],
                ),
              ),
              Positioned(
                bottom: 35,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 28, height: 2,
                    child: LinearProgressIndicator(
                      value: null,
                      backgroundColor: Colors.white.withOpacity(.10),
                      color: const Color(0xFF8DFFF4),
                      minHeight: 2,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AquaBackdrop extends StatelessWidget {
  const AquaBackdrop({super.key, this.reduced = false});
  final bool reduced;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xFF04141E),
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF071E2A), Color(0xFF04141E), Color(0xFF031018)]),
    ),
    child: Stack(children: [
      Positioned(left: -100, top: -100, child: _Glow(color: const Color(0x4420E4E8), size: 310, reduced: reduced)),
      Positioned(right: -130, top: 80, child: _Glow(color: const Color(0x222E83C5), size: 330, reduced: reduced)),
      Positioned(bottom: -160, left: 20, child: _Glow(color: const Color(0x2221B8A8), size: 390, reduced: reduced)),
    ]),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.reduced});
  final Color color;
  final double size;
  final bool reduced;
  @override
  Widget build(BuildContext context) {
    final circle = Container(width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color));
    // Static soft color is cheaper than a full-screen image blur.
    return reduced ? circle : ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
      child: circle,
    );
  }
}

class _Bubble {
  _Bubble(this.r, this.x, this.y, this.vx, this.vy, this.phase, this.opacity, this.hue);
  double r, x, y, vx, vy, phase, opacity, hue;
 }

class _Ripple {
  _Ripple(this.x, this.y, this.radius);
  final double x, y, radius;
  final Set<_Bubble> affected = <_Bubble>{};
  double life = 1;
  double previousRadius = 0;
}

class _WaterDroplet {
  _WaterDroplet(this.x, this.y, this.vx, this.vy, this.radius, this.hue);
  double x, y, vx, vy, radius, hue;
  double life = 1;
}

class BubbleField extends StatefulWidget {
  const BubbleField({super.key, required this.accent, required this.gravityEnabled, required this.reduced, required this.speed, this.onBubbleTap});
  final Color accent;
  final bool gravityEnabled;
  final bool reduced;
  final double speed;
  final VoidCallback? onBubbleTap;
  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final math.Random _random = math.Random();
  final List<_Bubble> _bubbles = <_Bubble>[];
  final List<_Ripple> _ripples = <_Ripple>[];
  final List<_WaterDroplet> _droplets = <_WaterDroplet>[];
  final AudioPlayer _audio = AudioPlayer();
  StreamSubscription<AccelerometerEvent>? _sensor;
  Size _size = Size.zero;
  Offset _gravity = Offset.zero;
  Offset? _gravityBaseline;
  Offset? _finger;
  double _lastTick = 0;
  double _lastReducedFrame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_advance)..repeat();
    _sensor = accelerometerEventStream().listen((event) {
      // Calibrate the resting phone orientation so bubbles stay buoyant
      // when the phone is still and react only to changes in tilt.
      _gravityBaseline ??= Offset(event.x, event.y);
      _gravity = Offset(
        ((event.x - _gravityBaseline!.dx) / 9.8).clamp(-1.0, 1.0).toDouble(),
        ((event.y - _gravityBaseline!.dy) / 9.8).clamp(-1.0, 1.0).toDouble(),
      );
    }, onError: (_) {});
  }

  _Bubble _createBubble({double? y}) {
    final radius = 11 + _random.nextDouble() * (widget.reduced ? 23 : 33);
    final hue = HSLColor.fromColor(widget.accent).hue + _random.nextDouble() * 24 - 12;
    return _Bubble(radius, radius + _random.nextDouble() * math.max(1.0, _size.width - radius * 2).toDouble(),
      y ?? _size.height + radius, (_random.nextDouble() - .5) * 1.2,
      -.3 - _random.nextDouble() * 1.1, _random.nextDouble() * math.pi * 2,
      .22 + _random.nextDouble() * .30, hue);
  }

  void _advance() {
    if (!mounted || _size.isEmpty) return;
    final now = _ticker.lastElapsedDuration?.inMicroseconds.toDouble() ?? 0;
    // Cap the low-memory bubble layer at about 30 FPS instead of repainting
    // on every display tick. Full mode keeps the normal frame rate.
    if (widget.reduced && now - _lastReducedFrame < 33333) return;
    if (widget.reduced) _lastReducedFrame = now;
    final dt = _lastTick == 0 ? 1.0 : ((now - _lastTick) / 16667).clamp(0.0, 2.0).toDouble();
    _lastTick = now;
    final count = widget.reduced ? 5 : (_size.width < 520 ? 20 : 28);
    while (_bubbles.length < count) {
      _bubbles.add(_createBubble(y: _random.nextDouble() * _size.height));
    }

    for (var index = 0; index < _bubbles.length; index++) {
      final b = _bubbles[index];
      b.phase += .018 * dt;
      if (widget.gravityEnabled) {
        // Tilt adds a calibrated gravity vector while buoyancy keeps a
        // gentle upward drift when the phone is held still.
        b.vx += _gravity.dx * .11 * dt;
        b.vy += _gravity.dy * .11 * dt - (.025 + b.r / 6500) * dt;
      } else {
        // Organic idle motion: buoyancy, lateral sway and fluid drift.
        b.vx += math.sin(b.phase) * .045 * dt + (_random.nextDouble() - .5) * .022 * dt;
        b.vy += math.cos(b.phase * .73) * .018 * dt - (.018 + b.r / 6500) * dt;
      }
      if (_finger != null) {
        final dx = _finger!.dx - b.x;
        final dy = _finger!.dy - b.y;
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance > 2 && distance < 260) {
          final pull = (1 - distance / 260) * .035 * dt;
          b.vx += dx / distance * pull;
          b.vy += dy / distance * pull;
        }
      }
      b.vx *= math.pow(.992, dt).toDouble();
      b.vy *= math.pow(.994, dt).toDouble();
      b.x += b.vx * dt * 2.2 * widget.speed;
      b.y += b.vy * dt * 2.2 * widget.speed;

      if (b.x < b.r) { b.x = b.r; b.vx = b.vx.abs() * .86; }
      if (b.x > _size.width - b.r) { b.x = _size.width - b.r; b.vx = -b.vx.abs() * .86; }
      // Bubbles rise out through the top and respawn below the screen.
      // Bouncing them off the top trapped them at the ceiling and stopped
      // the intended continuous underwater flow.
      if (b.y + b.r < 0) {
        _bubbles[index] = _createBubble(y: _size.height + b.r);
        continue;
      }
    }

     if (!widget.reduced) {
      for (var i = 0; i < _bubbles.length; i++) {
        for (var j = i + 1; j < _bubbles.length; j++) {
          final a = _bubbles[i], b = _bubbles[j];
          final dx = b.x - a.x, dy = b.y - a.y;
          final distance = math.sqrt(dx * dx + dy * dy);
          final minDistance = a.r + b.r;
          if (distance > .01 && distance < minDistance) {
            final nx = dx / distance, ny = dy / distance;
            final overlap = (minDistance - distance) * .5;
            a.x -= nx * overlap; a.y -= ny * overlap;
            b.x += nx * overlap; b.y += ny * overlap;
            final relative = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
            if (relative < 0) {
              final impulse = -(1 + .82) * relative * .5;
              a.vx -= impulse * nx; a.vy -= impulse * ny;
              b.vx += impulse * nx; b.vy += impulse * ny;
            }
          }
        }
      }
    }

    // The ripple grows outward, then contracts smoothly and disappears.
    // Bubbles are never resized or faded: only bubbles touched by the
    // moving wave line receive a small, damped movement impulse.
    for (final ripple in _ripples) {
      final progress = 1 - ripple.life;
      final ringRadius = ripple.radius * math.sin(math.pi * progress);
      final low = math.min(ripple.previousRadius, ringRadius);
      final high = math.max(ripple.previousRadius, ringRadius);
      for (final bubble in _bubbles) {
        if (ripple.affected.contains(bubble)) continue;
        final distance = (Offset(bubble.x, bubble.y) -
            Offset(ripple.x, ripple.y)).distance;
        if (distance + bubble.r >= low && distance - bubble.r <= high) {
          ripple.affected.add(bubble);
          final dx = bubble.x - ripple.x;
          final dy = bubble.y - ripple.y;
          final length = math.max(1.0, math.sqrt(dx * dx + dy * dy));
          bubble.vx += dx / length * .16;
          bubble.vy += dy / length * .16;
        }
      }
      ripple.previousRadius = ringRadius;
      ripple.life -= .009 * dt;
    }
    _ripples.removeWhere((r) => r.life <= 0);

    for (final drop in _droplets) {
      drop.x += drop.vx * dt * 2.2;
      drop.y += drop.vy * dt * 2.2;
      drop.vy += .035 * dt;
      drop.vx *= math.pow(.985, dt).toDouble();
      drop.vy *= math.pow(.985, dt).toDouble();
      drop.life -= .025 * dt;
    }
    _droplets.removeWhere((drop) => drop.life <= 0);
  }

  // Forward pointer events from the parent Listener because this painter
  // sits behind the interactive file-manager UI in the Stack.
  void handlePointerDown(Offset local) {
    _finger = local;
    _popAt(local);
  }

  void handlePointerMove(Offset local) => _pointer(local);

  void handlePointerUp() => _releasePointer();

  void _pointer(Offset local) => _finger = local;

  void _releasePointer() => _finger = null;

  void _popAt(Offset point) {
    var best = -1;
    var nearest = double.infinity;
    for (var i = 0; i < _bubbles.length; i++) {
      final b = _bubbles[i];
      final distance = (Offset(b.x, b.y) - point).distance;
      if (distance < b.r + 28 && distance < nearest) {
        nearest = distance;
        best = i;
      }
    }
    if (best < 0) return;
    widget.onBubbleTap?.call();
    final b = _bubbles.removeAt(best);
    _ripples.add(_Ripple(
      b.x,
      b.y,
      math.max(_size.width, _size.height) * .72,
    ));
    final particleCount = widget.reduced ? 7 : 16;
    for (var i = 0; i < particleCount; i++) {
      final angle = (math.pi * 2 * i / particleCount) +
          (_random.nextDouble() - .5) * .32;
      final speed = .65 + _random.nextDouble() * 1.65;
      _droplets.add(_WaterDroplet(
        b.x,
        b.y,
        math.cos(angle) * speed,
        math.sin(angle) * speed,
        1.3 + _random.nextDouble() * 2.2,
        b.hue,
      ));
    }
    unawaited(_playBloop());
  }

  Future<void> _playBloop() async {
    try {
      await _audio.stop();
      await _audio.play(BytesSource(_makeBloopWave()), volume: .42);
    } catch (_) {}
  }

  Uint8List _makeBloopWave() {
    const sampleRate = 22050;
    const sampleCount = 4400;
    final bytes = Uint8List(44 + sampleCount * 2);
    final data = ByteData.sublistView(bytes);
    void putText(int offset, String value) {
      for (var i = 0; i < value.length; i++) { bytes[offset + i] = value.codeUnitAt(i); }
    }
    putText(0, 'RIFF');
    data.setUint32(4, 36 + sampleCount * 2, Endian.little);
    putText(8, 'WAVE');
    putText(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    putText(36, 'data');
    data.setUint32(40, sampleCount * 2, Endian.little);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final envelope = math.exp(-18 * t);
      final frequency = 650 - 360 * (i / sampleCount);
      final sample = (math.sin(2 * math.pi * frequency * t) * envelope * 9000).round();
      data.setInt16(44 + i * 2, sample, Endian.little);
    }
    return bytes;
  }

  @override
  void didUpdateWidget(covariant BubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The sensor stream remains active; the gravity switch controls whether its vector is applied.
  }

  @override
  void dispose() {
    _sensor?.cancel();
    _ticker.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    _size = Size(constraints.maxWidth, constraints.maxHeight);
    return RepaintBoundary(child: CustomPaint(
      painter: _BubblePainter(_bubbles, _ripples, _droplets, _ticker),
      size: Size.infinite,
    ));
  });
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.bubbles, this.ripples, this.droplets, Listenable repaint)
      : super(repaint: repaint);
  final List<_Bubble> bubbles;
  final List<_Ripple> ripples;
  final List<_WaterDroplet> droplets;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ripple in ripples) {
      final progress = 1 - ripple.life;
      final radius = ripple.radius * math.sin(math.pi * progress);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 * ripple.life).clamp(.45, 2.2)
        ..color = const Color(0xFFB8FFF8).withOpacity(.58 * ripple.life);
      canvas.drawCircle(Offset(ripple.x, ripple.y), radius, paint);
      canvas.drawCircle(Offset(ripple.x, ripple.y), radius * .985, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..color = Colors.white.withOpacity(.24 * ripple.life));
    }
    for (final drop in droplets) {
      final color = HSLColor.fromAHSL(
        drop.life.clamp(0.0, 1.0), drop.hue % 360, .82, .72).toColor();
      canvas.drawCircle(Offset(drop.x, drop.y), drop.radius * drop.life,
        Paint()..color = color);
      canvas.drawCircle(Offset(drop.x, drop.y), drop.radius * drop.life,
        Paint()..style = PaintingStyle.stroke..strokeWidth = .6
          ..color = Colors.white.withOpacity(.55 * drop.life));
    }
    for (final b in bubbles) {
      final bubbleRadius = b.r;
      final bubbleOpacity = b.opacity;
      final color = HSLColor.fromAHSL(1, b.hue % 360, .78, .60).toColor();
      final rect = Rect.fromCircle(center: Offset(b.x, b.y), radius: bubbleRadius);
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.34, -.38),
          colors: [
            Colors.white.withOpacity(bubbleOpacity * .95),
            color.withOpacity(bubbleOpacity * .62),
            color.withOpacity(bubbleOpacity * .10),
          ],
        ).createShader(rect);
      canvas.drawCircle(Offset(b.x, b.y), bubbleRadius, paint);
      canvas.drawCircle(Offset(b.x, b.y), bubbleRadius, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = Colors.white.withOpacity(bubbleOpacity * .9));
      canvas.drawCircle(Offset(b.x - bubbleRadius * .34, b.y - bubbleRadius * .38), bubbleRadius * .17,
        Paint()..color = Colors.white.withOpacity(bubbleOpacity * .9));
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) => false;
}

class _SecretBoxGesturePainter extends CustomPainter {
  _SecretBoxGesturePainter(List<Offset> points) : points = List<Offset>.of(points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0x665DEBFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xD6B8F8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SecretBoxGesturePainter oldDelegate) => true;
}

