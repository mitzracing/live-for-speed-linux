# Website media and font records

## Actual Live for Speed screenshots

The website uses six game screenshots, not real-world car photographs. Four come from the [official LFS gallery](https://www.lfs.net/screenshots); two come from community vehicle-mod pages. They show different builds, including development graphics. Community mods require an LFS S3 licence. These images are not recordings of the Linux wrapper, proof of exact-build gameplay, or a claim of upstream endorsement.

Screenshot redistribution permission has not been verified. Source pages establish provenance, not a license grant. The screenshots remain the property of their respective owners, separate from the MIT code. The owner requested publication after this limitation was disclosed. This approval does not grant upstream rights, and the images are not represented as rights-cleared. No permission requests were sent for this task. The maintainer remains responsible for reuse terms and any rights-holder request.

| File | Primary source | Bytes | WebP SHA-256 |
| --- | --- | ---: | --- |
| `lfs-gt3.webp` | [FUND MUTSAND GT3](https://www.lfs.net/files/vehmods/FAC497), image [586401](https://www.lfs.net/attachment/586401) | 94000 | `8cbd924cde7f67b15a94df2783e5bd332939a98d6831c2f43637d1ccd7b8f454` |
| `lfs-open-wheel.webp` | [Official gallery image](https://www.lfs.net/static/screenshots/-12293061%20-12772904%20531234%20-17595%20447%200.0%2060.0.jpg) | 117078 | `eb941329e2ab934001de05d29de2dc35022b0341b6219d33fd69e307aca756f9` |
| `lfs-drift.webp` | [FZ5 DRIFT PACK](https://www.lfs.net/files/vehmods/EC3AC1), image [327687](https://www.lfs.net/attachment/327687) | 100332 | `9df3da55f6c54cc19f345ae42481234c2aff7e81df1f825e2cf2f831ab307f5c` |
| `lfs-blackwood.webp` | [FZR leaving the Blackwood pits](https://www.lfs.net/static/screenshots/bl-fzr-leaving-pit-box.jpg) | 67832 | `bb93c573cc80bd16c20ffa0d5239500703fd7ffb1193680c6f7f56d500de0c63` |
| `lfs-cockpit.webp` | [Cockpit shadows](https://www.lfs.net/static/screenshots/Cockpit%20Shadows9.jpg) | 48384 | `6c4c9725cdcb051f8289eea7a40b342f3c0130ac5c950a2eefe1913e83fc4d12` |
| `lfs-roadsters.webp` | [Roadsters side by side](https://www.lfs.net/static/screenshots/Reflections_08.jpg) | 51594 | `575b4985a923852a89f17202973bea13b3021e6e3606c1a56a95202285779ba5` |

All source images are 16:9. Pillow uses LANCZOS sampling with `ImageOps.fit`, WebP `quality=78`, `method=6`. GT3, open-wheel, drift and cockpit outputs are 1120×630. Blackwood and roadsters retain their original 1024×576 dimensions. No upscaling, color grading, added imagery or watermark removal is applied. CSS uses `object-fit: contain` to preserve the full screenshot.

The six files total 479,220 bytes, within the existing 550 KiB combined budget. They are served locally without hotlinks. The initial hero is high-priority, later slides load on selection, and gallery images load lazily. The website has no added credit panels; existing marks inside source images remain intact. Originals, source-page records, hashes and selection evidence remain in `artifacts/website-lfs-overhaul/`. Retired real-world photographs are absent from this candidate and preserved with their historical notices.

The maintainer owns future replacements. Update images, captions, alt text, dimensions, this record, reviewed hashes and the explicit builder list together. Review the actual images against their primary sources; a filename or caption alone does not prove that an image comes from LFS. Keep image budgets, motion preferences, manual controls, failure geometry and no-JavaScript behavior. Website media, fonts and records do not belong in installed Linux packages.

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
