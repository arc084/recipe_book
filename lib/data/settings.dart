import 'dart:io';

import 'package:flutter/material.dart';

/// How a sync conflict is resolved. The default is to ask — it is the user's
/// call, not the app's.

/// A device this one exchanges changes with. No account, no server — pairing
/// is a six-digit code typed on the device being added.
class PairedDevice {
  PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.recipeCount,
    required this.pantryCount,
    this.lastSync,
    this.psk,
    this.lastAddress,
    this.libraryWatermark,
    this.pantryWatermark,
  });

  final String id;
  String name;
  String platform;
  int recipeCount;
  int pantryCount;
  DateTime? lastSync;

  /// The highest stamp already taken from this peer, per database.
  ///
  /// Nothing at or below these is new, so a second sync with no changes in
  /// between transfers nothing and — crucially — re-asks nothing. A stamp
  /// alone cannot say "I have already seen and superseded your version".
  DateTime? libraryWatermark;
  DateTime? pantryWatermark;

  /// The shared secret both devices derived when they paired.
  ///
  /// Every later request is signed with it, so the six-digit code is needed
  /// once and never travels again. Null means the pairing never completed.
  String? psk;

  /// Where this device answered last time — a hint that saves a discovery
  /// round, never a substitute for one. Addresses change.
  String? lastAddress;

  bool get isPaired => psk != null;

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
    id: j['id'] as String,
    name: j['name'] as String,
    platform: j['platform'] as String? ?? '',
    recipeCount: (j['recipeCount'] as num?)?.toInt() ?? 0,
    pantryCount: (j['pantryCount'] as num?)?.toInt() ?? 0,
    lastSync: j['lastSync'] == null
        ? null
        : DateTime.parse(j['lastSync'] as String),
    psk: j['psk'] as String?,
    lastAddress: j['lastAddress'] as String?,
    libraryWatermark: DateTime.tryParse(j['libraryWatermark'] as String? ?? ''),
    pantryWatermark: DateTime.tryParse(j['pantryWatermark'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'recipeCount': recipeCount,
    'pantryCount': pantryCount,
    'lastSync': lastSync?.toIso8601String(),
    'psk': psk,
    'lastAddress': lastAddress,
    'libraryWatermark': libraryWatermark?.toIso8601String(),
    'pantryWatermark': pantryWatermark?.toIso8601String(),
  };
}

/// A permission the app asks for when it first needs it, and lists here after.
class PermissionState {
  PermissionState({
    required this.key,
    required this.label,
    required this.purpose,
    this.granted = false,
  });

  final String key;
  final String label;

  /// Every row says what it is for.
  final String purpose;
  bool granted;

  static final defaults = <PermissionState>[
    PermissionState(
      key: 'microphone',
      label: 'Microphone',
      purpose: 'Voice commands in cook mode — next, back, repeat, timer, stop.',
    ),
    PermissionState(
      key: 'wakelock',
      label: 'Keep the screen awake',
      purpose: 'So the screen does not sleep while you are cooking.',
    ),
    PermissionState(
      key: 'web',
      label: 'Fetch from the web',
      purpose: 'Reading a recipe off a page when you import a link.',
    ),
    PermissionState(
      key: 'photos',
      label: 'Photos folder',
      purpose: 'Reading the photographs you drop onto recipe cards.',
    ),
    PermissionState(
      key: 'notifications',
      label: 'Timer notifications',
      purpose: 'Telling you a cook-mode timer has finished.',
    ),
  ];

  factory PermissionState.fromJson(Map<String, dynamic> j) {
    final base = defaults.firstWhere(
      (p) => p.key == j['key'],
      orElse: () => PermissionState(
        key: j['key'] as String,
        label: j['key'] as String,
        purpose: '',
      ),
    );
    return PermissionState(
      key: base.key,
      label: base.label,
      purpose: base.purpose,
      granted: j['granted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'key': key, 'granted': granted};
}

/// Per-device settings. Theme is deliberately one of them, so the kitchen
/// laptop and the phone can differ.
/// What this device calls itself before the user renames it.
///
/// It shows up in the *other* device's paired list, so "This PC" on a phone is
/// actively confusing.
String get defaultDeviceName => Platform.isAndroid ? 'This phone' : 'This PC';

class AppSettings {
  AppSettings({
    this.deviceId,
    this.themeMode = ThemeMode.dark,
    String? deviceName,
    List<PairedDevice>? devices,
    List<PermissionState>? permissions,
    this.lastSync,
  }) : deviceName = deviceName ?? defaultDeviceName,
       devices = devices ?? <PairedDevice>[],
       permissions =
           permissions ??
           [
             for (final p in PermissionState.defaults)
               PermissionState(key: p.key, label: p.label, purpose: p.purpose),
           ];

  /// This device's identity, minted once on first run.
  ///
  /// Every stamp names the device that wrote it, so this has to exist before
  /// anything is loaded or stamped — see `AppState.load`.
  String? deviceId;

  ThemeMode themeMode;

  /// What the other device calls this one in its paired list. Defaults to
  /// something true of the platform rather than "This PC" on a phone.
  String deviceName;
  final List<PairedDevice> devices;
  final List<PermissionState> permissions;
  DateTime? lastSync;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == j['themeMode'],
      orElse: () => ThemeMode.dark,
    ),
    deviceName: j['deviceName'] as String?,
    devices: [
      for (final d in (j['devices'] as List? ?? []))
        PairedDevice.fromJson(d as Map<String, dynamic>),
    ],
    permissions: [
      for (final p in (j['permissions'] as List? ?? []))
        PermissionState.fromJson(p as Map<String, dynamic>),
    ],
    lastSync: j['lastSync'] == null
        ? null
        : DateTime.parse(j['lastSync'] as String),
  );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'themeMode': themeMode.name,
    'deviceName': deviceName,
    'devices': [for (final d in devices) d.toJson()],
    'permissions': [for (final p in permissions) p.toJson()],
    'lastSync': lastSync?.toIso8601String(),
  };
}
