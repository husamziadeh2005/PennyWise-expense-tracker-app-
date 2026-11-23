import 'package:flutter/material.dart';

import 'package:expense_tracker/app.dart';
import 'package:expense_tracker/features/auth/auth_service.dart';
import 'package:expense_tracker/state/app_state.dart';

/// App entry point: connect to Supabase, restore the saved theme, start the UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.init();
  await ThemeController.instance.load();
  runApp(const PennyWiseApp());
}
