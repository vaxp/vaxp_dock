import 'package:dbus/dbus.dart';
import '../models/desktop_entry.dart';

// D-Bus interface name for VAXP
const vaxpBusName = 'com.vaxp.dock';
const vaxpObjectPath = '/com/vaxp/dock';
const vaxpInterfaceName = 'com.vaxp.dock';

/// Internal class for handling D-Bus object methods
class _VaxpDockObject extends DBusObject {
  final void Function(String name, String exec, String? iconPath, bool isSvgIcon)? onPinRequest;
  final void Function(String name)? onUnpinRequest;
  final void Function()? onShowLauncher;
  final void Function(String state)? onLauncherState;

  _VaxpDockObject(
    DBusObjectPath path, {
    this.onPinRequest,
    this.onUnpinRequest,
    this.onShowLauncher,
    this.onLauncherState,
  }) : super(path);

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        vaxpInterfaceName,
        methods: [
          DBusIntrospectMethod(
            'PinApp',
            args: [
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('b'), DBusArgumentDirection.in_),
            ],
          ),
          DBusIntrospectMethod(
            'UnpinApp',
            args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_)],
          ),
          DBusIntrospectMethod('ShowLauncher'),
          DBusIntrospectMethod(
            'ReportLauncherState',
            args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_)],
          ),
        ],
        signals: [
          DBusIntrospectSignal(
            'MinimizeWindow',
            args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out)],
          ),
          DBusIntrospectSignal(
            'RestoreWindow',
            args: [DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out)],
          ),
        ],
      )
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != vaxpInterfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'PinApp':
        if (onPinRequest != null && methodCall.values.length == 4) {
          final name = (methodCall.values[0] as DBusString).value;
          final exec = (methodCall.values[1] as DBusString).value;
          final iconPath = (methodCall.values[2] as DBusString).value;
          final isSvgIcon = (methodCall.values[3] as DBusBoolean).value;
          onPinRequest!(name, exec, iconPath.isEmpty ? null : iconPath, isSvgIcon);
        }
        return DBusMethodSuccessResponse([]);

      case 'UnpinApp':
        if (onUnpinRequest != null && methodCall.values.length == 1) {
          final name = (methodCall.values[0] as DBusString).value;
          onUnpinRequest!(name);
        }
        return DBusMethodSuccessResponse([]);

      case 'ShowLauncher':
        onShowLauncher?.call();
        return DBusMethodSuccessResponse([]);

      case 'ReportLauncherState':
        if (methodCall.values.isNotEmpty) {
          final state = (methodCall.values[0] as DBusString).value;
          // notify listeners on the server side
          onLauncherState?.call(state);
        }
        return DBusMethodSuccessResponse([]);

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

/// Service for communicating between VAXP components via D-Bus
class VaxpDockService {
  final DBusClient _client;
  late final _VaxpDockObject _object;
  void Function(String name, String exec, String? iconPath, bool isSvgIcon)? _onPinRequest;
  void Function(String name)? _onUnpinRequest;
  void Function()? _onShowLauncher;
  void Function(String state)? _onLauncherState;

  VaxpDockService({DBusClient? client}) : _client = client ?? DBusClient.session() {
    _object = _VaxpDockObject(
      DBusObjectPath(vaxpObjectPath),
      onPinRequest: (name, exec, iconPath, isSvgIcon) => _onPinRequest?.call(name, exec, iconPath, isSvgIcon),
      onUnpinRequest: (name) => _onUnpinRequest?.call(name),
      onShowLauncher: () => _onShowLauncher?.call(),
      onLauncherState: (state) => _onLauncherState?.call(state),
    );
  }

  // Setters for callbacks
  set onPinRequest(void Function(String name, String exec, String? iconPath, bool isSvgIcon)? callback) {
    _onPinRequest = callback;
  }

  set onUnpinRequest(void Function(String name)? callback) {
    _onUnpinRequest = callback;
  }

  set onShowLauncher(void Function()? callback) {
    _onShowLauncher = callback;
  }

  set onLauncherState(void Function(String state)? callback) {
    _onLauncherState = callback;
  }

  /// Report the launcher's state to the dock (client-side call to the server)
  Future<void> reportLauncherState(String state) async {
    await _client.callMethod(
      destination: vaxpBusName,
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'ReportLauncherState',
      values: [DBusString(state)],
    );
  }

  // Server methods
  Future<void> listenAsServer() async {
    await _client.requestName(vaxpBusName);
    await _client.registerObject(_object);
  }

  // Connection methods
  Future<void> ensureClientConnection() async {
    try {
      // Try to call a simple method to test connection
      await _client.callMethod(
        destination: vaxpBusName,
        path: DBusObjectPath(vaxpObjectPath),
        interface: vaxpInterfaceName,
        name: 'ShowLauncher',
        values: [],
      );
    } catch (e) {
      throw Exception('Failed to connect to dock service: $e');
    }
  }

  // Client methods
  Future<void> pinApp(DesktopEntry entry) async {
    await _client.callMethod(
      destination: vaxpBusName,
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'PinApp',
      values: [
        DBusString(entry.name),
        DBusString(entry.exec ?? ''),
        DBusString(entry.iconPath ?? ''),
        DBusBoolean(entry.isSvgIcon),
      ],
    );
  }

  Future<void> unpinApp(String name) async {
    await _client.callMethod(
      destination: vaxpBusName,
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'UnpinApp',
      values: [DBusString(name)],
    );
  }

  Future<void> showLauncher() async {
    await _client.callMethod(
      destination: vaxpBusName,
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'ShowLauncher',
      values: [],
    );
  }

  /// Emit a signal requesting the launcher to minimize a window identified by [name].
  Future<void> emitMinimizeWindow(String name) async {
    await _client.emitSignal(
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'MinimizeWindow',
      values: [DBusString(name)],
    );
  }

  /// Emit a signal requesting the launcher to restore a window identified by [name].
  Future<void> emitRestoreWindow(String name) async {
    await _client.emitSignal(
      path: DBusObjectPath(vaxpObjectPath),
      interface: vaxpInterfaceName,
      name: 'RestoreWindow',
      values: [DBusString(name)],
    );
  }

  void dispose() {
    _client.close();
  }
}