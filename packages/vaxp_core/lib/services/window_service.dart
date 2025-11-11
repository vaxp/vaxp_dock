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
      // Use -lx to get window classes for better matching
      final result = await Process.run('wmctrl', ['-lx']);
      if (result.exitCode != 0) {
        // Fallback to -l if -lx is not supported
        await _pollWindowsFallback();
        return;
      }

      final lines = (result.stdout as String).split('\n');
      final newWindows = <WindowInfo>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        // wmctrl -lx format: ID DESK CLASS.INSTANCE HOSTNAME TITLE
        // Example: "0x00400001  0  firefox.Firefox  hostname  Firefox"
        // Or: "0x00400001  0  Navigator.Firefox  hostname  Firefox"
        // Note: Some systems may have different spacing, so we need flexible parsing
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 4) continue;

        final windowId = parts[0]; // e.g., "0x00400001"
        final desktopStr = parts[1]; // e.g., "0"
        final desktopIndex = int.tryParse(desktopStr) ?? 0;
        
        // Parse window class (format: Class.Instance or just Class)
        String? windowClass;
        String? windowInstance;
        final classPart = parts.length > 2 ? parts[2] : '';
        if (classPart.contains('.')) {
          final classParts = classPart.split('.');
          windowClass = classParts[0];
          windowInstance = classParts.length > 1 ? classParts[1] : null;
        } else if (classPart.isNotEmpty) {
          windowClass = classPart;
        }

        // Title is everything after the class and hostname
        // Format: ID DESK CLASS.INSTANCE HOSTNAME TITLE...
        // So title starts at index 4 (0=ID, 1=DESK, 2=CLASS, 3=HOSTNAME, 4+=TITLE)
        // Note: Some windows might not have a hostname, so we need flexible parsing
        String title;
        if (parts.length > 4) {
          // Standard case: ID DESK CLASS HOSTNAME TITLE...
          title = parts.sublist(4).join(' ').trim();
        } else if (parts.length > 3) {
          // No hostname or title is part of class field: ID DESK CLASS TITLE
          // Check if part[3] looks like a title (not a class name)
          final possibleTitle = parts[3];
          // If it contains spaces or looks like a title, use it
          if (possibleTitle.contains(' ') || possibleTitle.length > 10) {
            title = parts.sublist(3).join(' ').trim();
          } else {
            // Might be just the class, try to get more info
            title = possibleTitle;
          }
        } else {
          // Very minimal info, skip
          continue;
        }

        // Skip invisible/special windows (those often start with '-')
        // But allow desktop index -1 (sticky/all-desktops) as some apps use this
        // Only skip if desktop index is explicitly negative AND title suggests it's a system window
        if (desktopIndex < 0 && _isSystemWindow(title, windowClass)) continue;

        // Skip windows with empty titles (often internal)
        if (title.isEmpty) continue;

        // Filter out known non-GUI or system windows by class or title
        if (_isSystemWindow(title, windowClass)) continue;

        // Check for active window using xdotool or wmctrl -a check
        final isActive = await _checkIfActive(windowId);
        
        newWindows.add(WindowInfo(
          windowId: windowId,
          title: title,
          windowClass: windowClass,
          windowInstance: windowInstance,
          desktopIndex: desktopIndex,
          isActive: isActive,
        ));
      }

      _updateWindows(newWindows);
    } catch (_) {
      // wmctrl not available, try fallback
      await _pollWindowsFallback();
    }
  }

  /// Fallback method using wmctrl -l (without classes)
  Future<void> _pollWindowsFallback() async {
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

        final windowId = parts[0];
        final desktopStr = parts[1];
        final desktopIndex = int.tryParse(desktopStr) ?? 0;
        final title = parts.sublist(4).join(' ').trim();

        if (desktopIndex < 0) continue;
        if (title.isEmpty) continue;
        if (_isSystemWindow(title, null)) continue;

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

        final isActive = await _checkIfActive(windowId);
        
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

  /// Check if a window is currently active
  Future<bool> _checkIfActive(String windowId) async {
    try {
      // Get active window ID
      final result = await Process.run('xdotool', ['getactivewindow']);
      if (result.exitCode == 0) {
        final activeId = result.stdout.toString().trim();
        // Convert to wmctrl format (0x prefix)
        if (activeId.startsWith('0x')) {
          return activeId.toLowerCase() == windowId.toLowerCase();
        } else {
          // Convert decimal to hex
          final decimal = int.tryParse(activeId);
          if (decimal != null) {
            return '0x${decimal.toRadixString(16).padLeft(8, '0')}' == windowId.toLowerCase();
          }
        }
      }
    } catch (_) {
      // xdotool not available
    }
    return false;
  }

  /// Simple heuristic to filter out non-GUI/system windows
  /// Made less aggressive to avoid filtering legitimate apps
  static bool _isSystemWindow(String title, String? windowClass) {
    final lowerTitle = title.toLowerCase().trim();
    final lowerClass = windowClass?.toLowerCase() ?? '';
    
    // Only filter if title/class exactly matches or starts with known system patterns
    // This prevents filtering apps that happen to contain these words
    
    // Skip by exact window class matches (most reliable)
    final exactClassMatches = [
      'xfdesktop',
      'xfce4-panel',
      'gnome-shell',
      'polybar',
      'i3bar',
      'vaxp-dock',
      'conky',
      'tint2',
    ];
    
    for (final pattern in exactClassMatches) {
      if (lowerClass == pattern || lowerClass.startsWith('$pattern.')) {
        return true;
      }
    }
    
    // Skip by exact title matches (more precise than contains)
    final exactTitleMatches = [
      'xfdesktop',
      'xfce4-panel',
      'gnome-shell',
      'polybar',
      'i3bar',
      'vaxp-dock',
      'conky',
      'tint2',
    ];
    
    for (final pattern in exactTitleMatches) {
      if (lowerTitle == pattern) {
        return true;
      }
    }
    
    // Only filter titles that start with known system prefixes (less aggressive)
    final titlePrefixPatterns = [
      'desktop window', // desktop background windows
      'compositor', // compositor windows
    ];
    
    for (final pattern in titlePrefixPatterns) {
      if (lowerTitle.startsWith(pattern)) {
        return true;
      }
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
