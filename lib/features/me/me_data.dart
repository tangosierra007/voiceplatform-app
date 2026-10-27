import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calls/numbers.dart';
import '../../net/api.dart';

final callSettingsProvider = FutureProvider<CallSettings?>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return null;
  return ref.watch(appApiProvider).me.getMeCallSettings();
});

/// The office-hours schedule this user may change (the first one).
final officeHoursProvider = FutureProvider<OfficeHours?>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return null;
  final list = await ref.watch(appApiProvider).me.getMeOfficeHours();
  return list.firstOrNull;
});

final devicesProvider = FutureProvider<List<DeviceSummary>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return ref.watch(appApiProvider).device.getMeDevices();
});

final recordingsProvider = FutureProvider<List<Recording>>((ref) async {
  if (ref.watch(accessTokenProvider) == null) return const [];
  return (await ref.watch(appApiProvider).recordings.getRecordings()).items;
});

/// When Do not disturb ends, if it was set with an end.
final dndUntilProvider = NotifierProvider<DndUntilNotifier, DateTime?>(
  DndUntilNotifier.new,
);

class DndUntilNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => ref.watch(meProvider).value?.status.dndUntil;
  void set(DateTime? until) => state = until;
}

/// "Desk phone and app 15 s, then voicemail".
String callSettingsSummary(CallSettings s) {
  final forward = s.forwardAlwaysTo;
  if (forward != null && forward.isNotEmpty) {
    return 'All calls go to ${formatAuNumber(forward)}';
  }
  final devices = [
    for (final d in s.ringDevices)
      switch (d) {
        CallSettingsRingDevices.deskPhone => 'desk phone',
        CallSettingsRingDevices.apps => 'app',
        _ => 'mobile',
      },
  ];
  final ring = devices.isEmpty ? 'Nothing rings' : devices.join(' and ');
  final parts = [
    '${ring[0].toUpperCase()}${ring.substring(1)} ${s.ringSeconds} s',
    if (s.followMeTo != null && s.followMeTo!.isNotEmpty)
      '${formatAuNumber(s.followMeTo!)}${s.followMeSeconds == null ? '' : ' ${s.followMeSeconds} s'}',
    s.thenTo == CallSettingsThenTo.hangup ? 'end the call' : 'voicemail',
  ];
  return parts.join(', then ');
}

/// "This Pixel 8, Windows PC".
String devicesSummary(List<DeviceSummary> devices) => [
  for (final d in devices)
    if (d.kind != DeviceSummaryKind.deskPhone &&
        d.kind != DeviceSummaryKind.dect)
      d.isThisDevice ? 'This ${d.label}' : d.label,
].join(', ');
