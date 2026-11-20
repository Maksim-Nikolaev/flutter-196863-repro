# Repro for flutter/flutter#196863

On Wayland, a Flutter Linux window that is hidden and shown again (for example close-to-tray and reopen) stays black.

The app is a plain `flutter create --platforms=linux` project with no plugins. The Dart side draws a green screen. The runner (`linux/runner/my_application.cc`) calls `gtk_widget_hide()` 2 s after the first frame and then `gtk_widget_show()`.

`check.sh` builds the release bundle, runs it on a headless `kwin_wayland --virtual` with a private D-Bus session, and compares the window centre in a screenshot before the hide and after the show.

```bash
./check.sh                                    # stock engine → FAIL (black)
./check.sh path/to/libflutter_linux_gtk.so    # patched release engine
REPRO_DELAY_MS=0 REPRO_CYCLES=5 ./check.sh    # show directly after hide, 5 cycles
```

Requirements: `kwin_wayland`, `spectacle`, ImageMagick `convert`, `dbus-run-session`.

## Results

Ubuntu 26.04.1, KWin 6.6.6, Flutter 3.50.0 (engine 371f77202a), release build.

| Hide → show delay | Cycles | Stock 3.50 | 3.50 + #196862 |
|---|---|---|---|
| 1000 ms | 1 | black | renders (3/3 runs) |
| 0 ms | 1 | black | renders |
| 0 ms | 5 | black | renders |
| 100 ms | 5 | black | renders |
| 1000 ms | 3 | black | renders |

## Unit test for #196862

`engine-test/196862-unit-test.diff` adds two tests to the Linux embedder tests. Both put the renderer in an offscreen window and mock the Wayland display and the toplevel `wl_surface` in `testing/mock_gtk`.

- `FlViewRendererSubsurfaceTest.RecreateSubsurfaceAfterShow` hides and shows the window and makes the new surface available only after `map`. It fails without #196862 (one `wl_subsurface` instead of two) and passes with it.
- `FlViewRendererSubsurfaceTest.NoSubsurfaceWhenHiddenBeforeIdle` shows the window and hides it again before the idle callback runs, while the surface still exists. It fails if the `gtk_widget_get_mapped()` check in the idle callback is removed (a subsurface is made on the hidden window) and passes with #196862. It also checks that a later show makes the subsurface.

Apply it on top of the PR branch from the root of a flutter/flutter checkout:

```bash
curl -sL https://raw.githubusercontent.com/Maksim-Nikolaev/flutter-196863-repro/main/engine-test/196862-unit-test.diff | git apply
```

Then build `flutter/shell/platform/linux:flutter_linux_unittests` and run it with `--gtest_filter='FlViewRendererSubsurfaceTest.*'`.
