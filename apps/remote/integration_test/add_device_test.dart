// Full add-device flow on a real emulator or simulator, with the Simulated
// transport (no IR hardware needed). CI runs this nightly on an Android
// emulator; run locally with:
//   cd apps/remote && flutter test integration_test -d <device>
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:irremote/app.dart';
import 'package:irremote/data/database.dart';
import 'package:irremote/services/app_services.dart';
import 'package:irremote/services/code_library_loader.dart';
import 'package:irremote/transports/android_consumer_ir.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add a TV from the bundled database and use it', (tester) async {
    final sim = SimulatedTransport();
    final services = await AppServices.create(
      db: AppDatabase(NativeDatabase.memory()),
      codes: await loadBundledCodeLibrary(),
      emitter: EmitterInfo.none,
      extraTransports: [sim],
    );
    await services.settings.completeOnboarding();
    await tester.pumpWidget(IrRemoteApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samsung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Set 1 of'), findsOneWidget);

    await tester.tap(find.textContaining('Send Power'));
    await tester.pumpAndSettle();
    expect(sim.sent, isNotEmpty);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    final confirm = find.textContaining('Send ');
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final before = sim.sent.length;
    await tester.tap(find.bySemanticsLabel('Power').first);
    await tester.pumpAndSettle();
    expect(sim.sent.length, before + 1);
    expect(sim.sent.last.signal.carrierHz, greaterThan(30000));
  });
}
