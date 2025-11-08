import 'dart:io';
import '../utils/icon_provider.dart';

class DesktopEntry {
  final String name;
  final String? exec;
  final String? iconPath;
  final bool isSvgIcon;

  DesktopEntry({
    required this.name,
    this.exec,
    this.iconPath,
    this.isSvgIcon = false,
  });

  static Future<List<DesktopEntry>> loadAll() async {
    // 🗂️ جميع المسارات التي قد تحتوي على ملفات .desktop
    final List<String> dirs = [
      '/usr/share/applications',
      '/usr/local/share/applications',
      '/var/lib/flatpak/exports/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
      '${Platform.environment['HOME']}/.local/share/flatpak/exports/share/applications',
      '${Platform.environment['HOME']}/snap',
    ];

    final Set<String> seen = {};
    final List<DesktopEntry> entries = [];

    String currentDesktop =
        Platform.environment['XDG_CURRENT_DESKTOP']?.toUpperCase() ?? '';

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (!file.path.endsWith('.desktop')) continue;

        try {
          final lines = await File(file.path).readAsLines();

          String? name;
          String? exec;
          String? icon;
          bool inDesktopEntry = false;
          bool shouldDisplay = true;

          for (final line in lines) {
            final l = line.trim();
            if (l == '[Desktop Entry]') {
              inDesktopEntry = true;
              continue;
            }
            if (!inDesktopEntry || l.startsWith('#') || l.isEmpty) continue;

            // دعم اللغات المختلفة
            if (l.startsWith('Name=')) name ??= l.substring(5);
            if (l.startsWith('Name[') && name == null) {
              final idx = l.indexOf('=');
              if (idx != -1) name = l.substring(idx + 1);
            }

            if (l.startsWith('Exec=')) exec ??= l.substring(5);
            if (l.startsWith('Icon=')) icon ??= l.substring(5);

            // تجاهل التطبيقات المخفية بوضوح فقط
            if (l.contains('Hidden=true')) {
              shouldDisplay = false;
              break;
            }

            // ⚙️ GNOME-style: تجاهل OnlyShowIn فقط إذا كنا فعلاً ضمن بيئة مختلفة
            if (l.startsWith('OnlyShowIn=')) {
              final envs = l
                  .substring(11)
                  .split(';')
                  .where((e) => e.isNotEmpty)
                  .map((e) => e.toUpperCase())
                  .toList();

              if (envs.isNotEmpty && currentDesktop.isNotEmpty) {
                final knownDesktops = [
                  'GNOME',
                  'KDE',
                  'XFCE',
                  'MATE',
                  'LXQT',
                  'CINNAMON',
                  'UNITY'
                ];
                // إذا بيئتك مخصصة مثل Wayfire أو VAXP — تجاهل الشرط
                if (knownDesktops.contains(currentDesktop) &&
                    !envs.contains(currentDesktop)) {
                  shouldDisplay = false;
                  break;
                }
              }
            }

            if (l.startsWith('NotShowIn=')) {
              final envs = l
                  .substring(10)
                  .split(';')
                  .where((e) => e.isNotEmpty)
                  .map((e) => e.toUpperCase())
                  .toList();
              if (envs.contains(currentDesktop)) {
                shouldDisplay = false;
                break;
              }
            }

            // بعض الملفات تحتوي NoDisplay=true لكن GNOME يعرضها في القاذف
            // سنعرضها ما لم تكن Hidden=true صريحة
          }

          // تجاهل الإدخالات غير الصالحة
          if (name == null || exec == null || !shouldDisplay) continue;
          if (seen.contains(name)) continue;
          seen.add(name);

          // 🔍 حل الأيقونة
          String? resolvedIconPath;
          if (icon != null && icon.isNotEmpty) {
            resolvedIconPath = icon.startsWith('/')
                ? icon
                : IconProvider.findIcon(icon);
          }

          entries.add(
            DesktopEntry(
              name: name!,
              exec: exec,
              iconPath: resolvedIconPath,
              isSvgIcon: resolvedIconPath?.toLowerCase().endsWith('.svg') ?? false,
            ),
          );
        } catch (_) {
          // تجاهل الأخطاء في التحليل
        }
      }
    }

    // 🧹 ترتيب أبجدي
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'exec': exec,
        'iconPath': iconPath,
        'isSvgIcon': isSvgIcon,
      };

  static DesktopEntry fromJson(Map<String, dynamic> json) => DesktopEntry(
        name: json['name'] ?? '',
        exec: json['exec'],
        iconPath: json['iconPath'],
        isSvgIcon: json['isSvgIcon'] ?? false,
      );
}
