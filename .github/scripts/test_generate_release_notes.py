import contextlib
import http.client
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import generate_release_notes


class _Response:
    def __init__(self, payload):
        self._payload = json.dumps(payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self):
        return self._payload


class GenerateReleaseNotesSecurityTest(unittest.TestCase):
    @mock.patch.dict(os.environ, {"GEMINI_API_KEY": "test-key"})
    @mock.patch("generate_release_notes.get_recent_commits", return_value=["fix: test"])
    @mock.patch("generate_release_notes.get_release_notes_md", return_value="")
    @mock.patch("generate_release_notes.urllib.request.urlopen")
    def test_main_writes_local_fallback_for_invalid_ai_notes(self, urlopen, *_):
        urlopen.return_value = _Response({
            "candidates": [{"content": {"parts": [{"text": '{"ko": 123, "en": "English"}'}]}}],
        })
        original_dir = os.getcwd()
        with tempfile.TemporaryDirectory(dir=original_dir) as directory:
            try:
                os.chdir(directory)
                with mock.patch("sys.argv", ["generate_release_notes.py", "42"]), contextlib.redirect_stdout(io.StringIO()):
                    generate_release_notes.main()
                changelogs = Path("android/fastlane/metadata/android/ko-KR/changelogs")
                self.assertEqual((changelogs / "42.txt").read_text(encoding="utf-8"), "• 개선 사항: test\n")
                self.assertEqual((changelogs / "default.txt").read_text(encoding="utf-8"), "• 개선 사항: test\n")
            finally:
                os.chdir(original_dir)

    @mock.patch("generate_release_notes.urllib.request.urlopen")
    def test_invalid_localized_notes_use_fallback(self, urlopen):
        for invalid in (123, True, ["bullet"], {"text": "bullet"}, None, "", "  \n"):
            for locale in ("ko", "en"):
                with self.subTest(invalid=invalid, locale=locale):
                    notes = {"ko": "한국어", "en": "English"}
                    notes[locale] = invalid
                    urlopen.return_value = _Response({
                        "candidates": [{"content": {"parts": [{"text": json.dumps(notes)}]}}],
                    })
                    self.assertEqual(
                        generate_release_notes.generate_notes_with_gemini("test-key", [], ""),
                        (None, None),
                    )

    @mock.patch("generate_release_notes.urllib.request.urlopen")
    def test_non_object_notes_use_fallback(self, urlopen):
        urlopen.return_value = _Response({
            "candidates": [{"content": {"parts": [{"text": '["ko", "en"]'}]}}],
        })
        self.assertEqual(
            generate_release_notes.generate_notes_with_gemini("test-key", [], ""),
            (None, None),
        )

    @mock.patch("generate_release_notes.urllib.request.urlopen")
    def test_gemini_key_is_sent_in_header_not_url(self, urlopen):
        urlopen.return_value = _Response({
            "candidates": [{
                "content": {"parts": [{"text": json.dumps({"ko": "한국어", "en": "English"})}]},
            }],
        })
        api_key = "secret-sentinel"

        notes = generate_release_notes.generate_notes_with_gemini(api_key, ["fix: test"], "")

        request = urlopen.call_args.args[0]
        self.assertNotIn(api_key, request.full_url)
        self.assertNotIn("?key=", request.full_url)
        self.assertEqual(request.get_header("X-goog-api-key"), api_key)
        self.assertEqual(notes, ("한국어", "English"))

    @mock.patch("generate_release_notes.urllib.request.urlopen")
    def test_gemini_failure_does_not_log_secret(self, urlopen):
        api_key = "secret-sentinel"
        urlopen.side_effect = http.client.InvalidURL(f"invalid request containing {api_key}")
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            notes = generate_release_notes.generate_notes_with_gemini(api_key, [], "")

        self.assertEqual(notes, (None, None))
        self.assertNotIn(api_key, output.getvalue())
        self.assertIn("InvalidURL", output.getvalue())


if __name__ == "__main__":
    unittest.main()
