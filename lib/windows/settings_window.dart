import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../services/dock_settings_service.dart';
import '../widgets/dock/dock_settings_dialog.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key});

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  final DockSettingsService _settingsService = DockSettingsService();
  DockSettings _settings = DockSettings();
  WindowController? _windowController;

  @override
  void initState() {
    super.initState();
    _loadWindowController().then((_) {
      _loadSettings();
      _settingsService.addListener(_onSettingsChanged);
    });
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _loadWindowController() async {
    try {
      _windowController = await WindowController.fromCurrentEngine();
    } catch (e) {
      debugPrint('Failed to get window controller: $e');
    }
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
    // Notify other windows (main dock) about the update so they can reload
    // settings. Use a shared window method channel name that the main window
    // listens on.
    try {
      final channel = WindowMethodChannel('vaxp_dock_settings', mode: ChannelMode.unidirectional);
      await channel.invokeMethod('update', settings.toJson());
    } catch (e) {
      debugPrint('Failed to notify other windows about settings update: $e');
    }

    // Close the window after saving
    if (_windowController != null) {
      _windowController!.hide();
    }
  }

  Future<void> _restartDock() async {
    try {
      final channel = WindowMethodChannel('vaxp_dock_settings', mode: ChannelMode.unidirectional);
      await channel.invokeMethod('restart');
    } catch (e) {
      debugPrint('Failed to request dock restart: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dock Settings',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: Colors.grey[900],
        body: DockSettingsDialog(
          initialSettings: _settings,
          onSave: _saveSettings,
          isWindowMode: true,
          onRestart: _restartDock,
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

