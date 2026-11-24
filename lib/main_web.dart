import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const AquaApp());

class AquaApp extends StatefulWidget {
  const AquaApp({super.key});

  @override
  State<AquaApp> createState() => _AquaAppState();
}

class _AquaAppState extends State<AquaApp> {
  List<PlatformFile> _files = <PlatformFile>[];
  bool _isPickingFiles = false;

  Future<void> _pickFiles() async {
    setState(() => _isPickingFiles = true);
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && mounted) {
        setState(() => _files = <PlatformFile>[..._files, ...result.files]);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select files: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bubble File Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20E4E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Bubble File Manager')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Your browser workspace',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select files to view their names and sizes. Files stay on '
                    'your device; this web app does not browse device storage '
                    'or upload file contents.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isPickingFiles ? null : _pickFiles,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                        _isPickingFiles ? 'Opening files…' : 'Select files'),
                  ),
                  const SizedBox(height: 16),
                  Text('${_files.length} selected file(s)'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _files.isEmpty
                        ? const Center(child: Text('No files selected'))
                        : ListView.builder(
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              return ListTile(
                                leading: const Icon(
                                    Icons.insert_drive_file_outlined),
                                title: Text(file.name),
                                subtitle: Text(_formatSize(file.size)),
                                trailing: IconButton(
                                  tooltip: 'Remove ${file.name}',
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _files.removeAt(index)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
