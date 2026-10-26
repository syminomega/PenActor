# Icon sources

English | [简体中文](README.zh-CN.md)

The mark combines a pen tip with a continuous pressure-response stroke.

- `AppIcon.svg` and `AppIcon.pdf`: 1024 × 1024 vector masters.
- `MenuBarIcon.svg`: monochrome master for an 18-point menu bar image.
- `AppIcon-preview.png`: app icon preview.
- `MenuBarIcon-appearance-preview.png`: light/dark appearance preview.

Runtime assets live in `PenActor/Assets.xcassets`. The app icon uses the ten
traditional macOS PNG sizes (16–1024 pixels). The menu bar image uses a template
PDF with vector data preserved; macOS supplies its color.

Regenerate the masters, previews, and asset-catalog outputs from the repository root:

```sh
swift scripts/generate-icons.swift
```

The script shares geometry across SVG/PDF/PNG output and needs no fonts,
third-party tools, or network access. PNGs are runtime raster assets; the SVG/PDF
masters are editable vector artwork.
