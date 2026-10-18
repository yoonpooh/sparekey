# Render shimmer evidence

Run from a macOS checkout with Xcode Command Line Tools. The script compiles the
production cover artwork and shimmer sources directly with `swiftc`. It does not
need a package build, show a window, capture the screen, contact the helper, or
change the Mac's lock state.

## Still frames

```sh
scripts/render-shimmer.sh /tmp/sparekey-shimmer-evidence
```

The output contains three shimmer PNGs, two identical simulated Reduce Motion
PNGs, render notes, and the renderer executable. The default output directory is
`/tmp/sparekey-shimmer-evidence`. Keep generated files outside the checkout.

## Video

```sh
scripts/render-shimmer.sh /tmp/sparekey-shimmer-video --video
ffmpeg -n -framerate 30 -i /tmp/sparekey-shimmer-video/frames/frame-%04d.png \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart \
  -an /tmp/sparekey-shimmer-video/shimmer.mp4
```

Encoding needs an existing ffmpeg installation with libx264. The renderer creates
360 frames at 1440×900 for 12 seconds. The current 5.5-second cycle completes twice
at 11 seconds. ffmpeg refuses to overwrite an existing video with `-n`.

`CALayer.render(in:)` does not advance animations. The renderer samples the actual
production `CABasicAnimation` endpoints at `time % duration` using its linear
timing, then draws the same text mask and gradient layer. It checks the animation
shape before rendering. This verifies rendered appearance and timing; it does
not verify live WindowServer playback, physical cover visibility, or CPU/battery
usage. The frame loop exists only in this development tool.
