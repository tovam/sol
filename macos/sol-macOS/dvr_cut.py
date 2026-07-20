#!/usr/bin/env python3

"""Inspect and cut a clock-addressable HLS DVR playlist for Sol.

The worker deliberately accepts a media-playlist URL, not a Dailymotion page.
Sol resolves the selected Dailymotion format with yt-dlp before invoking it.
All machine-readable output is newline-delimited JSON on stdout.
"""

from __future__ import annotations

import argparse
import atexit
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urljoin, urlparse


USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Sol/1"
MINIMUM_DVR_SECONDS = 10.0
MINIMUM_FREE_BYTES = 128 * 1024 * 1024


class DVRCutError(Exception):
    pass


@dataclass
class Segment:
    sequence: int
    start: datetime
    end: datetime
    duration: float
    url: str
    tags: list[str]
    key_tag: str | None
    map_tag: str | None


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, ensure_ascii=False), flush=True)


def parse_date(value: str) -> datetime:
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    if len(normalized) > 5 and normalized[-5] in "+-" and normalized[-3] != ":":
        normalized = normalized[:-2] + ":" + normalized[-2:]
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise DVRCutError("Les heures doivent contenir un fuseau horaire.")
    return parsed


def iso(value: datetime) -> str:
    return value.isoformat(timespec="milliseconds")


def validated_https_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise DVRCutError("Le manifeste DVR contient une URL non sécurisée ou invalide.")
    return value


def absolute_url(base_url: str, value: str) -> str:
    return validated_https_url(urljoin(base_url, value))


def absolute_tag_uri(base_url: str, tag: str) -> str:
    def replace(match: re.Match[str]) -> str:
        return f'URI="{absolute_url(base_url, match.group(1))}"'

    return re.sub(r'URI="([^"]+)"', replace, tag)


def fetch_lines(url: str) -> tuple[list[str], str]:
    validated_https_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            final_url = response.geturl()
            validated_https_url(final_url)
            body = response.read().decode("utf-8-sig")
    except Exception as error:
        raise DVRCutError(f"Impossible de lire la playlist DVR : {error}") from error

    lines = [line.strip() for line in body.splitlines() if line.strip()]
    if not lines or lines[0] != "#EXTM3U":
        raise DVRCutError("La réponse reçue n'est pas une playlist HLS.")
    if any(line.startswith("#EXT-X-STREAM-INF:") for line in lines):
        raise DVRCutError("yt-dlp a renvoyé une playlist maître au lieu d'une qualité vidéo.")
    return lines, final_url


def parse_segments(url: str) -> tuple[list[Segment], bool, float]:
    lines, final_url = fetch_lines(url)
    base_url = final_url.rsplit("/", 1)[0] + "/"
    segments: list[Segment] = []
    pending_duration: float | None = None
    pending_time: datetime | None = None
    inferred_time: datetime | None = None
    pending_tags: list[str] = []
    active_key: str | None = None
    active_map: str | None = None
    target_duration = 0.0
    next_sequence = 0

    for line in lines:
        if line.startswith("#EXT-X-PROGRAM-DATE-TIME:"):
            pending_time = parse_date(line.split(":", 1)[1])
        elif line.startswith("#EXTINF:"):
            raw_duration = line.split(":", 1)[1].split(",", 1)[0]
            try:
                pending_duration = float(raw_duration)
            except ValueError as error:
                raise DVRCutError(f"Durée HLS invalide : {raw_duration}") from error
        elif line.startswith("#EXT-X-TARGETDURATION:"):
            try:
                target_duration = float(line.split(":", 1)[1])
            except ValueError:
                pass
        elif line.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            try:
                next_sequence = int(line.split(":", 1)[1])
            except ValueError as error:
                raise DVRCutError("Numéro de séquence HLS invalide.") from error
        elif line.startswith("#EXT-X-KEY:"):
            active_key = absolute_tag_uri(base_url, line)
        elif line.startswith("#EXT-X-MAP:"):
            active_map = absolute_tag_uri(base_url, line)
        elif line == "#EXT-X-DISCONTINUITY" or line.startswith(
            ("#EXT-X-BYTERANGE:", "#EXT-X-GAP")
        ):
            pending_tags.append(line)
        elif line.startswith("#"):
            continue
        else:
            if pending_duration is None:
                continue
            start = pending_time or inferred_time
            if start is None:
                raise DVRCutError(
                    "Cette playlist n'expose aucune heure réelle (PROGRAM-DATE-TIME)."
                )
            end = start + timedelta(seconds=pending_duration)
            segments.append(
                Segment(
                    sequence=next_sequence,
                    start=start,
                    end=end,
                    duration=pending_duration,
                    url=absolute_url(base_url, line),
                    tags=pending_tags,
                    key_tag=active_key,
                    map_tag=active_map,
                )
            )
            inferred_time = end
            next_sequence += 1
            pending_duration = None
            pending_time = None
            pending_tags = []

    if not segments:
        raise DVRCutError("Aucun segment horodaté n'est disponible dans ce DVR.")

    has_end_list = any(line == "#EXT-X-ENDLIST" for line in lines)
    if target_duration <= 0:
        target_duration = max(segment.duration for segment in segments)
    return segments, has_end_list, target_duration


def range_payload(url: str) -> dict[str, object]:
    segments, has_end_list, target_duration = parse_segments(url)
    start = segments[0].start
    end = segments[-1].end
    duration = max(0.0, (end - start).total_seconds())
    return {
        "start": iso(start),
        "end": iso(end),
        "duration": duration,
        "segmentCount": len(segments),
        "targetDuration": target_duration,
        "isDVR": not has_end_list and duration >= MINIMUM_DVR_SECONDS,
    }


def inspect_command(url: str) -> None:
    emit("range", **range_payload(url))


def write_local_playlist(
    path: Path,
    selected: list[Segment],
    target_duration: float,
) -> None:
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:7",
        f"#EXT-X-TARGETDURATION:{max(1, math.ceil(target_duration))}",
        f"#EXT-X-MEDIA-SEQUENCE:{selected[0].sequence}",
    ]
    previous_key: str | None = None
    previous_map: str | None = None
    for segment in selected:
        if segment.key_tag and segment.key_tag != previous_key:
            lines.append(segment.key_tag)
            previous_key = segment.key_tag
        if segment.map_tag and segment.map_tag != previous_map:
            lines.append(segment.map_tag)
            previous_map = segment.map_tag
        lines.extend(segment.tags)
        lines.append(f"#EXT-X-PROGRAM-DATE-TIME:{iso(segment.start)}")
        lines.append(f"#EXTINF:{segment.duration:.6f},")
        lines.append(segment.url)
    lines.append("#EXT-X-ENDLIST")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_ffmpeg_time(value: str) -> float | None:
    parts = value.split(":")
    if len(parts) != 3:
        return None
    try:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    except ValueError:
        return None


def cut_command(url: str, start_value: str, end_value: str, output_value: str) -> None:
    output = Path(output_value).expanduser()
    if not output.is_absolute() or output.suffix.lower() != ".mp4":
        raise DVRCutError("La destination doit être un chemin MP4 absolu.")
    if output.exists():
        raise DVRCutError("Un fichier existe déjà à cette destination.")
    output.parent.mkdir(parents=True, exist_ok=True)

    segments, _, target_duration = parse_segments(url)
    available_start = segments[0].start
    available_end = segments[-1].end
    requested_start = (
        available_start if start_value == "dvr-start" else parse_date(start_value)
    )
    requested_end = available_end if end_value == "dvr-end" else parse_date(end_value)
    if requested_end <= requested_start:
        raise DVRCutError("L'heure de fin doit être après l'heure de début.")
    tolerance = max(target_duration * 2, 6.0)
    if requested_start < available_start:
        expired_by = (available_start - requested_start).total_seconds()
        if expired_by > tolerance:
            raise DVRCutError("Le début demandé a déjà quitté la fenêtre DVR.")
        requested_start = available_start
    if requested_end > available_end:
        ahead_by = (requested_end - available_end).total_seconds()
        if ahead_by > tolerance:
            raise DVRCutError("La fin demandée n'est pas encore disponible dans le DVR.")
        requested_end = available_end

    selected = [
        segment
        for segment in segments
        if segment.end > requested_start and segment.start < requested_end
    ]
    if not selected:
        raise DVRCutError("Aucun segment trouvé dans cette plage.")

    requested_duration = (requested_end - requested_start).total_seconds()
    source_offset = max(0.0, (requested_start - selected[0].start).total_seconds())
    emit(
        "selection",
        start=iso(requested_start),
        end=iso(requested_end),
        duration=requested_duration,
        segmentCount=len(selected),
    )

    try:
        reservation = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(reservation)
    except FileExistsError as error:
        raise DVRCutError("Un fichier existe déjà à cette destination.") from error
    reserved_output = True

    def cleanup_reservation() -> None:
        if reserved_output:
            try:
                if output.exists() and output.stat().st_size == 0:
                    output.unlink()
            except OSError:
                pass

    atexit.register(cleanup_reservation)

    partial = output.with_name(f".{output.stem}.{os.getpid()}.partial{output.suffix}")
    child: subprocess.Popen[str] | None = None
    cancelled = False
    signal_count = 0

    def stop_child(_signum: int, _frame: object) -> None:
        nonlocal cancelled, signal_count
        cancelled = True
        signal_count += 1
        if child is not None and child.poll() is None:
            if signal_count == 1:
                child.send_signal(signal.SIGINT)
            else:
                child.kill()

    signal.signal(signal.SIGINT, stop_child)
    signal.signal(signal.SIGTERM, stop_child)

    with tempfile.TemporaryDirectory(prefix="sol-dvr-") as temporary_directory:
        playlist = Path(temporary_directory) / "cut.m3u8"
        write_local_playlist(playlist, selected, target_duration)
        command = [
            "ffmpeg",
            "-y",
            "-nostdin",
            "-loglevel",
            "error",
            "-protocol_whitelist",
            "file,http,https,tcp,tls,crypto",
            "-allowed_extensions",
            "ALL",
            "-i",
            str(playlist),
            "-ss",
            f"{source_offset:.6f}",
            "-t",
            f"{requested_duration:.6f}",
            "-map",
            "0:v:0",
            "-map",
            "0:a:0",
            "-c",
            "copy",
            "-movflags",
            "+faststart",
            "-progress",
            "pipe:1",
            "-nostats",
            str(partial),
        ]
        emit("recording", progress=0.0, elapsed=0.0, duration=requested_duration)
        child = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        if cancelled and child.poll() is None:
            child.send_signal(signal.SIGINT)
        elapsed = 0.0
        ffmpeg_error = ""
        disk_error = ""
        assert child.stdout is not None
        for raw_line in child.stdout:
            key, separator, value = raw_line.strip().partition("=")
            if not separator:
                if raw_line.strip():
                    ffmpeg_error = raw_line.strip()
                continue
            if key in ("out_time_us", "out_time_ms"):
                try:
                    elapsed = max(elapsed, float(value) / 1_000_000)
                except ValueError:
                    pass
            elif key == "out_time":
                parsed_time = parse_ffmpeg_time(value)
                if parsed_time is not None:
                    elapsed = max(elapsed, parsed_time)
            elif key == "progress":
                emit(
                    "progress",
                    progress=min(1.0, elapsed / requested_duration),
                    elapsed=elapsed,
                    duration=requested_duration,
                )
                if value != "end" and shutil.disk_usage(output.parent).free < MINIMUM_FREE_BYTES:
                    disk_error = "Espace disque devenu insuffisant pendant l'enregistrement."
                    if child.poll() is None:
                        child.send_signal(signal.SIGINT)
        return_code = child.wait()

    if cancelled:
        partial.unlink(missing_ok=True)
        emit("cancelled")
        raise SystemExit(130)
    if disk_error:
        partial.unlink(missing_ok=True)
        raise DVRCutError(disk_error)
    if return_code != 0:
        partial.unlink(missing_ok=True)
        message = ffmpeg_error or "FFmpeg a échoué."
        raise DVRCutError(message)

    emit("finalizing", progress=1.0, elapsed=requested_duration, duration=requested_duration)
    os.replace(partial, output)
    reserved_output = False
    emit("completed", path=str(output), bytes=output.stat().st_size)


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect or cut a Dailymotion HLS DVR")
    subparsers = parser.add_subparsers(dest="command", required=True)
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("url")
    cut_parser = subparsers.add_parser("cut")
    cut_parser.add_argument("url")
    cut_parser.add_argument("start")
    cut_parser.add_argument("end")
    cut_parser.add_argument("output")
    arguments = parser.parse_args()

    try:
        if arguments.command == "inspect":
            inspect_command(arguments.url)
        else:
            cut_command(arguments.url, arguments.start, arguments.end, arguments.output)
    except DVRCutError as error:
        emit("error", message=str(error))
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
