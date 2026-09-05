import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ESC/POS helpers for HS-802UL-style network printers (port 9100).
class EscPos {
  static final Uint8List init = Uint8List.fromList([0x1B, 0x40]);
  static final Uint8List cut = Uint8List.fromList([0x1D, 0x56, 0x00]);

  /// Kick cash drawer on pin 2 (most HS-802UL setups).
  static final Uint8List drawerKickPin2 = Uint8List.fromList([
    0x1B,
    0x70,
    0x00,
    0x19,
    0xFA,
  ]);

  /// Kick cash drawer on pin 5 (alternate wiring).
  static final Uint8List drawerKickPin5 = Uint8List.fromList([
    0x1B,
    0x70,
    0x01,
    0x19,
    0xFA,
  ]);

  static Uint8List textLine(String line) {
    // CP437-ish safe ASCII for spike; keep simple for first hardware test.
    final safe = line.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    return Uint8List.fromList(utf8.encode('$safe\n'));
  }

  static Uint8List testReceipt({required String host}) {
    final chunks = <int>[
      ...init,
      ...textLine('CoffeeSpot'),
      ...textLine('Printer spike test'),
      ...textLine('Host: $host'),
      ...textLine(DateTime.now().toIso8601String()),
      ...textLine('----------------'),
      ...textLine('If you can read this,'),
      ...textLine('network print works.'),
      ...textLine(''),
      ...textLine(''),
      ...textLine(''),
      ...cut,
    ];
    return Uint8List.fromList(chunks);
  }
}

class PrinterClient {
  PrinterClient({required this.host, this.port = 9100, this.timeout = const Duration(seconds: 4)});

  final String host;
  final int port;
  final Duration timeout;

  Future<void> send(Uint8List bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } finally {
      await socket?.close();
    }
  }

  Future<void> testPrint() => send(EscPos.testReceipt(host: host));

  Future<void> openDrawer({bool pin5 = false}) =>
      send(pin5 ? EscPos.drawerKickPin5 : EscPos.drawerKickPin2);
}
