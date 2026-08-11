#!/usr/bin/env python3

import argparse
import datetime
import os
import random
import shutil
import string
import subprocess
import sys
from pathlib import Path


DATE_FORMAT = "%Y_%m_%d"
RANDOM_NAME_LENGTH = 5
REVIEWED_SUFFIX = ".reviewed"


def is_empty_session(session_dir: Path) -> bool:
    """A session is empty when it has no files, or all its files are empty."""
    files = [path for path in session_dir.rglob("*") if path.is_file()]
    return all(not path.read_bytes().strip() for path in files)


def session_name(suffix: str | None = None) -> str:
    date = datetime.datetime.now().strftime(DATE_FORMAT)
    if suffix:
        return f"{date}__{suffix}"
    tag = "".join(random.choices(string.ascii_lowercase, k=RANDOM_NAME_LENGTH))
    return f"{date}__{tag}"


def unique_session_path(sessions_path: Path, suffix: str | None = None) -> Path:
    for _ in range(100):
        candidate = sessions_path / session_name(suffix)
        if not candidate.exists():
            return candidate
        suffix = None
    raise RuntimeError("could not generate a unique session name")


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


def unreviewed_sessions(sessions_path: Path) -> list[Path]:
    if not sessions_path.exists():
        return []
    return [
        path
        for path in sorted(sessions_path.iterdir())
        if path.is_dir()
        and not path.name.endswith(REVIEWED_SUFFIX)
        and not is_empty_session(path)
    ]


def review(sessions_path: Path) -> None:
    sessions = unreviewed_sessions(sessions_path)
    if not sessions:
        print("No unreviewed captures.")
        return

    print(f"{len(sessions)} unreviewed capture(s).")
    for index, session_path in enumerate(sessions, start=1):
        main_file = session_path / "main.md"
        main_file.touch(exist_ok=True)
        print(f"\n[{index}/{len(sessions)}] {session_path.name}")
        subprocess.run(zed_command(main_file), check=True)

        answer = input("Mark reviewed? [Y/n/q] ").strip().lower()
        if answer == "q":
            return
        if answer in ("", "y", "yes"):
            reviewed_path = session_path.with_name(
                session_path.name + REVIEWED_SUFFIX
            )
            session_path.rename(reviewed_path)
            print(f"Marked reviewed: {reviewed_path.name}")


def prune_empty_sessions(sessions_path: Path) -> None:
    if not sessions_path.exists():
        print("No empty sessions.")
        return

    empty_sessions = [
        path
        for path in sorted(sessions_path.iterdir())
        if path.is_dir() and is_empty_session(path)
    ]
    if not empty_sessions:
        print("No empty sessions.")
        return

    print(f"{len(empty_sessions)} empty session(s):")
    for session_path in empty_sessions:
        print(f"  {session_path}")
    if input("Delete them? [y/N] ").strip().lower() not in ("y", "yes"):
        print("Aborted.")
        return

    for session_path in empty_sessions:
        shutil.rmtree(session_path)


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
        elif args.command == "prune-empty":
            prune_empty_sessions(sessions_path)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"capture: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
