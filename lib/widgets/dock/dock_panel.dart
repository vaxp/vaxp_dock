import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vaxp_core/models/desktop_entry.dart';
import 'dock_icon.dart';

class DockPanel extends StatefulWidget {
  final Function(DesktopEntry) onLaunch;
  final VoidCallback onShowLauncher;
  final VoidCallback? onMinimizeLauncher;
  final VoidCallback? onRestoreLauncher;
  final List<DesktopEntry> pinnedApps;
  final List<DesktopEntry> runningApps;
  final List<DesktopEntry> transientApps;
  final Function(String) onUnpin;
  final Function(int oldIndex, int newIndex)? onReorder;
  final Function(String windowId)? onWindowActivate; // window ID to activate
  final Map<String, String>? windowIdMap; // maps window title -> window ID
  
  const DockPanel({
    super.key,
    required this.onLaunch,
    required this.onShowLauncher,
    this.onMinimizeLauncher,
    this.onRestoreLauncher,
    required this.pinnedApps,
    required this.runningApps,
    required this.transientApps,
    required this.onUnpin,
    this.onReorder,
    this.onWindowActivate,
    this.windowIdMap,
  });

  @override
  State<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends State<DockPanel> {
  Widget _buildDockIcon(DesktopEntry entry) {
    return _buildDockIconWithHandler(entry, () => widget.onLaunch(entry));
  }

  Widget _buildDockIconWithHandler(DesktopEntry entry, VoidCallback onTap) {
    final isRunning = _isEntryRunning(entry);
    if (entry.iconPath != null) {
      if (entry.isSvgIcon) {
        return DockIcon(
          customChild: SvgPicture.file(
            File(entry.iconPath!),
            width: 40,
            height: 40,
          ),
          tooltip: entry.name,
          isRunning: isRunning,
          onTap: onTap,
        );
      } else {
        return DockIcon(
          iconData: FileImage(File(entry.iconPath!)),
          tooltip: entry.name,
          isRunning: isRunning,
          onTap: onTap,
        );
      }
    } else {
      return DockIcon(
        icon: Icons.window_rounded,
        tooltip: entry.name,
        isRunning: isRunning,
        onTap: onTap,
      );
    }
  }

  bool _isEntryRunning(DesktopEntry entry) {
    final exec = entry.exec ?? '';
    final cleaned = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
    final firstToken = cleaned.isNotEmpty ? cleaned.split(RegExp(r'\s+')).first : '';
    final execBase = firstToken.split('/').last.toLowerCase();
    final nameLower = entry.name.toLowerCase();

    bool matchesEntry(DesktopEntry e) {
      final eExec = e.exec ?? '';
      final eClean = eExec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
      final eFirst = eClean.isNotEmpty ? eClean.split(RegExp(r'\s+')).first : '';
      final eBase = eFirst.split('/').last.toLowerCase();
      if (execBase.isNotEmpty && eBase.isNotEmpty && (eBase.contains(execBase) || execBase.contains(eBase))) return true;
      if (nameLower.isNotEmpty && e.name.toLowerCase().contains(nameLower)) return true;
      return false;
    }

    for (final ra in widget.runningApps) {
      if (matchesEntry(ra)) return true;
    }

    for (final ta in widget.transientApps) {
      if (matchesEntry(ta)) return true;
    }

    return false;
  }

  void _showDockIconMenu(BuildContext context, TapUpDetails details, DesktopEntry entry) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        details.globalPosition,
        details.globalPosition,
      ),
      Offset.zero & overlay.size,
    );
    
    showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          child: const Text('Unpin from dock'),
          onTap: () => widget.onUnpin(entry.name),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha((0.3 * 255).toInt()),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onSecondaryTapUp: (details) {
                    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                    final position = RelativeRect.fromRect(
                      Rect.fromPoints(
                        details.globalPosition,
                        details.globalPosition,
                      ),
                      Offset.zero & overlay.size,
                    );
                    showMenu(
                      context: context,
                      position: position,
                      items: [
                        if (widget.onMinimizeLauncher != null)
                          PopupMenuItem(
                            onTap: widget.onMinimizeLauncher,
                            child: const Text('Minimize Launcher'),
                          ),
                        if (widget.onRestoreLauncher != null)
                          PopupMenuItem(
                            onTap: widget.onRestoreLauncher,
                            child: const Text('Restore Launcher'),
                          ),
                      ],
                    );
                  },
                  child: DockIcon(
                    icon: Icons.apps,
                    tooltip: 'Show all apps',
                    onTap: widget.onShowLauncher,
                  ),
                ),
                // Separator
                Container(
                  width: 1,
                  height: 42,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.2 * 255).toInt()),
                    borderRadius: BorderRadius.circular(0.5),
                  ),
                ),
                // Transient apps (windows)
                if (widget.transientApps.isNotEmpty)
                  ...widget.transientApps.asMap().entries.expand((entry) {
                    final windowId = widget.windowIdMap?[entry.value.name];
                    final onTapHandler = windowId != null && widget.onWindowActivate != null
                        ? () => widget.onWindowActivate!(windowId)
                        : () {};
                    // Create a temporary entry with the tap handler for _buildDockIcon
                    final entryWithHandler = DesktopEntry(
                      name: entry.value.name,
                      exec: entry.value.exec,
                      iconPath: entry.value.iconPath,
                      isSvgIcon: entry.value.isSvgIcon,
                    );
                    return [
                      GestureDetector(
                        onTap: onTapHandler,
                        onSecondaryTapUp: (details) => _showDockIconMenu(context, details, entry.value),
                        child: _buildDockIconWithHandler(entryWithHandler, onTapHandler),
                      ),
                      if (entry.key < widget.transientApps.length - 1)
                        Container(
                          width: 8,
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                    ];
                  }),

                // Pinned apps (user persisted)
                if (widget.pinnedApps.isNotEmpty)
                  ...widget.pinnedApps.asMap().entries.expand((entry) {
                    return [
                      Draggable<int>(
                        data: entry.key,
                        feedback: Material(
                          color: Colors.transparent,
                          child: _buildDockIcon(entry.value),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _buildDockIcon(entry.value),
                        ),
                        child: DragTarget<int>(
                          onWillAcceptWithDetails: (details) => details.data != entry.key,
                          onAcceptWithDetails: (details) {
                            widget.onReorder?.call(details.data, entry.key);
                          },
                          builder: (context, candidateData, rejectedData) {
                            return _buildDockIcon(entry.value);
                          },
                        ),
                      ),
                      if (entry.key < widget.pinnedApps.length - 1)
                        Container(
                          width: 8,
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                    ];
                  }),
                // Right side utilities separator
                Container(
                  width: 1,
                  height: 42,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(0.5),
                  ),
                ),
                // Downloads folder
                DockIcon(
                  icon: Icons.folder,
                  tooltip: 'Downloads',
                  onTap: () async {
                    try {
                      await Process.start('/bin/sh', ['-c', 'xdg-open ~/Downloads']);
                    } catch (e) {
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to open Downloads')),
                      );
                    }
                  },
                ),
                // Trash
                DockIcon(
                  icon: Icons.delete_outline,
                  tooltip: 'Trash',
                  onTap: () async {
                    try {
                      await Process.start('/bin/sh', ['-c', 'xdg-open trash://']);
                    } catch (e) {
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to open Trash')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}                     
