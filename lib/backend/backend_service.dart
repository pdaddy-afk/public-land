import 'dart:convert';

import '../services/models.dart';
import '../services/net.dart';

/// Where the web/PWA build is hosted. Share links open this page.
const appBaseUrl = String.fromEnvironment('APP_BASE_URL', defaultValue: 'https://pdaddy-afk.github.io/public-land/');

/// Optional free Supabase project. Leave empty to use link-only mode.
/// Pass at build time: --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// How outings and friends' replies travel between people.
abstract class BackendService {
  String get label;

  /// True when replies sync automatically (no reply link needed).
  bool get syncsReplies;

  /// Link a friend opens to see the outing and answer.
  Future<Uri> outingLink(Outing o);

  /// Called by the friend's device when they answer.
  /// Returns a reply link to send back to the organizer (link mode), or null
  /// when the answer was stored on the server.
  Future<Uri?> submitResponse(Outing o, OutingResponse r);

  /// Organizer pulls the latest answers.
  Future<List<OutingResponse>> fetchResponses(Outing o);

  static BackendService? _instance;
  static BackendService get instance => _instance ??= (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty)
      ? SupabaseBackend(supabaseUrl, supabaseAnonKey)
      : LinkBackend();
}

Uri buildLink(String param, Map<String, dynamic> payload) =>
    Uri.parse(appBaseUrl).replace(queryParameters: {param: LinkCodec.encode(payload)});

/// Default: no account, no server. The outing rides inside the link; friends
/// send a reply link back through any messenger (share sheet).
class LinkBackend implements BackendService {
  @override
  String get label => 'Link sharing (no account)';
  @override
  bool get syncsReplies => false;

  @override
  Future<Uri> outingLink(Outing o) async => buildLink('o', o.toShare());

  @override
  Future<Uri?> submitResponse(Outing o, OutingResponse r) async =>
      buildLink('r', {'i': o.id, 't': o.title, ...r.toJson()});

  @override
  Future<List<OutingResponse>> fetchResponses(Outing o) async => o.responses;
}

/// Optional: a free Supabase project (Postgres + REST). Turns on only when
/// SUPABASE_URL and SUPABASE_ANON_KEY are compiled in. See README for the SQL.
class SupabaseBackend implements BackendService {
  final String url;
  final String anonKey;
  SupabaseBackend(this.url, this.anonKey);

  @override
  String get label => 'Supabase sync';
  @override
  bool get syncsReplies => true;

  Map<String, String> get _h => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      };

  @override
  Future<Uri> outingLink(Outing o) async {
    try {
      await Net.post(Uri.parse('$url/rest/v1/outings'), jsonEncode({'id': o.id, 'data': o.toShare()}), extra: _h);
    } catch (_) {
      // Link still works without the server copy.
    }
    return buildLink('o', o.toShare());
  }

  @override
  Future<Uri?> submitResponse(Outing o, OutingResponse r) async {
    try {
      await Net.post(
          Uri.parse('$url/rest/v1/responses'),
          jsonEncode({'outing_id': o.id, 'name': r.name, 'data': r.toJson()}),
          extra: _h);
      return null;
    } catch (_) {
      return LinkBackend().submitResponse(o, r); // fall back to a reply link
    }
  }

  @override
  Future<List<OutingResponse>> fetchResponses(Outing o) async {
    final body = await Net.get(Uri.parse('$url/rest/v1/responses?outing_id=eq.${Uri.encodeComponent(o.id)}&select=data'),
        extra: _h);
    final list = jsonDecode(body) as List;
    return [for (final row in list) OutingResponse.fromJson(((row as Map)['data'] as Map).cast<String, dynamic>())];
  }
}
