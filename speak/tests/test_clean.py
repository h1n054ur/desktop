"""Tests for speak/lib/clean.py. Run: python3 speak/tests/test_clean.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

from clean import CUT_NOTE, clean  # noqa: E402


REPLY_WITH_CODE = """\
## Done

I fixed the **off by one** error in `parse_args`. The loop now stops at the last item.

```python
for i in range(len(items)):
    print(items[i])
```

Tests pass now.
"""

REPLY_WITH_TABLE = """\
Here is the status of the three hosts:

| Host | State |
|------|-------|
| alpha | up |
| beta | down |

Beta needs a restart.
"""

REPLY_WITH_BULLETS = """\
Three things changed:

- The bar shows a *muted* icon
- Replay works while muted
1. Stop clears the queue
"""

REPLY_WITH_PATHS = """\
Edited these files:

/home/user/project/src/main.py
src/lib/util.ts:42
`~/.config/speak/config.toml`

See https://example.com/docs/page for details. Run `bun test` to check.
"""

LONG_REPLY = """\
First sentence here. Second one follows. Third is short.
Fourth adds more. Fifth should be cut. Sixth too.
"""


class CleanTests(unittest.TestCase):
    def test_drops_code_block_and_heading(self):
        out = clean(REPLY_WITH_CODE)
        self.assertNotIn("range(", out)
        self.assertNotIn("#", out)
        self.assertNotIn("`", out)
        self.assertNotIn("*", out)
        self.assertIn("off by one", out)
        self.assertIn("parse_args", out)
        self.assertTrue(out.startswith("Done."))
        self.assertIn("Tests pass now.", out)

    def test_drops_tables(self):
        out = clean(REPLY_WITH_TABLE)
        self.assertNotIn("|", out)
        self.assertNotIn("alpha", out)
        self.assertEqual(out, "Here is the status of the three hosts. Beta needs a restart.")

    def test_bullets_become_sentences(self):
        out = clean(REPLY_WITH_BULLETS)
        self.assertEqual(
            out,
            "Three things changed. The bar shows a muted icon. "
            "Replay works while muted. Stop clears the queue.",
        )

    def test_drops_paths_urls_and_keeps_short_code(self):
        out = clean(REPLY_WITH_PATHS)
        self.assertNotIn("/home", out)
        self.assertNotIn("util.ts", out)
        self.assertNotIn("config.toml", out)
        self.assertNotIn("http", out)
        self.assertIn("bun test", out)
        self.assertNotIn("`", out)

    def test_cuts_after_max_sentences(self):
        out = clean(LONG_REPLY, 4)
        self.assertTrue(out.endswith(CUT_NOTE))
        self.assertIn("Fourth adds more.", out)
        self.assertNotIn("Fifth", out)
        self.assertEqual(clean("One. Two.", 4), "One. Two.")

    def test_emoji_removed(self):
        self.assertEqual(clean("All green ✅ \U0001f680 now"), "All green now.")

    def test_empty_results(self):
        self.assertEqual(clean(""), "")
        self.assertEqual(clean("```\nonly code\n```"), "")
        self.assertEqual(clean("| a | b |\n|---|---|\n| 1 | 2 |"), "")
        self.assertEqual(clean("https://example.com"), "")

    def test_long_inline_code_dropped(self):
        out = clean("Run `git log --format='%h %G?' -n 5 main` first, then push.")
        self.assertNotIn("git log", out)
        self.assertIn("then push", out)

    def test_inline_path_becomes_the_file(self):
        out = clean("The installer is in `~/setup/install.sh`, so it's quick.")
        self.assertEqual(out, "The installer is in the file, so it's quick.")

    def test_inline_url_becomes_the_link(self):
        self.assertEqual(
            clean("See https://example.com/docs/page for details."), "See the link for details."
        )

    def test_long_command_becomes_the_command(self):
        out = clean("Run `git log --format='%h %G?' -n 5 main` first, then push.")
        self.assertEqual(out, "Run the command first, then push.")

    def test_bare_paths_in_prose(self):
        self.assertEqual(
            clean("The error is in src/app/main.ts, line 3."), "The error is in the file, line 3."
        )
        self.assertEqual(clean("Edit /etc/hosts. Then restart."), "Edit the file. Then restart.")
        self.assertEqual(clean("Check lib/clean.py:42 now."), "Check the file now.")

    def test_no_doubled_nouns_or_articles(self):
        self.assertEqual(clean("Open the `~/a/b.toml` file."), "Open the file.")
        self.assertEqual(clean("Open this `src/b.toml`."), "Open this file.")
        self.assertEqual(clean("Edit `src/b.toml` file."), "Edit the file.")

    def test_start_of_sentence_is_capitalised(self):
        self.assertEqual(clean("`src/main.py` is fixed."), "The file is fixed.")
        self.assertEqual(clean("Done. `src/main.py` is fixed."), "Done. The file is fixed.")

    def test_flags_and_code(self):
        self.assertEqual(clean("Pass `--force` to skip it."), "Pass the option to skip it.")
        self.assertEqual(clean("I fixed `items[i]` in place."), "I fixed the code in place.")

    def test_lines_of_only_paths_or_links_still_drop(self):
        self.assertEqual(clean("/home/user/project/src/main.py"), "")
        self.assertEqual(clean("`~/.config/speak/config.toml`"), "")
        self.assertEqual(clean("Links: https://a.example https://b.example"), "")
        self.assertEqual(clean("Done.\n\nsrc/lib/util.ts:42\n"), "Done.")


if __name__ == "__main__":
    unittest.main()
