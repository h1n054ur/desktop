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


if __name__ == "__main__":
    unittest.main()
