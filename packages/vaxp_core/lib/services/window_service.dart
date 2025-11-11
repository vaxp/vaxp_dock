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
  /// Also uses xdotool as a fallback to ensure ALL windows are captured
  Future<void> _pollWindows() async {
    try {
      // Use -lx to get window classes for better matching
      final result = await Process.run('wmctrl', ['-lx']);
      if (result.exitCode != 0) {
        // Fallback to -l if -lx is not supported
        await _pollWindowsFallback();
        return;
      }
      
      // Also try xdotool to catch any windows wmctrl might miss
      await _pollWindowsXdotool();

      final lines = (result.stdout as String).split('\n');
      final newWindows = <WindowInfo>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        // wmctrl -lx format: ID DESK CLASS.INSTANCE HOSTNAME TITLE
        // Example: "0x00400001  0  firefox.Firefox  hostname  Firefox"
        // Or: "0x00400001  0  Navigator.Firefox  hostname  Firefox"
        // Note: Some systems may have different spacing, so we need flexible parsing
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 3) continue; // Minimum: ID DESK CLASS

        final windowId = parts[0]; // e.g., "0x00400001"
        if (!windowId.startsWith('0x')) continue; // Must be a valid window ID
        
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
        // Note: Some windows might not have a hostname or title, so we need flexible parsing
        String title;
        if (parts.length > 4) {
          // Standard case: ID DESK CLASS HOSTNAME TITLE...
          title = parts.sublist(4).join(' ').trim();
        } else if (parts.length > 3) {
          // No hostname or title is part of class field: ID DESK CLASS TITLE
          title = parts.sublist(3).join(' ').trim();
        } else {
          // No title available, use window class or window ID as fallback
          title = windowClass ?? windowInstance ?? windowId;
        }

        // If title is still empty, use window class or ID
        if (title.isEmpty) {
          title = windowClass ?? windowInstance ?? windowId;
        }

        // Only filter out the dock itself - system services don't have graphical windows
        final lowerClass = windowClass?.toLowerCase() ?? '';
        final lowerTitle = title.toLowerCase();
        if (lowerClass.contains('vaxp-dock') || lowerTitle.contains('vaxp-dock')) {
          continue;
        }

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

  /// Additional method using xdotool to catch ALL windows
  /// This ensures we don't miss any windows that wmctrl might skip
  Future<void> _pollWindowsXdotool() async {
    try {
      // Get all visible window IDs using xdotool
      // Use a pattern that matches everything (.* matches any string)
      final result = await Process.run('xdotool', ['search', '--onlyvisible', '.*']);
      if (result.exitCode != 0) {
        // Fallback: try searching without onlyvisible to catch all windows
        final altResult = await Process.run('xdotool', ['search', '.*']);
        if (altResult.exitCode != 0) return;
        final windowIds = (altResult.stdout as String)
            .split('\n')
            .where((id) => id.trim().isNotEmpty)
            .toList();
        await _processXdotoolWindows(windowIds);
        return;
      }

      final windowIds = (result.stdout as String)
          .split('\n')
          .where((id) => id.trim().isNotEmpty)
          .toList();
      
      await _processXdotoolWindows(windowIds);
    } catch (_) {
      // xdotool not available or failed, continue with wmctrl results only
    }
  }

  /// Process windows found by xdotool
  Future<void> _processXdotoolWindows(List<String> windowIds) async {
    final newWindows = <WindowInfo>[];
    final existingWindowIds = _activeWindows.map((w) => w.windowId.toLowerCase()).toSet();

    for (final windowId in windowIds) {
        // Convert to wmctrl format (0x prefix)
        final hexId = windowId.startsWith('0x') 
            ? windowId 
            : '0x${int.tryParse(windowId)?.toRadixString(16).padLeft(8, '0') ?? windowId}';
        
        // Skip if we already have this window from wmctrl
        if (existingWindowIds.contains(hexId.toLowerCase())) continue;
        
        // Skip the dock itself
        if (hexId.toLowerCase().contains('vaxp-dock')) continue;

        try {
          // Get window name/title
          final nameResult = await Process.run('xdotool', ['getwindowname', windowId]);
          final title = nameResult.exitCode == 0 
              ? nameResult.stdout.toString().trim() 
              : hexId;

          if (title.isEmpty) continue;

          // Get window class
          final classResult = await Process.run('xdotool', ['getwindowclassname', windowId]);
          String? windowClass;
          if (classResult.exitCode == 0) {
            windowClass = classResult.stdout.toString().trim();
            if (windowClass.isEmpty) windowClass = null;
          }

          // Get desktop (workspace)
          int desktopIndex = 0;
          try {
            final desktopResult = await Process.run('xdotool', ['get_desktop_for_window', windowId]);
            if (desktopResult.exitCode == 0) {
              desktopIndex = int.tryParse(desktopResult.stdout.toString().trim()) ?? 0;
            }
          } catch (_) {
            // Desktop detection failed, use default
          }

          final isActive = await _checkIfActive(hexId);

          newWindows.add(WindowInfo(
            windowId: hexId,
            title: title,
            windowClass: windowClass,
            desktopIndex: desktopIndex,
            isActive: isActive,
          ));
        } catch (_) {
          // Skip this window if we can't get its info
          continue;
        }
      }

    // Merge with existing windows
    if (newWindows.isNotEmpty) {
      final allWindows = <WindowInfo>[..._activeWindows, ...newWindows];
      // Remove duplicates based on windowId
      final uniqueWindows = <String, WindowInfo>{};
      for (final window in allWindows) {
        uniqueWindows[window.windowId.toLowerCase()] = window;
      }
      _updateWindows(uniqueWindows.values.toList());
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
