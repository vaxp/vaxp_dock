import '../models/desktop_entry.dart';
import '../utils/icon_provider.dart';
import 'window_service.dart';

/// Service to match windows to desktop entries and resolve icons
class WindowMatcherService {
  List<DesktopEntry> _desktopEntries = [];
  bool _entriesLoaded = false;

  /// Load all desktop entries (call this once at startup)
  Future<void> loadDesktopEntries() async {
    if (_entriesLoaded) return;
    _desktopEntries = await DesktopEntry.loadAll();
    _entriesLoaded = true;
  }

  /// Match a window to a desktop entry and return it with icon resolved
  DesktopEntry? matchWindowToEntry(WindowInfo window) {
    if (!_entriesLoaded) return null;

    DesktopEntry? bestMatch;

    // Strategy 1: Match by window class (most reliable)
    if (window.windowClass != null) {
      bestMatch = _matchByClass(window.windowClass!, window.windowInstance);
      if (bestMatch != null) return _resolveIcon(bestMatch);
    }

    // Strategy 2: Match by window title
    bestMatch = _matchByTitle(window.title);
    if (bestMatch != null) return _resolveIcon(bestMatch);

    // Strategy 3: Match by window instance
    if (window.windowInstance != null) {
      bestMatch = _matchByInstance(window.windowInstance!);
      if (bestMatch != null) return _resolveIcon(bestMatch);
    }

    return null;
  }

  /// Match desktop entry by window class
  DesktopEntry? _matchByClass(String windowClass, String? windowInstance) {
    final lowerClass = windowClass.toLowerCase();
    final lowerInstance = windowInstance?.toLowerCase();

    // Try exact match first
    for (final entry in _desktopEntries) {
      if (entry.exec == null) continue;
      final execBase = _getExecBase(entry.exec!);
      if (execBase.toLowerCase() == lowerClass) {
        return entry;
      }
    }

    // Try partial match
    for (final entry in _desktopEntries) {
      if (entry.exec == null) continue;
      final execBase = _getExecBase(entry.exec!);
      final lowerExec = execBase.toLowerCase();
      
      if (lowerExec.contains(lowerClass) || lowerClass.contains(lowerExec)) {
        return entry;
      }
      
      // Also check name
      if (entry.name.toLowerCase().contains(lowerClass) || 
          lowerClass.contains(entry.name.toLowerCase())) {
        return entry;
      }
    }

    // Try matching by instance if available
    if (lowerInstance != null) {
      for (final entry in _desktopEntries) {
        if (entry.exec == null) continue;
        final execBase = _getExecBase(entry.exec!);
        if (execBase.toLowerCase() == lowerInstance) {
          return entry;
        }
      }
    }

    return null;
  }

  /// Match desktop entry by window title
  DesktopEntry? _matchByTitle(String title) {
    final lowerTitle = title.toLowerCase();
    
    // Remove common suffixes like " - Mozilla Firefox"
    final cleanTitle = lowerTitle
        .replaceAll(RegExp(r'\s*-\s*.*$'), '')
        .replaceAll(RegExp(r'\s*—\s*.*$'), '')
        .trim();

    // Try exact match
    for (final entry in _desktopEntries) {
      if (entry.name.toLowerCase() == cleanTitle) {
        return entry;
      }
    }

    // Try partial match
    for (final entry in _desktopEntries) {
      final lowerName = entry.name.toLowerCase();
      if (lowerName.contains(cleanTitle) || cleanTitle.contains(lowerName)) {
        return entry;
      }
    }

    return null;
  }

  /// Match desktop entry by window instance
  DesktopEntry? _matchByInstance(String instance) {
    final lowerInstance = instance.toLowerCase();
    
    for (final entry in _desktopEntries) {
      if (entry.exec == null) continue;
      final execBase = _getExecBase(entry.exec!);
      if (execBase.toLowerCase() == lowerInstance) {
        return entry;
      }
    }

    return null;
  }

  /// Extract executable base name from Exec field
  String _getExecBase(String exec) {
    // Remove placeholders like %U, %f, etc.
    final cleaned = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
    if (cleaned.isEmpty) return '';
    
    // Get first token (the executable)
    final firstToken = cleaned.split(RegExp(r'\s+')).first;
    
    // Extract base name (without path)
    return firstToken.split('/').last;
  }

  /// Resolve icon for a desktop entry (ensure icon path is set)
  DesktopEntry _resolveIcon(DesktopEntry entry) {
    // If icon already resolved, return as is
    if (entry.iconPath != null && entry.iconPath!.isNotEmpty) {
      return entry;
    }

    // Try to find icon by entry name
    final iconPath = IconProvider.findIcon(entry.name.toLowerCase());
    if (iconPath != null) {
      return DesktopEntry(
        name: entry.name,
        exec: entry.exec,
        iconPath: iconPath,
        isSvgIcon: iconPath.toLowerCase().endsWith('.svg'),
        autoRemoveOnExit: entry.autoRemoveOnExit,
      );
    }

    // Try to find icon by exec base name
    if (entry.exec != null) {
      final execBase = _getExecBase(entry.exec!);
      if (execBase.isNotEmpty) {
        final execIconPath = IconProvider.findIcon(execBase);
        if (execIconPath != null) {
          return DesktopEntry(
            name: entry.name,
            exec: entry.exec,
            iconPath: execIconPath,
            isSvgIcon: execIconPath.toLowerCase().endsWith('.svg'),
            autoRemoveOnExit: entry.autoRemoveOnExit,
          );
        }
      }
    }

    // Return entry without icon (will use default)
    return entry;
  }

  /// Get all desktop entries (for debugging)
  List<DesktopEntry> get desktopEntries => List.from(_desktopEntries);
}

