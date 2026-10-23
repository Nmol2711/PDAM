import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/dispenser.dart';
import 'package:app_movil_pdam/features/dispenser/domain/entity/scanned_device.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/views/wifi_provisioning_page.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/device_card_widget.dart';

import '../../presentation/bloc/dispenser_bloc_test.dart';

void main() {
  testWidgets('WifiProvisioningPage displays 2.4GHz warning and form elements in Spanish', (WidgetTester tester) async {
    final mockDevice = const ScannedDevice(
      name: 'PDAM-Config-[123456]',
      remoteId: 'AA:BB:CC:DD:EE:FF',
      rssi: -45,
    );

    final mockRepo = MockDispenserRepository();
    final dispensersBloc = buildDispenserBloc(mockRepo);

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

  testWidgets('DeviceCardWidget oculta conexión y estado de WiFi pero conserva el reset (RF-1, RF-2)', (WidgetTester tester) async {
    const dispenser = Dispenser(
      id: 1,
      macAddress: 'AA:BB:CC:DD:EE:FF',
      name: 'Dispensador 1',
      isActive: true,
      wifiSsid: 'HomeWiFi',
      currentFoodGrams: 5000.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceCardWidget(dispenser: dispenser, onResetWifi: () {}),
        ),
      ),
    );

    expect(find.text('Estado de WiFi:'), findsNothing);
    expect(find.textContaining('Red:'), findsNothing);
    expect(find.text('Aún no se han proporcionado las credenciales de wifi'), findsNothing);
    expect(find.text('Conectado'), findsNothing);
    expect(find.text('Desconectado'), findsNothing);
    expect(find.text('Resetear WiFi'), findsOneWidget);
  });

  testWidgets('DeviceCardWidget no muestra el reset si no se proporciona (RF-1)', (WidgetTester tester) async {
    const dispenser = Dispenser(
      id: 1,
      macAddress: 'AA:BB:CC:DD:EE:FF',
      name: 'Dispensador 1',
      isActive: true,
      currentFoodGrams: 5000.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceCardWidget(dispenser: dispenser),
        ),
      ),
    );

    expect(find.text('Resetear WiFi'), findsNothing);
    expect(find.text('Estado de WiFi:'), findsNothing);
  });
}
