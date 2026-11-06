import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LocationAlbumsPage extends StatefulWidget {
  const LocationAlbumsPage({super.key, required this.targetDirectory, required this.accent});
  final Directory targetDirectory;
  final Color accent;

  @override
  State<LocationAlbumsPage> createState() => _LocationAlbumsPageState();
}

class _LocationAlbumsPageState extends State<LocationAlbumsPage> {
  bool _scanning = false;
  int _checked = 0;
  String _status = 'Scan photos to find locations saved in their GPS metadata.';
  List<_LocatedPhoto> _photos = <_LocatedPhoto>[];

  Map<String, List<_LocatedPhoto>> get _groups {
    final result = <String, List<_LocatedPhoto>>{};
    for (final photo in _photos) {
      // Three decimal places groups photos within roughly 100 metres.
      final key = '${photo.latitude.toStringAsFixed(3)}, ${photo.longitude.toStringAsFixed(3)}';
      (result[key] ??= <_LocatedPhoto>[]).add(photo);
    }
    return result;
  }

  double? _coordinate(String? raw, String reference) {
    if (raw == null) return null;
    final values = RegExp(r'-?\d+(?:\.\d+)?').allMatches(raw)
        .map((match) => double.tryParse(match.group(0)!))
        .whereType<double>().toList();
    if (values.isEmpty) return null;
    final degrees = values[0].abs();
    final minutes = values.length > 1 ? values[1] : 0.0;
    final seconds = values.length > 2 ? values[2] : 0.0;
    var value = degrees + minutes / 60 + seconds / 3600;
    if (reference.toUpperCase().contains('S') || reference.toUpperCase().contains('W')) {
      value = -value;
    }
    return value;
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _checked = 0;
      _status = 'Reading photo GPS metadata on this device…';
    });
    final roots = <Directory>[];
    final seenRoots = <String>{};
    for (final path in <String>[widget.targetDirectory.path, '/storage/emulated/0', '/storage']) {
      final root = Directory(path);
      if (await root.exists() && seenRoots.add(root.path)) roots.add(root);
    }
    try {
      final pending = <Directory>[...roots];
      final visited = <String>{};
      final found = <_LocatedPhoto>[];
      const extensions = <String>{'jpg', 'jpeg', 'tif', 'tiff', 'heic', 'heif'};
      const maxFiles = 5000;
      while (pending.isNotEmpty && _checked < maxFiles) {
        final directory = pending.removeLast();
        if (!visited.add(directory.path)) continue;
        try {
          await for (final entity in directory.list(followLinks: false)) {
            if (entity is Directory) {
              final path = entity.path;
              final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
              if (name.startsWith('.') ||
                  path.contains('/Android/data') ||
                  path.contains('/Android/obb') ||
                  path.contains('/aqua_encrypted_vault') ||
                  path.contains('/aqua_recycle_bin')) continue;
              pending.add(entity);
            } else if (entity is File) {
              final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
              final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
              if (!extensions.contains(extension)) continue;
              _checked++;
              if (_checked % 40 == 0 && mounted) {
                setState(() => _status = 'Checked $_checked photos…');
              }
              try {
                final length = await entity.length();
                if (length == 0 || length > 20 * 1024 * 1024) continue;
                final tags = await readExifFromBytes(await entity.readAsBytes());
                final lat = _coordinate(tags['GPS GPSLatitude']?.printable,
                    tags['GPS GPSLatitudeRef']?.printable ?? 'N');
                final lon = _coordinate(tags['GPS GPSLongitude']?.printable,
                    tags['GPS GPSLongitudeRef']?.printable ?? 'E');
                if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
                found.add(_LocatedPhoto(entity, lat, lon));
              } catch (_) {
                // Ignore unsupported, damaged, or inaccessible images and continue.
              }
              if (_checked >= maxFiles) break;
            }
          }
        } catch (_) {
          // Android may deny access to individual folders; continue with the rest.
        }
      }
      if (!mounted) return;
      setState(() {
        _photos = found;
        _status = 'Checked $_checked photos. Found GPS details in ${found.length} photos across ${_groups.length} location groups.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Location scan failed: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _showMap(_LocatedPhoto selected, List<_LocatedPhoto> photos) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF102B38),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .76,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Photo location map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(selected.latitude, selected.longitude),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.aqua.filemanager',
                ),
                MarkerLayer(markers: photos.map((photo) => Marker(
                  point: LatLng(photo.latitude, photo.longitude),
                  width: 38,
                  height: 42,
                  child: Icon(Icons.location_on, color: widget.accent, size: 36),
                )).toList()),
              ],
            )),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Map tiles are loaded from OpenStreetMap. Exact coordinates remain in this app; place-name lookup is not enabled.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.white60)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF071E2A),
    appBar: AppBar(
      title: const Text('Location Albums'),
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(
          tooltip: 'Scan photos',
          onPressed: _scanning ? null : _scan,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF12313F),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.location_on_rounded, color: widget.accent, size: 28),
                const SizedBox(width: 10),
                const Expanded(child: Text('Find photos by captured location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ]),
              const SizedBox(height: 8),
              const Text('Uses GPS coordinates embedded in photo metadata. Photos without GPS data cannot be assigned a real location.',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.travel_explore),
                label: Text(_scanning ? 'Scanning…' : 'Scan phone photos'),
              ),
              if (_scanning) const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 5),
              const Text('Privacy: GPS metadata is processed locally. Opening the map loads map tiles from OpenStreetMap.',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (_groups.isNotEmpty) ...[
          Text('PLACES FOUND • ${_groups.length}', style: const TextStyle(
            letterSpacing: 1.4, color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._groups.entries.map((entry) {
            final photos = entry.value;
            final first = photos.first;
            return Card(
              color: const Color(0xFF12313F),
              child: ExpansionTile(
                leading: Icon(Icons.place_rounded, color: widget.accent),
                title: Text('Location group • ${photos.length} photo(s)'),
                subtitle: Text(entry.key, style: const TextStyle(color: Colors.white60)),
                trailing: IconButton(
                  tooltip: 'Show this group on map',
                  onPressed: () => _showMap(first, photos),
                  icon: const Icon(Icons.map_outlined),
                ),
                children: photos.map((photo) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.photo_outlined, color: Colors.white70),
                  title: Text(photo.file.uri.pathSegments.last,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(photo.file.parent.path,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  trailing: IconButton(
                    tooltip: 'Show photo location',
                    onPressed: () => _showMap(photo, <_LocatedPhoto>[photo]),
                    icon: const Icon(Icons.location_searching),
                  ),
                )).toList(),
              ),
            );
          }),
        ] else if (!_scanning) const Padding(
          padding: EdgeInsets.all(22),
          child: Text('No location albums yet. Scan your photos to look for GPS metadata.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );
}

class _LocatedPhoto {
  const _LocatedPhoto(this.file, this.latitude, this.longitude);
  final File file;
  final double latitude;
  final double longitude;
}
