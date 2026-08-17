from __future__ import annotations

import fcntl
import os
import re
import shutil
import subprocess
import sys
import time
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path


FD = "@FD@"
CACHE_TTL_SECONDS = 15 * 60
COMMON_EXCLUDES = (
    ".git",
    ".cache",
    ".direnv",
    "node_modules",
    "target",
    "__pycache__",
    ".local/share/Trash",
)
SKIPPED_COMPONENTS = {".git", ".cache", ".direnv", "node_modules", "target", "__pycache__"}


def home() -> Path:
    return Path.home().resolve()


def cache_directory() -> Path:
    base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return base / "open-file-picker"


def cache_path() -> Path:
    return cache_directory() / "home-visible.nul"


def priority_directories() -> tuple[Path, ...]:
    root = home()
    return tuple(
        root / name
        for name in (
            "Downloads",
            "Documents",
            "code",
            "Projects",
            "pictures",
            "Pictures",
            "videos",
            "Videos",
            "music",
            "Music",
        )
    )


def fd_paths(
    root: Path,
    *,
    hidden: bool = False,
    no_ignore: bool = False,
    exclude_common: bool = True,
    pattern: str = ".",
    full_path: bool = False,
) -> Iterator[bytes]:
    if not root.exists():
        return

    command = [
        FD,
        "--absolute-path",
        "--color",
        "never",
        "--print0",
        "--type",
        "directory",
        "--type",
        "file",
        "--type",
        "symlink",
    ]
    if hidden:
        command.append("--hidden")
    if no_ignore:
        command.append("--no-ignore")
    if full_path:
        command.append("--full-path")
    if exclude_common:
        for excluded in COMMON_EXCLUDES:
            command.extend(("--exclude", excluded))
    command.extend((pattern, os.fspath(root)))

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    assert process.stdout is not None
    pending = b""
    while chunk := process.stdout.read(1024 * 256):
        fields = (pending + chunk).split(b"\0")
        pending = fields.pop()
        yield from (field for field in fields if field)
    if pending:
        yield pending
    process.wait()


def write_paths(paths: Iterator[bytes]) -> None:
    output = sys.stdout.buffer
    for path in paths:
        output.write(path)
        output.write(b"\0")


def copy_cache(path: Path) -> None:
    with path.open("rb") as source:
        shutil.copyfileobj(source, sys.stdout.buffer, length=1024 * 1024)


def refresh_cache() -> None:
    directory = cache_directory()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_path = directory / "index.lock"

    with lock_path.open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        visible_temp = directory / f"home-visible.{os.getpid()}.tmp"
        try:
            priority_roots = tuple(root.resolve() for root in priority_directories() if root.is_dir())
            priority_prefixes = tuple(os.fsencode(root) + b"/" for root in priority_roots)
            with visible_temp.open("wb") as output:
                for root in priority_roots:
                    output.write(os.fsencode(root) + b"/\0")
                    for path in fd_paths(root):
                        output.write(path + b"\0")
                for path in fd_paths(home()):
                    normalized = path.rstrip(b"/") + b"/"
                    if any(normalized.startswith(prefix) for prefix in priority_prefixes):
                        continue
                    output.write(path + b"\0")

            os.replace(visible_temp, cache_path())
            # Remove the abandoned global fallback cache from the Bash-era
            # implementation. Query-directed fallback scans are far smaller.
            (directory / "home-fallback.nul").unlink(missing_ok=True)
        finally:
            visible_temp.unlink(missing_ok=True)


def cache_is_stale() -> bool:
    path = cache_path()
    if not path.is_file():
        return True
    return time.time() - path.stat().st_mtime >= CACHE_TTL_SECONDS


def ensure_cache() -> None:
    if not cache_path().is_file():
        refresh_cache()


@dataclass(frozen=True)
class Scope:
    path: Path | None
    exact: bool
    absolute_query: bool


def resolve_scope(query: str) -> Scope:
    if query.startswith("~/"):
        query = query[2:]

    if query.startswith("/"):
        candidate = Path("/") if query == "/" else Path(query).parent
        if candidate.is_dir():
            return Scope(candidate.resolve(), True, True)
        return Scope(None, False, True)

    if "/" not in query:
        return Scope(None, False, False)

    candidate = home() / query.rsplit("/", 1)[0]
    if candidate.is_dir():
        return Scope(candidate.resolve(), True, False)
    return Scope(None, False, False)


def inside_skipped_tree(path: Path) -> bool:
    parts = path.parts
    if any(part in SKIPPED_COMPONENTS for part in parts):
        return True
    return any(parts[index : index + 3] == (".local", "share", "Trash") for index in range(len(parts) - 2))


def immediate_hidden_paths(root: Path) -> Iterator[bytes]:
    try:
        with os.scandir(root) as entries:
            for entry in entries:
                if entry.name.startswith("."):
                    yield os.fsencode(entry.path)
    except OSError:
        return


def root_paths(*, fallback: bool, pattern: str = ".") -> Iterator[bytes]:
    root = Path("/")
    current_home = home()
    useful_roots = (
        current_home,
        Path("/etc"),
        Path("/opt"),
        Path("/srv"),
        Path("/var"),
        Path("/usr"),
        Path("/boot"),
        Path("/mnt"),
        Path("/media"),
        Path("/tmp"),
        Path("/root"),
        Path("/nix/var"),
    )
    for scan_root in useful_roots:
        yield from fd_paths(
            scan_root,
            hidden=fallback,
            no_ignore=fallback,
            pattern=pattern,
            full_path=fallback,
        )

    local_homes = Path("/home")
    try:
        for entry in local_homes.iterdir():
            if entry != current_home:
                yield from fd_paths(
                    entry,
                    hidden=fallback,
                    no_ignore=fallback,
                    pattern=pattern,
                    full_path=fallback,
                )
    except OSError:
        pass

    excluded_top_level = {
        "boot",
        "dev",
        "etc",
        "home",
        "media",
        "mnt",
        "nix",
        "opt",
        "proc",
        "root",
        "run",
        "srv",
        "sys",
        "tmp",
        "usr",
        "var",
    }
    try:
        for entry in root.iterdir():
            if entry.name in excluded_top_level:
                continue
            if entry.is_dir():
                yield from fd_paths(
                    entry,
                    hidden=fallback,
                    no_ignore=fallback,
                    pattern=pattern,
                    full_path=fallback,
                )
            else:
                yield os.fsencode(entry)
    except OSError:
        pass


def candidates(mode: str, query: str) -> None:
    fallback = mode == "fallback"
    scope = resolve_scope(query)
    final_component = query.rsplit("/", 1)[-1]
    fallback_pattern = ".*".join(re.escape(character) for character in query.removeprefix("~/")) or "."

    if scope.exact and scope.path is not None:
        if scope.path == Path("/"):
            write_paths(root_paths(fallback=fallback, pattern=fallback_pattern))
        elif inside_skipped_tree(scope.path):
            write_paths(fd_paths(scope.path, hidden=True, no_ignore=True, exclude_common=False))
        elif fallback:
            write_paths(
                fd_paths(
                    scope.path,
                    hidden=True,
                    no_ignore=True,
                    pattern=fallback_pattern,
                    full_path=True,
                )
            )
        elif final_component.startswith("."):
            write_paths(fd_paths(scope.path))
            write_paths(immediate_hidden_paths(scope.path))
        else:
            write_paths(fd_paths(scope.path))
        return

    if scope.absolute_query:
        write_paths(root_paths(fallback=fallback, pattern=fallback_pattern))
    elif fallback:
        write_paths(
            fd_paths(
                home(),
                hidden=True,
                no_ignore=True,
                pattern=fallback_pattern,
                full_path=True,
            )
        )
    else:
        ensure_cache()
        copy_cache(cache_path())


def prompt(query: str) -> None:
    scope = resolve_scope(query)
    if scope.exact and scope.path is not None:
        try:
            display = "~" if scope.path == home() else f"~/{scope.path.relative_to(home())}"
        except ValueError:
            display = os.fspath(scope.path)
        print(f"{display} › ", end="")
    elif scope.absolute_query:
        print("/ › ", end="")
    else:
        print("Home › ", end="")


def complete(path_string: str) -> None:
    path = Path(path_string)
    try:
        completed = "~" if path.resolve() == home() else os.fspath(path.resolve().relative_to(home()))
    except (OSError, ValueError):
        completed = os.fspath(path)
    if path.is_dir() and not completed.endswith("/"):
        completed += "/"
    print(completed, end="")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: open-file-search MODE [QUERY]", file=sys.stderr)
        return 2

    mode = sys.argv[1]
    if mode == "default":
        ensure_cache()
        copy_cache(cache_path())
    elif mode == "refresh":
        refresh_cache()
    elif mode == "refresh-if-stale":
        if cache_is_stale():
            refresh_cache()
    elif mode in {"normal", "fallback"}:
        candidates(mode, sys.argv[2] if len(sys.argv) > 2 else "")
    elif mode == "prompt":
        prompt(sys.argv[2] if len(sys.argv) > 2 else "")
    elif mode == "complete":
        complete(sys.argv[2])
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
