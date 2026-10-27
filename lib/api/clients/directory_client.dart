// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unnecessary_cast, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/colleagues.dart';
import '../models/presence_entry.dart';
import '../models/shared_contact.dart';
import '../models/team.dart';

part 'directory_client.g.dart';

@RestApi()
abstract class DirectoryClient {
  factory DirectoryClient(Dio dio, {String? baseUrl}) = _DirectoryClient;

  /// Colleagues in the tenant with presence (AppContacts, AppTransfer)
  @GET('/directory/colleagues')
  Future<Colleagues> getDirectoryColleagues();

  /// Ring groups as teams, with members and how many are free (AppContacts Teams)
  @GET('/directory/teams')
  Future<List<Team>> getDirectoryTeams();

  /// The tenant phonebook entries marked "in the apps" (B18)
  @GET('/directory/shared-contacts')
  Future<List<SharedContact>> getDirectorySharedContacts({
    @Query('q') String? q,
  });

  /// Live presence and badge events (Server-Sent Events), foreground only.
  ///
  /// Opened while the app is in the foreground, closed when it goes to the background.
  /// Events, each `data` a JSON object:.
  /// - `presence.snapshot`: `{ items: PresenceEntry[] }`, first, for the user's tenant.
  /// - `presence`: one `PresenceEntry`, per change, at most one per extension per second.
  /// - `badges`: `{ recents, messages }` when either changes.
  /// - `reauth`: the access token expires within a minute; reconnect with a new one.
  /// A comment line every 25 s keeps the connection open. One stream per device; a second.
  /// one closes the first. Changes fan out across API replicas with PostgreSQL NOTIFY on a.
  /// per-tenant channel, so a stream only ever carries its own tenant's events (T1).
  ///
  /// [lastEventId] - Ignored for presence (a fresh snapshot is sent); kept for the SSE client.
  @GET('/events')
  Future<String> getEvents({
    @Header('Last-Event-ID') String? lastEventId,
  });

  /// Presence snapshot; the fallback when the event stream fails three times (polled every 30 s while Contacts or Transfer is open)
  @GET('/presence')
  Future<List<PresenceEntry>> getPresence({
    @Header('If-None-Match') String? ifNoneMatch,
  });
}
