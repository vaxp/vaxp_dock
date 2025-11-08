import 'dart:ffi';
import 'dart:io' show Platform, Directory, File;
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
// ignore: depend_on_referenced_packages
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

class IconLoader {
  static late final DynamicLibrary _lib;
  static late final void Function() _initGtk;
  static late final Pointer<Utf8> Function(Pointer<Utf8>, int) _getIconPath;
  static late final void Function(Pointer<Utf8>) _freeIconPath;
  static bool _initialized = false;
  static bool _gtkAvailable = true;

  /// Initialize the GTK icon loader. This should be called early in the app lifecycle.
  static void initialize() {
    if (_initialized) return;

    try {
      // Load the dynamic library
      final libraryPath = _findLibrary();
      if (libraryPath != null) {
        _lib = DynamicLibrary.open(libraryPath);

        // Look up functions
        _initGtk = _lib.lookupFunction<Void Function(), void Function()>('init_gtk');
        
        _getIconPath = _lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Int32),
            Pointer<Utf8> Function(Pointer<Utf8>, int)>('get_icon_path');
        
        _freeIconPath = _lib.lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)>('free_icon_path');

        // Initialize GTK
        _initGtk();
        _initialized = true;
      } else {
        _gtkAvailable = false;
      }
    } catch (e) {      
      _gtkAvailable = false;
    }
  }

  /// Get an ImageProvider for an icon name using GTK's icon theme system.
  /// Returns null if the icon cannot be found or if it's an SVG file.
  static ImageProvider<Object>? getIcon(String iconName, {int size = 48}) {
    // Try GTK first if available
    if (_gtkAvailable) {
      if (!_initialized) initialize();
      
      if (_initialized) {
        try {
          final iconPath = getIconPath(iconName, size: size);
          if (iconPath != null) {
            return _createImageProvider(iconPath);
          }
        } catch (e) {
          print('GTK icon lookup failed: $e');
        }
      }
    }

    return null;
  }

  /// Internal method to get an icon path using GTK
  static String? getIconPath(String iconName, {int size = 48}) {
    if (!_initialized) initialize();

    if (!_gtkAvailable) return null;

    final iconNamePtr = iconName.toNativeUtf8();
    final resultPtr = _getIconPath(iconNamePtr, size);
    
    // Free the input string
    malloc.free(iconNamePtr);

    if (resultPtr.address == 0) return null;

    // Convert result to Dart string
    final result = resultPtr.toDartString();
    
    // Free the result
    _freeIconPath(resultPtr);
    
    return result;
  }

  /// Look for the native library in standard locations
  static String? _findLibrary() {
    if (!Platform.isLinux) return null;

    final libName = 'libicon_loader.so';
    final locations = [
      // Build directory
      path.join(Directory.current.path, 'build', 'lib', libName),
      // Local lib directory
      path.join(Directory.current.path, 'lib', libName),
      // System library paths
      '/usr/local/lib/$libName',
      '/usr/lib/$libName',
    ];

    for (final location in locations) {
      if (File(location).existsSync()) {
        return location;
      }
    }

    return null;
  }

  /// Returns true if the file at the given path is an SVG file
  static bool _isSvgFile(String path) {
    // First check the extension
    if (path.toLowerCase().endsWith('.svg')) {
      try {
        // Try to read the first few bytes to verify it's an SVG
        final file = File(path);
        if (!file.existsSync()) return false;
        
        final bytes = file.readAsBytesSync().take(100).toList();
        final content = String.fromCharCodes(bytes);
        
        // Check for SVG XML header or root element
        return content.contains('<?xml') || content.contains('<svg');
      } catch (e) {
        print('Error checking SVG file: $e');
        return false;
      }
    }
    return false;
  }

  /// Create a proper image provider based on file type
  static ImageProvider<Object>? _createImageProvider(String path) {
    if (!File(path).existsSync()) {
      print('File does not exist: $path');
      return null;
    }

    try {
      // Skip trying to load SVG files as regular images
      if (_isSvgFile(path)) {
        print('Skipping SVG file: $path');
        return null;
      }

      return FileImage(File(path));
    } catch (e) {
      print('Error creating image provider for $path: $e');
      return null;
    }
  }
}