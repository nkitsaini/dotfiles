import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import capture


class CaptureRenameTests(unittest.TestCase):
    def make_session(
        self,
        root: Path,
        name: str,
        contents: str,
        *,
        reviewed: bool = False,
    ) -> Path:
        parent = root / capture.REVIEWED_DIRNAME if reviewed else root
        parent.mkdir(parents=True, exist_ok=True)
        session = parent / name
        session.mkdir()
        (session / "main.md").write_text(contents)
        return session

    def test_capture_renames_from_heading_after_zed_exits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)

            def write_capture(command: list[str], **_: object) -> None:
                Path(command[-1]).write_text("# Project ideas\n")

            with (
                mock.patch.object(
                    capture,
                    "zed_command",
                    side_effect=lambda main_file: ["zed", str(main_file)],
                ),
                mock.patch.object(
                    capture.subprocess, "run", side_effect=write_capture
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                capture.capture(root)

            self.assertEqual(
                [path.name for path in root.iterdir()],
                [f"{capture.datetime.datetime.now():%Y_%m_%d}__project-ideas"],
            )

    def test_review_moves_capture_into_reviewed_folder(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.make_session(
                root, "2026_08_12__capture-1234abcd", "# Release plan\n"
            )

            with (
                mock.patch.object(capture, "zed_command", return_value=["zed"]),
                mock.patch.object(capture.subprocess, "run"),
                mock.patch("builtins.input", return_value="y"),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                capture.review(root)

            self.assertTrue(
                (root / "reviewed" / "2026_08_12__release-plan").is_dir()
            )
            self.assertFalse(
                (root / "2026_08_12__capture-1234abcd").exists()
            )

    def test_bulk_rename_filters_and_warns_for_missing_top_heading(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.make_session(root, "2026_08_10__abcde", "# Old format\n")
            self.make_session(
                root,
                "2026_08_11__capture-1234abcd",
                "# Reviewed note\n",
                reviewed=True,
            )
            missing_heading = self.make_session(
                root,
                "2026_08_12__capture-deadbeef",
                "Intro text\n# Later heading\n",
            )
            self.make_session(
                root, "2026_08_12__already-named", "# Already named\n"
            )
            stderr = io.StringIO()

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                capture.rename_captures(root, reviewed=False)

            self.assertTrue((root / "2026_08_10__old-format").is_dir())
            self.assertTrue(missing_heading.is_dir())
            self.assertTrue(
                (
                    root / "reviewed" / "2026_08_11__capture-1234abcd"
                ).is_dir()
            )
            self.assertIn(missing_heading.name, stderr.getvalue())

    def test_rename_preserves_reviewed_dir_and_avoids_collisions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            session = self.make_session(
                root,
                "2026_08_12__capture-1234abcd",
                "\n# Same title\n",
                reviewed=True,
            )
            self.make_session(
                root,
                "2026_08_12__same-title",
                "# Existing\n",
                reviewed=True,
            )

            with contextlib.redirect_stdout(io.StringIO()):
                renamed = capture.rename_from_heading(session)

            self.assertEqual(renamed.name, "2026_08_12__same-title-2")
            self.assertEqual(renamed.parent.name, "reviewed")
            self.assertTrue(renamed.is_dir())

    def test_rename_warns_on_heading_folder_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            mismatched = self.make_session(
                root, "2026_08_12__old-name", "# New Name\n"
            )
            stderr = io.StringIO()

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                capture.rename_captures(root)

            self.assertTrue(mismatched.is_dir())
            err = stderr.getvalue()
            self.assertIn("differs from folder name", err)
            self.assertIn("capture rename --sync-headings", err)

    def test_sync_headings_renames_mismatched_folders(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.make_session(
                root, "2026_08_12__old-name", "# New Name\n"
            )
            stderr = io.StringIO()

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                capture.rename_captures(root, sync_headings=True)

            self.assertTrue((root / "2026_08_12__new-name").is_dir())
            self.assertFalse((root / "2026_08_12__old-name").exists())
            self.assertNotIn("differs from folder name", stderr.getvalue())

    def test_sync_headings_preserves_reviewed_filter_in_hint(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.make_session(
                root, "2026_08_12__old-name", "# New Name\n"
            )
            stderr = io.StringIO()

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                capture.rename_captures(root, reviewed=False)

            self.assertIn(
                "capture rename --sync-headings --unreviewed",
                stderr.getvalue(),
            )

    def test_write_headings_inserts_and_replaces_without_renaming(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            missing = self.make_session(
                root,
                "2026_07_06__kalpit-call",
                "- notes\n",
                reviewed=True,
            )
            mismatched = self.make_session(
                root,
                "2026_06_30__matific_issue",
                "# Wrong\nbody\n",
                reviewed=True,
            )
            uuid_capture = self.make_session(
                root, "2026_08_12__capture-deadbeef", "scratch\n"
            )

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                capture.rename_captures(root, write_headings=True)

            self.assertEqual(
                (missing / "main.md").read_text(),
                "# Kalpit Call\n\n- notes\n",
            )
            self.assertEqual(
                (mismatched / "main.md").read_text(),
                "# Matific Issue\nbody\n",
            )
            self.assertEqual(
                (uuid_capture / "main.md").read_text(), "scratch\n"
            )
            self.assertTrue(missing.is_dir())
            self.assertTrue(mismatched.is_dir())

    def test_missing_heading_hint_suggests_write_headings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.make_session(
                root,
                "2026_07_06__kalpit-call",
                "- notes\n",
                reviewed=True,
            )
            stderr = io.StringIO()

            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                capture.rename_captures(root)

            self.assertIn(
                "capture rename --write-headings", stderr.getvalue()
            )

    def test_migrate_reviewed_moves_legacy_suffix_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            legacy = root / "2026_07_06__kalpit-call.reviewed"
            legacy.mkdir()
            (legacy / "main.md").write_text("# Kalpit Call\n")
            already = root / "reviewed"
            already.mkdir()
            nested_legacy = already / "2026_07_07__mcp-demo.reviewed"
            nested_legacy.mkdir()
            (nested_legacy / "main.md").write_text("# Mcp Demo\n")

            with contextlib.redirect_stdout(io.StringIO()):
                capture.migrate_reviewed_suffix(root)

            self.assertTrue(
                (root / "reviewed" / "2026_07_06__kalpit-call").is_dir()
            )
            self.assertTrue(
                (root / "reviewed" / "2026_07_07__mcp-demo").is_dir()
            )
            self.assertFalse(legacy.exists())
            self.assertFalse(nested_legacy.exists())


if __name__ == "__main__":
    unittest.main()
