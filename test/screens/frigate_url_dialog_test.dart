import "package:danawallet/screens/settings/network/frigate_url_dialog.dart";
import "package:flutter/material.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart";
import "package:flutter_test/flutter_test.dart";

/// Acceptance tests for finding t_3ba59c28 (repro of the t_d3352d51
/// regression class): a failed frigate URL parse/probe must NOT close the
/// dialog and must NOT surface a transient raw-error snackbar; the dialog
/// stays open with a persistent inline error on the URL field so the user
/// can correct and retry without retyping.
///
/// The dialog is tested against injected [FrigateUrlDialog.validate]
/// callbacks (the real probe is a Rust bridge call); error-message
/// cleaning is tested against [frigateProbeFailureMessage].
void main() {
  Future<void> pumpDialog(WidgetTester tester,
      {required Future<String?> Function(String) validate}) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<dynamic>(
                context: context,
                builder: (dialogContext) => FrigateUrlDialog(
                  controller: controller,
                  titleText: "Set frigate url",
                  labelText: "host:port or ssl://host:port",
                  validate: validate,
                ),
              ),
              child: const Text("open"),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  testWidgets("probe failure: dialog stays open with inline field error",
      (tester) async {
    await pumpDialog(tester,
        validate: (url) async => "Frigate unreachable: connection refused");

    await tester.enterText(find.byType(TextField), "127.0.0.1:1");
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();

    // dialog is still up ...
    expect(find.text("Set frigate url"), findsOneWidget);
    // ... with the error shown inline on the field ...
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
        field.decoration!.errorText, "Frigate unreachable: connection refused");
    // ... and the typed URL is preserved for correction without retyping.
    expect(field.controller!.text, "127.0.0.1:1");
  });

  testWidgets("parse failure (empty input): dialog stays open, inline error",
      (tester) async {
    await pumpDialog(tester,
        validate: (url) async => "Invalid frigate url: URL is empty");

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();

    expect(find.text("Set frigate url"), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.errorText, "Invalid frigate url: URL is empty");
  });

  testWidgets("success: dialog closes and returns the url", (tester) async {
    String? captured;
    await pumpDialog(tester, validate: (url) async {
      captured = url;
      return null;
    });

    await tester.enterText(find.byType(TextField), "192.168.1.44:50002");
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();

    expect(captured, "192.168.1.44:50002");
    expect(find.text("Set frigate url"), findsNothing);
  });

  testWidgets("editing the field clears the stale inline error",
      (tester) async {
    await pumpDialog(tester,
        validate: (url) async => "Frigate unreachable: connection refused");

    await tester.enterText(find.byType(TextField), "127.0.0.1:1");
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(
        find.text("Frigate unreachable: connection refused"), findsOneWidget);

    await tester.enterText(find.byType(TextField), "192.168.1.44:50002");
    await tester.pump();
    expect(find.text("Frigate unreachable: connection refused"), findsNothing);
  });

  testWidgets("error message cleaning: no raw AnyhowException wrapper",
      (tester) async {
    final e = AnyhowException(
        "connection error: can\"t connect to socket \"127.0.0.1:1\": "
        "Connection refused (os error 111)");
    final msg = frigateProbeFailureMessage(e);
    expect(msg, startsWith("Frigate unreachable:"));
    expect(msg.contains("AnyhowException"), isFalse,
        reason: "raw Rust error wrapper must not leak to the UI");
    expect(msg, contains("Connection refused (os error 111)"));
  });
}
