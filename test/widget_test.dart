import 'package:flutter_test/flutter_test.dart';
import 'package:bubble_file_manager/main.dart';

void main() {
  testWidgets('Bubble File Manager shows splash then opens My Files home', (tester) async {
    await tester.pumpWidget(const AquaApp());

    expect(find.text('BUBBLE'), findsOneWidget);
    expect(find.text('FILE MANAGER'), findsOneWidget);
    expect(find.text('Safety and Relax File Management System'), findsOneWidget);
    expect(find.text('Created by H.G.Aluthge'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pump();

    expect(find.text('My Files'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
  });
}
