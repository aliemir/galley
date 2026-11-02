#!/usr/bin/env python3
"""Writes the website's theme cards from the app's own themes.

Reads every `static let … = Theme(…)` in app/Galley/Appearance/Theme.swift,
in the order of `Theme.all`, and rewrites the block between
<!-- themes:start --> and <!-- themes:end --> in website/public/index.html:
one card per theme, drawn as Settings → Themes draws it — the name, a change
bar beside a sentence with inserted words, a highlight and a link, and a
line of code. Run it after changing a theme:

    python3 tools/theme-cards.py
"""
import html
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
swift = (root / "app/Galley/Appearance/Theme.swift").read_text()
page_path = root / "website/public/index.html"

themes = {}
for match in re.finditer(r"static let (\w+) = Theme\((.*?)\n    \)", swift, re.S):
    fields = dict(re.findall(r'(\w+): ("[^"]*"|true|false)', match.group(2)))
    themes[match.group(1)] = {key: value.strip('"') for key, value in fields.items()}

order = re.search(r"static let all: \[Theme\] = \[(.*?)\]", swift, re.S).group(1)
names = re.findall(r"\.(\w+)", order)


def card(theme):
    style = ";".join(f"--{css}:{theme[key]}" for css, key in [
        ("t-paper", "paper"), ("t-ink", "ink"), ("t-ink2", "inkSecondary"), ("t-accent", "accent"),
        ("t-rule", "rule"), ("t-code", "codeBackground"), ("t-change", "change"), ("t-insert", "insert"),
        ("t-hl", "highlight"), ("t-kw", "codeKeyword"), ("t-str", "codeString"), ("t-num", "codeNumber"),
        ("t-fn", "codeFunction"),
    ])
    return (
        f'        <li style="{style}">\n'
        f'          <strong>{html.escape(theme["name"])}</strong>\n'
        f'          <p>The agent <ins>rewrote the plan</ins> overnight; you <mark>marked a step</mark>'
        f' and <u>the next file</u> <span>waits.</span></p>\n'
        f'          <code><b>func</b> <i>read</i>(<s>"plan.md"</s>, <em>2</em>)</code>\n'
        f'        </li>'
    )


def group(title, dark):
    cards = "\n".join(card(themes[n]) for n in names if (themes[n]["isDark"] == "true") == dark)
    return f'      <h3>{title}</h3>\n      <ul>\n{cards}\n      </ul>'


block = (
    "<!-- themes:start — written by tools/theme-cards.py from Theme.swift -->\n"
    '    <div class="themes" aria-label="The themes">\n'
    f'{group("Light", False)}\n{group("Dark", True)}\n'
    "    </div>\n"
    "    <!-- themes:end -->"
)
page = page_path.read_text()
page, count = re.subn(r"<!-- themes:start.*?<!-- themes:end -->", lambda _: block, page, flags=re.S)
if count != 1:
    raise SystemExit("index.html needs one <!-- themes:start --> … <!-- themes:end --> block")
page_path.write_text(page)
print(f"{len(names)} themes written to {page_path.relative_to(root)}")
