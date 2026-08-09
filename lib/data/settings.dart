import 'package:flutter/material.dart';

/// How a sync conflict is resolved. The default is to ask — it is the user's
/// call, not the app's.
enum ConflictPolicy {
  ask('Ask me'),
  newestWins('Newest wins'),
  keepBoth('Keep both');

  const ConflictPolicy(this.label);
  final String label;

  static ConflictPolicy parse(String? s) => ConflictPolicy.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ConflictPolicy.ask,
      );
}

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
  });

  final String id;
  String name;
  String platform;
  int recipeCount;
  int pantryCount;
  DateTime? lastSync;

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        platform: j['platform'] as String? ?? '',
        recipeCount: (j['recipeCount'] as num?)?.toInt() ?? 0,
        pantryCount: (j['pantryCount'] as num?)?.toInt() ?? 0,
        lastSync: j['lastSync'] == null
            ? null
            : DateTime.parse(j['lastSync'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'recipeCount': recipeCount,
        'pantryCount': pantryCount,
        'lastSync': lastSync?.toIso8601String(),
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
class AppSettings {
  AppSettings({
    this.themeMode = ThemeMode.dark,
    this.deviceName = 'This PC',
    this.conflictPolicy = ConflictPolicy.ask,
    List<PairedDevice>? devices,
    List<PermissionState>? permissions,
    this.lastSync,
  })  : devices = devices ?? <PairedDevice>[],
        permissions = permissions ??
            [
              for (final p in PermissionState.defaults)
                PermissionState(
                  key: p.key,
                  label: p.label,
                  purpose: p.purpose,
                ),
            ];

  ThemeMode themeMode;
  String deviceName;
  ConflictPolicy conflictPolicy;
  final List<PairedDevice> devices;
  final List<PermissionState> permissions;
  DateTime? lastSync;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == j['themeMode'],
          orElse: () => ThemeMode.dark,
        ),
        deviceName: j['deviceName'] as String? ?? 'This PC',
        conflictPolicy: ConflictPolicy.parse(j['conflictPolicy'] as String?),
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
        'conflictPolicy': conflictPolicy.name,
        'devices': [for (final d in devices) d.toJson()],
        'permissions': [for (final p in permissions) p.toJson()],
        'lastSync': lastSync?.toIso8601String(),
      };
}
