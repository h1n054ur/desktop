"""Turn an agent's markdown reply into short prose that reads well aloud.

Stdlib only. The main entry is clean(text, max_sentences).
"""

import re
import sys

CUT_NOTE = "Rest is on screen."

_FENCE = re.compile(r"^\s*(```|~~~)")
_TABLE_ROW = re.compile(r"^\s*\|.*\|\s*$")
_TABLE_RULE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
_HRULE = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")
_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+")
_BULLET = re.compile(r"^\s*(?:[-*+]|\d{1,3}[.)])\s+(?:\[[ xX]\]\s+)?")
_QUOTE = re.compile(r"^\s*>\s?")
_URL = re.compile(r"(?:https?|ftp|file)://\S+|\bwww\.\S+")
_MD_LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_INLINE_CODE = re.compile(r"`([^`\n]*)`")
_BOLD_ITALIC = re.compile(r"(\*\*\*|\*\*|__|\*|_)(?=\S)(.+?)(?<=\S)\1")
_STRIKE = re.compile(r"~~(.+?)~~")
_HTML_TAG = re.compile(r"</?[a-zA-Z][^>]*>")
_EMOJI = re.compile(
    "["
    "\U0001f000-\U0001faff"
    "\U00002600-\U000027bf"
    "\U0001f1e6-\U0001f1ff"
    "\U00002b00-\U00002bff"
    "‍️⃣"
    "]+"
)
# Things that look like paths, flags, commands or code rather than words.
_PATHY = re.compile(r"^(?:~|\.{1,2})?/\S*$|^\S+/\S+$|^--?\w[\w-]*=?\S*$|^\$\S*$|^\S+\.\w{1,5}:\d+$")
_CODEY = re.compile(r"[{}();=<>\[\]\\]|::|->|=>|&&|\|\|")
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(])")

# A path written in prose: absolute, home or dot relative, or a/b/name.ext, or name.ext:line.
_BARE_PATH = re.compile(
    r"(?<![\w/\x00])(?:(?:~|\.{1,2})?/[\w.@+~-]+(?:/[\w.@+~-]+)*/?"
    r"|[\w.-]+(?:/[\w.@+-]+)+\.[A-Za-z]\w{0,4}(?::\d+)?"
    r"|[\w-]+\.[A-Za-z]\w{0,4}:\d+)"
)

# Inline code longer than this many words, or with code punctuation, is replaced by a short word.
_SHORT_CODE_WORDS = 3

# Something removed from prose leaves a marker that later becomes a short phrase such as
# "the file", so the sentence still reads well. Markers hold one of the nouns below.
_MARK = "\x00{}\x00"
_MARK_RE = re.compile(r"(?:(\S+)(\s+))?\x00(\w+)\x00(?=(?:\s+(\w+))?)")
_DETERMINERS = {"the", "a", "an", "this", "that", "these", "those", "your", "my", "our", "its", "their"}
_NOUNS = {
    "file", "files", "folder", "directory", "script", "command", "link", "url", "path",
    "page", "config", "flag", "option", "options", "repo", "code",
}


def _mark(noun):
    return _MARK.format(noun)


def _inline_code(match):
    inner = match.group(1).strip()
    if not inner:
        return ""
    if "\x00" in inner:
        return inner  # already a marker (a URL inside backticks)
    if _PATHY.match(inner):
        if inner.startswith("-"):
            return _mark("option")
        if inner.startswith("$"):
            return _mark("command")
        return _mark("file")
    if len(inner.split()) > _SHORT_CODE_WORDS or len(inner) > 40:
        return _mark("command")
    if _CODEY.search(inner):
        return _mark("code")
    return inner


def _bare_path(match):
    path = match.group(0)
    core = path.rstrip(".,:;")
    return _mark("file") + path[len(core):]


def _resolve_mark(match):
    prev, space, noun, nxt = match.group(1), match.group(2), match.group(3), match.group(4)
    prev_word = (prev or "").strip("\"'(,.;:").lower()
    if nxt and nxt.lower() in _NOUNS:
        # "the `x.py` file" reads as "the file", and "edit `x.py` file" as "edit the file".
        phrase = "" if prev_word in _DETERMINERS else "the"
    elif prev_word in _DETERMINERS:
        phrase = noun
    else:
        phrase = "the " + noun
    if phrase and (prev is None or prev.endswith((".", "!", "?"))):
        phrase = phrase[0].upper() + phrase[1:]
    if prev is None:
        return phrase
    return prev + (space if phrase else "") + phrase


def _resolve_marks(line):
    while "\x00" in line:
        line, count = _MARK_RE.subn(_resolve_mark, line, count=1)
        if not count:
            return line.replace("\x00", "")
    return re.sub(r"\s{2,}", " ", line)


def _mostly_technical(line):
    """True when most words on the line are paths, flags, commands, links or code."""
    words = line.split()
    if not words:
        return False
    tech = sum(
        1 for w in words if "\x00" in w or _PATHY.match(w.strip(",.;:")) or _CODEY.search(w)
    )
    return tech / len(words) >= 0.5


def _looks_like_shell(line):
    s = line.strip()
    return s.startswith(("$ ", "# ", "sudo ", "> ")) and len(s.split()) >= 2


def _strip_inline(line):
    line = _HTML_TAG.sub("", line)
    line = _MD_LINK.sub(lambda m: m.group(1), line)
    line = _URL.sub(lambda m: _mark("link"), line)
    # Lines that are mostly paths or commands go before inline code is unwrapped.
    if _mostly_technical(_INLINE_CODE.sub(lambda m: m.group(1), line)):
        return ""
    line = _INLINE_CODE.sub(_inline_code, line)
    line = _BARE_PATH.sub(_bare_path, line)
    # A line that is nothing but removed items says nothing.
    if not re.search(r"[A-Za-z0-9]", re.sub(r"\x00\w+\x00", "", line)):
        return ""
    line = _resolve_marks(line)
    line = _STRIKE.sub(lambda m: m.group(1), line)
    for _ in range(2):
        line = _BOLD_ITALIC.sub(lambda m: m.group(2), line)
    line = line.replace("**", "").replace("__", "")
    line = _EMOJI.sub("", line)
    return line


def _blocks(text):
    """Yield speakable blocks: paragraphs and single bullet items."""
    in_fence = False
    para = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if _FENCE.match(raw):
            in_fence = not in_fence
            if para:
                yield " ".join(para)
                para = []
            continue
        if in_fence:
            continue
        if _TABLE_ROW.match(raw) or _TABLE_RULE.match(raw) or _HRULE.match(raw):
            if para:
                yield " ".join(para)
                para = []
            continue
        if not raw.strip():
            if para:
                yield " ".join(para)
                para = []
            continue
        if raw.startswith(("    ", "\t")) and not _BULLET.match(raw) and not para:
            # Indented code block.
            continue
        line = _QUOTE.sub("", raw)
        heading = bool(_HEADING.match(line))
        bullet = bool(_BULLET.match(line))
        line = _HEADING.sub("", line)
        line = _BULLET.sub("", line)
        if _looks_like_shell(line):
            continue
        line = _strip_inline(line).strip()
        if not line:
            continue
        if heading or bullet:
            if para:
                yield " ".join(para)
                para = []
            yield line
            continue
        para.append(line)
    if para:
        yield " ".join(para)


def _as_sentence(block):
    block = re.sub(r"\s+", " ", block).strip(" -:,;")
    block = re.sub(r"\s+([,.!?;:])", r"\1", block)
    block = re.sub(r"\(\s*\)", "", block).strip()
    if not re.search(r"[A-Za-z0-9]", block):
        return ""
    if block[-1] not in ".!?":
        block += "."
    return block


def clean(text, max_sentences=4):
    """Return speakable prose, or an empty string when nothing is worth saying."""
    if not text:
        return ""
    sentences = []
    for block in _blocks(text):
        block = _as_sentence(block)
        if block:
            sentences.extend(s.strip() for s in _SENTENCE_END.split(block) if s.strip())
    if not sentences:
        return ""
    if max_sentences and max_sentences > 0 and len(sentences) > max_sentences:
        return " ".join(sentences[:max_sentences] + [CUT_NOTE])
    return " ".join(sentences)


if __name__ == "__main__":
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    print(clean(sys.stdin.read(), limit))
