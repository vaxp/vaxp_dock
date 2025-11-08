import 'dart:io';
import '../utils/icon_provider.dart';

class DesktopEntry {
  final String name;
  final String? exec;
  late final String? iconPath;
  final bool isSvgIcon;

  DesktopEntry({
    required this.name,
    this.exec,
    this.iconPath,
    this.isSvgIcon = false,
  });

  static Future<List<DesktopEntry>> loadAll() async {
    final List<String> dirs = [
      '/usr/share/applications',
      '/usr/local/share/applications',
      if (Platform.environment['XDG_DATA_HOME'] != null)
        '${Platform.environment['XDG_DATA_HOME']!}/applications'
      else
        Platform.environment['HOME'] != null
            ? '${Platform.environment['HOME']!}/.local/share/applications'
            : '',
    ];

    final Set<String> seen = {};
    final List<DesktopEntry> entries = [];

    for (final dir in dirs) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final file in d.list()) {
        if (!file.path.endsWith('.desktop')) continue;
        try {
          final lines = await File(file.path).readAsLines();
          String? name;
          String? exec;
          String? icon;
          bool inDesktopEntry = false;
          bool shouldDisplay = true;
          String currentDesktop = Platform.environment['XDG_CURRENT_DESKTOP']?.toUpperCase() ?? '';
          
          for (final line in lines) {
            final l = line.trim();
            if (l == '[Desktop Entry]') {
              inDesktopEntry = true;
              continue;
            }
            if (!inDesktopEntry || l.startsWith('#')) continue;
            
            if (l.startsWith('Name=')) name = l.substring(5);
            if (l.startsWith('Exec=')) exec = l.substring(5);
            if (l.startsWith('Icon=')) icon = l.substring(5);
            
            if (l == 'NoDisplay=true' || l == 'Hidden=true') {
              shouldDisplay = false;
              break;
            }
            
            if (l.startsWith('OnlyShowIn=')) {
              final environments = l.substring(11).split(';')
                .where((e) => e.isNotEmpty)
                .map((e) => e.toUpperCase())
                .toList();
              if (!environments.contains(currentDesktop)) {
                shouldDisplay = false;
                break;
              }
            }
            
            if (l.startsWith('NotShowIn=')) {
              final environments = l.substring(10).split(';')
                .where((e) => e.isNotEmpty)
                .map((e) => e.toUpperCase())
                .toList();
              if (environments.contains(currentDesktop)) {
                shouldDisplay = false;
                break;
              }
            }
          }
          
          if (name != null && exec != null && shouldDisplay && !seen.contains(name)) {
            seen.add(name);
            if (icon != null) {
              final iconPath = icon.startsWith('/') ? icon : IconProvider.findIcon(icon);
              if (iconPath != null) {
                entries.add(
                  DesktopEntry(
                    name: name,
                    exec: exec,
                    iconPath: iconPath,
                    isSvgIcon: iconPath.toLowerCase().endsWith('.svg'),
                  ),
                );
              } else {
                entries.add(DesktopEntry(name: name, exec: exec));
              }
            } else {
              entries.add(DesktopEntry(name: name, exec: exec));
            }
          }
        } catch (_) {
          // Ignore parse errors
        }
      }
    }
    
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'exec': exec,
      'iconPath': iconPath,
      'isSvgIcon': isSvgIcon,
    };
  }

  static DesktopEntry fromJson(Map<String, dynamic> json) {
    return DesktopEntry(
      name: json['name'] as String? ?? '',
      exec: json['exec'] as String?,
      iconPath: json['iconPath'] as String?,
      isSvgIcon: json['isSvgIcon'] as bool? ?? false,
    );
  }
}