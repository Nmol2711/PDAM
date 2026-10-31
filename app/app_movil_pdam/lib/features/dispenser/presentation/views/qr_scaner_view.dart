import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:app_movil_pdam/core/services/qr_validator.dart';
import 'package:app_movil_pdam/features/dispenser/presentation/widgets/scanner_notice_band.dart';
import 'package:go_router/go_router.dart';

/// Muestra el aviso de QR inválido con el rol de error y su contenido.
void mostrarErrorQr(BuildContext context) {
  final esquema = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: esquema.error,
      content: Text(
        'Código QR inválido para el sistema PDAM',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: esquema.onError),
      ),
    ),
  );
}

class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;
  String? _scannerError;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _handleBarcode(Barcode barcode) {
    if (_isProcessing) return;

    final String? rawValue = barcode.rawValue;
    if (rawValue == null) return;

    setState(() {
      _isProcessing = true;
    });

    final result = QrValidator.processQrCode(rawValue);
    if (result['mac_address'] != null && result['secret_key_qr'] != null) {
      context.pop(result);
      return;
    }

    mostrarErrorQr(context);

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR del Dispensador')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                _handleBarcode(barcodes.first);
              }
            },
            placeholderBuilder: (context, child) {
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, child) {
              final String message = error.errorCode.name;
              return ScannerNoticeBand(
                message: 'No se pudo iniciar la cámara:\n$message',
              );
            },
          ),
          if (_scannerError != null)
            ScannerNoticeBand(message: _scannerError!, withScrim: true),
        ],
      ),
    );
  }
}
