// A bench app for vp_linphone: starts and stops the engine (the foreground
// service and its liblinphone Core) and shows what it reports. It never
// registers; live SIP tests go through mobile-lead.

import 'dart:async';

import 'package:call_engine/call_engine.dart';
import 'package:flutter/material.dart';
import 'package:vp_linphone/vp_linphone.dart';

void main() {
  // What the app does at start (WS4): the native licences into the licence list.
  addVpLinphoneLicenses();
  runApp(const BenchApp());
}

class BenchApp extends StatefulWidget {
  const BenchApp({super.key, this.engine});

  final CallEngine? engine;

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> {
  late final CallEngine _engine = widget.engine ?? VpLinphoneEngine();
  final List<String> _lines = [];
  final List<StreamSubscription<Object?>> _subs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_engine.registration.listen((e) => _add('registration ${e.state.name} ${e.failure?.name ?? ''}')))
      ..add(_engine.calls.listen((c) => _add('call ${c.id} ${c.state.name}')))
      ..add(_engine.audio.listen((a) => _add('audio ${a.route.name} of ${a.available.map((r) => r.name).join(',')}')));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() {
      _lines.insert(0, line);
      if (_lines.length > 50) _lines.removeLast();
    });
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    setState(() => _busy = true);
    try {
      final r = await action();
      _add('$label ok${r == null ? '' : ' $r'}');
    } on CallEngineError catch (e) {
      _add('$label failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('vp_linphone bench')),
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: _busy ? null : () => _run('start', _engine.start), child: const Text('Start')),
                OutlinedButton(onPressed: _busy ? null : () => _run('stop', _engine.stop), child: const Text('Stop')),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run('export', () async => '${(await _engine.exportLastCallLog()).length} bytes'),
                  child: const Text('Export log'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(children: [for (final l in _lines) ListTile(dense: true, title: Text(l))]),
            ),
          ],
        ),
      ),
    );
  }
}
