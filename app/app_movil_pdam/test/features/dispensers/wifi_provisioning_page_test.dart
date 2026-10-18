import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/dispensers/domain/entities/scanned_device.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/bloc/dispensers_bloc.dart';
import 'package:app_movil_pdam/features/dispensers/presentation/views/wifi_provisioning_page.dart';
import 'dispensers_bloc_test.dart';

void main() {
  testWidgets('WifiProvisioningPage displays 2.4GHz warning and form elements in Spanish', (WidgetTester tester) async {
    final mockDevice = const ScannedDevice(
      name: 'PDAM-Config-[123456]',
      remoteId: 'AA:BB:CC:DD:EE:FF',
      rssi: -45,
    );

    final mockRepo = MockDispensersRepository();
    final dispensersBloc = DispensersBloc(repository: mockRepo);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: dispensersBloc,
          child: WifiProvisioningPage(device: mockDevice),
        ),
      ),
    );

    // Verify 2.4GHz prominent warning text (RF-04 & RNF-05)
    expect(find.textContaining('SOLO es compatible con redes WiFi de 2.4GHz'), findsOneWidget);
    expect(find.text('Nombre de red WiFi (SSID - 2.4GHz)'), findsOneWidget);
    expect(find.text('Contraseña WiFi'), findsOneWidget);
    expect(find.text('Enviar Credenciales y Conectar'), findsOneWidget);

    dispensersBloc.close();
  });
}
