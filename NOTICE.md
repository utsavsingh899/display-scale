# Notices

## App icon

The app icon is a render of the **"Laptop"** 3D model by [Polyfork](https://polyfork.dev).

- Source: https://polyfork.dev/asset/laptop-e775ba
- License: the Polyfork license (https://polyfork.dev/licensing). It permits use in apps, and it does not require attribution. It does not permit sharing the model files as standalone assets.

For this reason, this repository does not include the model file (`laptop-e775ba.glb`). It includes only the rendered icon image.

These files are not covered by the MIT License of this project:

- `app/icon/laptop.png` (the render of the model)
- `AppIcon.icns` in the built app (the same render at the standard icon sizes)

The Polyfork license terms apply to them.

`app/icon/render-glb.swift` made the render, and it is under the MIT License. To make the render again, download the model from the source page, then run:

```bash
swift app/icon/render-glb.swift laptop-e775ba.glb app/icon/laptop.png 30 22
```

## Menu bar icon

The menu bar icon is the "display" SF Symbol. macOS supplies it at run time, so this project does not include it.
