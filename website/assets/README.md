# Website media and font credits

## Blackwood rallycross

- File: `blackwood-rallycross.webp`
- Work: *Rallycross at Blackwood*, an archival Live for Speed screenshot
- Author: Martin Kapal
- Source and license record: <https://commons.wikimedia.org/wiki/File:Rallycross_blackwood_lfs.jpg>
- Original image: <https://upload.wikimedia.org/wikipedia/commons/4/48/Rallycross_blackwood_lfs.jpg>
- License: **CC BY-SA 3.0**, <https://creativecommons.org/licenses/by-sa/3.0/>
- Original SHA-256: `3767a8c0e26fbb38339fa47b54c43d784de35e47b88015a589a25dac4fc6d51e`
- WebP SHA-256: `992b8b0e43fb8f8226a7be962ae995837639ffcc7b58a38a8542fc208cbaea9f`

The image was converted to WebP with Pillow (`quality=88`, `method=6`), retaining its 1024×640 dimensions. The website applies cropping and colour treatment through CSS. This adaptation remains under CC BY-SA 3.0, separately from the project's MIT-licensed code. Retain attribution, source and license links, and disclosure of changes when reusing it.

This is archival imagery, not a representation of the currently pinned game version or proof of Linux gameplay. It does not imply endorsement by the author or the LFS developers.

Website media, fonts, and these credits are distributed with the website and source archives, not installed by the Linux packages. Official-gallery reference images with unverified reuse permission are not included.

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
