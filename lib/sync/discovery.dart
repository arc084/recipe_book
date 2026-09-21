import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// A device that answered on the network.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.isPairing,
    required this.seenAt,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String address;
  final int port;

  /// Whether it is showing a pairing code right now.
  final bool isPairing;
  final DateTime seenAt;

  Uri get base => Uri.parse('http://$address:$port');
}

/// Finds other copies of the app on the same network, and says where this one
/// is.
///
/// UDP broadcast rather than multicast: multicast on Android needs a
/// `WifiManager.MulticastLock` and the `CHANGE_WIFI_MULTICAST_STATE`
/// permission, and reaching that from Flutter means a platform channel.
/// Broadcast covers the same subnet with neither.
///
/// It runs only while the user has the sync sheet open. The app is offline by
/// design; a socket announcing itself all day would not fit that.
class Discovery {
  Discovery({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    DateTime Function()? now,
    this.broadcastAddress = '255.255.255.255',
    this.announceEvery = const Duration(seconds: 2),
    this.port = kDiscoveryPort,
    int? sendToPort,
  }) : _sendToPort = sendToPort ?? port,
       _now = now ?? DateTime.now;

  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime Function() _now;

  /// Test seams, all four. A test cannot broadcast to the subnet and expect
  /// the packet back, waiting two seconds a tick makes for a slow test, and
  /// two of these in one process cannot share a port — so a test gives the
  /// listener and the announcer one each and points the announcer at the
  /// listener's.
  final String broadcastAddress;
  final Duration announceEvery;
  final int port;
  final int _sendToPort;

  RawDatagramSocket? _socket;
  Timer? _announcer;
  StreamSubscription<RawSocketEvent>? _listening;

  final _found = StreamController<DiscoveredDevice>.broadcast();

  /// Devices seen this session, most recent announcement per device.
  final Map<String, DiscoveredDevice> devices = {};

  Stream<DiscoveredDevice> get onFound => _found.stream;

  bool get isRunning => _socket != null;

  /// Starts listening, and — when [servingPort] is given — announcing.
  ///
  /// Announcing is what a device does while it is *offering* to be paired
  /// with or synced to; a device that only wants to find others can listen
  /// without saying anything.
  ///
  /// [isPairing] is asked again before every announcement rather than read
  /// once. A code lives two minutes and announcements outlive it: a flag
  /// fixed at start meant a device went on saying "I am showing a code" long
  /// after it stopped being true, and the joiner found out by typing six
  /// digits and being told there was no code on offer.
  Future<void> start({int? servingPort, bool Function()? isPairing}) async {
    if (_socket != null) return;

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: false,
    );
    socket.broadcastEnabled = true;
    _socket = socket;

    _listening = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null) return;
      _absorb(packet.data, packet.address.address);
    });

    if (servingPort != null) {
      void announce() => _announce(servingPort, isPairing?.call() ?? false);
      announce();
      _announcer = Timer.periodic(announceEvery, (_) => announce());
    }
  }

  Future<void> stop() async {
    _announcer?.cancel();
    _announcer = null;
    await _listening?.cancel();
    _listening = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await stop();
    await _found.close();
  }

  void _announce(int port, bool pairing) {
    final socket = _socket;
    if (socket == null) return;
    final message = utf8.encode(
      jsonEncode({
        'v': kProtocolVersion,
        'deviceId': deviceId,
        'name': deviceName,
        'platform': platform,
        'port': port,
        'pairing': pairing,
      }),
    );
    try {
      socket.send(message, InternetAddress(broadcastAddress), _sendToPort);
    } on SocketException {
      // A network that refuses broadcast is a reason to fall back to typing an
      // address, not a reason to fail loudly.
    }
  }

  void _absorb(List<int> data, String address) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } on FormatException {
      return; // something else is using this port
    }

    final id = json['deviceId'];
    final port = (json['port'] as num?)?.toInt();
    if (id is! String || port == null) return;
    // Our own broadcast comes back to us.
    if (id == deviceId) return;
    if ((json['v'] as num?)?.toInt() != kProtocolVersion) return;

    final device = DiscoveredDevice(
      deviceId: id,
      name: json['name'] as String? ?? 'A device',
      platform: json['platform'] as String? ?? '',
      address: address,
      port: port,
      isPairing: json['pairing'] as bool? ?? false,
      seenAt: _now().toUtc(),
    );

    devices[id] = device;
    if (!_found.isClosed) _found.add(device);
  }
}
