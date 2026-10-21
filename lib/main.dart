import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/home_tabs.dart';
import 'screens/outing_screens.dart';
import 'services/models.dart';
import 'services/store.dart';
import 'widgets/glass.dart';

/// Last startup/runtime error, shown on screen instead of a blank screen.
final ValueNotifier<String?> bootError = ValueNotifier(null);

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      bootError.value ??= d.exceptionAsString();
    };
    ErrorWidget.builder = (d) => Material(
          color: const Color(0xFF1B1F24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Something went wrong:\n${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        );
    try {
      await Store.instance.init().timeout(const Duration(seconds: 5));
    } catch (e) {
      bootError.value = 'Storage failed to load: $e';
    }
    runApp(const PublicLandApp());
  }, (e, st) {
    bootError.value ??= '$e';
  });
}

class PublicLandApp extends StatelessWidget {
  const PublicLandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Public Land',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ValueListenableBuilder<String?>(
        valueListenable: bootError,
        builder: (context, err, child) => Stack(children: [
          child!,
          if (err != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 100,
              child: Material(
                color: const Color(0xEE7A1E2C),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: SelectableText('Error: $err',
                          maxLines: 6, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => bootError.value = null,
                    ),
                  ]),
                ),
              ),
            ),
        ]),
        child: const LinkGate(),
      ),
    );
  }
}

/// Opens outing (?o=) and reply (?r=) links on the web build; otherwise the tabs.
class LinkGate extends StatefulWidget {
  const LinkGate({super.key});
  @override
  State<LinkGate> createState() => _LinkGateState();
}

class _LinkGateState extends State<LinkGate> {
  Outing? _invite;
  String? _replyMsg;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _readUrl();
  }

  Future<void> _readUrl() async {
    final q = Uri.base.queryParameters;
    try {
      if (q['o'] != null) {
        final o = Outing.fromShare(LinkCodec.decode(q['o']!));
        final mine = Store.instance.outing(o.id);
        // The organizer opening their own link sees the organizer view.
        if (mine != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutingDetail(outingId: o.id)));
          });
        } else {
          setState(() => _invite = o);
        }
      } else if (q['r'] != null) {
        final msg = await importReply(LinkCodec.decode(q['r']!));
        setState(() => _replyMsg = msg);
        final id = LinkCodec.decode(q['r']!)['i'] as String;
        if (Store.instance.outing(id) != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutingDetail(outingId: id)));
          });
        }
      }
    } catch (_) {
      _replyMsg = 'That link could not be read.';
    }
    if (_replyMsg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) toast(context, _replyMsg!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invite;
    if (inv != null) {
      return Scaffold(
        body: Stack(children: [
          FriendRespondScreen(outing: inv),
          Positioned(
            right: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: TextButton(
              onPressed: () => setState(() => _invite = null),
              child: const Text('Open app', style: TextStyle(color: C.text2, fontSize: 15)),
            ),
          ),
        ]),
      );
    }
    return const HomeTabs();
  }
}
