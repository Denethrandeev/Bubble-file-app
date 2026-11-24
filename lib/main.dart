import 'main_web.dart' if (dart.library.io) 'main_android.dart' as app;

export 'main_web.dart' if (dart.library.io) 'main_android.dart';

void main() => app.main();
