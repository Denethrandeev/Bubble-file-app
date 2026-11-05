import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AquaAdvancedTools extends StatefulWidget {
  const AquaAdvancedTools({super.key, required this.targetDirectory, required this.accent});
  final Directory targetDirectory;
  final Color accent;

  @override
  State<AquaAdvancedTools> createState() => _AquaAdvancedToolsState();
}

class _AquaAdvancedToolsState extends State<AquaAdvancedTools> {
  static const _secure = FlutterSecureStorage();
  final _auth = LocalAuthentication();
  bool _busy = false;
  String _status = 'Choose a tool to begin.';
  List<File> _vaultFiles = <File>[];
  List<_GeoPhoto> _geoPhotos = <_GeoPhoto>[];
  List<File> _cleanupSuggestions = <File>[];

  void _say(String value) {
    if (mounted) setState(() => _status = value);
  }

  Future<Directory> _vaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/aqua_encrypted_vault');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Uint8List> _getVaultKey() async {
    final stored = await _secure.read(key: 'aqua_vault_key');
    if (stored == null) throw StateError('Vault has not been initialized. Set a PIN first.');
    return Uint8List.fromList(base64Decode(stored));
  }

  Future<bool> _verifyPin({bool setup = false}) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final storedHash = await _secure.read(key: 'aqua_vault_pin_hash');
    final salt = await _secure.read(key: 'aqua_vault_pin_salt');
    if (storedHash == null && !setup) {
      _say('Create a Vault PIN first.');
      return false;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(storedHash == null ? 'Create Vault PIN' : 'Unlock Vault'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pinController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN (at least 6 digits)')),
          if (storedHash == null) TextField(controller: confirmController, obscureText: true,
            keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm PIN')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, pinController.text), child: const Text('Continue')),
        ],
      ),
    );
    if (pin == null) return false;
    if (storedHash == null) {
      if (pin.length < 6 || pin != confirmController.text) {
        _say('PIN must be at least 6 digits and both entries must match.');
        return false;
      }
      final newSalt = base64Encode(Cryptography.instance.randomBytes(16));
      final digest = hashes.sha256.convert(utf8.encode('$newSalt:$pin')).toString();
      final key = await AesGcm.with256bits().newSecretKey();
      final keyBytes = await key.extractBytes();
      await _secure.write(key: 'aqua_vault_pin_salt', value: newSalt);
      await _secure.write(key: 'aqua_vault_pin_hash', value: digest);
      await _secure.write(key: 'aqua_vault_key', value: base64Encode(keyBytes));
      _say('Encrypted Vault created. Keep your PIN safe; it cannot be recovered.');
      return true;
    }
    final digest = hashes.sha256.convert(utf8.encode('$salt:$pin')).toString();
    if (digest != storedHash) {
      _say('Incorrect PIN.');
      return false;
    }
    return true;
  }

  Future<bool> _unlockVault({bool setup = false}) async {
    final hasPin = await _secure.read(key: 'aqua_vault_pin_hash') != null;
    if (!hasPin) return _verifyPin(setup: true);
    final useBiometric = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock encrypted Vault'),
        content: const Text('Use device authentication, or enter your Vault PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Use PIN')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fingerprint / device')),
        ],
      ),
    );
    if (useBiometric == true) {
      try {
        final available = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
        if (available && await _auth.authenticate(
          localizedReason: 'Authenticate to open your encrypted Aqua Vault',
          options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
        )) return true;
      } catch (_) {}
      _say('Device authentication was unavailable or cancelled. Use your PIN.');
      return false;
    }
    return _verifyPin();
  }

  Future<void> _openVault() async {
    if (!await _unlockVault()) return;
    final directory = await _vaultDirectory();
    await _refreshVault();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF102B38),
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: SizedBox(height: MediaQuery.of(context).size.height * .65,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Encrypted Secret Vault', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Files are stored encrypted with AES-256-GCM.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () async { Navigator.pop(context); await _addToVault(); },
              icon: const Icon(Icons.add), label: const Text('Encrypt a file into Vault')),
            Expanded(child: _vaultFiles.isEmpty
              ? const Center(child: Text('Vault is empty.'))
              : ListView(children: _vaultFiles.map((file) => ListTile(
                  leading: const Icon(Icons.lock, color: Colors.cyanAccent),
                  title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.save_alt), onPressed: () async {
                    Navigator.pop(context);
                    await _exportFromVault(file);
                  }),
                )).toList())),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ])),
      )),
    );
  }

  Future<void> _refreshVault() async {
    final directory = await _vaultDirectory();
    final files = await directory.list().where((e) => e is File && e.path.endsWith('.aqua')).cast<File>().toList();
    if (mounted) setState(() => _vaultFiles = files);
  }

  Future<void> _addToVault() async {
    if (!await _unlockVault()) return;
    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final source = File(path);
      final bytes = await source.readAsBytes();
      final key = SecretKey(await _getVaultKey());
      final box = await AesGcm.with256bits().encrypt(bytes, secretKey: key);
      final envelope = jsonEncode({
        'name': source.uri.pathSegments.last,
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      });
      final directory = await _vaultDirectory();
      final id = DateTime.now().microsecondsSinceEpoch;
      await File('${directory.path}/$id.aqua').writeAsString(envelope, flush: true);
      await _refreshVault();
      _say('File encrypted and added to Vault.');
    } catch (e) {
      _say('Vault encryption failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportFromVault(File encryptedFile) async {
    if (!await _unlockVault()) return;
    final destination = await FilePicker.platform.getDirectoryPath();
    if (destination == null) return;
    try {
      final envelope = jsonDecode(await encryptedFile.readAsString()) as Map<String, dynamic>;
      final box = SecretBox(
        base64Decode(envelope['data'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(await _getVaultKey()));
      final name = (envelope['name'] as String).replaceAll(RegExp(r'[/\\\\]'), '_');
      await File('$destination/$name').writeAsBytes(clear, flush: true);
      _say('Decrypted file exported to the selected folder.');
    } catch (e) {
      _say('Vault decryption failed: $e');
    }
  }

  Future<void> _createZip() async {
    final selected = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (selected == null || selected.files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final archive = Archive();
      for (final item in selected.files) {
        final path = item.path;
        if (path == null) continue;
        final file = File(path);
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(item.name, bytes.length, bytes));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw StateError('ZIP encoding failed.');
      final output = File('${widget.targetDirectory.path}/Aqua_${DateTime.now().millisecondsSinceEpoch}.zip');
      await output.writeAsBytes(encoded, flush: true);
      _say('ZIP created in the current Aqua folder.');
    } catch (e) {
      _say('ZIP creation failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extractZip() async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: false);
    final path = selected?.files.single.path;
    if (path == null) return;
    final destination = await FilePicker.platform.getDirectoryPath() ?? widget.targetDirectory.path;
    setState(() => _busy = true);
    try {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final root = Directory(destination).absolute.path;
      for (final item in archive) {
        final normalized = item.name.replaceAll('\\\\', '/');
        if (normalized.startsWith('/') || normalized.split('/').contains('..')) continue;
        final output = File('$root/$normalized').absolute;
        if (!output.path.startsWith('$root${Platform.pathSeparator}') && output.path != root) continue;
        if (item.isFile) {
          await output.parent.create(recursive: true);
          await output.writeAsBytes(item.content as List<int>, flush: true);
        } else {
          await Directory(output.path).create(recursive: true);
        }
      }
      _say('ZIP extraction completed in the selected folder.');
    } catch (e) {
      _say('ZIP extraction failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importExternal() async {
    final selected = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (selected == null) return;
    var copied = 0;
    for (final item in selected.files) {
      final path = item.path;
      if (path == null) continue;
      try {
        final target = File('${widget.targetDirectory.path}/${item.name}');
        await File(path).copy(target.path);
        copied++;
      } catch (_) {}
    }
    _say('Imported $copied file(s) from the Android file picker. Choose SD card or USB storage in the system picker.');
  }

  Future<void> _scanGpsPhotos() async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: false);
    if (selected == null) return;
    setState(() => _busy = true);
    final found = <_GeoPhoto>[];
    try {
      for (final item in selected.files) {
        final path = item.path;
        if (path == null) continue;
        final file = File(path);
        if (await file.length() > 25 * 1024 * 1024) continue;
        try {
          final tags = await readExifFromBytes(await file.readAsBytes());
          final latTag = tags['GPS GPSLatitude']?.printable;
          final lonTag = tags['GPS GPSLongitude']?.printable;
          if (latTag == null || lonTag == null) continue;
          final latRef = tags['GPS GPSLatitudeRef']?.printable ?? 'N';
          final lonRef = tags['GPS GPSLongitudeRef']?.printable ?? 'E';
          final lat = _dmsToDecimal(latTag, latRef);
          final lon = _dmsToDecimal(lonTag, lonRef);
          if (lat != null && lon != null) found.add(_GeoPhoto(file, lat, lon));
        } catch (_) {}
      }
      if (mounted) setState(() => _geoPhotos = found);
      _say('Found GPS coordinates in ${found.length} selected image(s). Images without GPS are kept out of map groups.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double? _dmsToDecimal(String raw, String ref) {
    final values = RegExp(r'-?\\d+(?:\\.\\d+)?').allMatches(raw)
      .map((m) => double.tryParse(m.group(0)!)).whereType<double>().toList();
    if (values.isEmpty) return null;
    final degrees = values[0];
    final minutes = values.length > 1 ? values[1] : 0.0;
    final seconds = values.length > 2 ? values[2] : 0.0;
    var decimal = degrees.abs() + minutes / 60 + seconds / 3600;
    if (degrees < 0 || ref.toUpperCase().contains('S') || ref.toUpperCase().contains('W')) decimal = -decimal;
    return decimal;
  }

  Future<void> _openMap(_GeoPhoto photo) async {
    final uri = Uri.parse('https://www.openstreetmap.org/?mlat=${photo.latitude}&mlon=${photo.longitude}#map=16/${photo.latitude}/${photo.longitude}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) _say('Could not open the map application.');
  }

  Future<void> _smartCleanup() async {
    setState(() => _busy = true);
    final candidates = <File>[];
    final pending = <Directory>[widget.targetDirectory];
    var visited = 0;
    try {
      while (pending.isNotEmpty && visited < 5000) {
        final dir = pending.removeLast();
        try {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is Directory) {
              if (!entity.path.contains('/Android/data/')) pending.add(entity);
            } else if (entity is File) {
              visited++;
              try {
                final stat = await entity.stat();
                if (stat.size >= 100 * 1024 * 1024 ||
                    DateTime.now().difference(stat.modified).inDays >= 180) {
                  candidates.add(entity);
                }
              } catch (_) {}
            }
            if (visited >= 5000) break;
          }
        } catch (_) {}
      }
      candidates.sort((a, b) => b.statSync().size.compareTo(a.statSync().size));
      if (mounted) setState(() => _cleanupSuggestions = candidates);
      _say('Smart Cleanup found ${candidates.length} large or older files. Nothing was deleted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _toolCard(String title, String subtitle, IconData icon, VoidCallback action) =>
    Card(color: const Color(0xFF12313F).withOpacity(.92), child: ListTile(
      leading: Icon(icon, color: widget.accent, size: 28),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy ? null : action,
    ));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF071E2A),
    appBar: AppBar(title: const Text('Aqua Advanced Tools'), backgroundColor: Colors.transparent),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const LinearProgressIndicator(),
      Text(_status, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      _toolCard('Encrypted Secret Vault', 'AES-256-GCM encryption, PIN and device authentication', Icons.lock, _openVault),
      _toolCard('Create ZIP', 'Compress selected files into one archive', Icons.archive, _createZip),
      _toolCard('Extract ZIP', 'Extract an archive with path-traversal checks', Icons.unarchive, _extractZip),
      _toolCard('GPS photo map', 'Read EXIF GPS from selected images and open map locations', Icons.location_on, _scanGpsPhotos),
      if (_geoPhotos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Photo locations (${_geoPhotos.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        ..._geoPhotos.map((photo) => ListTile(
          leading: const Icon(Icons.photo, color: Colors.cyanAccent),
          title: Text(photo.file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${photo.latitude.toStringAsFixed(5)}, ${photo.longitude.toStringAsFixed(5)}'),
          trailing: IconButton(icon: const Icon(Icons.map), onPressed: () => _openMap(photo)),
        )),
      ],
      _toolCard('Smart Cleanup suggestions', 'Find large and older files; never delete automatically', Icons.cleaning_services, _smartCleanup),
      if (_cleanupSuggestions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Review suggestions (${_cleanupSuggestions.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        ..._cleanupSuggestions.take(100).map((file) => ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.info_outline),
        )),
      ],
      _toolCard('Import from SD card / USB', 'Use Android system picker to select files from removable storage', Icons.usb, _importExternal),
      _toolCard('Face Similarity / Person Albums', 'Not enabled: requires a bundled offline face-embedding model and device testing', Icons.face, () {
        _say('Face detection alone cannot safely identify matching people. Similarity albums need a verified offline embedding model; this feature is not falsely marked as complete.');
      }),
      const SizedBox(height: 12),
      const Text('Privacy: GPS scans only the images you select. Vault files are encrypted locally; losing the PIN and device key means the original files cannot be recovered.', style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]),
  );
}

class _GeoPhoto {
  const _GeoPhoto(this.file, this.latitude, this.longitude);
  final File file;
  final double latitude;
  final double longitude;
}
