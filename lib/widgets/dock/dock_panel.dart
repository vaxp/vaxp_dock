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
  final Function(String) onUnpin;
  final Function(int oldIndex, int newIndex)? onReorder;
  
  const DockPanel({
    super.key,
    required this.onLaunch,
    required this.onShowLauncher,
    this.onMinimizeLauncher,
    this.onRestoreLauncher,
    required this.pinnedApps,
    required this.onUnpin,
    this.onReorder,
  });

  @override
  State<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends State<DockPanel> {
  Widget _buildDockIcon(DesktopEntry entry) {
    if (entry.iconPath != null) {
      if (entry.isSvgIcon) {
        return GestureDetector(
          onSecondaryTapUp: (details) => _showDockIconMenu(context, details, entry),
          child: DockIcon(
            customChild: SvgPicture.file(
              File(entry.iconPath!),
              width: 40,
              height: 40,
            ),
            tooltip: entry.name,
            onTap: () => widget.onLaunch(entry),
          ),
        );
      } else {
        return GestureDetector(
          onSecondaryTapUp: (details) => _showDockIconMenu(context, details, entry),
          child: DockIcon(
            iconData: FileImage(File(entry.iconPath!)),
            tooltip: entry.name,
            onTap: () => widget.onLaunch(entry),
          ),
        );
      }
    } else {
      return GestureDetector(
        onSecondaryTapUp: (details) => _showDockIconMenu(context, details, entry),
        child: DockIcon(
          icon: Icons.apps,
          tooltip: entry.name,
          onTap: () => widget.onLaunch(entry),
        ),
      );
    }
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
                // Pinned apps
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
                          onWillAcceptWithDetails: (details) => details.data != null && details.data != entry.key,
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
