import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/home_tabs.dart';
import 'screens/outing_screens.dart';
import 'services/models.dart';
import 'services/store.dart';
import 'widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.init();
  runApp(const PublicLandApp());
}

class PublicLandApp extends StatelessWidget {
  const PublicLandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Public Land',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LinkGate(),
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
