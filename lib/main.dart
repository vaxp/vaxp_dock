import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaxp_core/models/desktop_entry.dart';
import 'package:vaxp_core/services/window_service.dart';
import 'package:vaxp_core/services/window_matcher_service.dart';
import 'package:vaxp_core/services/dock_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/dock_settings_service.dart';
import 'widgets/dock/dock_panel.dart';
import 'windows/settings_window.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if this is a sub-window (settings window)
  // When created via `desktop_multi_window` the arguments are prefixed
  // (for example: ["multi_window", windowId, config.arguments]).
  // Create a dedicated function to run the settings window and detect
  // the presence of 'settings' anywhere in the args to handle that case.
  void runSettingsWindow() {
    runApp(const SettingsWindow());
  }

  if (args.isNotEmpty) {
    // If 'settings' is passed directly or as one of the multi-window args
    // then run the SettingsWindow entrypoint.
    if (args.contains('settings') || (args.length > 1 && args[0] == 'settings')) {
      runSettingsWindow();
      return;
    }
  }
  
  // Initialize D-Bus service
  final dockService = VaxpDockService();
  await dockService.listenAsServer();
  
  runApp(DockApp(dockService: dockService));
}

class DockApp extends StatelessWidget {
  final VaxpDockService dockService;

  const DockApp({
    super.key,
    required this.dockService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAXP Dock',
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(125, 0, 170, 255),
        ),
      ),
      home: DockHome(dockService: dockService),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DockHome extends StatefulWidget {
  final VaxpDockService dockService;

  const DockHome({
    super.key,
    required this.dockService,
  });

  @override
  State<DockHome> createState() => _DockHomeState();
}

class _DockHomeState extends State<DockHome> {
  List<DesktopEntry> _pinnedApps = [];
  List<WindowInfo> _openWindows = [];
  bool _launcherVisible = false;
  bool _launcherMinimized = false;
  late final WindowService _windowService;
  late final WindowMatcherService _windowMatcher;
  final DockSettingsService _settingsService = DockSettingsService();
  DockSettings _settings = DockSettings();

  @override
  void initState() {
    super.initState();
    widget.dockService.onPinRequest = _handlePinRequest;
    widget.dockService.onUnpinRequest = _handleUnpinRequest;
    widget.dockService.onLauncherState = _handleLauncherState;
    // Ensure Flutter bindings are initialized for shared_preferences
    WidgetsFlutterBinding.ensureInitialized();
    _loadSettings();
    _loadPinnedApps();
    _setupHotkey();

    // Initialize window matcher and load desktop entries
    _windowMatcher = WindowMatcherService();
    _windowMatcher.loadDesktopEntries();

    // Start window monitoring
    _windowService = WindowService();
    _windowService.start();
    _windowService.onWindowsChanged.listen((windows) {
      if (!mounted) return;
      setState(() {
        _openWindows = windows;
      });
    });

    // Listen to settings changes
    _settingsService.addListener(_onSettingsChanged);

    // Listen for settings updates from sub-windows (settings window).
    // Use a WindowMethodChannel so the settings window (which runs in a
    // separate engine) can notify the main window to reload/apply settings.
    () async {
      try {
        final channel = WindowMethodChannel('vaxp_dock_settings', mode: ChannelMode.unidirectional);
        await channel.setMethodCallHandler((call) async {
          if (call.method == 'update') {
            try {
              final args = call.arguments;
              if (args is Map) {
                final settings = DockSettings.fromJson(Map<String, dynamic>.from(args));
                // Update local settings state (this will save and notify listeners)
                await _saveSettings(settings);
              }
            } catch (e) {
              debugPrint('Failed to handle settings update call: $e');
            }
          } else if (call.method == 'restart') {
            // Request to restart the dock process. Spawn a new process and exit.
            try {
              // On Linux, /proc/self/exe points to the running executable. Start a
              // new instance and exit the current process. If that fails, try to
              // spawn a fallback command name 'vaxp-dock'.
              try {
                await Process.start('/proc/self/exe', []);
              } catch (_) {
                await Process.start('vaxp-dock', []);
              }
            } catch (e) {
              debugPrint('Failed to restart dock: $e');
            }
            // Exit current process so the newly spawned instance becomes primary
            // Note: in debug/flutter run this may stop the tooling; intended for
            // packaged runtime.
            try {
              exit(0);
            } catch (_) {}
          }
          return null;
        });
      } catch (e) {
        debugPrint('Failed to set settings channel handler: $e');
      }
    }();
  }

  void _onSettingsChanged(DockSettings settings) {
    if (!mounted) return;
    setState(() {
      _settings = settings;
    });
  }

  Future<void> _loadSettings() async {
    await _settingsService.load();
    setState(() {
      _settings = _settingsService.settings;
    });
  }

  Future<void> _saveSettings(DockSettings settings) async {
    await _settingsService.updateSettings(settings);

    // Clear Flutter's image cache so updated files (background image,
    // custom icons) are reloaded immediately. Also evict any file images
    // referenced by the new settings to ensure fresh data is read from disk.
    try {
      // Clear global image cache
      PaintingBinding.instance.imageCache.clear();

      // Evict any mapped icons
      if (settings.iconMappings.isNotEmpty) {
        for (final path in settings.iconMappings.values) {
          if (path.isNotEmpty) {
            try {
              await FileImage(File(path)).evict();
            } catch (_) {}
          }
        }
      }

      // If an icon pack directory is set, evict any likely icon files by
      // scanning the directory and evicting their FileImage entries.
      if (settings.iconPackPath != null) {
        try {
          final dir = Directory(settings.iconPackPath!);
          if (dir.existsSync()) {
            await for (final entity in dir.list(recursive: true)) {
              if (entity is File) {
                try {
                  await FileImage(entity).evict();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Failed to clear image cache: $e');
    }
  }

  void _handleLauncherState(String state) {
    setState(() {
      if (state == 'visible') {
        _launcherVisible = true;
        _launcherMinimized = false;
      } else if (state == 'minimized') {
        _launcherVisible = true;
        _launcherMinimized = true;
      } else {
        _launcherVisible = false;
        _launcherMinimized = false;
      }
    });
  }

  Future<void> _loadPinnedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinnedAppsJson = prefs.getStringList('pinnedApps') ?? [];
      
  setState(() {
    _pinnedApps = pinnedAppsJson
    .map((json) => DesktopEntry.fromJson(jsonDecode(json) as Map<String, dynamic>))
    .toList();
  });
    } catch (e) {
      debugPrint('Error loading pinned apps: $e');
    }
  }

  Future<void> _savePinnedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinnedAppsJson = _pinnedApps
          .map((entry) => jsonEncode(entry.toJson()))
          .toList();
      await prefs.setStringList('pinnedApps', pinnedAppsJson);
    } catch (e) {
      debugPrint('Error saving pinned apps: $e');
    }
  }

  void _handlePinRequest(String name, String exec, String? iconPath, bool isSvgIcon) {
    // Legacy: PinApp requests are ignored; windows are tracked via wmctrl only
  }

  void _handleUnpinRequest(String name) {
    setState(() {
      var changed = false;
      _pinnedApps.removeWhere((app) {
        if (app.name == name) {
          changed = true;
          return true;
        }
        return false;
      });
      if (changed) _savePinnedApps(); // Save persistent pinned changes
    });
  }

  void _launchEntry(DesktopEntry entry) async {
    final cmd = entry.exec;
    if (cmd == null) return;
    // remove placeholders like %U, %f, etc.
    final cleaned = cmd.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
    if (cleaned.isEmpty) return;
    try {
      await Process.start('/bin/sh', ['-c', cleaned]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to launch ${entry.name}: $e')),
      );
    }
  }

  void _launchLauncher() async {
    try {
      // If the launcher is visible and not minimized, ask it to minimize/hide
      if (_launcherVisible && !_launcherMinimized) {
        await widget.dockService.emitMinimizeWindow('vaxp-launcher');
        return;
      }

      // If the launcher is minimized, ask it to restore
      if (_launcherMinimized) {
        await widget.dockService.emitRestoreWindow('vaxp-launcher');
        return;
      }

      // Otherwise, try to start the launcher process
      await Process.start('/bin/sh', ['-c', 'vaxp-launcher']);
    } catch (e) {
      // If signaling failed (no listener / error), try to launch the launcher process.
      try {
        await Process.start('/bin/sh', ['-c', 'vaxp-launcher']);
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to launch VAXP Launcher')),
        );
      }
    }
  }

  Future<void> _setupHotkey() async {
    // Register Super/Windows key as hotkey
    final hotKey = HotKey(
      KeyCode.metaLeft,
      scope: HotKeyScope.system, // Listen to hotkey when app is not focused
    );

    await HotKeyManager.instance.register(
      hotKey,
      keyDownHandler: (hotKey) => _launchLauncher(),
    );
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    HotKeyManager.instance.unregisterAll();
    widget.dockService.dispose();
    _windowService.dispose();
    super.dispose();
  }

  Future<void> _activateWindow(String windowId) async {
    final activated = await _windowService.activateWindow(windowId);
    if (!activated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to activate window')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_settings.backgroundImagePath != null)
            Image.file(
              File(_settings.backgroundImagePath!),
              fit: BoxFit.cover,
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DockPanel(
              onLaunch: _launchEntry,
              onShowLauncher: _launchLauncher,
              onMinimizeLauncher: () async {
                try {
                  await widget.dockService.emitMinimizeWindow('vaxp-launcher');
                } catch (e) {
                  debugPrint('Failed to emit minimize signal: $e');
                }
              },
              onRestoreLauncher: () async {
                try {
                  await widget.dockService.emitRestoreWindow('vaxp-launcher');
                } catch (e) {
                  debugPrint('Failed to emit restore signal: $e');
                }
              },
              pinnedApps: _pinnedApps,
              runningApps: [],
              transientApps: _openWindows.map((w) {
                // Try to match window to desktop entry for icon
                final matched = _windowMatcher.matchWindowToEntry(w);
                if (matched != null) {
                  // Check for custom icon from settings
                  String? finalIconPath = matched.iconPath;
                  bool isSvg = matched.isSvgIcon;
                  
                  // Check custom icon mappings first
                  if (_settings.iconMappings.containsKey(matched.name)) {
                    final customPath = _settings.iconMappings[matched.name];
                    if (customPath != null && File(customPath).existsSync()) {
                      finalIconPath = customPath;
                      isSvg = customPath.toLowerCase().endsWith('.svg');
                    }
                  } else if (_settings.iconPackPath != null) {
                    // Check icon pack directory
                    final iconPackDir = Directory(_settings.iconPackPath!);
                    if (iconPackDir.existsSync()) {
                      final extensions = ['.svg', '.png', '.ico', '.xpm', '.bmp', '.jpg', '.jpeg', '.gif', '.webp'];
                      for (final ext in extensions) {
                        final iconPath = '${_settings.iconPackPath}/${matched.name}$ext';
                        if (File(iconPath).existsSync()) {
                          finalIconPath = iconPath;
                          isSvg = ext == '.svg';
                          break;
                        }
                      }
                    }
                  }
                  
                  // Use window title as name to ensure windowIdMap lookup works
                  return DesktopEntry(
                    name: w.title,
                    exec: matched.exec,
                    iconPath: finalIconPath,
                    isSvgIcon: isSvg,
                  );
                }
                // Fallback: create entry with window title, but check custom icons
                String? customIconPath;
                bool isSvg = false;
                if (_settings.iconMappings.containsKey(w.title)) {
                  final customPath = _settings.iconMappings[w.title];
                  if (customPath != null && File(customPath).existsSync()) {
                    customIconPath = customPath;
                    isSvg = customPath.toLowerCase().endsWith('.svg');
                  }
                } else if (_settings.iconPackPath != null) {
                  final iconPackDir = Directory(_settings.iconPackPath!);
                  if (iconPackDir.existsSync()) {
                    final extensions = ['.svg', '.png', '.ico', '.xpm', '.bmp', '.jpg', '.jpeg', '.gif', '.webp'];
                    for (final ext in extensions) {
                      final iconPath = '${_settings.iconPackPath}/${w.title}$ext';
                      if (File(iconPath).existsSync()) {
                        customIconPath = iconPath;
                        isSvg = ext == '.svg';
                        break;
                      }
                    }
                  }
                }
                
                return DesktopEntry(
                  name: w.title,
                  exec: null,
                  iconPath: customIconPath,
                  isSvgIcon: isSvg,
                );
              }).toList(),
              windowIdMap: Map.fromEntries(_openWindows.map((w) => MapEntry(w.title, w.windowId))),
              onWindowActivate: _activateWindow,
              onUnpin: (name) => _handleUnpinRequest(name),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  final item = _pinnedApps.removeAt(oldIndex);
                  _pinnedApps.insert(newIndex, item);
                  _savePinnedApps();
                });
              },
              settings: _settings,
              onSettingsChanged: _saveSettings,
            ),
          ),
        ],
      ),
    );
  }
}