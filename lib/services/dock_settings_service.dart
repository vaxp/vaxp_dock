import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class DockSettings {
  final Color barColor;
  final double transparency; // 0.0 to 1.0
  final String? backgroundImagePath;
  final String? iconPackPath; // Directory path containing custom icons
  final Map<String, String> iconMappings; // App name -> icon file path

  DockSettings({
    Color? barColor,
    double? transparency,
    this.backgroundImagePath,
    this.iconPackPath,
    Map<String, String>? iconMappings,
  })  : barColor = barColor ?? Colors.black,
        transparency = transparency ?? 0.3,
        iconMappings = iconMappings ?? {};

  Map<String, dynamic> toJson() => {
        'barColor': barColor.value,
        'transparency': transparency,
        'backgroundImagePath': backgroundImagePath,
        'iconPackPath': iconPackPath,
        'iconMappings': iconMappings,
      };

  factory DockSettings.fromJson(Map<String, dynamic> json) => DockSettings(
        barColor: json['barColor'] != null
            ? Color(json['barColor'] as int)
            : null,
        transparency: json['transparency']?.toDouble(),
        backgroundImagePath: json['backgroundImagePath'] as String?,
        iconPackPath: json['iconPackPath'] as String?,
        iconMappings: json['iconMappings'] != null
            ? Map<String, String>.from(json['iconMappings'] as Map)
            : null,
      );

  DockSettings copyWith({
    Color? barColor,
    double? transparency,
    String? backgroundImagePath,
    String? iconPackPath,
    Map<String, String>? iconMappings,
  }) {
    return DockSettings(
      barColor: barColor ?? this.barColor,
      transparency: transparency ?? this.transparency,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      iconPackPath: iconPackPath ?? this.iconPackPath,
      iconMappings: iconMappings ?? this.iconMappings,
    );
  }
}

class DockSettingsService {
  // Singleton so that any code creating a DockSettingsService instance
  // receives the same backing state and listener list. This ensures that
  // the settings window (which may run in a separate engine) updates the
  // shared settings and notifies listeners registered by the dock.
  static final DockSettingsService _instance = DockSettingsService._internal();
  factory DockSettingsService() => _instance;
  DockSettingsService._internal();

  static const String _prefsKey = 'dockSettings';
  DockSettings _settings = DockSettings();
  final List<Function(DockSettings)> _listeners = [];

  DockSettings get settings => _settings;

  /// Load settings from SharedPreferences
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_prefsKey);
      if (settingsJson != null) {
        _settings = DockSettings.fromJson(
          jsonDecode(settingsJson) as Map<String, dynamic>,
        );
        _notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading dock settings: $e');
    }
  }

  /// Save settings to SharedPreferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_settings.toJson()));
      _notifyListeners();
    } catch (e) {
      debugPrint('Error saving dock settings: $e');
    }
  }

  /// Update settings
  Future<void> updateSettings(DockSettings newSettings) async {
    _settings = newSettings;
    await save();
  }

  /// Add a listener for settings changes
  void addListener(Function(DockSettings) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(Function(DockSettings) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener(_settings);
    }
  }
}

