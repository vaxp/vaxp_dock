import 'dart:io';
import 'package:flutter/material.dart';

/// نموذج لتطبيق مكتشف من ملفات .desktop
class DesktopApp {
  final String name;
  final String exec;
  final String? iconPath;

  DesktopApp({
    required this.name,
    required this.exec,
    this.iconPath,
  });
}

/// فئة لإدارة الأيقونات (من كودك الأصلي مع تحسينات طفيفة)
class IconProvider {
  static String? findIcon(String iconName) {
    if (iconName.isEmpty) return null;

    // إذا كان مسار مطلق
    if (iconName.startsWith('/') && File(iconName).existsSync()) {
      return iconName;
    }

    final systemPaths = [
      '/usr/share/icons',
      '/usr/local/share/icons',
      '/usr/share/pixmaps',
      '/usr/local/share/pixmaps',
      '${Platform.environment['HOME']}/.icons',
      '${Platform.environment['HOME']}/.local/share/icons',
      '/var/lib/flatpak/exports/share/icons',
      '${Platform.environment['HOME']}/.local/share/flatpak/exports/share/icons',
      '/var/lib/snapd/desktop/icons',
    ].where((p) => Directory(p).existsSync()).toList();

    final themeSearchOrder = [
      _detectIconTheme(),
      'hicolor',
      'Adwaita',
      'breeze',
      'Papirus',
      'Numix',
      'elementary',
      'default',
    ].whereType<String>().toList();

    final sizes = [
      '512x512', '256x256', '128x128', '96x96',
      '64x64', '48x48', '32x32', '24x24', '16x16', 'scalable'
    ];
    final categories = [
      'apps', 'actions', 'devices', 'categories',
      'places', 'status', 'emblems', 'mimetypes'
    ];
    final extensions = ['.svg', '.png', '.xpm'];

    for (final base in systemPaths) {
      for (final theme in themeSearchOrder) {
        for (final size in sizes) {
          for (final cat in categories) {
            for (final ext in extensions) {
              final path = '$base/$theme/$size/$cat/$iconName$ext';
              if (File(path).existsSync()) return path;
            }
          }
        }
      }
    }

    // fallback: pixmaps
    for (final ext in extensions) {
      final pix = '/usr/share/pixmaps/$iconName$ext';
      if (File(pix).existsSync()) return pix;
    }

    return null;
  }

  static String? _detectIconTheme() {
    try {
      final res = Process.runSync(
        'gsettings',
        ['get', 'org.gnome.desktop.interface', 'icon-theme'],
      );
      if (res.exitCode == 0) {
        final theme = res.stdout.toString().trim().replaceAll("'", '');
        if (theme.isNotEmpty) return theme;
      }
    } catch (_) {}

    try {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final gtkFile = File('$home/.config/gtk-3.0/settings.ini');
        if (gtkFile.existsSync()) {
          final content = gtkFile.readAsStringSync();
          final match = RegExp(r'gtk-icon-theme-name\s*=\s*(.+)')
              .firstMatch(content);
          if (match != null) {
            return match.group(1)?.trim();
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static ImageProvider<Object>? getIcon(String iconName) {
    final path = findIcon(iconName);
    if (path != null) return FileImage(File(path));
    return null;
  }
}

/// فئة لقراءة ملفات .desktop واستخلاص التطبيقات (مثل GNOME Launcher)
class DesktopEntryScanner {
  static List<DesktopApp> scanSystemApplications() {
    final appDirs = [
      '/usr/share/applications',
      '/usr/local/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];

    final apps = <DesktopApp>[];

    for (final dirPath in appDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      for (final file in dir.listSync()) {
        if (!file.path.endsWith('.desktop')) continue;

        try {
          final lines = File(file.path).readAsLinesSync();
          String? name;
          String? exec;
          String? icon;

          for (final line in lines) {
            if (line.startsWith('Name=')) name = line.substring(5).trim();
            if (line.startsWith('Exec=')) {
              exec = line.substring(5).trim().split(' ').first;
            }
            if (line.startsWith('Icon=')) icon = line.substring(5).trim();
          }

          if (name != null && exec != null) {
            final iconPath = (icon != null)
                ? (IconProvider.findIcon(icon) ?? icon)
                : null;

            apps.add(DesktopApp(
              name: name,
              exec: exec,
              iconPath: iconPath,
            ));
          }
        } catch (_) {
          // تجاهل الملفات التالفة أو المشفرة
        }
      }
    }

    // إزالة التكرار حسب الاسم
    final unique = <String, DesktopApp>{};
    for (final app in apps) {
      unique[app.name] = app;
    }

    return unique.values.toList();
  }
}
