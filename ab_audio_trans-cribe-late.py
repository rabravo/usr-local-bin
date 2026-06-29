#!/usr/bin/env python3

import argparse
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import torch
import whisper
from tqdm import tqdm
from whisper.tokenizer import LANGUAGES

MODEL_DIR = Path(__file__).parent / "models"


def download_youtube_audio(url: str) -> Path:
    if not shutil.which("yt-dlp"):
        sys.exit("yt-dlp not found — install it: pip install yt-dlp  OR  brew install yt-dlp")

    match = re.search(r"(?:v=|youtu\.be/)([^&?/]+)", url)
    if not match:
        sys.exit("Could not extract video ID from URL.")
    video_id = match.group(1)

    out_path = Path(f"{video_id}.mp3")
    print(f"Downloading audio from YouTube ({video_id})...", file=sys.stderr)
    subprocess.run(
        [
            "yt-dlp",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "-o", f"{video_id}.%(ext)s",
            f"https://www.youtube.com/watch?v={video_id}",
        ],
        check=True,
    )
    return out_path


def run_whisper(model, audio_path: Path, task: str, language: str | None, duration: float, pass_label: str) -> list:
    fp16 = torch.cuda.is_available()
    options: dict = {"task": task, "fp16": fp16, "verbose": False}
    if language:
        options["language"] = language

    result_holder: list = [None]

    def run() -> None:
        result_holder[0] = model.transcribe(str(audio_path), **options)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()

    with tqdm(
        total=int(duration),
        unit="s",
        desc=f"  {pass_label}",
        bar_format="{l_bar}{bar}| {n:.0f}/{total:.0f}s [{elapsed}<{remaining}]",
        ncols=72,
        file=sys.stderr,
    ) as pbar:
        start_time = time.monotonic()
        last = 0
        while thread.is_alive():
            elapsed = time.monotonic() - start_time
            estimated = min(int(elapsed * 8), int(duration) - 1)
            if estimated > last:
                pbar.update(estimated - last)
                last = estimated
            time.sleep(0.25)
        pbar.update(int(duration) - last)

    thread.join()
    return result_holder[0]["segments"]


def format_time(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def lang_name(code: str) -> str:
    return LANGUAGES.get(code, code).capitalize() if code else "Unknown"


def print_segments(segments: list) -> None:
    for seg in segments:
        print(f"[{format_time(seg['start'])} --> {format_time(seg['end'])}]  {seg['text'].strip()}")


def write_text(audio_path: Path, segments: list, label: str) -> None:
    out = Path.cwd() / f"{audio_path.stem}_{label}.txt"
    lines = [f"[{format_time(seg['start'])} --> {format_time(seg['end'])}]  {seg['text'].strip()}" for seg in segments]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Saved → {out}", file=sys.stderr)


def ask_mode() -> int:
    print()
    print("What would you like to generate?")
    print("  1) Transcription in original language  (text)")
    print("  2) English translation                 (text)")
    print("  3) Both — original + translation       (HTML)")
    print()
    while True:
        choice = input("Choice [1-3]: ").strip()
        if choice in ("1", "2", "3"):
            return int(choice)
        print("Please enter 1, 2, or 3.")


def transcribe(audio_path: Path, model_name: str, language: str | None, mode: int) -> None:
    MODEL_DIR.mkdir(exist_ok=True)
    print(f"Loading model '{model_name}'...", file=sys.stderr)
    model = whisper.load_model(model_name, download_root=str(MODEL_DIR))

    print("Loading audio...", file=sys.stderr)
    audio = whisper.load_audio(str(audio_path))
    duration = len(audio) / whisper.audio.SAMPLE_RATE

    if mode == 3:
        orig_segments = run_whisper(model, audio_path, "transcribe", language, duration, "Pass 1/2: Transcribing")
        trans_segments = run_whisper(model, audio_path, "translate",  language, duration, "Pass 2/2: Translating ")
        write_text(audio_path, orig_segments, "transcription")
        write_text(audio_path, trans_segments, "translation")
        write_html(audio_path, orig_segments, trans_segments, language)
    elif mode == 1:
        segments = run_whisper(model, audio_path, "transcribe", language, duration, "Transcribing")
        print_segments(segments)
        write_text(audio_path, segments, "transcription")
    else:
        segments = run_whisper(model, audio_path, "translate", language, duration, "Translating")
        print_segments(segments)
        write_text(audio_path, segments, "translation")


def best_translation(orig_seg: dict, trans_segs: list) -> str | None:
    """Return the text of the translate segment with the most time overlap with orig_seg."""
    best_text = None
    best_overlap = 0.0
    for t in trans_segs:
        ov = max(0.0, min(orig_seg["end"], t["end"]) - max(orig_seg["start"], t["start"]))
        if ov > best_overlap:
            best_overlap = ov
            best_text = t["text"].strip()
    # Require at least 0.5 s of overlap to avoid spurious matches on silence
    return best_text if best_overlap >= 0.5 else None


def write_html(audio_path: Path, orig: list, trans: list | None, language: str | None) -> None:
    src_lang = lang_name(language) if language else "Original"
    bilingual = trans is not None

    rows = []
    for seg in orig:
        ts = f"{format_time(seg['start'])} → {format_time(seg['end'])}"
        original_text = seg["text"].strip()
        if bilingual:
            translation_text = best_translation(seg, trans)
            if translation_text:
                rows.append(f"""
        <tr>
          <td class="ts">{ts}</td>
          <td class="orig">{original_text}</td>
          <td class="tran">{translation_text}</td>
        </tr>""")
            else:
                rows.append(f"""
        <tr>
          <td class="ts">{ts}</td>
          <td class="orig" colspan="2">{original_text}</td>
        </tr>""")
        else:
            rows.append(f"""
        <tr>
          <td class="ts">{ts}</td>
          <td class="orig" colspan="2">{original_text}</td>
        </tr>""")

    translation_header = '<th>English</th>' if bilingual else ''

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{audio_path.stem}</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; }}
    body {{
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 960px;
      margin: 2rem auto;
      padding: 0 1rem;
      background: #fafafa;
      color: #222;
    }}
    h1 {{ font-size: 1.4rem; margin-bottom: 0.25rem; }}
    p.meta {{ color: #666; font-size: 0.85rem; margin-top: 0; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      margin-top: 1.5rem;
      background: #fff;
      box-shadow: 0 1px 4px rgba(0,0,0,.08);
      border-radius: 6px;
      overflow: hidden;
    }}
    thead {{ background: #f0f0f0; }}
    th, td {{ padding: 0.6rem 0.8rem; text-align: left; vertical-align: top; }}
    th {{ font-size: 0.78rem; text-transform: uppercase; letter-spacing: .05em; color: #555; }}
    td.ts {{ white-space: nowrap; font-size: 0.78rem; color: #888; width: 11rem; }}
    td.orig {{ color: #111; line-height: 1.6; }}
    td.tran {{ color: #2a5db0; line-height: 1.6; }}
    tr:not(:last-child) td {{ border-bottom: 1px solid #eee; }}
    tr:hover td {{ background: #f7f9ff; }}
  </style>
</head>
<body>
  <h1>{audio_path.name}</h1>
  <p class="meta">Source language: {src_lang}{" · Translation: English" if bilingual else ""}</p>
  <table>
    <thead>
      <tr>
        <th>Time</th>
        <th>{src_lang}</th>
        {translation_header}
      </tr>
    </thead>
    <tbody>{"".join(rows)}
    </tbody>
  </table>
</body>
</html>
"""

    out = Path.cwd() / f"{audio_path.stem}.html"
    out.write_text(html, encoding="utf-8")
    print(f"Saved → {out}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Transcribe or translate lyrics from an audio file using Whisper.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  # local file — interactive menu picks mode
  ./ab_audio_trans-cribe-late.py ~/Music/song.mp3 --language ja

  # specify language and a smaller/faster model
  ./ab_audio_trans-cribe-late.py ~/Music/song.mp3 --language it --model medium

  # YouTube URL directly (skips the YouTube prompt)
  ./ab_audio_trans-cribe-late.py --url "https://www.youtube.com/watch?v=VIDEO_ID" --language ja

  # no arguments — prompts for audio source and mode
  ./ab_audio_trans-cribe-late.py

modes (chosen interactively):
  1  Transcription in original language → stdout + <stem>_transcription.txt
  2  English translation                → stdout + <stem>_translation.txt
  3  Both (original + translation)      → <stem>_transcription.txt + <stem>_translation.txt + <stem>.html

  all output files are written to the current working directory.

supported language codes (--language):
  ja  Japanese    ko  Korean     zh  Chinese    fr  French
  it  Italian     es  Spanish    de  German     pt  Portuguese
  ru  Russian     ar  Arabic     hi  Hindi      (and many more)

model sizes (--model):
  tiny / base / small   fast, less accurate
  medium                good balance
  large / large-v3      best accuracy, slower
  default: large (used when --model is not specified)
        """,
    )
    parser.add_argument(
        "audio",
        nargs="?",
        help="Path to a local audio file (e.g. audio.mp3). Omit to download from YouTube.",
    )
    parser.add_argument(
        "--url",
        help="YouTube URL to download audio from (skips the interactive prompt).",
    )
    parser.add_argument(
        "--model",
        default="large",
        choices=["tiny", "base", "small", "medium", "large", "large-v2", "large-v3"],
        help="Whisper model size (default: large)",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Source language code, e.g. 'ja' Japanese, 'it' Italian, 'fr' French. Auto-detected if omitted.",
    )
    args = parser.parse_args()

    if args.audio:
        audio_path = Path(args.audio).expanduser()
        if not audio_path.exists():
            sys.exit(f"File not found: {audio_path}")
    else:
        url = args.url
        if not url:
            answer = input("No local audio given. Download from YouTube? [y/N]: ").strip().lower()
            if answer != "y":
                sys.exit("Aborted.")
            url = input("YouTube URL: ").strip()
        audio_path = download_youtube_audio(url)

    mode = ask_mode()
    transcribe(audio_path, args.model, args.language, mode)


if __name__ == "__main__":
    main()
