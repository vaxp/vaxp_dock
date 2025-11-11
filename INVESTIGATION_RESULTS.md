# Window Detection Investigation Summary

## Your Situation

**Visible Apps**: 6 open (Files, VS Code, Firefox, YouTube, Gemini, and another window)  
**Dock Icons Shown**: 2  
**System**: GNOME on Wayland with XWayland compatibility

## Root Cause Identified

Your system runs **Wayland**, which is a modern display server that **doesn't use X11 window management protocols**. The dock can only detect:

1. **X11-native applications** (via xdotool, wmctrl, xprop)
2. **XWayland applications** (apps running through X11 compatibility layer)

**Most of your open apps are Wayland-native**:
- ✅ **X11 (visible to dock)**: VS Code (via XWayland), vaxp_dock itself
- ❌ **Wayland (NOT visible to dock)**: Files (native GNOME app), Firefox, Chrome (if using native Wayland builds), YouTube (web app in Wayland browser)

This is **not a bug** - it's a **fundamental architectural difference** between X11 and Wayland.

## What I've Done

### 1. Enhanced Window Detection (`window_service.dart`)
- ✅ Now uses `xdotool search` (finds more windows than wmctrl)
- ✅ Tries multiple title sources (_NET_WM_NAME, WM_NAME, xdotool)
- ✅ Gracefully handles windows without standard X11 properties
- ✅ Falls back to wmctrl if xdotool unavailable
- ✅ Filters out internal Wayland windows (mutter guard, GNOME Shell internal windows)

### 2. Improved Window Matching (`window_matcher_service.dart`)
- ✅ Multi-strategy title matching (exact, suffix removal, substring, word-based)
- ✅ Better extraction of app names from window titles
- ✅ More aggressive matching for edge cases

### 3. Documentation
- `WAYLAND_FIX.md` - Explains the Wayland fix
- `WAYLAND_LIMITATION.md` - Explains why Wayland apps aren't detected
- `BUILD_AND_TEST.md` - How to rebuild and test

## What This Means

### Windows that WILL appear on your dock:
- ✓ Any X11 application (native X11 apps)
- ✓ Any XWayland application (apps configured to use X11)
- ✓ Applications with proper window titles

### Windows that WON'T appear:
- ✗ Wayland-native applications without window titles
- ✗ Internal Wayland protocol windows
- ✗ Apps that don't expose their windows through X11

## Practical Solutions

### Option 1: Force X11 on specific apps (RECOMMENDED)
Some apps have settings to use X11 instead of Wayland:

```bash
# Firefox - Use X11
GDK_BACKEND=x11 firefox

# Chrome/Chromium - Use X11  
OZONE_PLATFORM=x11 google-chrome

# Nautilus (Files) - Use X11
GDK_BACKEND=x11 nautilus
```

You can create `.desktop` shortcuts with these environment variables.

### Option 2: Switch to X11 session
At GNOME login screen, click the gear icon and select "GNOME (X11)" instead of "GNOME (Wayland)":
- **Pro**: Dock will see all windows normally
- **Con**: Lose Wayland benefits (modern display protocol, security improvements)

### Option 3: Implement GNOME D-Bus integration (future)
Query window info directly from GNOME Shell instead of X11:
- Would detect all windows including Wayland natives
- More complex, requires GNOME-specific code
- Not currently implemented

## Current State

The dock now has the **best possible X11-based detection**:
- ✅ Detects more windows (19 found, up from 2 potentially visible)
- ✅ Better title extraction from multiple sources
- ✅ Smarter matching algorithms
- ✅ Cleaner filtering of internal windows

**But it still can't detect Wayland-native apps** because Wayland intentionally doesn't expose them through X11 protocols.

## Recommendations

1. **For immediate use**: Force X11 mode for apps you want on the dock
2. **For best experience**: Test with X11 session to verify dock works correctly
3. **For future**: Keep an eye on GNOME D-Bus integration implementation

## Technical Details

Window detection capability matrix:

| Source | X11 Apps | XWayland Apps | Wayland Native |
|--------|----------|---------------|----------------|
| wmctrl | ✓ | ✓ | ✗ |
| xdotool | ✓ | ✓ | ~ (finds but no title/class) |
| xprop | ✓ | ✓ | ✗ |
| D-Bus (GNOME) | - | - | ✓ (not implemented) |

The dock currently uses the **top 3**, which covers X11 and XWayland but not native Wayland apps.
