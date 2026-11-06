import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'face_albums.dart';
import 'location_albums.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

class AquaAdvancedTools extends StatefulWidget {
  const AquaAdvancedTools({
    super.key,
    required this.targetDirectory,
    required this.accent,
    this.openVaultOnStart = false,
  });
  final Directory targetDirectory;
  final Color accent;
  final bool openVaultOnStart;

  @override
  State<AquaAdvancedTools> createState() => _AquaAdvancedToolsState();
}

class _AquaAdvancedToolsState extends State<AquaAdvancedTools> {
  static const _secure = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    if (widget.openVaultOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openVault();
        // Return to the normal Home screen after the hidden Vault flow closes.
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }
  final _auth = LocalAuthentication();
  bool _busy = false;
  String _status = 'Choose a tool to begin.';
  List<File> _vaultFiles = <File>[];
  List<_GeoPhoto> _geoPhotos = <_GeoPhoto>[];
  List<File> _cleanupSuggestions = <File>[];
  Map<String, dynamic>? _deviceDiagnostics;
  String _performanceSummary = '';

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

  String _normaliseRecoveryAnswer(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<String> _saltedDigest(String value) async {
    final random = math.Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
    final digest = hashes.sha256.convert(utf8.encode('$salt:$value')).toString();
    return '$salt:$digest';
  }

  Future<bool> _verifyPin({bool setup = false}) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final recoveryQuestionController = TextEditingController();
    final recoveryAnswerController = TextEditingController();
    final storedHash = await _secure.read(key: 'aqua_vault_pin_hash');
    final salt = await _secure.read(key: 'aqua_vault_pin_salt');
    if (storedHash == null && !setup) {
      _say('Create a Vault PIN first.');
      return false;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(storedHash == null ? 'Create Vault PIN' : 'Unlock Vault'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pinController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN (at least 6 digits)')),
          if (storedHash == null) ...[
            TextField(controller: confirmController, obscureText: true, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm PIN')),
            TextField(controller: recoveryQuestionController,
              decoration: const InputDecoration(labelText: 'Your recovery question')),
            TextField(controller: recoveryAnswerController, obscureText: true,
              decoration: const InputDecoration(labelText: 'Your answer')),
          ],
        ])),
        actions: [
          if (storedHash != null)
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'recover'),
              child: const Text('Forgot PIN?')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'pin'),
            child: const Text('Continue')),
        ],
      ),
    );
    if (result == 'recover') {
      final recovered = await _recoverPin();
      pinController.dispose();
      confirmController.dispose();
      recoveryQuestionController.dispose();
      recoveryAnswerController.dispose();
      return recovered;
    }
    if (result != 'pin') {
      pinController.dispose();
      confirmController.dispose();
      recoveryQuestionController.dispose();
      recoveryAnswerController.dispose();
      return false;
    }

    final pin = pinController.text;
    if (storedHash == null) {
      final question = recoveryQuestionController.text.trim();
      final answer = _normaliseRecoveryAnswer(recoveryAnswerController.text);
      if (pin.length < 6 || pin != confirmController.text || question.length < 5 || answer.length < 2) {
        _say('Use a PIN of at least 6 digits, confirm it, and enter your own recovery question and answer.');
        pinController.dispose();
        confirmController.dispose();
        recoveryQuestionController.dispose();
      recoveryAnswerController.dispose();
        return false;
      }
      final pinRecord = await _saltedDigest(pin);
      final answerRecord = await _saltedDigest(answer);
      final key = await AesGcm.with256bits().newSecretKey();
      final keyBytes = await key.extractBytes();
      await _secure.write(key: 'aqua_vault_pin_salt', value: pinRecord.split(':').first);
      await _secure.write(key: 'aqua_vault_pin_hash', value: pinRecord.split(':').last);
      await _secure.write(key: 'aqua_vault_recovery_question', value: question);
      await _secure.write(key: 'aqua_vault_recovery_salt', value: answerRecord.split(':').first);
      await _secure.write(key: 'aqua_vault_recovery_hash', value: answerRecord.split(':').last);
      await _secure.write(key: 'aqua_vault_key', value: base64Encode(keyBytes));
      _say('Encrypted Vault created. Keep your PIN and recovery answer private.');
      pinController.dispose();
      confirmController.dispose();
      recoveryQuestionController.dispose();
      recoveryAnswerController.dispose();
      return true;
    }
    final digest = hashes.sha256.convert(utf8.encode('$salt:$pin')).toString();
    pinController.dispose();
    confirmController.dispose();
    recoveryQuestionController.dispose();
      recoveryAnswerController.dispose();
    if (digest != storedHash) {
      _say('Incorrect PIN.');
      return false;
    }
    return _setRecoveryAnswerIfMissing();
  }

  Future<bool> _setRecoveryAnswerIfMissing() async {
    final existing = await _secure.read(key: 'aqua_vault_recovery_hash');
    final existingQuestion = await _secure.read(key: 'aqua_vault_recovery_question');
    if (existing != null && existingQuestion != null) return true;
    final questionController = TextEditingController();
    final answerController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set up PIN recovery'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Create your own question and answer. Choose an answer that is private and difficult for others to guess.'),
          TextField(controller: questionController,
            decoration: const InputDecoration(labelText: 'Your recovery question')),
          TextField(controller: answerController, obscureText: true,
            decoration: const InputDecoration(labelText: 'Your answer')),
        ]),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save recovery answer')),
        ],
      ),
    );
    final question = questionController.text.trim();
    final answer = _normaliseRecoveryAnswer(answerController.text);
    questionController.dispose();
    answerController.dispose();
    if (result != true || question.length < 5 || answer.length < 2) {
      _say('A recovery question and answer are required to finish Vault sign-in.');
      return false;
    }
    final record = await _saltedDigest(answer);
    await _secure.write(key: 'aqua_vault_recovery_question', value: question);
    await _secure.write(key: 'aqua_vault_recovery_salt', value: record.split(':').first);
    await _secure.write(key: 'aqua_vault_recovery_hash', value: record.split(':').last);
    return true;
  }

  Future<bool> _recoverPin() async {
    final answerController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmController = TextEditingController();
    final recoveryQuestion = await _secure.read(key: 'aqua_vault_recovery_question');
    final recoverySalt = await _secure.read(key: 'aqua_vault_recovery_salt');
    final recoveryHash = await _secure.read(key: 'aqua_vault_recovery_hash');
    if (recoveryQuestion == null || recoverySalt == null || recoveryHash == null) {
      _say('Recovery is not configured on this Vault. Unlock with your PIN and set a recovery question first.');
      answerController.dispose();
      newPinController.dispose();
      confirmController.dispose();
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recover Vault PIN'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(recoveryQuestion),
          TextField(controller: answerController, obscureText: true,
            decoration: const InputDecoration(labelText: 'Your answer')),
          TextField(controller: newPinController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'New PIN (at least 6 digits)')),
          TextField(controller: confirmController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confirm new PIN')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reset PIN')),
        ],
      ),
    );
    if (result != true) {
      answerController.dispose();
      newPinController.dispose();
      confirmController.dispose();
      return false;
    }
    final answerDigest = hashes.sha256.convert(
      utf8.encode('$recoverySalt:${_normaliseRecoveryAnswer(answerController.text)}'),
    ).toString();
    final newPin = newPinController.text;
    if (answerDigest != recoveryHash || newPin.length < 6 || newPin != confirmController.text) {
      _say('Recovery answer or new PIN is invalid. Try again.');
      answerController.dispose();
      newPinController.dispose();
      confirmController.dispose();
      return false;
    }
    final pinRecord = await _saltedDigest(newPin);
    await _secure.write(key: 'aqua_vault_pin_salt', value: pinRecord.split(':').first);
    await _secure.write(key: 'aqua_vault_pin_hash', value: pinRecord.split(':').last);
    _say('PIN reset successfully. Your encrypted Vault files are unchanged.');
    answerController.dispose();
    newPinController.dispose();
    confirmController.dispose();
    return true;
  }

  Future<void> _changePin() async {
    if (!await _verifyPin()) return;
    final newPinController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Vault PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: newPinController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'New PIN (at least 6 digits)')),
          TextField(controller: confirmController, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confirm new PIN')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save PIN')),
        ],
      ),
    );
    if (result == true) {
      final pin = newPinController.text;
      if (pin.length < 6 || pin != confirmController.text) {
        _say('PIN must be at least 6 digits and both entries must match.');
      } else {
        final pinRecord = await _saltedDigest(pin);
        await _secure.write(key: 'aqua_vault_pin_salt', value: pinRecord.split(':').first);
        await _secure.write(key: 'aqua_vault_pin_hash', value: pinRecord.split(':').last);
        _say('Vault PIN changed successfully.');
      }
    }
    newPinController.dispose();
    confirmController.dispose();
  }

  Future<bool> _unlockVault() async {
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
    await _vaultDirectory();
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
            OutlinedButton.icon(
              onPressed: _busy ? null : _changePin,
              icon: const Icon(Icons.password),
              label: const Text('Change Vault PIN'),
            ),
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
      if (await source.length() > 100 * 1024 * 1024) throw StateError('For low-memory safety, Vault import is limited to 100 MB per file.');
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
      final name = (envelope['name'] as String).replaceAll(RegExp(r'[/\\]'), '_');
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
        if (await file.length() > 100 * 1024 * 1024) continue;
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(item.name, bytes.length, bytes));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw StateError('ZIP encoding failed.');
      final output = File('${widget.targetDirectory.path}/Aqua_${DateTime.now().millisecondsSinceEpoch}.zip');
      await output.writeAsBytes(encoded, flush: true);
      _say('ZIP created in the current Aqua folder. Files over 100 MB were skipped for low-memory safety.');
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
        final normalized = item.name.replaceAll('\\', '/');
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

  Future<void> _runDeviceDiagnostics() async {
    if (_busy) return;
    setState(() => _busy = true);
    _say('Checking Android storage access, removable volumes and runtime performance…');
    try {
      final stopwatch = Stopwatch()..start();
      var scannedEntries = 0;
      try {
        await for (final _ in widget.targetDirectory.list(followLinks: false).take(500)) {
          scannedEntries++;
        }
      } catch (_) {}
      stopwatch.stop();
      final diagnostics = await const MethodChannel('aqua/storage')
          .invokeMapMethod<String, dynamic>('deviceDiagnostics');
      if (diagnostics == null) {
        throw StateError('Android diagnostic channel returned no data. Rebuild the APK first.');
      }
      if (!mounted) return;
      setState(() {
        _deviceDiagnostics = diagnostics;
        _performanceSummary =
            'Current folder: $scannedEntries entries checked in ${stopwatch.elapsedMilliseconds} ms (maximum 500).';
      });
      _say('Device diagnostics completed. Physical USB/SD access still needs a real-device check.');
    } catch (e) {
      _say('Device diagnostics unavailable: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, List<_GeoPhoto>> get _geoGroups {
    final groups = <String, List<_GeoPhoto>>{};
    for (final photo in _geoPhotos) {
      final key = '${photo.latitude.toStringAsFixed(2)}, ${photo.longitude.toStringAsFixed(2)}';
      (groups[key] ??= <_GeoPhoto>[]).add(photo);
    }
    return groups;
  }

  Future<void> _openMap(_GeoPhoto photo) async {
    final locations = _geoPhotos.isEmpty ? <_GeoPhoto>[photo] : _geoPhotos;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF102B38),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Photo locations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(photo.latitude, photo.longitude),
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.aqua.filemanager',
                ),
                MarkerLayer(markers: locations.map((item) => Marker(
                  point: LatLng(item.latitude, item.longitude),
                  width: 42,
                  height: 42,
                  child: const Icon(Icons.location_on, color: Colors.redAccent, size: 38),
                )).toList()),
              ],
            )),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Map data © OpenStreetMap contributors',
                style: TextStyle(fontSize: 10, color: Colors.white60)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _smartCleanup() async {
    setState(() => _busy = true);
    final candidates = <File>[];
    final pending = <Directory>[];
    final seenRoots = <String>{};
    // Scan Android shared-storage mount points, including removable volumes
    // when Android exposes them to this app. SAF-only providers are not paths.
    for (final mount in <String>['/storage', '/mnt/media_rw']) {
      final root = Directory(mount);
      try {
        if (await root.exists()) {
          await for (final entry in root.list(followLinks: false)) {
            if (entry is Directory && seenRoots.add(entry.path)) pending.add(entry);
          }
        }
      } catch (_) {}
    }
    if (seenRoots.add(widget.targetDirectory.path)) pending.add(widget.targetDirectory);
    var visited = 0;
    try {
      while (pending.isNotEmpty && visited < 30000) {
        final dir = pending.removeLast();
        try {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is Directory) {
              if (!entity.path.contains('/Android/data/') &&
                  !entity.path.contains('/Android/obb/') &&
                  !entity.path.contains('/aqua_recycle_bin/') &&
                  !entity.path.contains('/aqua_encrypted_vault/')) pending.add(entity);
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
            if (visited >= 30000) break;
          }
        } catch (_) {}
      }
      candidates.sort((a, b) {
        try { return b.statSync().size.compareTo(a.statSync().size); } catch (_) { return 0; }
      });
      if (mounted) setState(() => _cleanupSuggestions = candidates);
      _say('Smart Cleanup scanned up to ${visited} files across accessible internal/removable storage mounts and found ${candidates.length} large or older files. Nothing was deleted.');
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

  Widget _diagnosticRow(String label, String value) => ListTile(
    dense: true,
    title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    subtitle: Text(value, style: const TextStyle(fontSize: 11)),
  );

  String _formatDiagnosticBytes(dynamic value) {
    final bytes = value is num ? value.toInt() : 0;
    if (bytes <= 0) return 'Unavailable';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var index = 0;
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(1)} ${units[index]}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF071E2A),
    appBar: AppBar(title: const Text('Aqua Advanced Tools'), backgroundColor: Colors.transparent),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const LinearProgressIndicator(),
      Text(_status, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 12),
      _toolCard('Secret Vault', 'Unlock your encrypted private files, create a PIN, import and export files', Icons.lock, _openVault),
      _toolCard('Create ZIP', 'Compress selected files into one archive', Icons.archive, _createZip),
      _toolCard('Extract ZIP', 'Extract an archive with path-traversal checks', Icons.unarchive, _extractZip),
      _toolCard('Location Albums', 'Group phone photos by embedded GPS location and view them on a map', Icons.location_on, () {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LocationAlbumsPage(
            targetDirectory: widget.targetDirectory,
            accent: widget.accent,
          ),
        ));
      }),
      if (_geoPhotos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Photo locations (${_geoPhotos.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        ..._geoGroups.entries.map((entry) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.place, color: Colors.cyanAccent),
              title: Text('Location group • ${entry.value.length} photo(s)'),
              subtitle: Text('Approx. ${entry.key}'),
              trailing: IconButton(icon: const Icon(Icons.map), onPressed: () => _openMap(entry.value.first)),
            ),
            ...entry.value.map((photo) => Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Text(photo.file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            )),
          ],
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
      _toolCard('Android 11+ storage & performance diagnostics', 'Check All files access, mounted storage volumes, RAM and current-folder scan time', Icons.memory, _runDeviceDiagnostics),
      if (_deviceDiagnostics != null) ...[
        const SizedBox(height: 8),
        _diagnosticRow('Android API', '${_deviceDiagnostics!['sdkInt'] ?? 'Unknown'}'),
        _diagnosticRow('All files access', '${_deviceDiagnostics!['allFilesAccess'] ?? 'Unknown'}'),
        _diagnosticRow('Total RAM', _formatDiagnosticBytes(_deviceDiagnostics!['totalRamBytes'])),
        _diagnosticRow('Available RAM', _formatDiagnosticBytes(_deviceDiagnostics!['availableRamBytes'])),
        _diagnosticRow('Mounted volumes', '${(_deviceDiagnostics!['volumes'] as List? ?? const []).length}'),
        ...((_deviceDiagnostics!['volumes'] as List? ?? const []).whereType<Map>().map((volume) =>
          _diagnosticRow(
            '${volume['removable'] == true ? 'Removable' : 'Storage'} • ${volume['state'] ?? 'unknown'}',
            '${volume['path'] ?? 'Path unavailable'}',
          ))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(_performanceSummary, style: const TextStyle(color: Colors.white70, fontSize: 11))),
      ],
      _toolCard('Import from SD card / USB', 'Use Android system picker to select files from removable storage', Icons.usb, _importExternal),
      _toolCard('Face Similarity / Person Albums', 'Find similar faces locally and review possible people groups', Icons.face_retouching_natural, () {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => FaceAlbumsPage(
            targetDirectory: widget.targetDirectory,
            accent: widget.accent,
          ),
        ));
      }),
      const SizedBox(height: 12),
      const Text('Privacy: photo GPS metadata is processed locally. Map tiles are requested from OpenStreetMap only when you open a map. Encrypted private files stay on this device; keep authentication details safe.', style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]),
  );
}

class _GeoPhoto {
  const _GeoPhoto(this.file, this.latitude, this.longitude);
  final File file;
  final double latitude;
  final double longitude;
}