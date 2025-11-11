/// Detect running applications and match to desktop entries
/// Used as fallback when X11 window detection fails on Wayland
import 'dart:io';
import '../models/desktop_entry.dart';

class ProcessWindowDetector {
  /// Get running application processes and match to desktop entries
  static Future<List<String>> detectRunningApps(List<DesktopEntry> desktopEntries) async {
    final runningApps = <String>[];
    
    try {
      // Get list of running processes
      final result = await Process.run('ps', ['aux']);
      if (result.exitCode != 0) return runningApps;
      
      final lines = (result.stdout as String).split('\n');
      
      for (final entry in desktopEntries) {
        if (entry.exec == null) continue;
        
        // Extract the executable name from the Exec field
        final execBase = _getExecBase(entry.exec!);
        if (execBase.isEmpty) continue;
        
        // Check if process is running
        for (final line in lines) {
          if (line.contains(execBase)) {
            runningApps.add(entry.name);
            break; // Found this app, move to next entry
          }
        }
      }
    } catch (_) {
      // ps command failed
    }
    
    return runningApps;
  }
  
  /// Extract executable base name from Exec field
  static String _getExecBase(String exec) {
    // Remove placeholders like %U, %f, etc.
    final cleaned = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
    if (cleaned.isEmpty) return '';
    
    // Get first token (the executable)
    final firstToken = cleaned.split(RegExp(r'\s+')).first;
    
    // Extract base name (without path)
    return firstToken.split('/').last;
  }
}
