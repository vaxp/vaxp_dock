# Window Detection Fix for Wayland Environments

## Problem Analysis

Your system is running **GNOME with Wayland + XWayland compatibility**. The original window detection was using `wmctrl -lx`, which only reports X11 windows. Result:

- Only **2 windows detected** (VS Code via XWayland, and the dock itself)
- **6 Wayland native windows** (Files, Firefox, Chrome, etc.) were completely invisible
- Window matching failed because window information was incomplete

## Root Cause

1. **Wayland windows don't have X11 WM_CLASS attributes** - they're not part of the X11 window management protocol
2. **wmctrl only shows X11 windows** - Wayland native apps are hidden
3. **xdotool -lx encounters the same limitation** but can still enumerate windows via `xdotool search`

## Solution Implemented

### 1. **Enhanced Window Detection** (`window_service.dart`)

Changed from wmctrl-first strategy to **xdotool-first strategy**:

```dart
// NEW: Use xdotool to get ALL windows (works on both X11 and Wayland)
final xdotoolWindowIds = await _getWindowsViaXdotool();
for (final windowId in xdotoolWindowIds) {
  // Get title (works for both X11 and Wayland windows)
  final titleResult = await Process.run('xdotool', ['getwindowname', windowId]);
  
  // Try xprop to get WM_CLASS (X11 only, won't work for Wayland)
  final xpropResult = await Process.run('xprop', ['-id', windowId, 'WM_CLASS']);
}
```

**Key improvements**:
- Uses `xdotool search --onlyvisible --class ''` to find ALL visible windows (ignores WM_CLASS)
- Gets window titles for every window (works on Wayland)
- Attempts to get WM_CLASS via xprop (X11 windows will have it)
- Skips Wayland-only internal windows (mutter guard windows, etc.)
- Falls back to wmctrl if xdotool fails

### 2. **Improved Window Matching** (`window_matcher_service.dart`)

Enhanced title-based matching to handle Wayland app detection:

```dart
// Strategy 1: Exact title match
// Strategy 2: Remove known app suffixes ("- Code", "- Firefox")
// Strategy 3: Extract app name from title (e.g., "Files" from "Downloads - Files")
// Strategy 4: First word matching
// Strategy 5: Last word matching (for "X - AppName" format)
```

**Now detects**:
- ✓ "Downloads - Files" → matches "Files" entry
- ✓ "Gmail - Google Chrome" → matches "Chrome" or "Chromium" entry
- ✓ "Linux - Wikipedia" → partial match via title
- ✓ Simple titles like "Terminal", "code"

### 3. **Performance Optimization**

- Gets active window **once per poll cycle** (1 xdotool call)
- Compares all windows against it (no per-window calls)
- Previously was calling `_checkIfActive()` for each window (N calls)

## Expected Results After Fix

1. **All visible windows should now appear as dock icons**
   - X11 windows (VS Code via XWayland)
   - Wayland native windows (Files, Firefox, Chrome, GNOME apps)

2. **Window matching should work better**
   - Apps matched by window class (X11)
   - Apps matched by window title (Wayland)
   - Title extraction handles both "Title - AppName" and "AppName - Title" formats

3. **Clicking dock icons should activate windows**
   - `wmctrl -i -a <windowid>` works for both X11 and Wayland

## Testing Steps

1. Launch the updated dock
2. Open multiple applications (Files, Firefox, VS Code, etc.)
3. Verify all open windows appear as dock icons
4. Click on icons to activate windows
5. Check that active window is highlighted

## Files Modified

1. **packages/vaxp_core/lib/services/window_service.dart**
   - Changed primary detection from wmctrl to xdotool
   - Added `_getWindowsViaXdotool()` method
   - Optimized active window detection to single call
   - Added `_toHexWindowId()` for window ID format conversion

2. **packages/vaxp_core/lib/services/window_matcher_service.dart**
   - Enhanced `_matchByTitle()` with multi-strategy approach
   - Added intelligent suffix removal
   - Added word-based extraction matching
   - Better handling of Wayland apps without WM_CLASS

## Limitations & Known Issues

1. **Window class still unavailable for Wayland apps** - this is a Wayland limitation, not a bug
2. **Some internal Wayland windows (mutter guard) are filtered out** - intentional to reduce clutter
3. **Complex window titles might not match perfectly** - fallback to default icon

## Future Improvements

1. **GNOME Shell D-Bus Integration** - Query window info directly from GNOME
2. **Process-based matching** - Match running processes to .desktop entries
3. **Icon caching** - Cache matched window→icon mappings to reduce lookup overhead
4. **Wayland-specific APIs** - Use GTK/GNOME APIs directly if available
