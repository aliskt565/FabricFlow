import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fabricflow/theme/app_theme.dart';
import 'package:fabricflow/widgets/skeletons.dart';
import 'package:fabricflow/screens/auth/login_screen.dart';
import 'package:fabricflow/screens/auth/signup_screen.dart';
import 'package:fabricflow/screens/customers/customer_screen.dart';
import 'package:fabricflow/screens/inventory/inventory_screen.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

void setupFirebaseCoreMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'initializeApp') {
        return {
          'name': methodCall.arguments['appName'] ?? '[DEFAULT]',
          'options': methodCall.arguments['options'] ?? {},
          'pluginConstants': {},
        };
      }
      return null;
    },
  );
}

void main() {
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  test('AppColors smoke test', () {
    expect(AppColors.primary, const Color(0xFF667EEA));
  });

  testWidgets('SkeletonBox and SkeletonCard render without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SkeletonBox(width: 100, height: 100),
              SkeletonCard(),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.byType(SkeletonCard), findsOneWidget);
  });

  testWidgets('Login form validation shows inline error messages', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    // Tap sign in button without entering anything
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    // Check error messages
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    // Enter invalid email and see validation error
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(textFields.at(0), 'invalidemail');
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('Signup form validation shows inline error messages', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SignupScreen(),
      ),
    );

    // Tap create account button without entering anything
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    // Enter mismatching passwords
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(4));

    await tester.enterText(textFields.at(0), 'John Doe');
    await tester.enterText(textFields.at(1), 'john@example.com');
    await tester.enterText(textFields.at(2), '123456');
    await tester.enterText(textFields.at(3), '1234567');
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('Customer form validation shows inline error messages', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomerScreen(),
      ),
    );

    // Tap Add Customer Floating Action Button
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify fields in bottom sheet
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(4)); // Name, Email, Phone, Address

    // Enter invalid email and submit
    await tester.enterText(textFields.at(0), 'Bob');
    await tester.enterText(textFields.at(1), 'notanemail');
    await tester.tap(find.text('Add Customer'));
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('Inventory form validation shows inline error messages', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InventoryScreen(),
      ),
    );

    // Tap Add Product FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify form fields: Product Name, Tag Number, Price, Stock, Description
    final textFields = find.byType(TextFormField);
    expect(textFields, findsAtLeastNWidgets(3));

    // Submit empty form and see validation messages
    await tester.tap(find.text('Add Product'));
    await tester.pump();

    expect(find.text('Product name is required'), findsOneWidget);
    expect(find.text('Required'), findsNWidgets(2)); // Price and Stock are required
  });
}