import contextlib
import http.client
import io
import json
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
