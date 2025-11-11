import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaxp_core/models/desktop_entry.dart';
import 'package:vaxp_core/services/window_service.dart';
import 'package:vaxp_core/services/window_matcher_service.dart';
import 'package:vaxp_core/services/dock_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'widgets/dock/dock_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  String? _backgroundImagePath;
  List<DesktopEntry> _pinnedApps = [];
  List<WindowInfo> _openWindows = [];
  bool _launcherVisible = false;
  bool _launcherMinimized = false;
  late final WindowService _windowService;
  late final WindowMatcherService _windowMatcher;

  @override
  void initState() {
    super.initState();
    widget.dockService.onPinRequest = _handlePinRequest;
    widget.dockService.onUnpinRequest = _handleUnpinRequest;
    widget.dockService.onLauncherState = _handleLauncherState;
    // Ensure Flutter bindings are initialized for shared_preferences
    WidgetsFlutterBinding.ensureInitialized();
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
          if (_backgroundImagePath != null)
            Image.file(
              File(_backgroundImagePath!),
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
                  // Use window title as name to ensure windowIdMap lookup works
                  return DesktopEntry(
                    name: w.title,
                    exec: matched.exec,
                    iconPath: matched.iconPath,
                    isSvgIcon: matched.isSvgIcon,
                  );
                }
                // Fallback: create entry with window title
                return DesktopEntry(
                  name: w.title,
                  exec: null,
                  iconPath: null,
                  isSvgIcon: false,
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
            ),
          ),
        ],
      ),
    );
  }
}