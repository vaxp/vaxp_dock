import 'dart:async';
import 'dart:io';
import 'package:dbus/dbus.dart';

/// Monitor active well-known DBus names via org.freedesktop.DBus
/// This is a heuristic monitor: many GUI apps do not own DBus names, but
/// apps that do will be tracked here. The service exposes callbacks when
/// the set of active names changes.
class RunningAppService {
  final DBusClient _client;
  final StreamController<Set<String>> _controller = StreamController.broadcast();
  Set<String> _activeNames = {};
  Timer? _pollTimer;

  RunningAppService({DBusClient? client}) : _client = client ?? DBusClient.session();

  /// Stream of currently active well-known names on the session bus.
  Stream<Set<String>> get onActiveNamesChanged => _controller.stream;

  /// Start monitoring. This performs an initial ListNames and then listens
  /// for NameOwnerChanged signals on org.freedesktop.DBus.
  Future<void> start() async {
    try {
      // Initial population and start polling periodically as a robust fallback
      await _pollListNames();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _pollListNames();
      });
    } catch (e) {
      // ignore errors but keep controller open
    }
  }

  Future<void> _pollListNames() async {
    try {
      final reply = await _client.callMethod(
        destination: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'ListNames',
      );

      final names = <String>{};
      if (reply.values.isNotEmpty) {
        final arr = reply.values[0] as DBusArray;
        // DBusArray children contain DBusValue elements
        for (final child in arr.children) {
          if (child is DBusString) names.add(child.value);
        }
      }
      _updateNames(names);
    } catch (_) {
      // ignore poll errors
    }
  }

  void _updateNames(Set<String> names) {
    _activeNames = names;
    if (!_controller.isClosed) _controller.add(Set<String>.from(_activeNames));
  }

  /// Helper: get current snapshot
  Set<String> currentNames() => Set<String>.from(_activeNames);

  /// Try to activate a running application represented by a DesktopEntry.
  /// Returns true if an activation strategy succeeded.
  /// Strategies:
  ///  - call 'Activate' on interface 'org.freedesktop.Application' on the app's bus name
  ///  - call 'Activate' on path '/org/gtk/Application' as a fallback
  ///  - run a window manager helper 'wmctrl -a <execBase>' if available
  Future<bool> activateByBusName(String busName, {String? execBase}) async {
    try {
      // Try org.freedesktop.Application Activate
      await _client.callMethod(
        destination: busName,
        path: DBusObjectPath('/'),
        interface: 'org.freedesktop.Application',
        name: 'Activate',
      );
      return true;
    } catch (_) {}

    try {
      // Try a common GTK application path
      await _client.callMethod(
        destination: busName,
        path: DBusObjectPath('/org/gtk/Application'),
        interface: 'org.gtk.Application',
        name: 'Activate',
      );
      return true;
    } catch (_) {}

    // Fallback: try wmctrl to focus a window by name/class
    if (execBase != null && execBase.isNotEmpty) {
      try {
        final res = await Process.run('wmctrl', ['-a', execBase]);
        if (res.exitCode == 0) return true;
      } catch (_) {}
    }

    return false;
  }

  /// Find a bus name matching heuristically to an exec or display name.
  String? findMatchingBusNameFor({required String exec, required String displayName}) {
    final cleaned = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
    if (cleaned.isEmpty) return null;
    final firstToken = cleaned.split(RegExp(r'\s+')).first;
    final execBase = firstToken.split('/').last.toLowerCase();

    for (final busName in _activeNames) {
      final b = busName.toLowerCase();
      if (b.contains(execBase) || execBase.contains(b)) return busName;
      if (b.contains(displayName.toLowerCase()) || displayName.toLowerCase().contains(b)) return busName;
      final segments = b.split('.');
      if (segments.isNotEmpty && segments.last == execBase) return busName;
    }
    return null;
  }

  void dispose() {
    _pollTimer?.cancel();
    _controller.close();
    _client.close();
  }
}
