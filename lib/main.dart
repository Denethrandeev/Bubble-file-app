import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const AquaApp());

const accents = <Color>[
  Color(0xFF18D8E8), Color(0xFF9B7BFF), Color(0xFF45D6A0),
  Color(0xFFFFB84D), Color(0xFFFF70B7),
];

class AquaApp extends StatefulWidget {
  const AquaApp({super.key});
  @override
  State<AquaApp> createState() => _AquaAppState();
}

class _AquaAppState extends State<AquaApp> {
  int tab = 0;
  int themeIndex = 0;
  bool animations = true;
  bool sound = true;
  bool performance = false;

  @override
  Widget build(BuildContext context) {
    final accent = accents[themeIndex];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF061923),
        colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: AquaBackdrop()),
          if (animations) Positioned.fill(child: BubbleField(accent: accent, reduced: performance)),
          SafeArea(child: Column(children: [
            _topBar(accent),
            Expanded(child: IndexedStack(index: tab, children: [
              _home(accent),
              _files(accent),
              _settings(accent),
            ])),
            _navigation(accent),
          ])),
        ]),
      ),
    );
  }

  Widget _topBar(Color accent) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(
        color: accent.withOpacity(.15), borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withOpacity(.35))),
        child: Icon(Icons.water_drop_rounded, color: accent)),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('AQUA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 3)),
        Text('FILE MANAGER', style: TextStyle(fontSize: 9, letterSpacing: 2.2, color: Colors.white54)),
      ])),
      IconButton(onPressed: () => setState(() => tab = 2), icon: const Icon(Icons.tune_rounded, color: Colors.white70)),
    ]),
  );

  Widget _home(Color accent) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 22), children: [
    const SizedBox(height: 12),
    const Text('Your space,', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300)),
    const Text('beautifully organized.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
    const SizedBox(height: 22),
    _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.sd_storage_rounded, color: accent), const SizedBox(width: 9),
        const Text('PHONE STORAGE', style: TextStyle(fontSize: 11, letterSpacing: 1.8, color: Colors.white70))]),
      const SizedBox(height: 18),
      const Text('Storage overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('Storage access will appear here when enabled.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 18),
      ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(
        value: .38, minHeight: 7, backgroundColor: Colors.white10, color: accent)),
      const SizedBox(height: 9),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Storage preview', style: TextStyle(fontSize: 11, color: Colors.white54)),
        Text('38%', style: TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    ])),
    const SizedBox(height: 22),
    const Text('BROWSE YOUR FILES', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54)),
    const SizedBox(height: 12),
    GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55,
      children: [
        _category('Images', Icons.image_rounded, const Color(0xFF55C9E8)),
        _category('Videos', Icons.movie_rounded, const Color(0xFFB28BFF)),
        _category('Audio', Icons.headphones_rounded, const Color(0xFFFFB84D)),
        _category('Documents', Icons.description_rounded, const Color(0xFF45D6A0)),
        _category('Downloads', Icons.download_rounded, const Color(0xFFFF70B7)),
        _category('Recycle Bin', Icons.delete_outline_rounded, const Color(0xFF9DB8C5)),
      ]),
    const SizedBox(height: 18),
    _glass(child: Row(children: [
      Icon(Icons.shield_moon_rounded, color: accent, size: 27), const SizedBox(width: 13),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Private Vault', style: TextStyle(fontWeight: FontWeight.w600)),
        Text('Your private space is being prepared', style: TextStyle(fontSize: 11, color: Colors.white54)),
      ])),
      Icon(Icons.lock_outline_rounded, color: accent),
    ])),
  ]);

  Widget _category(String title, IconData icon, Color color) => InkWell(
    borderRadius: BorderRadius.circular(20), onTap: () => setState(() => tab = 1),
    child: _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 25), const SizedBox(height: 11),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    ])),
  );

  Widget _files(Color accent) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('My Files', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    const Text('Your folders and files will appear here after storage access is connected.',
      style: TextStyle(color: Colors.white60, height: 1.5)),
    const SizedBox(height: 20),
    _glass(child: Row(children: [Icon(Icons.folder_open_rounded, color: accent, size: 30),
      const SizedBox(width: 12), const Expanded(child: Text('Internal storage')),
      const Icon(Icons.chevron_right_rounded, color: Colors.white54)])),
    const SizedBox(height: 12),
    _glass(child: Row(children: [Icon(Icons.usb_rounded, color: accent, size: 30),
      const SizedBox(width: 12), const Expanded(child: Text('SD card / USB OTG')),
      const Icon(Icons.chevron_right_rounded, color: Colors.white54)])),
  ]);

  Widget _settings(Color accent) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
    const SizedBox(height: 18),
    _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ACCENT THEME', style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: Colors.white60)),
      const SizedBox(height: 15),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(accents.length, (i) =>
        GestureDetector(onTap: () => setState(() => themeIndex = i), child: Container(
          width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: accents[i],
            border: Border.all(color: themeIndex == i ? Colors.white : Colors.transparent, width: 3)))))),
    ])),
    const SizedBox(height: 12),
    _settingSwitch('Bubble animations', 'Show floating water bubbles', animations, (v) => setState(() => animations = v), accent),
    _settingSwitch('Bubble sound', 'Soft pop sound (audio engine pending)', sound, (v) => setState(() => sound = v), accent),
    _settingSwitch('Performance mode', 'Reduce animation workload', performance, (v) => setState(() => performance = v), accent),
    const SizedBox(height: 12),
    _glass(child: const Text('Aqua File Manager • Early development build\nFile access, vault security and media tools are not enabled yet.',
      style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.6))),
  ]);

  Widget _settingSwitch(String title, String subtitle, bool value, ValueChanged<bool> change, Color accent) =>
    Padding(padding: const EdgeInsets.only(bottom: 10), child: _glass(child: SwitchListTile(
      contentPadding: EdgeInsets.zero, value: value, onChanged: change, activeColor: accent,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
    )));

  Widget _glass({required Widget child}) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.065),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withOpacity(.12))),
    child: child,
  );

  Widget _navigation(Color accent) => Container(
    margin: const EdgeInsets.fromLTRB(20, 8, 20, 12), padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: const Color(0xCC102B38), borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(.12))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _navItem('Home', Icons.water_drop_rounded, 0, accent),
      _navItem('Files', Icons.folder_rounded, 1, accent),
      _navItem('Settings', Icons.settings_rounded, 2, accent),
    ]),
  );

  Widget _navItem(String label, IconData icon, int index, Color accent) => InkWell(
    onTap: () => setState(() => tab = index), borderRadius: BorderRadius.circular(16),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: tab == index ? accent : Colors.white54),
        Text(label, style: TextStyle(fontSize: 10, color: tab == index ? accent : Colors.white54)),
      ])),
  );
}

class AquaBackdrop extends StatelessWidget {
  const AquaBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const DecoratedBox(decoration: BoxDecoration(
    gradient: RadialGradient(center: Alignment(-.9, -1), radius: 1.1,
      colors: [Color(0x3324D9E7), Color(0x00061923)]),
  ));
}

class Bubble {
  Bubble(this.r, this.x, this.y, this.vx, this.vy, this.phase, this.speed, this.opacity, this.hue);
  double r, x, y, vx, vy, phase, speed, opacity, hue;
}

class BubbleField extends StatefulWidget {
  const BubbleField({super.key, required this.accent, required this.reduced});
  final Color accent;
  final bool reduced;
  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField> with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  final random = math.Random();
  final bubbles = <Bubble>[];
  Size size = Size.zero;
  Offset pointer = Offset.zero;
  double last = 0;
  @override
  void initState() {
    super.initState();
    ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_step)..repeat();
  }
  Bubble _newBubble({double? y}) {
    final r = 11 + random.nextDouble() * 33;
    final hue = HSLColor.fromColor(widget.accent).hue + random.nextDouble() * 24 - 12;
    return Bubble(r, random.nextDouble() * math.max(1, size.width), y ?? size.height + r,
      (random.nextDouble() - .5) * .3, -.25 - random.nextDouble() * .7,
      random.nextDouble() * math.pi * 2, .7 + random.nextDouble() * .8,
      .20 + random.nextDouble() * .34, hue);
  }
  void _step() {
    if (!mounted || size.isEmpty) return;
    final now = ticker.lastElapsedDuration?.inMicroseconds.toDouble() ?? 0;
    final dt = last == 0 ? 1.0 : ((now - last) / 16667).clamp(0.0, 2.0);
    last = now;
    final count = size.width < 520 ? (widget.reduced ? 10 : 20) : (widget.reduced ? 14 : 28);
    while (bubbles.length < count) bubbles.add(_newBubble(y: random.nextDouble() * size.height));
    for (final b in bubbles) {
      b.phase += .018 * dt;
      b.vx += math.sin(b.phase) * .012 * dt + (pointer.dx - .5) * .003 * dt;
      b.vy -= (.003 + b.r / 10000) * dt;
      b.vx *= math.pow(.986, dt).toDouble();
      b.vy *= math.pow(.991, dt).toDouble();
      b.x += b.vx * b.speed * dt * 8;
      b.y += b.vy * b.speed * dt * 8;
      if (b.x < b.r || b.x > size.width - b.r) b.vx *= -.72;
      b.x = b.x.clamp(b.r, math.max(b.r, size.width - b.r));
      if (b.y < -b.r - 50) b.vy = b.vy.abs() * .25;
      if (b.y > size.height + b.r) {
        final fresh = _newBubble();
        b.r = fresh.r; b.x = fresh.x; b.y = fresh.y; b.vx = fresh.vx; b.vy = fresh.vy;
        b.phase = fresh.phase; b.speed = fresh.speed; b.opacity = fresh.opacity; b.hue = fresh.hue;
      }
    }
    if (!widget.reduced) {
      for (var i = 0; i < bubbles.length; i++) {
        for (var j = i + 1; j < bubbles.length; j++) {
          final a = bubbles[i], b = bubbles[j];
          final dx = b.x - a.x, dy = b.y - a.y;
          final distance = math.sqrt(dx * dx + dy * dy);
          final minDistance = a.r + b.r;
          if (distance > 0 && distance < minDistance) {
            final nx = dx / distance, ny = dy / distance;
            final overlap = (minDistance - distance) * .5;
            a.x -= nx * overlap; a.y -= ny * overlap;
            b.x += nx * overlap; b.y += ny * overlap;
            final relative = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
            if (relative < 0) {
              final impulse = -(1 + .85) * relative * .5;
              a.vx -= impulse * nx; a.vy -= impulse * ny;
              b.vx += impulse * nx; b.vy += impulse * ny;
            }
          }
        }
      }
    }
    setState(() {});
  }
  @override
  void didUpdateWidget(covariant BubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Existing bubbles keep their hue; newly recycled bubbles use the current accent.
  }
  @override
  void dispose() { ticker.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    size = Size(constraints.maxWidth, constraints.maxHeight);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (d) => pointer = Offset((d.localPosition.dx / math.max(1, size.width)).clamp(0, 1), 0),
      onTapDown: (d) {
        final p = d.localPosition;
        var best = -1, bestDistance = double.infinity;
        for (var i = 0; i < bubbles.length; i++) {
          final b = bubbles[i], dist = (Offset(b.x, b.y) - p).distance;
          if (dist < b.r + 26 && dist < bestDistance) { best = i; bestDistance = dist; }
        }
        if (best >= 0) { bubbles[best] = _newBubble(); }
      },
      child: CustomPaint(painter: BubblePainter(bubbles), size: Size.infinite),
    );
  });
}

class BubblePainter extends CustomPainter {
  BubblePainter(this.bubbles);
  final List<Bubble> bubbles;
  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      final color = HSLColor.fromAHSL(1, b.hue % 360, .78, .58).toColor();
      final rect = Rect.fromCircle(center: Offset(b.x, b.y), radius: b.r);
      final paint = Paint()..shader = RadialGradient(center: const Alignment(-.34, -.38),
        colors: [Colors.white.withOpacity(b.opacity * .85), color.withOpacity(b.opacity * .55),
          color.withOpacity(b.opacity * .12)]).createShader(rect);
      canvas.drawCircle(Offset(b.x, b.y), b.r, paint);
      canvas.drawCircle(Offset(b.x, b.y), b.r, Paint()..style = PaintingStyle.stroke
        ..strokeWidth = 1.1..color = Color.lerp(Colors.white, color, .35)!.withOpacity(b.opacity));
      canvas.drawCircle(Offset(b.x - b.r * .34, b.y - b.r * .38), b.r * .17,
        Paint()..color = Colors.white.withOpacity(b.opacity * .75));
    }
  }
  @override
  bool shouldRepaint(covariant BubblePainter oldDelegate) => true;
}
