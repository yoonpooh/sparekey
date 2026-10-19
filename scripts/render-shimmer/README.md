# Sparekey shimmer renderer

Render the production cover artwork offscreen as PNG images or animation frames.

Return to the [project README](../../README.md) for installation and architecture.

## Requirements

Use a macOS checkout with Xcode Command Line Tools and `swiftc`.
Video encoding additionally requires an existing `ffmpeg` installation with `libx264`.
The wrapper compiles production artwork sources directly; it does not need a Swift package build.

## Usage

Run from the repository root:

```sh
scripts/render-shimmer.sh /tmp/sparekey-shimmer-evidence
```

The exact wrapper syntax is:

```text
scripts/render-shimmer.sh [OUTPUT_DIRECTORY [--video]]
```

The default directory is `/tmp/sparekey-shimmer-evidence`. `--video` must follow an explicit output directory.
Keep outputs outside the checkout. Existing outputs with the same names can be overwritten.

| Mode | Output |
| --- | --- |
| Default | `render-shimmer`, `shimmer-1.png` through `shimmer-3.png`, `reduce-motion.png`, `reduce-motion-repeat.png`, `render-notes.txt` |
| `--video` | `render-shimmer`, `frames/frame-0000.png` through `frames/frame-0359.png`, `video-render-notes.txt` |

Images are 1440 × 900 pixels. The default mode samples the shimmer at 30%, 50%, and 70% of the production cycle and renders two static Reduce Motion samples.
Video mode generates 360 frames at 30 fps, representing 12 seconds. The production cycle is 5.5 seconds.

Encode the frame sequence separately:

```sh
scripts/render-shimmer.sh /tmp/sparekey-shimmer-video --video
ffmpeg -n -framerate 30 -i /tmp/sparekey-shimmer-video/frames/frame-%04d.png \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart \
  -an /tmp/sparekey-shimmer-video/shimmer.mp4
```

The `-n` option makes ffmpeg refuse to overwrite an existing video.

## How it works and limits

The [wrapper](../render-shimmer.sh) compiles `CoverLayout.swift`, `CoverShimmer.swift`, `EmbeddedLogo.swift`, and this directory's [main.swift](main.swift).
`CALayer.render(in:)` does not advance animations, so the tool samples the production animation's endpoints and draws the text mask and gradient at each position.
Video mode checks the animation's linear `position.x` shape before sampling.

No window is shown, no screen is captured, and no helper or lock operation is performed.
The output supports visual inspection of artwork and sampled timing. It does not prove live WindowServer playback, physical cover visibility, or CPU and battery usage.

## Troubleshooting

- For compiler errors, check the macOS SDK and `swiftc` installation.
- For an animation precondition failure, compare this renderer with the production animation before using its frames as evidence.
- For encoding failures, check that ffmpeg supports `libx264` and that the target video does not already exist.

## License

[MIT](../../LICENSE), as part of Sparekey.
