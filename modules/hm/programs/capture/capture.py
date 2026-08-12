#!/usr/bin/env python3

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import uuid
from pathlib import Path


DATE_FORMAT = "%Y_%m_%d"
REVIEWED_DIRNAME = "reviewed"
LEGACY_REVIEWED_SUFFIX = ".reviewed"
GENERATED_SUFFIX_RE = re.compile(r"(?:capture-[0-9a-f]{8}|[a-z]{5})")
SESSION_NAME_RE = re.compile(r"(?P<date>\d{4}_\d{2}_\d{2})__(?P<suffix>.+)$")
TOP_LEVEL_HEADING_RE = re.compile(r"^#\s+(.+?)\s*$")

# ANSI styles used when stdout/stderr is a TTY (respects NO_COLOR / FORCE_COLOR).
_STYLE = {
    "bold": "1",
    "dim": "2",
    "red": "31",
    "green": "32",
    "yellow": "33",
    "cyan": "36",
}


def use_color(stream: object) -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    isatty = getattr(stream, "isatty", None)
    return bool(isatty and isatty())


def paint(text: str, *styles: str, stream: object = sys.stdout) -> str:
    if not styles or not use_color(stream):
        return text
    codes = ";".join(_STYLE[style] for style in styles)
    return f"\033[{codes}m{text}\033[0m"


def reviewed_path(sessions_path: Path) -> Path:
    return sessions_path / REVIEWED_DIRNAME


def is_reviewed_session(session_path: Path) -> bool:
    return session_path.parent.name == REVIEWED_DIRNAME


def is_empty_session(session_dir: Path) -> bool:
    """A session is empty when it has no files, or all its files are empty."""
    files = [path for path in session_dir.rglob("*") if path.is_file()]
    return all(not path.read_bytes().strip() for path in files)


def session_name(suffix: str | None = None) -> str:
    date = datetime.datetime.now().strftime(DATE_FORMAT)
    if suffix:
        return f"{date}__{suffix}"
    return f"{date}__capture-{uuid.uuid4().hex[:8]}"


def unique_session_path(sessions_path: Path, suffix: str | None = None) -> Path:
    for _ in range(100):
        candidate = sessions_path / session_name(suffix)
        if not candidate.exists():
            return candidate
        suffix = None
    raise RuntimeError("could not generate a unique session name")


def unique_child_path(parent: Path, name: str, *, current: Path | None = None) -> Path:
    candidate = parent / name
    if not candidate.exists() or candidate == current:
        return candidate
    stem = name
    counter = 2
    while True:
        candidate = parent / f"{stem}-{counter}"
        if not candidate.exists() or candidate == current:
            return candidate
        counter += 1


def session_parts(session_path: Path) -> tuple[str, str, bool] | None:
    match = SESSION_NAME_RE.fullmatch(session_path.name)
    if match is None:
        return None
    return match["date"], match["suffix"], is_reviewed_session(session_path)


def is_generated_suffix(suffix: str) -> bool:
    return GENERATED_SUFFIX_RE.fullmatch(suffix) is not None


def is_uuid_capture_suffix(suffix: str) -> bool:
    return re.fullmatch(r"capture-[0-9a-f]{8}", suffix) is not None


def top_level_heading(main_file: Path) -> str | None:
    if not main_file.exists():
        return None
    for line in main_file.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        match = TOP_LEVEL_HEADING_RE.fullmatch(line)
        return match[1].strip() if match else None
    return None


def slugify(title: str) -> str:
    normalized = unicodedata.normalize("NFKD", title)
    ascii_title = normalized.encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_title.lower()).strip("-")


def title_from_suffix(suffix: str) -> str:
    words = [word for word in re.split(r"[_-]+", suffix.strip("_-")) if word]
    return " ".join(word.capitalize() for word in words)


def unique_titled_path(session_path: Path, date: str, slug: str) -> Path:
    return unique_child_path(
        session_path.parent, f"{date}__{slug}", current=session_path
    )


def iter_session_dirs(sessions_path: Path) -> list[Path]:
    if not sessions_path.exists():
        return []
    sessions: list[Path] = []
    for path in sorted(sessions_path.iterdir()):
        if not path.is_dir():
            continue
        if path.name == REVIEWED_DIRNAME:
            sessions.extend(
                sorted(child for child in path.iterdir() if child.is_dir())
            )
        else:
            sessions.append(path)
    return sessions


def print_renamed(old_label: str, new_label: str) -> None:
    print(
        f"{paint('Renamed', 'green', 'bold')}: "
        f"{paint(old_label, 'dim')} -> {paint(new_label, 'green')}",
        flush=True,
    )


def print_warning(message: str) -> None:
    print(
        f"{paint('warning', 'yellow', 'bold')}: {message}",
        file=sys.stderr,
        flush=True,
    )


def print_heading_written(session_name: str, title: str) -> None:
    print(
        f"{paint('Heading', 'cyan', 'bold')}: "
        f"{paint(session_name, 'dim')} -> "
        f"{paint(f'# {title}', 'cyan')}",
        flush=True,
    )


def session_label(session_path: Path) -> str:
    if is_reviewed_session(session_path):
        return f"{REVIEWED_DIRNAME}/{session_path.name}"
    return session_path.name


def write_heading_from_folder(session_path: Path) -> bool:
    """Insert or replace the top L1 heading from the folder suffix.

    Does not rename the folder. Skips uuid-style ``capture-<hex>`` names.
    Returns True when main.md was changed.
    """
    parts = session_parts(session_path)
    if parts is None:
        return False
    _date, suffix, _reviewed = parts
    if is_uuid_capture_suffix(suffix):
        return False

    title = title_from_suffix(suffix)
    if not title:
        return False
    heading_line = f"# {title}"

    main_file = session_path / "main.md"
    text = main_file.read_text(errors="replace") if main_file.exists() else ""
    lines = text.splitlines()
    first_idx = next(
        (index for index, line in enumerate(lines) if line.strip()), None
    )

    if first_idx is None:
        new_text = heading_line + "\n"
    elif TOP_LEVEL_HEADING_RE.fullmatch(lines[first_idx].strip()):
        if lines[first_idx].strip() == heading_line:
            return False
        lines[first_idx] = heading_line
        new_text = "\n".join(lines)
        if text.endswith("\n"):
            new_text += "\n"
    else:
        body = "\n".join(lines)
        new_text = heading_line + "\n\n" + body
        if text.endswith("\n") and not new_text.endswith("\n"):
            new_text += "\n"

    main_file.parent.mkdir(parents=True, exist_ok=True)
    main_file.write_text(new_text)
    print_heading_written(session_label(session_path), title)
    return True


def rename_from_heading(session_path: Path, *, warn: bool = False) -> Path:
    parts = session_parts(session_path)
    if parts is None:
        return session_path
    date, suffix, _reviewed = parts
    if not is_generated_suffix(suffix):
        return session_path

    heading = top_level_heading(session_path / "main.md")
    slug = slugify(heading) if heading else ""
    if not slug:
        if warn:
            print_warning(
                f"{paint(session_label(session_path), 'bold', stream=sys.stderr)}: "
                "main.md does not start with a level 1 heading"
            )
        return session_path

    renamed_path = unique_titled_path(session_path, date, slug)
    if renamed_path != session_path:
        session_path.rename(renamed_path)
        print_renamed(
            session_label(session_path), session_label(renamed_path)
        )
    return renamed_path


def rename_filter_flags(*, reviewed: bool | None) -> str:
    if reviewed is True:
        return " --reviewed"
    if reviewed is False:
        return " --unreviewed"
    return ""


def sync_session_to_heading(
    session_path: Path, *, apply: bool, warn_missing: bool
) -> tuple[Path, str | None]:
    """Return (path, warning_kind). warning_kind is 'missing' or 'mismatch'."""
    parts = session_parts(session_path)
    if parts is None:
        return session_path, None
    date, _suffix, _reviewed = parts

    heading = top_level_heading(session_path / "main.md")
    slug = slugify(heading) if heading else ""
    if not slug:
        if warn_missing:
            print_warning(
                f"{paint(session_label(session_path), 'bold', stream=sys.stderr)}: "
                "main.md does not start with a level 1 heading"
            )
            return session_path, "missing"
        return session_path, None

    renamed_path = unique_titled_path(session_path, date, slug)
    if renamed_path == session_path:
        return session_path, None

    if apply:
        session_path.rename(renamed_path)
        print_renamed(
            session_label(session_path), session_label(renamed_path)
        )
        return renamed_path, None

    print_warning(
        f"{paint(session_label(session_path), 'bold', stream=sys.stderr)}: "
        f"heading {paint(heading, 'cyan', stream=sys.stderr)} differs from "
        f"folder name (would become "
        f"{paint(session_label(renamed_path), 'green', stream=sys.stderr)})"
    )
    return session_path, "mismatch"


def mark_reviewed(session_path: Path, sessions_path: Path) -> Path:
    destination_dir = reviewed_path(sessions_path)
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = unique_child_path(
        destination_dir, session_path.name, current=session_path
    )
    session_path.rename(destination)
    return destination


def zed_command(main_file: Path) -> list[str]:
    zed = shutil.which("zed")
    if zed is None:
        raise RuntimeError("zed is not available on PATH")
    # The session directory is passed as the project root so adjacent files can
    # be created from within the window. The project panel stays hidden because
    # of project_panel.starts_open = false in the Zed settings.
    return [zed, "--new", "--wait", str(main_file.parent), str(main_file)]


def capture(sessions_path: Path, suffix: str | None = None) -> None:
    session_path = unique_session_path(sessions_path, suffix)
    session_path.mkdir(parents=True)
    main_file = session_path / "main.md"
    main_file.touch()

    try:
        subprocess.run(zed_command(main_file), check=True)
    except Exception:
        if is_empty_session(session_path):
            shutil.rmtree(session_path)
        raise

    if is_empty_session(session_path):
        shutil.rmtree(session_path)
    else:
        rename_from_heading(session_path)


def unreviewed_sessions(sessions_path: Path) -> list[Path]:
    if not sessions_path.exists():
        return []
    return [
        path
        for path in sorted(sessions_path.iterdir())
        if path.is_dir()
        and path.name != REVIEWED_DIRNAME
        and not is_empty_session(path)
    ]


def review(sessions_path: Path) -> None:
    sessions = unreviewed_sessions(sessions_path)
    if not sessions:
        print("No unreviewed captures.")
        return

    print(f"{paint(str(len(sessions)), 'bold')} unreviewed capture(s).")
    for index, session_path in enumerate(sessions, start=1):
        main_file = session_path / "main.md"
        main_file.touch(exist_ok=True)
        print(
            f"\n[{index}/{len(sessions)}] {paint(session_path.name, 'bold')}"
        )
        subprocess.run(zed_command(main_file), check=True)
        session_path = rename_from_heading(session_path)

        answer = input("Mark reviewed? [Y/n/q] ").strip().lower()
        if answer == "q":
            return
        if answer in ("", "y", "yes"):
            reviewed_session = mark_reviewed(session_path, sessions_path)
            print(
                f"{paint('Marked reviewed', 'green', 'bold')}: "
                f"{paint(session_label(reviewed_session), 'green')}"
            )


def rename_captures(
    sessions_path: Path,
    *,
    reviewed: bool | None = None,
    sync_headings: bool = False,
    write_headings: bool = False,
) -> None:
    if not sessions_path.exists():
        print("No captures.")
        return

    sessions = []
    for path in iter_session_dirs(sessions_path):
        parts = session_parts(path)
        if parts is not None and (
            reviewed is None or parts[2] == reviewed
        ):
            sessions.append(path)
    if not sessions:
        print("No captures matching the naming scheme.")
        return

    headings_written = 0
    if write_headings:
        for session_path in sessions:
            if write_heading_from_folder(session_path):
                headings_written += 1

    renamed = 0
    mismatches = 0
    missing = 0
    for session_path in sessions:
        parts = session_parts(session_path)
        assert parts is not None
        _date, suffix, _reviewed = parts
        apply = sync_headings or is_generated_suffix(suffix)
        new_path, warning = sync_session_to_heading(
            session_path,
            apply=apply,
            warn_missing=not write_headings,
        )
        if warning == "mismatch" and not apply:
            mismatches += 1
        elif warning == "missing" and not is_uuid_capture_suffix(suffix):
            missing += 1
        elif new_path != session_path:
            renamed += 1

    if write_headings:
        print(
            f"{paint('Wrote', 'cyan' if headings_written else 'dim')} "
            f"{paint(str(headings_written), 'bold')} heading(s)."
        )
    print(
        f"{paint('Renamed', 'green' if renamed else 'dim')} "
        f"{paint(str(renamed), 'bold')} of {len(sessions)} capture(s)."
    )
    flags = rename_filter_flags(reviewed=reviewed)
    if missing:
        command = f"capture rename --write-headings{flags}"
        print(
            f"{paint(str(missing), 'yellow', 'bold', stream=sys.stderr)} "
            "capture(s) are missing a top-level heading. "
            f"Add them with: {paint(command, 'cyan', 'bold', stream=sys.stderr)}",
            file=sys.stderr,
        )
    if mismatches:
        command = f"capture rename --sync-headings{flags}"
        print(
            f"{paint(str(mismatches), 'yellow', 'bold', stream=sys.stderr)} "
            "capture(s) have headings that differ from their folder names. "
            f"Update them with: {paint(command, 'cyan', 'bold', stream=sys.stderr)}",
            file=sys.stderr,
        )


def migrate_reviewed_suffix(sessions_path: Path) -> None:
    """Move ``*.reviewed`` session dirs into ``reviewed/`` and strip the suffix."""
    if not sessions_path.exists():
        print("No captures.")
        return

    legacy_sessions: list[Path] = []
    for path in sorted(sessions_path.iterdir()):
        if not path.is_dir():
            continue
        if path.name == REVIEWED_DIRNAME:
            legacy_sessions.extend(
                sorted(
                    child
                    for child in path.iterdir()
                    if child.is_dir()
                    and child.name.endswith(LEGACY_REVIEWED_SUFFIX)
                )
            )
        elif path.name.endswith(LEGACY_REVIEWED_SUFFIX):
            legacy_sessions.append(path)

    if not legacy_sessions:
        print("No legacy .reviewed captures to migrate.")
        return

    destination_dir = reviewed_path(sessions_path)
    destination_dir.mkdir(parents=True, exist_ok=True)
    migrated = 0
    for session_path in legacy_sessions:
        new_name = session_path.name[: -len(LEGACY_REVIEWED_SUFFIX)]
        destination = unique_child_path(
            destination_dir, new_name, current=session_path
        )
        session_path.rename(destination)
        print_renamed(session_label(session_path), session_label(destination))
        migrated += 1

    print(
        f"{paint('Migrated', 'green', 'bold')} "
        f"{paint(str(migrated), 'bold')} capture(s) into "
        f"{paint(f'{REVIEWED_DIRNAME}/', 'green')}."
    )


def prune_empty_sessions(sessions_path: Path) -> None:
    empty_sessions = [
        path
        for path in iter_session_dirs(sessions_path)
        if is_empty_session(path)
    ]
    if not empty_sessions:
        print("No empty sessions.")
        return

    print(
        f"{paint(str(len(empty_sessions)), 'yellow', 'bold')} empty session(s):"
    )
    for session_path in empty_sessions:
        print(f"  {paint(session_label(session_path), 'dim')}")
    if input("Delete them? [y/N] ").strip().lower() not in ("y", "yes"):
        print(paint("Aborted.", "yellow"))
        return

    for session_path in empty_sessions:
        shutil.rmtree(session_path)
    print(paint(f"Deleted {len(empty_sessions)} empty session(s).", "green"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture and review notes.")
    parser.add_argument(
        "--directory",
        default=os.environ.get("CAPTURE_SESSIONS_DIRECTORY"),
        help="sessions directory (or set CAPTURE_SESSIONS_DIRECTORY)",
    )
    subparsers = parser.add_subparsers(dest="command")

    new_parser = subparsers.add_parser("new", help="open a new capture")
    new_parser.add_argument("name", nargs="?", help="optional capture name")
    subparsers.add_parser("review", help="review unreviewed captures")
    rename_parser = subparsers.add_parser(
        "rename", help="rename default-named captures from their headings"
    )
    rename_filter = rename_parser.add_mutually_exclusive_group()
    rename_filter.add_argument(
        "--reviewed", action="store_true", help="only rename reviewed captures"
    )
    rename_filter.add_argument(
        "--unreviewed",
        action="store_true",
        help="only rename unreviewed captures",
    )
    rename_parser.add_argument(
        "--sync-headings",
        action="store_true",
        help="also rename captures whose heading differs from the folder name",
    )
    rename_parser.add_argument(
        "--write-headings",
        action="store_true",
        help=(
            "set each capture's top-level heading from its folder name "
            "(does not rename folders)"
        ),
    )
    subparsers.add_parser(
        "migrate-reviewed",
        help=(
            "move legacy *.reviewed session folders into reviewed/ "
            "and strip the suffix"
        ),
    )
    subparsers.add_parser("prune-empty", help="delete empty captures")

    args = parser.parse_args()
    if args.directory is None:
        parser.error(
            "--directory or CAPTURE_SESSIONS_DIRECTORY must be configured"
        )
    sessions_path = Path(args.directory).expanduser()

    try:
        if args.command in (None, "new"):
            capture(sessions_path, getattr(args, "name", None))
        elif args.command == "review":
            review(sessions_path)
        elif args.command == "rename":
            reviewed = True if args.reviewed else None
            if args.unreviewed:
                reviewed = False
            rename_captures(
                sessions_path,
                reviewed=reviewed,
                sync_headings=args.sync_headings,
                write_headings=args.write_headings,
            )
        elif args.command == "migrate-reviewed":
            migrate_reviewed_suffix(sessions_path)
        elif args.command == "prune-empty":
            prune_empty_sessions(sessions_path)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(
            f"{paint('capture', 'red', 'bold', stream=sys.stderr)}: {error}",
            file=sys.stderr,
        )
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
