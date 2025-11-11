import 'dart:async';
import 'dart:io';

/// Represents a single open window with minimal transient info.
/// Window ID is the primary key; info is not persisted.
class WindowInfo {
  final String windowId; // X11 window ID (hex)
  final String title; // Window title from wmctrl
  final String? windowClass; // Window class (WM_CLASS) for matching
  final String? windowInstance; // Window instance (WM_CLASS) for matching
  final int desktopIndex; // Desktop/workspace index
  final bool isActive; // Currently active window

  WindowInfo({
    required this.windowId,
    required this.title,
    this.windowClass,
    this.windowInstance,
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

  /// Create a copy of this window with optionally updated fields
  WindowInfo copyWith({
    String? windowId,
    String? title,
    String? windowClass,
    String? windowInstance,
    int? desktopIndex,
    bool? isActive,
  }) {
    return WindowInfo(
      windowId: windowId ?? this.windowId,
      title: title ?? this.title,
      windowClass: windowClass ?? this.windowClass,
      windowInstance: windowInstance ?? this.windowInstance,
      desktopIndex: desktopIndex ?? this.desktopIndex,
      isActive: isActive ?? this.isActive,
    );
  }
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

  /// Poll for current windows
  /// Strategy: Use xdotool to enumerate ALL windows (Wayland-aware), 
  /// then supplement with wmctrl for X11-only windows
  Future<void> _pollWindows() async {
    try {
      final newWindows = <WindowInfo>[];

      // First, try xdotool to get all visible windows (works on both X11 and Wayland)
      final xdotoolWindowIds = await _getWindowsViaXdotool();
      if (xdotoolWindowIds.isNotEmpty) {
        // Get active window once
        final activeWindowId = await _getActiveWindowId();

        // Process each window from xdotool
        for (final windowId in xdotoolWindowIds) {
          try {
            // Get window title
            var titleResult = await Process.run('xdotool', ['getwindowname', windowId]);
            var title = titleResult.exitCode == 0 
                ? titleResult.stdout.toString().trim() 
                : '';

            // If no title from xdotool, try xprop to get _NET_WM_NAME
            if (title.isEmpty) {
              try {
                final netWmResult = await Process.run('xprop', ['-id', windowId, '_NET_WM_NAME']);
                if (netWmResult.exitCode == 0) {
                  final match = RegExp(r'_NET_WM_NAME\(UTF8_STRING\)\s*=\s*"([^"]+)"').firstMatch(netWmResult.stdout.toString());
                  if (match != null) {
                    title = match.group(1) ?? '';
                  }
                }
              } catch (_) {
                // Try WM_NAME as fallback
                try {
                  final wmNameResult = await Process.run('xprop', ['-id', windowId, 'WM_NAME']);
                  if (wmNameResult.exitCode == 0) {
                    final match = RegExp(r'WM_NAME\(STRING\)\s*=\s*"([^"]+)"').firstMatch(wmNameResult.stdout.toString());
                    if (match != null) {
                      title = match.group(1) ?? '';
                    }
                  }
                } catch (_) {}
              }
            }

            // Skip windows with no title or dock windows
            if (title.isEmpty || title.toLowerCase().contains('vaxp-dock')) continue;

            // Skip mutter guard windows and internal Wayland windows
            final lowerTitle = title.toLowerCase();
            if (lowerTitle.contains('mutter guard') || 
                lowerTitle.contains('gnome-shell') ||
                lowerTitle.isEmpty) continue;

            // Convert window ID to hex format
            final hexId = _toHexWindowId(windowId);

            // Try to get window class via xprop
            String? windowClass;
            try {
              final xpropResult = await Process.run('xprop', ['-id', windowId, 'WM_CLASS']);
              if (xpropResult.exitCode == 0) {
                final output = xpropResult.stdout.toString();
                final match = RegExp(r'WM_CLASS\(STRING\)\s*=\s*"([^"]+)"\s*,').firstMatch(output);
                if (match != null) {
                  windowClass = match.group(1);
                }
              }
            } catch (_) {
              // xprop not available, continue without class
            }

            // Check if active
            final isActive = activeWindowId != null && 
                activeWindowId.toLowerCase() == hexId.toLowerCase();

            newWindows.add(WindowInfo(
              windowId: hexId,
              title: title,
              windowClass: windowClass,
              desktopIndex: 0, // Not available from xdotool
              isActive: isActive,
            ));
          } catch (_) {
            // Skip this window if any error
            continue;
          }
        }

        if (newWindows.isNotEmpty) {
          _updateWindows(newWindows);
          return;
        }
      }

      // Fallback: try wmctrl if xdotool didn't find windows
      await _pollWindowsFallback();
    } catch (_) {
      // If all methods fail, try fallback
      await _pollWindowsFallback();
    }
  }

  /// Get all visible window IDs via xdotool (works on Wayland)
  /// Also tries to find windows without proper visibility reporting
  Future<List<String>> _getWindowsViaXdotool() async {
    try {
      // Try to get visible windows first
      var result = await Process.run('xdotool', ['search', '--onlyvisible', '--class', '']);
      if (result.exitCode == 0) {
        final visible = (result.stdout as String)
            .split('\n')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();
        
        // If we found windows, return them
        if (visible.isNotEmpty) {
          return visible;
        }
      }
      
      // Fallback: search for ALL windows (even if not marked as visible)
      // This helps on some Wayland setups where window visibility is not properly reported
      result = await Process.run('xdotool', ['search', '--class', '']);
      if (result.exitCode == 0) {
        return (result.stdout as String)
            .split('\n')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // xdotool not available
    }
    return [];
  }

  /// Convert decimal or hex window ID to standard hex format (0x...)
  String _toHexWindowId(String windowId) {
    if (windowId.startsWith('0x')) return windowId.toLowerCase();
    try {
      final decimal = int.parse(windowId);
      return '0x${decimal.toRadixString(16).padLeft(8, '0')}';
    } catch (_) {
      return '0x$windowId'; // Fallback
    }
  }

  /// Fallback method using wmctrl -l (without classes)
  Future<void> _pollWindowsFallback() async {
    try {
      // Get active window ID once
      final activeWindowId = await _getActiveWindowId();

      final result = await Process.run('wmctrl', ['-l']);
      if (result.exitCode != 0) return;

      final lines = (result.stdout as String).split('\n');
      final newWindows = <WindowInfo>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        // wmctrl -l format: ID DESK PID MACHINE TITLE
        // Example: "0x00400001 0 1234 host Firefox"
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 3) continue; // Minimum: ID DESK (at least)

        final windowId = parts[0];
        if (!windowId.startsWith('0x')) continue; // Must be a valid window ID
        
        final desktopStr = parts[1];
        final desktopIndex = int.tryParse(desktopStr) ?? 0;
        
        // Title is everything after DESK PID MACHINE (index 4+)
        // But handle cases where there might be fewer parts
        String title;
        if (parts.length > 4) {
          title = parts.sublist(4).join(' ').trim();
        } else if (parts.length > 3) {
          // Might not have a proper title, use what's available
          title = parts.sublist(3).join(' ').trim();
        } else {
          // Very minimal info, use window ID as fallback
          title = windowId;
        }

        // If title is still empty, use window ID as fallback
        if (title.isEmpty) {
          title = windowId;
        }
        
        // Only filter out the dock itself
        final lowerTitle = title.toLowerCase();
        if (lowerTitle.contains('vaxp-dock')) continue;

        // Try to get window class using xprop as fallback
        String? windowClass;
        try {
          final xpropResult = await Process.run('xprop', ['-id', windowId, 'WM_CLASS']);
          if (xpropResult.exitCode == 0) {
            final output = xpropResult.stdout.toString();
            final match = RegExp(r'WM_CLASS\(STRING\)\s*=\s*"([^"]+)"\s*,\s*"([^"]+)"').firstMatch(output);
            if (match != null) {
              windowClass = match.group(1);
            }
          }
        } catch (_) {
          // xprop not available, continue without class
        }

        // Check if active
        final isActive = activeWindowId != null && 
            activeWindowId.toLowerCase() == windowId.toLowerCase();
        
        newWindows.add(WindowInfo(
          windowId: windowId,
          title: title,
          windowClass: windowClass,
          desktopIndex: desktopIndex,
          isActive: isActive,
        ));
      }

      _updateWindows(newWindows);
    } catch (_) {
      // Both methods failed, ignore
    }
  }

  /// Get the currently active window ID (in hex format 0x...)
  Future<String?> _getActiveWindowId() async {
    try {
      final result = await Process.run('xdotool', ['getactivewindow']);
      if (result.exitCode == 0) {
        final activeId = result.stdout.toString().trim();
        // Convert to wmctrl format (0x prefix)
        if (activeId.startsWith('0x')) {
          return activeId.toLowerCase();
        } else {
          // Convert decimal to hex
          final decimal = int.tryParse(activeId);
          if (decimal != null) {
            return '0x${decimal.toRadixString(16).padLeft(8, '0')}';
          }
        }
      }
    } catch (_) {
      // xdotool not available
    }
    return null;
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
