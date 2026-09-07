# Website media and font records

## Motorsport photographs

These six photographs use the [Unsplash License](https://unsplash.com/license). Attribution is not required. The license permits free download, copying, modification, distribution and use, including commercial use. It does not permit selling unmodified images or compiling a competing image service. These photographs remain separately licensed from the MIT code.

Each linked photo page identifies its image as free to use under the Unsplash License. These are real-world motorsport photographs, not LFS screenshots, bundled game content or evidence of Linux gameplay. The website labels that distinction and displays no photo credits. No endorsement by depicted people or brands is claimed.

| File | Photo page | Bytes | WebP SHA-256 |
| --- | --- | ---: | --- |
| `pit-lane.webp` | [sR-MmCZuo4A](https://unsplash.com/photos/race-cars-are-being-worked-on-in-the-pit-lane-sR-MmCZuo4A) | 124820 | `56db2dcac374fd328264abd0727e566b7e323ba3d34e2f03775cd589b9d5c065` |
| `gt3-track.webp` | [GaXm8_GKJiA](https://unsplash.com/photos/black-porsche-gt3-rs-with-yellow-accents-on-track-GaXm8_GKJiA) | 75672 | `a4f8a7ba126391b32ca44975385655ba2042cedce6a57c24fb7eb24d68903d32` |
| `drift-smoke.webp` | [RI8h-awF3sA](https://unsplash.com/photos/drifting-car-creating-smoke-on-race-track-RI8h-awF3sA) | 39056 | `8047f0d0c67cd727fd2942c3e07144ec6d71f0827d84c8f3818281303e6b7aa9` |
| `garage.webp` | [WpHw-FnxbuU](https://unsplash.com/photos/race-car-with-hood-open-in-garage-pit-stop-WpHw-FnxbuU) | 72434 | `4c1326ff8fadebd06c286a304bc2c8f5bd41c0c63835b8bdf103f1cc4e861c80` |
| `drift-action.webp` | [3Z7lDp8LPvU](https://unsplash.com/photos/drifting-car-on-a-race-track-with-smoke-3Z7lDp8LPvU) | 65136 | `ca82884582c8cadce7418ccd75c6922da5c6df0da0f42a8af511ae64ee328c2d` |
| `gt3-detail.webp` | [eLipvu7I2hQ](https://unsplash.com/photos/rear-view-of-a-grey-porsche-gt3-with-large-wing-eLipvu7I2hQ) | 90158 | `9aad4b2161aa8f0ed6e60f6ae990b2e4b1682dba46e7322119e238f930cf7659` |

The downloaded source images retain a maximum width of 1920 pixels. Pillow `ImageOps.fit` crops and resizes them to 1120×630 with LANCZOS sampling. WebP uses `quality=78`, `method=6`. Crop centers are pit lane `(0.5, 0.46)`, GT3 track `(0.5, 0.54)`, drift smoke `(0.5, 0.55)`, garage `(0.5, 0.5)`, drift action `(0.5, 0.75)` and GT3 detail `(0.5, 0.5)`. The hero applies an additional centered CSS crop. No watermark was removed.

The six files total 467,276 bytes. They are served locally, without hotlinks. The initial hero is high-priority, later slides load on selection, and gallery images load lazily. Private downloaded sources, source-page records and hashes remain in `artifacts/website-photo-refresh/`. The former six screenshot assets are not in the current website or assembled output. Their original notices remain with historical versions and private backups.

The maintainer owns future replacements. Update images, captions, alt text, dimensions, this record, asset hashes and the explicit builder list together. Keep image budgets, motion preferences, manual controls, failure geometry and the no-JavaScript fallback. Website media, fonts and these records belong to the website/source tree, not installed Linux packages.

## Space Grotesk

- File: `spacegrotesk.woff2`, 13,284 bytes; used for 600-weight headings
- Copyright 2020 The Space Grotesk Project Authors: <https://github.com/floriankarsten/space-grotesk>
- License: **SIL Open Font License 1.1**, included in [`spacegrotesk-OFL.txt`](spacegrotesk-OFL.txt)
- Font source: <https://fonts.gstatic.com/s/spacegrotesk/v22/V8mQoQDjQSkFtoMM3T6r8E7mF71Q-gOoraIAEj42VnskPMA.woff2>
- License source: <https://raw.githubusercontent.com/google/fonts/main/ofl/spacegrotesk/OFL.txt>
- Font SHA-256: `685bbbf69fa616df1ef81847c85fc76be097ddfb3468ff2257be54511ab3130f`
- Original license SHA-256: `564ce565c371c5e5bbf286006565a7c9aa55a9f56e7ca58d56e05d649dd61a72`
- Stored license SHA-256: `18a4de52385f6b988782639d5d0cc1326e5a8c2de9a7f01d7b20d9aedcc60943`

The font is copied without modification. The license preserves every word; only line endings and trailing whitespace were normalized to repository conventions. The website serves the font locally, without requests to a font service. CSS uses `font-display: swap` and a sans-serif fallback. The font retains its OFL license, separately from the MIT code.

## Native GTK interface demonstration

The project-generated recording shows the MIT-licensed community launcher interface and community icon. It contains no proprietary game footage and does not imply upstream endorsement.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `installer-demo.webm` | 149,546 | `07d55f1b1d310e8d8bcb5365b52d5cac9916bfc6f0f9adfe96b076ee4ec4ef08` |
| `installer-demo.mp4` | 149,077 | `53e7c66bf81792b0fb2e901014962c21e15dc82101112f57be1f2464db31df5b` |
| `installer-poster.webp` | 40,144 | `6ba27303d47bf45902a437a768bbaf6b888dfa501856da4bd1b48b2bfd0bde30` |

The silent clip is 10.5 seconds at 24 fps, 1240×1200. WebM uses VP9; MP4 supplies H.264 fallback. The poster is a still from the same demonstration.

Capture used the unchanged `libexec/lfs_linux_gtk.py` from commit `28c6562d4d490ed8ea10cf451e74d68617762983`, through its existing Unix-socket transport. Renderer SHA-256: `92e0aade1202b833af37d2deca09f3d5a6228d6baf1f7fb17fa4a9cfd0d9ff52`. Native pointer actions select **Install and play** and open **Details**. Data and timing are scripted: a generated local fixture grows to 6 MiB of an illustrative 8 MiB total. No installer controller, core, Wine, game, or player state is used.

The renderer ran on an owned Xephyr display with private Xauthority, Adwaita dark theme, 2× GTK scale, and Cairo rendering. FFmpeg captured only that window and added the persistent demonstration label. It did not capture the user's desktop. The video is not proof of real download speed, game installation, or gameplay acceptance.

The project maintainer owns media updates when the GTK interface changes. Keep the demonstration disclosure, written steps, fallback poster, and this provenance with the media. Private capture scripts and lossless master remain in the maintainer's `artifacts/website-video/` directory; they are not package dependencies.
