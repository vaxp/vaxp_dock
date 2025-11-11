import 'dart:async';
import 'dart:io';

/// Represents a single open window with minimal transient info.
/// Window ID is the primary key; info is not persisted.
class WindowInfo {
  final String windowId; // X11 window ID (hex)
  final String title; // Window title from wmctrl
  final int desktopIndex; // Desktop/workspace index
  final bool isActive; // Currently active window

  WindowInfo({
    required this.windowId,
    required this.title,
    required this.desktopIndex,
    required this.isActive,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowInfo &&
          runtimeType == other.runtimeType &&
          windowId == other.windowId;

  @override
  int get hashCode => windowId.hashCode;
}

/// Monitor all open GUI windows via wmctrl/xdotool.
/// Polls periodically and exposes a stream of active windows.
/// No persistence; window info exists only while the window is open.
class WindowService {
  final StreamController<List<WindowInfo>> _controller = StreamController.broadcast();
  List<WindowInfo> _activeWindows = [];
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(milliseconds: 500);

  /// Stream of currently open windows.
  Stream<List<WindowInfo>> get onWindowsChanged => _controller.stream;

  /// Start monitoring windows.
  Future<void> start() async {
    try {
      // Initial poll
      await _pollWindows();
      // Poll periodically
      _pollTimer = Timer.periodic(_pollInterval, (_) async {
        await _pollWindows();
      });
    } catch (e) {
      // Silently ignore errors; wmctrl may not be available
    }
  }

  /// Poll wmctrl for current windows
  Future<void> _pollWindows() async {
    try {
      final result = await Process.run('wmctrl', ['-l']);
      if (result.exitCode != 0) return;

      final lines = (result.stdout as String).split('\n');
      final newWindows = <WindowInfo>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        // wmctrl -l format: ID DESK PID MACHINE TITLE
        // Example: "0x00400001 0 1234 host Firefox"
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 5) continue;

        final windowId = parts[0]; // e.g., "0x00400001"
        final desktopStr = parts[1]; // e.g., "0"
        final desktopIndex = int.tryParse(desktopStr) ?? 0;
        final title = parts.sublist(4).join(' '); // everything after MACHINE

        // Skip invisible/special windows (those often start with '-')
        if (desktopIndex < 0) continue; // -1 means sticky/all-desktops or hidden

        // Skip windows with empty titles (often internal)
        if (title.trim().isEmpty) continue;

        // Filter out known non-GUI or system windows
        if (_isSystemWindow(title)) continue;

        final isActive = parts.length > 2 && parts[2] == '*'; // marked as active
        newWindows.add(WindowInfo(
          windowId: windowId,
          title: title,
          desktopIndex: desktopIndex,
          isActive: isActive,
        ));
      }

      _updateWindows(newWindows);
    } catch (_) {
      // wmctrl not available, ignore
    }
  }

  /// Simple heuristic to filter out non-GUI/system windows
  static bool _isSystemWindow(String title) {
    final lower = title.toLowerCase();
    // Common non-GUI windows to skip
    final skipPatterns = [
      'xfdesktop', // desktop window
      'panel', // system panel
      'notification', // notifications
      'gnome-shell', // shell
      'xfce4-panel',
      'polybar',
      'i3bar',
      'sway',
      'openbox',
      'fluxbox',
      'enlightenment',
      'vaxp-dock', // self
    ];

    for (final pattern in skipPatterns) {
      if (lower.contains(pattern)) return true;
    }

    return false;
  }

  void _updateWindows(List<WindowInfo> windows) {
    // Only emit if the window list changed
    if (windows.length != _activeWindows.length ||
        !windows.every((w) => _activeWindows.contains(w))) {
      _activeWindows = windows;
      if (!_controller.isClosed) _controller.add(List<WindowInfo>.from(_activeWindows));
    }
  }

  /// Get current snapshot
  List<WindowInfo> currentWindows() => List<WindowInfo>.from(_activeWindows);

  /// Activate (focus) a window by its ID
  Future<bool> activateWindow(String windowId) async {
    try {
      final result = await Process.run('wmctrl', ['-i', '-a', windowId]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Close a window by its ID
  Future<bool> closeWindow(String windowId) async {
    try {
      final result = await Process.run('wmctrl', ['-i', '-c', windowId]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _controller.close();
  }
}
