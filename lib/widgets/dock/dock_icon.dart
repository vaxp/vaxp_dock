import 'package:flutter/material.dart';

class DockIcon extends StatefulWidget {
  final IconData? icon;
  final ImageProvider<Object>? iconData;
  final Widget? customChild;
  final String? tooltip;
  final VoidCallback onTap;
  final String? name;

  const DockIcon({
    super.key,
    this.icon,
    this.iconData,
    this.customChild,
    this.tooltip,
    required this.onTap,
    this.name,
  }) : assert(icon != null || iconData != null || customChild != null, 
             'Either icon, iconData, or customChild must be provided');

  @override
  State<DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<DockIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip ?? widget.name ?? '',
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: widget.iconData != null ? null : Colors.transparent,
                      ),
                      child: widget.customChild != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: widget.customChild!,
                            )
                          : widget.iconData != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image(
                                    image: widget.iconData!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  widget.icon ?? Icons.apps,
                                  size: 40,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                    ),
                    // Running indicator dot
                    // Container(
                    //   margin: const EdgeInsets.only(top: 5),
                    //   width: 5,
                    //   height: 5,
                    //   decoration: BoxDecoration(
                    //     color: Colors.white.withOpacity(0.8),
                    //     shape: BoxShape.circle,
                    //   ),
                    // ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}