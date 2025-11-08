import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/desktop_entry.dart';

class AppGrid extends StatelessWidget {
  final List<DesktopEntry> apps;
  final void Function(DesktopEntry) onLaunch;
  final void Function(DesktopEntry)? onPin;

  const AppGrid({
    super.key, 
    required this.apps, 
    required this.onLaunch,
    this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final e = apps[index];
        return GestureDetector(
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
                PopupMenuItem(
                  child: const Text('Pin to dock'),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    onPin?.call(e);
                  },
                ),
              ],
            );
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).maybePop();
              onLaunch(e);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.transparent),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Builder(
                    builder: (context) {
                      if (e.iconPath == null) {
                        return const Icon(Icons.apps, size: 48);
                      }
                      
                      if (e.isSvgIcon) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: SvgPicture.file(
                            File(e.iconPath!),
                            width: 56,
                            height: 56,
                          ),
                        );
                      }
                      
                      return CircleAvatar(
                        backgroundColor: Colors.transparent,
                        radius: 28,
                        backgroundImage: FileImage(File(e.iconPath!)),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(e.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}