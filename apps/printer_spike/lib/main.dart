import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'escpos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrinterSpikeApp());
}

class PrinterSpikeApp extends StatelessWidget {
  const PrinterSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoffeeSpot Printer Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF85020),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SpikeHomePage(),
    );
  }
}

class SpikeHomePage extends StatefulWidget {
  const SpikeHomePage({super.key});

  @override
  State<SpikeHomePage> createState() => _SpikeHomePageState();
}

class _SpikeHomePageState extends State<SpikeHomePage> {
  static const _hostKey = 'printer_host';
  static const _portKey = 'printer_port';

  final _hostController = TextEditingController(text: '192.168.1.100');
  final _portController = TextEditingController(text: '9100');
  String _status = 'Enter printer IP (same Wi‑Fi as this tablet).';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_hostKey);
    final port = prefs.getInt(_portKey);
    if (!mounted) return;
    setState(() {
      if (host != null && host.isNotEmpty) _hostController.text = host;
      if (port != null) _portController.text = '$port';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, _hostController.text.trim());
    await prefs.setInt(_portKey, int.tryParse(_portController.text.trim()) ?? 9100);
  }

  PrinterClient _client() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    if (host.isEmpty) {
      throw StateError('Printer IP is required');
    }
    return PrinterClient(host: host, port: port);
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      await _save();
      await action();
      if (!mounted) return;
      setState(() => _status = '$label OK');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '$label failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF382010),
        foregroundColor: Colors.white,
        title: const Text('CoffeeSpot · Printer spike'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Option 1 hardware test only.\n'
              'Same Wi‑Fi as HS-802UL. No POS yet.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _hostController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Printer IP',
                hintText: '192.168.x.x',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '9100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run('Test print', () => _client().testPrint()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFFF85020),
              ),
              child: const Text('Test print'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run('Open kaha (pin 2)', () => _client().openDrawer()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: const Text('Open kaha (pin 2)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        'Open kaha (pin 5)',
                        () => _client().openDrawer(pin5: true),
                      ),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Open kaha (pin 5 alternate)'),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(_status, style: const TextStyle(height: 1.35)),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
