import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_file_manager/main.dart';

void main() {
  testWidgets('Aqua File Manager opens its home screen', (tester) async {
    await tester.pumpWidget(const AquaApp());
    expect(find.text('AQUA'), findsOneWidget);
    expect(find.text('FILE MANAGER'), findsOneWidget);
    expect(find.text('Your space,'), findsOneWidget);
  });
}
