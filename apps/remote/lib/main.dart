import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database.dart';
import 'services/app_services.dart';
import 'services/code_library_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase(driftDatabase(name: 'irremote'));
  final codes = await loadBundledCodeLibrary();
  final services = await AppServices.create(db: db, codes: codes);
  runApp(IrRemoteApp(services: services));
}
