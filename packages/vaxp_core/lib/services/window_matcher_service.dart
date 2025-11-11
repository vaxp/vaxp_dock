import 'dart:io';
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
    if (window.windowClass != null && window.windowClass!.isNotEmpty) {
      bestMatch = _matchByClass(window.windowClass!, window.windowInstance);
      if (bestMatch != null) return _resolveIcon(bestMatch);
    }

    // Strategy 2: Match by window title (works well even for Wayland apps)
    bestMatch = _matchByTitle(window.title);
    if (bestMatch != null) return _resolveIcon(bestMatch);

    // Strategy 3: Match by window instance
    if (window.windowInstance != null && window.windowInstance!.isNotEmpty) {
      bestMatch = _matchByInstance(window.windowInstance!);
      if (bestMatch != null) return _resolveIcon(bestMatch);
    }

    return null;
  }

  /// Match desktop entry by window class
  DesktopEntry? _matchByClass(String windowClass, String? windowInstance) {
    final lowerClass = windowClass.toLowerCase();
    final lowerInstance = windowInstance?.toLowerCase();

    // Try exact match first (most reliable)
    for (final entry in _desktopEntries) {
      if (entry.exec == null) continue;
      final execBase = _getExecBase(entry.exec!);
      final lowerExec = execBase.toLowerCase();
      
      // Exact match
      if (lowerExec == lowerClass) {
        return entry;
      }
      
      // Match without common prefixes/suffixes
      if (_normalizeForMatch(lowerExec) == _normalizeForMatch(lowerClass)) {
        return entry;
      }
    }

    // Try matching by instance if available (often more specific)
    if (lowerInstance != null) {
      for (final entry in _desktopEntries) {
        if (entry.exec == null) continue;
        final execBase = _getExecBase(entry.exec!);
        final lowerExec = execBase.toLowerCase();
        
        if (lowerExec == lowerInstance || 
            _normalizeForMatch(lowerExec) == _normalizeForMatch(lowerInstance)) {
          return entry;
        }
      }
    }

    // Try partial match (less reliable but catches more cases)
    for (final entry in _desktopEntries) {
      if (entry.exec == null) continue;
      final execBase = _getExecBase(entry.exec!);
      final lowerExec = execBase.toLowerCase();
      
      // Check if class contains exec or vice versa (with word boundaries)
      if (_matchesPartially(lowerExec, lowerClass)) {
        return entry;
      }
      
      // Also check name (some apps have different exec vs name)
      final lowerName = entry.name.toLowerCase();
      if (_matchesPartially(lowerName, lowerClass)) {
        return entry;
      }
    }

    return null;
  }

  /// Normalize strings for matching (remove common variations)
  String _normalizeForMatch(String str) {
    return str
        .replaceAll(RegExp(r'[-_]'), '') // Remove dashes and underscores
        .replaceAll(RegExp(r'\s+'), '') // Remove spaces
        .toLowerCase();
  }

  /// Check if two strings match partially (one contains the other or vice versa)
  bool _matchesPartially(String str1, String str2) {
    final norm1 = _normalizeForMatch(str1);
    final norm2 = _normalizeForMatch(str2);
    
    // Check if one contains the other (with minimum length to avoid false positives)
    if (norm1.length >= 3 && norm2.length >= 3) {
      return norm1.contains(norm2) || norm2.contains(norm1);
    }
    
    return false;
  }

  /// Match desktop entry by window title
  DesktopEntry? _matchByTitle(String title) {
    final lowerTitle = title.toLowerCase();
    
    // Strategy 1: Try exact match first
    for (final entry in _desktopEntries) {
      if (entry.name.toLowerCase() == lowerTitle) {
        return entry;
      }
    }

    // Strategy 2: Try removing common app name suffixes (like "- Code", "- Firefox")
    // and match what remains
    final commonSuffixes = [
      RegExp(r'\s*-\s*code\s*$'),
      RegExp(r'\s*-\s*visual\s+studio\s+code\s*$'),
      RegExp(r'\s*-\s*mozilla\s+firefox\s*$'),
      RegExp(r'\s*-\s*google\s+chrome\s*$'),
      RegExp(r'\s*-\s*chromium\s*$'),
      RegExp(r'\s*—\s*.*$'), // Em-dash with anything after
    ];
    
    for (final suffix in commonSuffixes) {
      final cleanTitle = lowerTitle.replaceAll(suffix, '').trim();
      if (cleanTitle.isNotEmpty && cleanTitle != lowerTitle) {
        for (final entry in _desktopEntries) {
          if (entry.name.toLowerCase() == cleanTitle) {
            return entry;
          }
        }
      }
    }

    // Strategy 3: Try matching entry names against full title (substring match)
    for (final entry in _desktopEntries) {
      final lowerName = entry.name.toLowerCase();
      
      // Check if entry name is in the title (like "Files" in "Downloads - Files")
      if (lowerTitle.contains(lowerName)) {
        return entry;
      }
    }

    // Strategy 4: Try first word matching (for simple titles)
    final titleWords = lowerTitle.split(RegExp(r'[\s-]+'));
    final firstWord = titleWords.isNotEmpty ? titleWords.first : '';
    if (firstWord.isNotEmpty && firstWord.length > 2) { // Avoid matching single letters
      for (final entry in _desktopEntries) {
        final lowerName = entry.name.toLowerCase();
        if (lowerName == firstWord || lowerName.startsWith(firstWord)) {
          return entry;
        }
      }
    }

    // Strategy 5: Try matching last meaningful word (after the dash)
    if (lowerTitle.contains('-')) {
      final parts = lowerTitle.split('-');
      final lastPart = parts.last.trim();
      if (lastPart.isNotEmpty && lastPart.length > 2) {
        for (final entry in _desktopEntries) {
          if (entry.name.toLowerCase() == lastPart) {
            return entry;
          }
        }
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
  /// Handles symbolic links automatically via IconProvider
  DesktopEntry _resolveIcon(DesktopEntry entry) {
    // If icon already resolved, ensure symlink is resolved
    if (entry.iconPath != null && entry.iconPath!.isNotEmpty) {
      // IconProvider.findIcon already resolves symlinks, but if we have a direct path,
      // we should verify it's resolved
      final resolvedPath = _resolveSymlinkIfNeeded(entry.iconPath!);
      if (resolvedPath != entry.iconPath) {
        return DesktopEntry(
          name: entry.name,
          exec: entry.exec,
          iconPath: resolvedPath,
          isSvgIcon: resolvedPath.toLowerCase().endsWith('.svg'),
          autoRemoveOnExit: entry.autoRemoveOnExit,
        );
      }
      return entry;
    }

    // Try to find icon by entry name (IconProvider handles symlinks)
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

  /// Resolve symbolic link if the path is a symlink
  String _resolveSymlinkIfNeeded(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.resolveSymbolicLinksSync();
      }
    } catch (_) {
      // Not a symlink or error, return original
    }
    return path;
  }

  /// Get all desktop entries (for debugging)
  List<DesktopEntry> get desktopEntries => List.from(_desktopEntries);
}

