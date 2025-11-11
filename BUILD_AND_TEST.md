# Building and Testing the Updated Dock

## Quick Build

```bash
cd /home/xxx/Desktop/vaxp_dock
flutter build linux --debug
```

## Run

```bash
./build/linux/x64/debug/bundle/vaxp_dock
```

Or in debug mode:

```bash
flutter run -d linux
```

## Testing Procedure

1. **Before testing, open multiple applications:**
   ```bash
   nautilus ~/Downloads &    # File manager
   firefox &                  # Browser
   gedit &                    # Text editor
   code .                      # VS Code
   gnome-terminal &           # Terminal
   ```

2. **Launch the dock:**
   ```bash
   ./build/linux/x64/debug/bundle/vaxp_dock &
   ```

3. **Expected Results:**
   - You should see **5+ dock icons** (one for each open app)
   - Previously you only saw **2 icons**
   - Clicking each icon should activate its window
   - The active window should be highlighted

4. **Debug Window Detection:**
   ```bash
   # See all visible windows
   xdotool search --onlyvisible --class ''
   
   # Get details for each window
   for wid in $(xdotool search --onlyvisible --class ''); do
     echo "=== Window $wid ==="
     xdotool getwindowname "$wid"
     xprop -id "$wid" WM_CLASS 2>/dev/null || echo "(no WM_CLASS - Wayland app)"
   done
   ```

5. **Check Dock Logs:**
   - Monitor window detection in Flutter DevTools
   - Check if window matching is working

## What Changed?

See `WAYLAND_FIX.md` for full details, but key improvements:

- ✅ Now uses `xdotool` for window enumeration (Wayland-aware)
- ✅ Falls back to `wmctrl` if needed
- ✅ Enhanced title-based matching for Wayland apps
- ✅ Optimized performance (single active window check per poll)

## Troubleshooting

**Only seeing 2 icons?**
- The build is still using the old binary (from Nov 11)
- Run `flutter clean` then `flutter build linux --debug`

**Seeing many dock icons but icons are wrong?**
- The xdotool window detection is working, but matching might need tweaks
- Check logs for which .desktop entries are being matched
- May need to add more matching rules

**Active window not highlighted?**
- `xdotool getactivewindow` might not work on your Wayland setup
- This is a known limitation of Wayland, not a bug in the dock
