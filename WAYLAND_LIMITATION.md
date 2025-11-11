# Wayland Window Detection Limitation - Analysis

## Problem

On your system:
- **6 visible windows** (Files, VS Code, Firefox, YouTube, Gemini, etc.) but **only 2 dock icons** shown
- **Root cause**: Wayland-native applications are not exposing their window information through X11/XWayland protocols

## Technical Analysis

### What xdotool/xprop finds:
```
✓ 19 total windows (both X11 and Wayland)
✓ Only 5 have meaningful titles (VS Code, code windows, Chromium clipboard helper)
✗ Most have empty titles (Wayland-native windows)
✗ Most lack WM_CLASS property (not X11-compliant)
```

### What wmctrl finds:
```
✓ 2 windows total (only X11 windows)
  - VS Code (running via XWayland)
  - vaxp_dock (running via XWayland)
✗ No Wayland-native apps (Files, Firefox, GNOME apps)
```

### Why this happens:

1. **Wayland is a different display protocol** than X11
2. **XWayland provides X11 compatibility** for apps that need it
3. **Native Wayland apps don't expose window info to X11 tools**
4. **GNOME Shell manages Wayland windows directly**, not through X11

This is **by design** - Wayland applications intentionally don't expose X11 properties to maintain sandboxing and security.

## Current Implementation

The dock correctly:
- ✓ Uses xdotool to find ALL windows (including Wayland)
- ✓ Extracts titles using xdotool and xprop
- ✓ Tries multiple title sources (_NET_WM_NAME, WM_NAME, xdotool)
- ✓ Matches windows by title to desktop entries
- ✓ Falls back to wmctrl if xdotool unavailable

The dock limitations:
- ✗ Can't detect Wayland windows without titles
- ✗ Can't get WM_CLASS from Wayland windows
- ✗ Depends on X11/XWayland for all information

## Possible Solutions (for future work)

1. **GNOME Shell D-Bus Interface** (org.freedesktop.DBus.Properties)
   - Query window info directly from GNOME Shell
   - Would find all windows including Wayland natives
   - More complex to implement

2. **Process-Based Detection**
   - Match running processes to .desktop entries
   - Doesn't provide window titles
   - Unreliable for multiple instances

3. **GTK Window Tracker**
   - Use GTK's native window API
   - Would work for GTK apps (Files, GNOME apps)
   - Doesn't work for Qt apps (Firefox), Chromium, etc.

4. **User Configuration**
   - Document which apps need manual config
   - Provide .desktop file templates
   - Less user-friendly solution

## Workaround for Your System

Until a better solution is implemented, you can:

1. **Use native X11 apps when available**
   - Replace Wayland-native apps with XWayland versions
   - Check app preferences for Wayland/X11 selection

2. **Monitor specific processes** (future feature)
   - Add process-based fallback matching
   - Would at least show indicators for running apps

3. **Disable Wayland**
   - Switch to X11 session at login screen
   - Dock would then see all windows normally
   - Trade-off: lose Wayland benefits (better display handling, security)

## References

- Wayland documentation: https://wayland.freedesktop.org/
- XWayland: https://wayland.freedesktop.org/xwayland/
- GNOME Wayland migration: https://wiki.gnome.org/Initiatives/Wayland
