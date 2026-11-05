import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'advanced_tools.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const AquaApp());

const List<Color> aquaAccents = <Color>[
  Color(0xFF20E4E8),
  Color(0xFFAA8BFF),
  Color(0xFF4DE0A5),
  Color(0xFFFFC15A),
  Color(0xFFFF83C5),
];

class AquaApp extends StatefulWidget {
  const AquaApp({super.key});
  @override
  State<AquaApp> createState() => _AquaAppState();
}

class _AquaAppState extends State<AquaApp> {
  int _tab = 0;
  int _theme = 0;
  bool _gravity = true;
  bool _animations = true;
  bool _performance = false;
  bool _light = false;
  bool _checkingPermission = false;
  bool _hasStorage = false;
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
  Directory? _recycleDirectory;
  File? _recycleIndex;
  List<Map<String, dynamic>> _recycleRecords = <Map<String, dynamic>>[];
  FileSystemEntity? _clipboardEntity;
  bool _clipboardMove = false;
  Timer? _recycleTimer;
  static const FlutterSecureStorage _folderPinStore = FlutterSecureStorage();

  Color get _accent => aquaAccents[_theme];

  @override
  void initState() {
    super.initState();
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

  Future<void> _expireRecycleRecords() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keep = <Map<String, dynamic>>[];
    for (final record in _recycleRecords) {
      final stage = record['stage'] as String? ?? 'bin';
      final started = (record['stageStartedAt'] as num?)?.toInt() ?? now;
      final lifetime = stage == 'shred' ? const Duration(hours: 2).inMilliseconds : const Duration(days: 30).inMilliseconds;
      if (now - started >= lifetime) {
        try { await _deleteEntityPermanently(record['storedPath'] as String); } catch (_) {}
      } else {
        keep.add(record);
      }
    }
    if (keep.length != _recycleRecords.length) {
      if (mounted) setState(() => _recycleRecords = keep);
      else _recycleRecords = keep;
      await _saveRecycleRecords();
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
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final storedPath = '${folder.path}/${id}_${_nameOf(entity)}';
      await _copyEntityRecursively(entity, storedPath);
      await _deleteEntityPermanently(entity.path);
      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() => _recycleRecords.add({
        'id': id, 'name': _nameOf(entity), 'originalPath': entity.path,
        'storedPath': storedPath, 'stage': 'bin', 'stageStartedAt': now,
      }));
      await _saveRecycleRecords();
      await _loadDirectory(_current);
      _message('Moved to Recycle Bin for 30 days.');
    } catch (e) {
      _message('Could not move item to Recycle Bin: ' + e.toString());
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
    setState(() {
      record['stage'] = 'shred';
      record['stageStartedAt'] = DateTime.now().millisecondsSinceEpoch;
    });
    await _saveRecycleRecords();
    _message('Moved to 2-hour temporary recovery stage.');
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

  Future<void> _loadDirectory(Directory directory) async {
    if (!_hasStorage && !await Permission.manageExternalStorage.isGranted) return;
    try {
      final entries = await directory.list(followLinks: false).toList();
      entries.sort((a, b) {
        if (_foldersFirst) {
          final ad = a is Directory ? 0 : 1;
          final bd = b is Directory ? 0 : 1;
          if (ad != bd) return ad.compareTo(bd);
        }
        return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      });
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

  bool _matchesCategory(FileSystemEntity item) {
    if (item is Directory || _fileCategory == 'All files') return true;
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
    final items = _items.where((item) =>
      (_showHidden || !_nameOf(item).startsWith('.')) &&
      _nameOf(item).toLowerCase().contains(_search.toLowerCase()) &&
      _matchesCategory(item)).toList();
    items.sort((a, b) {
      if (_foldersFirst && a is Directory != (b is Directory)) {
        return a is Directory ? -1 : 1;
      }
      switch (_sortMode) {
        case 'Size':
          int sizeOf(FileSystemEntity item) {
            try { return item is File ? item.lengthSync() : 0; } catch (_) { return 0; }
          }
          return sizeOf(b).compareTo(sizeOf(a));
        case 'Date':
          DateTime dateOf(FileSystemEntity item) {
            try { return item.statSync().modified; } catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
          }
          return dateOf(b).compareTo(dateOf(a));
        case 'Type':
          return _extensionOf(a).compareTo(_extensionOf(b));
        default:
          return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      }
    });
    return items;
  }

  Future<void> _findDuplicates() async {
    if (_scanningDuplicates || !_hasStorage) return;
    setState(() => _scanningDuplicates = true);
    _message('Scanning storage for identical files…');
    try {
      final bySize = <int, List<File>>{};
      final pending = <Directory>[_root];
      var visited = 0;
      while (pending.isNotEmpty && visited < 15000) {
        final directory = pending.removeLast();
        try {
          await for (final entity in directory.list(followLinks: false)) {
            if (entity is Directory) {
              final path = entity.path;
              if (!path.contains('/Android/data/') &&
                  !path.contains('/Android/obb/') &&
                  !path.contains('/aqua_recycle_bin/')) {
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
        } catch (_) {}
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

  Future<void> _openAdvancedTools() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AquaAdvancedTools(targetDirectory: _current, accent: _accent),
    ));
    if (_hasStorage) await _loadDirectory(_current);
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

  @override
  void dispose() {
    _recycleTimer?.cancel();
    super.dispose();
  }


  Future<bool> _unlockFolderIfNeeded(Directory directory) async {
    final key = 'aqua_folder_pin_\${sha256.convert(utf8.encode(directory.path))}';
    final stored = await _folderPinStore.read(key: key);
    if (stored == null) return true;
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlock \${_nameOf(directory)}'),
        content: TextField(controller: controller, obscureText: true,
          keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Folder PIN')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    if (pin == null) return false;
    final digest = sha256.convert(utf8.encode('\${directory.path}:$pin')).toString();
    if (digest != stored) { _message('Incorrect folder PIN.'); return false; }
    return true;
  }

  Future<void> _setFolderPin(Directory directory) async {
    final key = 'aqua_folder_pin_\${sha256.convert(utf8.encode(directory.path))}';
    final stored = await _folderPinStore.read(key: key);
    if (stored != null) {
      final controller = TextEditingController();
      final pin = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove PIN • \${_nameOf(directory)}'),
          content: TextField(controller: controller, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Current PIN')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Remove lock')),
          ],
        ),
      );
      if (pin == null) return;
      if (sha256.convert(utf8.encode('\${directory.path}:$pin')).toString() != stored) {
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
        title: Text('Protect \${_nameOf(directory)}'),
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
      value: sha256.convert(utf8.encode('\${directory.path}:$pin')).toString());
    _message('Folder PIN protection enabled.');
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      if (await _unlockFolderIfNeeded(entity)) await _loadDirectory(entity);
    } else {
      await _showDetails(entity);
    }
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
      home: Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: AquaBackdrop()),
          if (_animations)
            Positioned.fill(child: BubbleField(
              key: const ValueKey('aqua-bubbles'),
              accent: _accent,
              gravityEnabled: _gravity,
              reduced: _performance,
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
        ]),
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
        Text('AQUA', style: TextStyle(color: foreground, fontSize: 18,
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
      _glass(child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(
          color: _accent.withOpacity(.15), borderRadius: BorderRadius.circular(15)),
          child: Icon(Icons.sd_storage_rounded, color: _accent, size: 25)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PHONE STORAGE', style: TextStyle(fontSize: 10, letterSpacing: 1.6, color: Colors.white60)),
          Text(_hasStorage ? 'Access enabled' : 'Permission required',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Text('Internal storage browser', style: TextStyle(fontSize: 11, color: Colors.white54)),
        ])),
        Icon(_hasStorage ? Icons.check_circle_rounded : Icons.lock_outline_rounded, color: _accent),
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
    onTap: () => setState(() {
      _fileCategory = title;
      _search = '';
      _tab = 1;
    }),
    child: _glass(child: Row(children: [
      Icon(icon, color: _accent, size: 25),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
    ])),
  );

  Widget _files(Color foreground) {
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
                tooltip: 'Sort files',
                onSelected: (value) => setState(() {
                  if (value == 'Folders first' || value == 'No folder priority') {
                    _foldersFirst = value == 'Folders first';
                  } else {
                    _sortMode = value;
                  }
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Name', child: Text('Sort by name')),
                  PopupMenuItem(value: 'Size', child: Text('Sort by size')),
                  PopupMenuItem(value: 'Date', child: Text('Sort by date')),
                  PopupMenuItem(value: 'Type', child: Text('Sort by type')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'Folders first', child: Text('Folders first')),
                  PopupMenuItem(value: 'No folder priority', child: Text('No folder priority')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('Sort: $_sortMode', style: TextStyle(fontSize: 10, color: _accent)),
                ),
              ),
            ]),
          ]),
        )),
        const SizedBox(height: 8),
        Expanded(child: _visibleItems.isEmpty
          ? const Center(child: Text('This folder is empty', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              itemCount: _visibleItems.length,
              itemBuilder: (context, index) {
                final item = _visibleItems[index];
                final isFolder = item is Directory;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _glass(child: Row(children: [
                    Icon(isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                      color: isFolder ? _accent : Colors.white70, size: 25),
                    const SizedBox(width: 11),
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
                        if (item is Directory) const PopupMenuItem(value: 'folder_pin', child: Text('Set / remove Folder PIN')),
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
      _switchTile('Bubble animation', 'Show floating water bubbles', _animations,
        (v) => setState(() => _animations = v)),
      _switchTile('Performance mode', 'Use fewer bubbles and less motion work', _performance,
        (v) => setState(() => _performance = v)),
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
        'Aqua File Manager • Development build\n'
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

  Widget _glass({required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(23),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.white.withOpacity(.14), Colors.white.withOpacity(.045)]),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: Colors.white.withOpacity(.17), width: 1),
          boxShadow: [BoxShadow(color: _accent.withOpacity(.055), blurRadius: 24)],
        ),
        child: child,
      ),
    ),
  );

  Widget _bottomNav(Color foreground) => Padding(
    padding: const EdgeInsets.fromLTRB(19, 7, 19, 11),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
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

class AquaBackdrop extends StatelessWidget {
  const AquaBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Color(0xFF04141E),
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF071E2A), Color(0xFF04141E), Color(0xFF031018)]),
    ),
    child: Stack(children: [
      Positioned(left: -100, top: -100, child: _Glow(color: Color(0x4420E4E8), size: 310)),
      Positioned(right: -130, top: 80, child: _Glow(color: Color(0x222E83C5), size: 330)),
      Positioned(bottom: -160, left: 20, child: _Glow(color: Color(0x2221B8A8), size: 390)),
    ]),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
    child: Container(width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
  );
}

class _Bubble {
  _Bubble(this.r, this.x, this.y, this.vx, this.vy, this.phase, this.opacity, this.hue);
  double r, x, y, vx, vy, phase, opacity, hue;
}

class _Ripple {
  _Ripple(this.x, this.y, this.radius);
  final double x, y, radius;
  double life = 1;
}

class BubbleField extends StatefulWidget {
  const BubbleField({super.key, required this.accent, required this.gravityEnabled, required this.reduced});
  final Color accent;
  final bool gravityEnabled;
  final bool reduced;
  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final math.Random _random = math.Random();
  final List<_Bubble> _bubbles = <_Bubble>[];
  final List<_Ripple> _ripples = <_Ripple>[];
  final AudioPlayer _audio = AudioPlayer();
  StreamSubscription<AccelerometerEvent>? _sensor;
  Size _size = Size.zero;
  Offset _gravity = Offset.zero;
  Offset? _gravityBaseline;
  Offset? _finger;
  double _lastTick = 0;

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
    final dt = _lastTick == 0 ? 1.0 : ((now - _lastTick) / 16667).clamp(0.0, 2.0).toDouble();
    _lastTick = now;
    final count = widget.reduced ? 10 : (_size.width < 520 ? 20 : 28);
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
      b.x += b.vx * dt * 2.2;
      b.y += b.vy * dt * 2.2;

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

    for (final ripple in _ripples) { ripple.life -= .045 * dt; }
    _ripples.removeWhere((r) => r.life <= 0);
  }

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
    final b = _bubbles[best];
    _ripples.add(_Ripple(b.x, b.y, b.r));
    _bubbles[best] = _createBubble();
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) => _pointer(details.localPosition),
      onPanUpdate: (details) => _pointer(details.localPosition),
      onPanEnd: (_) => _releasePointer(),
      onTapDown: (details) {
        _pointer(details.localPosition);
        _popAt(details.localPosition);
      },
      onTapUp: (_) => _releasePointer(),
      onTapCancel: _releasePointer,
      child: RepaintBoundary(child: CustomPaint(
        painter: _BubblePainter(_bubbles, _ripples, _ticker),
        size: Size.infinite,
      )),
    );
  });
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.bubbles, this.ripples, Listenable repaint) : super(repaint: repaint);
  final List<_Bubble> bubbles;
  final List<_Ripple> ripples;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ripple in ripples) {
      final progress = 1 - ripple.life;
      final radius = ripple.radius * (1 + progress * .75);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * ripple.life
        ..color = Colors.white.withOpacity(.42 * ripple.life);
      canvas.drawCircle(Offset(ripple.x, ripple.y), radius, paint);
    }
    for (final b in bubbles) {
      final color = HSLColor.fromAHSL(1, b.hue % 360, .78, .60).toColor();
      final rect = Rect.fromCircle(center: Offset(b.x, b.y), radius: b.r);
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.34, -.38),
          colors: [
            Colors.white.withOpacity(b.opacity * .95),
            color.withOpacity(b.opacity * .62),
            color.withOpacity(b.opacity * .10),
          ],
        ).createShader(rect);
      canvas.drawCircle(Offset(b.x, b.y), b.r, paint);
      canvas.drawCircle(Offset(b.x, b.y), b.r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = Colors.white.withOpacity(b.opacity * .9));
      canvas.drawCircle(Offset(b.x - b.r * .34, b.y - b.r * .38), b.r * .17,
        Paint()..color = Colors.white.withOpacity(b.opacity * .9));
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) => false;
}
