# Third-party components and release audit

G-Collie project-owned source is GPL-3.0-only (see LICENSE). This does not replace third-party licenses or grant trademark rights. No warranty is provided.

## Runtime components

| Component | Source / license | Distributed material |
|---|---|---|
| Node.js 22.22.1 | https://nodejs.org/ ; MIT and bundled dependency notices | Linux runtime/LICENSE copied to package Node-LICENSE |
| JavaScript dependencies | Exact versions in package-lock.json; React, Express, marked, Lucide, PDF.js, mammoth and others keep their own MIT/ISC/Apache/BSD terms | Package JavaScript-LICENSES.txt contains license and NOTICE files for modules actually bundled by esbuild |
| Tailscale and linked Go modules | https://github.com/tailscale/tailscale ; BSD-3-Clause plus dependency-specific terms | android/assets/NETWORK-NOTICES.txt, regenerated from linked modules and Go runtime; included in DEB and Android assets |
| Flutter/Dart and plugins | Versions in flutter_client/pubspec.lock; SDK and individual plugin terms apply | Flutter-generated NOTICES.Z in APK assets/flutter_assets; Flutter license registry available in built assets |
| FFmpeg 7.0.2 | https://ffmpeg.org/releases/ffmpeg-7.0.2.tar.xz ; LGPL-2.1-or-later for the selected native build | DEB includes unmodified complete source tar, COPYING.LGPLv2.1, exact build.sh/configure options, compiler info and source/binary SHA256 in usr/share/doc/g-collie/ffmpeg |
| zlib / libc | System libraries provided by the distribution | Not copied into the FFmpeg executable; DEB declares zlib1g/libc6 dependencies |
| Lucide SVG UI icons | ISC; copyright Lucide contributors | flutter_client/assets/ui/LICENSE |
| Noto Sans CJK | SIL Open Font License, upstream copyright applies | Browser prototype only; PrototypeCJK-LICENSE.txt accompanies generated preview, not a production APK dependency |

The old imageio/johnvansickle FFmpeg GPL static executable is retained only in ignored local development tools. It is **not** shipped in the 0.3.26 candidate. Its old source index did not identify all sources corresponding to that exact build, so it has been replaced rather than treating an unrelated source URL as compliance.

## Brand asset provenance

- Codex SVG exactly matches tiann/hapi revision `6557dda7f6c55a73795e8c06d6eb11471f91b4a9`. Upstream license at that revision is AGPL-3.0. The unmodified SVG is retained under that license, not relabeled as project GPL; full license and editable original accompany it in `public/icons/licenses/` and Android assets. No hapi application code is incorporated by this asset attribution.
- Hermes PNG is a 1024→256 LANCZOS resize of the icon in NousResearch/hermes-agent revision `4b7229d612324adcf86ede7c181df542a1697fd6`; decoded resized RGBA pixels match exactly. Upstream MIT license, Copyright (c) 2025 Nous Research, is retained alongside the original source image.
- Exact URLs, source hashes, transformations and license texts are in `public/icons/licenses/provenance.json`. These checks establish the recorded upstream source and license, not ownership of third-party trademarks or an endorsement.
- On 2026-11-15 the project owner confirmed G-Collie dog artwork is self-owned/generated and authorized retaining it. Keep that source declaration with this audit; do not invent an upstream author or license for generated artwork.
- Agent names identify integrations. This project is independent and is not an official client or endorsement.

## Distributing source and binaries

Publish the matching G-Collie source snapshot alongside each binary and its SHA256, including build scripts, lockfiles, LICENSE and this file. Do not substitute an older Git commit for uncommitted source actually used to build. Preserve the separate third-party notices. Do not publish signing keys, signing properties, account credentials or user data.

Reference guidance: https://ffmpeg.org/legal.html and https://www.gnu.org/licenses/gpl-3.0.html . The actual license texts govern redistribution.
