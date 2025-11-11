import 'dart:io';
import 'package:flutter/material.dart';

class IconProvider {
  /// Resolve a symbolic link to its target path
  /// Returns the resolved path, or the original path if not a symlink
  static String _resolveSymlink(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        // Check if it's a symbolic link
        final linkTarget = file.resolveSymbolicLinksSync();
        return linkTarget;
      }
    } catch (_) {
      // Not a symlink or error resolving, return original
    }
    return path;
  }

  /// Find an icon file in the system icon theme
  /// Handles symbolic links by resolving them to actual files
  static String? findIcon(String iconName) {
    if (iconName.isEmpty) return null;
    
    // 1. If it's an absolute path, try it directly and resolve symlinks
    if (iconName.startsWith('/')) {
      final file = File(iconName);
      if (file.existsSync()) {
        return _resolveSymlink(iconName);
      }
    }
    
    // 2. Additional system icon paths
    final systemPaths = [
      '/usr/share/icons',
      '/usr/local/share/icons',
      '/usr/share/pixmaps',
      '/usr/local/share/pixmaps',
      '${Platform.environment['HOME']}/.icons',
      '${Platform.environment['HOME']}/.local/share/icons',
      '/var/lib/flatpak/exports/share/icons',  // Flatpak icons
      '${Platform.environment['HOME']}/.local/share/flatpak/exports/share/icons',
      '/var/lib/snapd/desktop/icons',  // Snap icons
    ].where((path) => Directory(path).existsSync()).toList();
    
    // 3. Theme search order (similar to GTK implementation)
    final themeSearchOrder = [
      _detectIconTheme(),
      'hicolor',
      'Adwaita',
      'gnome',
      'oxygen',
      'Humanity',
      'elementary',
      'breeze',
      'Papirus',
      'Numix',
      'default',
    ].where((theme) => theme != null).toSet().toList();
    
    // 4. Icon sizes to check (larger first for better quality)
    final sizes = ['512x512', '256x256', '128x128', '96x96', '72x72', '64x64', '48x48', '32x32', '24x24', '22x22', '16x16', 'scalable'];
    
    // 5. Icon categories to check
    final categories = ['apps', 'actions', 'devices', 'categories', 'places', 'status', 'emblems', 'mimetypes'];
    
    // 6. Extensions to try - support all common icon formats
    final extensions = ['.svg', '.png', '.ico', '.xpm', '.bmp', '.jpg', '.jpeg', '.gif', '.webp'];
    
    // Search for icon
    for (final basePath in systemPaths) {
      for (final theme in themeSearchOrder) {
        final themePath = '$basePath/$theme';
        if (!Directory(themePath).existsSync()) continue;

        // Try each size directory
        for (final size in sizes) {
          for (final category in categories) {
            final sizeDir = '$themePath/$size/$category';
            if (!Directory(sizeDir).existsSync()) continue;

            // Try with extensions
            for (final ext in extensions) {
              final path = '$sizeDir/$iconName$ext';
              if (File(path).existsSync()) {
                return _resolveSymlink(path);
              }
            }

            // Try without extension
            final path = '$sizeDir/$iconName';
            if (File(path).existsSync()) {
              return _resolveSymlink(path);
            }
          }
        }
      }
    }

    // Check pixmaps directory as fallback (try all extensions)
    for (final ext in extensions) {
      final pixmapPath = '/usr/share/pixmaps/$iconName$ext';
      if (File(pixmapPath).existsSync()) {
        return _resolveSymlink(pixmapPath);
      }
    }

    // Try pixmaps without extension (might be a file without extension)
    final pixmapPath = '/usr/share/pixmaps/$iconName';
    if (File(pixmapPath).existsSync()) {
      return _resolveSymlink(pixmapPath);
    }
    
    // Also try checking if the iconName itself is a full path with any extension
    if (iconName.contains('.')) {
      // Already has an extension, try it as-is if it's a relative path
      for (final basePath in systemPaths) {
        for (final theme in themeSearchOrder) {
          final themePath = '$basePath/$theme';
          if (!Directory(themePath).existsSync()) continue;
          
          for (final size in sizes) {
            for (final category in categories) {
              final sizeDir = '$themePath/$size/$category';
              if (!Directory(sizeDir).existsSync()) continue;
              
              final path = '$sizeDir/$iconName';
              if (File(path).existsSync()) {
                return _resolveSymlink(path);
              }
            }
          }
        }
      }
      
      // Try pixmaps with the extension from iconName
      final pixmapPathWithExt = '/usr/share/pixmaps/$iconName';
      if (File(pixmapPathWithExt).existsSync()) {
        return _resolveSymlink(pixmapPathWithExt);
      }
    }

    return null;
  }

  /// Get an ImageProvider for the icon file
  static ImageProvider<Object>? getIcon(String iconName) {
    final path = findIcon(iconName);
    if (path != null) {
      return FileImage(File(path));
    }
    return null;
  }

  // Icon theme detection
  static String? _detectIconTheme() {
    try {
      // Try gsettings first (GNOME/Ubuntu)
      final result = Process.runSync('gsettings', ['get', 'org.gnome.desktop.interface', 'icon-theme']);
      if (result.exitCode == 0) {
        final theme = result.stdout.toString().trim()
            .replaceAll("'", '')
            .replaceAll('"', '');
        if (theme.isNotEmpty && theme != 'default') {
          return theme;
        }
      }
    } catch (_) {}

    try {
      // Try GTK settings
      final home = Platform.environment['HOME'];
      if (home != null) {
        final configFile = File('$home/.config/gtk-3.0/settings.ini');
        if (configFile.existsSync()) {
          final content = configFile.readAsStringSync();
          final match = RegExp(r'gtk-icon-theme-name\s*=\s*([^\s]+)', caseSensitive: false)
              .firstMatch(content);
          if (match != null && match.group(1) != null) {
            final theme = match.group(1)!
                .replaceAll('"', '')
                .replaceAll("'", '');
            if (theme.isNotEmpty && theme != 'default') {
              return theme;
            }
          }
        }
      }
    } catch (_) {}

    // Default to null, will fall back to hicolor
    return null;
  }
}