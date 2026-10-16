"""Audio conversion helpers for the Builder prompt upload UI.

Converts uploaded audio files (mp3, m4a, flac, etc.) to Asterisk native formats:
8 kHz mono PCM 16-bit WAV and mu-law (.ulaw).
"""

from __future__ import annotations

import logging
import re
import shutil
import subprocess
from pathlib import Path

log = logging.getLogger(__name__)

CONVERTIBLE_SUFFIXES = {".mp3", ".m4a", ".aac", ".flac", ".ogg", ".oga", ".opus", ".wma", ".aiff"}
TARGET_SUFFIX = ".wav"
FFMPEG_TIMEOUT = 60
CONVERT_SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "convert_sound.sh"


def ffmpeg_binary() -> str | None:
    """Absolute path of ffmpeg, or None when it is not installed."""
    return shutil.which("ffmpeg")


def needs_conversion(suffix: str) -> bool:
    return suffix.lower() in CONVERTIBLE_SUFFIXES


def snake_case_stem(name: str) -> str:
    stem = Path(name).stem.lower()
    slug = re.sub(r"[^a-z0-9]+", "_", stem).strip("_")
    return slug or "prompt"


def convert_audio(source: Path, stem: str, out_dir: Path) -> str:
    """Convert *source* into ``<out_dir>/<stem>.ulaw`` and ``.wav``."""
    if CONVERT_SCRIPT.is_file():
        try:
            proc = subprocess.run(
                ["bash", str(CONVERT_SCRIPT), str(source), stem, str(out_dir)],
                check=False,
                capture_output=True,
                text=True,
                timeout=FFMPEG_TIMEOUT,
            )
            detail = (proc.stdout or proc.stderr or "").strip()
            if proc.returncode == 0 and (out_dir / f"{stem}.wav").is_file():
                return detail.splitlines()[-1] if detail else "converted to 8 kHz mono wav"
            return detail[:200] or f"convert_sound.sh exited {proc.returncode}"
        except (OSError, subprocess.TimeoutExpired) as exc:
            return f"convert_sound.sh failed: {exc}"

    ffmpeg = ffmpeg_binary()
    if not ffmpeg:
        return "ffmpeg is not installed - install it or upload .wav/.ulaw/.alaw/.gsm audio"
    if not source.is_file():
        return f"uploaded file vanished: {source}"

    out_dir.mkdir(parents=True, exist_ok=True)
    made: list[str] = []
    for suffix, codec, muxer in ((".ulaw", "pcm_mulaw", "mulaw"), (".wav", "pcm_s16le", "wav")):
        tmp = out_dir / f".convert-{stem}{suffix}"
        command = [
            ffmpeg, "-y", "-nostdin", "-loglevel", "error",
            "-i", str(source), "-ac", "1", "-ar", "8000",
            "-acodec", codec, "-f", muxer, str(tmp),
        ]
        try:
            proc = subprocess.run(
                command, check=False, capture_output=True, text=True, timeout=FFMPEG_TIMEOUT
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            tmp.unlink(missing_ok=True)
            return f"ffmpeg failed: {exc}"
        if proc.returncode != 0 or not tmp.is_file():
            tmp.unlink(missing_ok=True)
            detail = (proc.stderr or proc.stdout or f"exit {proc.returncode}").strip().splitlines()
            return f"ffmpeg could not convert {source.suffix or 'file'}: {detail[-1] if detail else 'unknown error'}"
        tmp.replace(out_dir / f"{stem}{suffix}")
        made.append(suffix)
    return f"converted {source.suffix} to 8 kHz mono {', '.join(made)}"
