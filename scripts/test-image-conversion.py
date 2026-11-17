#!/usr/bin/env python3
"""Pixel regression evidence using the actual release FFmpeg, not a mock decoder.
Usage: python3 scripts/test-image-conversion.py --ffmpeg .tools/ffmpeg-release/ffmpeg --output /tmp/image-qa /path/to/upload/content ...
Requires Pillow only for independent verification. Does not modify source images.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageChops, ImageStat, ImageOps

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ffmpeg', default='.tools/ffmpeg-release/ffmpeg')
parser.add_argument('--output', required=True)
parser.add_argument('sources', nargs='+')
args = parser.parse_args()
out = Path(args.output); out.mkdir(parents=True, exist_ok=True, mode=0o700)
report = []
for index, name in enumerate(args.sources, 1):
    source = Path(name)
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    original = ImageOps.exif_transpose(Image.open(source)).convert('RGB')
    original.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
    original.save(out / f'{index}-source.png')
    row = {'attachment': source.parent.name, 'source_sha256': before, 'variants': {}}
    for label, flags in [('old', []), ('scalar', ['-cpuflags', '0'])]:
        jpeg = out / f'{index}-{label}.jpg'
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', *flags, '-threads', '1', '-i', str(source), '-frames:v', '1', '-vf', 'scale=2048:2048:force_original_aspect_ratio=decrease', '-q:v', '3', '-y', str(jpeg)], check=True)
        decoded = Image.open(jpeg).convert('RGB')
        decoded.save(out / f'{index}-{label}.png')
        reference = original.resize(decoded.size, Image.Resampling.LANCZOS)
        mae = sum(ImageStat.Stat(ImageChops.difference(reference, decoded)).mean) / 3
        row['variants'][label] = {'size': list(decoded.size), 'bytes': jpeg.stat().st_size, 'rgb_mae': mae}
    assert row['variants']['scalar']['rgb_mae'] < 3, row
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    report.append(row)
(out / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
