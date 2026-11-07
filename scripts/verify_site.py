#!/usr/bin/env python3
"""Confirm the published chronicle still matches the locked player recap."""

from __future__ import annotations

import hashlib
import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin

ROOT = Path(__file__).resolve().parents[1]
CHRONICLE = ROOT / "eternal-concord" / "index.html"
PDF = ROOT / "eternal-concord" / "eternal-concord-session-chronicle.pdf"
LOCK = Path(__file__).resolve().parent / "chronicle_lock.json"
PROJECT = "https://jbagnoli.github.io/jbagnoli_DM/"

SESSION_LINKS = [
    "https://share.sessionkeeper.ai/s/fJbD7u",
    "https://share.sessionkeeper.ai/s/UX5ndw",
    "https://share.sessionkeeper.ai/s/4MSZyv",
    "https://share.sessionkeeper.ai/s/XSbRae",
    "https://share.sessionkeeper.ai/s/4HzqVr",
    "https://share.sessionkeeper.ai/s/NLNSsp",
    "https://share.sessionkeeper.ai/s/XY8nBr",
    "https://share.sessionkeeper.ai/s/xbsJcT",
]


class ChronicleExtractor(HTMLParser):
    """Pull story blocks, quotes, and achievements in document order."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.story: list[dict[str, str]] = []
        self.quotes: list[dict[str, str]] = []
        self.awards: list[dict[str, str]] = []
        self.quote_groups: list[dict[str, str]] = []
        self.award_groups: list[dict[str, str]] = []
        self.notes: list[str] = []
        self.source_labels: list[dict[str, str]] = []
        self.hrefs: list[str] = []
        self.section: str | None = None
        self.capture: str | None = None
        self.buf: list[str] = []
        self.quote: dict[str, str] | None = None
        self.quote_field: str | None = None
        self.award: dict[str, str] | None = None
        self.award_field: str | None = None
        self.footer_buf: list[str] = []
        self.group_date = ""
        self.reading_date = False
        self.reading_group_title = False
        self.reading_note = False
        self.reading_source_date = False
        self.reading_source_title = False
        self.source_date = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {key: value or "" for key, value in attrs}
        classes = set(attr.get("class", "").split())
        if tag == "a" and attr.get("href"):
            self.hrefs.append(attr["href"])
            if self.section == "sources":
                self.reading_source_title = True
                self.buf = []
        if tag == "section":
            self.section = attr.get("id") or None
        if self.section == "story" and self.quote is None and tag in {"h2", "h3", "p", "aside"}:
            self.capture = tag
            self.buf = []
        if self.section == "story" and tag == "div" and "date" in classes:
            self.capture = "div"
            self.buf = []
        if tag == "blockquote" and "quote" in classes:
            self.quote = {"text": "", "speaker": "", "context": ""}
            self.quote_field = None
        if self.quote is not None and tag == "p":
            self.quote_field = "text"
            self.buf = []
        if self.quote is not None and tag == "cite":
            self.quote_field = "speaker"
            self.buf = []
        if self.quote is not None and tag == "footer":
            self.footer_buf = []
        if tag == "article" and "award" in classes:
            self.award = {"recipient": "", "title": "", "description": ""}
        if self.award is not None and tag == "div" and "recipient" in classes:
            self.award_field = "recipient"
            self.buf = []
        if self.award is not None and tag == "h4":
            self.award_field = "title"
            self.buf = []
        if self.award is not None and tag == "p":
            self.award_field = "description"
            self.buf = []
        if self.section in {"quotes", "achievements"} and self.award is None and self.quote is None:
            if tag == "div" and "date" in classes:
                self.reading_date = True
                self.buf = []
            elif tag == "h3":
                self.reading_group_title = True
                self.buf = []
        if self.section == "sources" and tag == "div" and "date" in classes:
            self.reading_source_date = True
            self.buf = []
        if self.section == "sources" and tag == "p" and "note" in classes:
            self.reading_note = True
            self.buf = []

    def handle_endtag(self, tag: str) -> None:
        text = "".join(self.buf).strip()
        if self.capture and tag == self.capture and self.quote is None and self.award is None:
            if text:
                self.story.append({"tag": tag, "text": text})
            self.capture = None
            self.buf = []
        if self.reading_date and tag == "div":
            self.group_date = text
            self.reading_date = False
            self.buf = []
        if self.reading_group_title and tag == "h3":
            group = {"date": self.group_date, "title": text}
            if self.section == "quotes":
                self.quote_groups.append(group)
            elif self.section == "achievements":
                self.award_groups.append(group)
            self.reading_group_title = False
            self.buf = []
        if self.reading_source_date and tag == "div":
            self.source_date = text
            self.reading_source_date = False
            self.buf = []
        if self.reading_source_title and tag == "a":
            self.source_labels.append({"date": self.source_date, "title": text})
            self.reading_source_title = False
            self.buf = []
        if self.reading_note and tag == "p":
            if text:
                self.notes.append(text)
            self.reading_note = False
            self.buf = []
        if self.quote is not None and tag == "p" and self.quote_field == "text":
            self.quote["text"] = text
            self.quote_field = None
            self.buf = []
        if self.quote is not None and tag == "cite":
            self.quote["speaker"] = text
            self.quote_field = None
            self.buf = []
        if self.quote is not None and tag == "footer":
            footer = "".join(self.footer_buf)
            marker = "·"
            self.quote["context"] = footer.split(marker, 1)[1].strip() if marker in footer else footer.strip()
        if tag == "blockquote" and self.quote is not None:
            self.quotes.append(self.quote)
            self.quote = None
        if self.award is not None and tag in {"div", "h4", "p"} and self.award_field:
            self.award[self.award_field] = text
            self.award_field = None
            self.buf = []
        if tag == "article" and self.award is not None:
            self.awards.append(self.award)
            self.award = None
        if tag == "section":
            self.section = None

    def handle_data(self, data: str) -> None:
        if self.quote is not None and self.quote_field:
            self.buf.append(data)
        elif self.award is not None and self.award_field:
            self.buf.append(data)
        elif self.capture or self.reading_date or self.reading_group_title or self.reading_note or self.reading_source_date or self.reading_source_title:
            self.buf.append(data)
        if self.quote is not None and not self.quote_field:
            self.footer_buf.append(data)


def extract(path: Path) -> ChronicleExtractor:
    parser = ChronicleExtractor()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    return parser


class TextNodes(HTMLParser):
    """Visible text, with style and script contents left out."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.nodes: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"style", "script"}:
            self.skip += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in {"style", "script"} and self.skip:
            self.skip -= 1

    def handle_data(self, data: str) -> None:
        if self.skip:
            return
        text = " ".join(data.split())
        if text:
            self.nodes.append(text)


def text_nodes(path: Path) -> list[str]:
    parser = TextNodes()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    return parser.nodes


ADDED_TEXT = ("Printable PDF", "DM projects", "Download the printable PDF")


def fail(message: str) -> None:
    print(f"FAIL {message}")
    raise SystemExit(1)


def check_files() -> None:
    for path in (ROOT / "index.html", CHRONICLE, PDF, ROOT / ".nojekyll", ROOT / ".github/workflows/pages.yml", LOCK):
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")
    header = PDF.read_bytes()[:8]
    if not header.startswith(b"%PDF-"):
        fail("printable companion is not a PDF")
    digest = hashlib.sha256(PDF.read_bytes()).hexdigest()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if digest != lock["pdf_sha256"]:
        fail("printable PDF bytes differ from the locked companion")


def check_no_remote_behavior(html: str, label: str) -> None:
    lowered = html.lower()
    for banned in ("<script", "googletagmanager", "google-analytics", "gtag(", "plausible", "umami", "cdn.jsdelivr", "fonts.googleapis"):
        if banned in lowered:
            fail(f"{label} contains {banned}")
    if "src=" in lowered or "url(" in lowered:
        fail(f"{label} references an external or embedded asset URL")


def check_relative(path: Path, page_url: str) -> list[str]:
    html = path.read_text(encoding="utf-8")
    parser = extract(path)
    resolved: list[str] = []
    for href in parser.hrefs:
        if href.startswith(("mailto:", "javascript:")):
            fail(f"{path.name} has disallowed href {href}")
        if href.startswith("/"):
            fail(f"{path.name} uses root-relative href {href}; project Pages base is /jbagnoli_DM/")
        if href.startswith("#"):
            continue
        absolute = urljoin(page_url, href)
        if absolute.startswith("https://share.sessionkeeper.ai/"):
            resolved.append(absolute)
            continue
        if not absolute.startswith(PROJECT):
            fail(f"{path.name} href {href} resolves outside {PROJECT} to {absolute}")
        relative = absolute[len(PROJECT):]
        target = ROOT / relative
        if relative.endswith("/"):
            target = ROOT / relative / "index.html"
        if not target.is_file():
            fail(f"{path.name} href {href} does not match a file ({target.relative_to(ROOT)})")
        resolved.append(absolute)
    return parser.hrefs


def check_chronicle() -> None:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    parsed = extract(CHRONICLE)
    if parsed.story != lock["story"]:
        fail("story prose differs from the locked recap")
    if parsed.quotes != lock["quotes"]:
        fail(f"quotes differ ({len(parsed.quotes)} found, {len(lock['quotes'])} locked)")
    if parsed.quote_groups != lock["quote_groups"]:
        fail("quote session headings differ from the locked recap")
    if parsed.awards != lock["awards"]:
        fail(f"achievements differ ({len(parsed.awards)} found, {len(lock['awards'])} locked)")
    if parsed.award_groups != lock["award_groups"]:
        fail("achievement session headings differ from the locked recap")
    if parsed.source_labels != lock["source_labels"]:
        fail("session source titles differ from the locked recap")
    if parsed.notes != lock["notes"]:
        fail("source notes differ from the locked recap")
    nodes = text_nodes(CHRONICLE)
    for extra in ADDED_TEXT:
        if extra not in nodes:
            fail(f"missing added link text: {extra}")
        nodes.remove(extra)
    if nodes != lock["text_nodes"]:
        fail("visible chronicle text differs from the locked recap")
    if len(parsed.quotes) != 24:
        fail(f"expected 24 quotes, found {len(parsed.quotes)}")
    if len(parsed.awards) != 13:
        fail(f"expected 13 achievements, found {len(parsed.awards)}")
    sources = [href for href in parsed.hrefs if href.startswith("https://share.sessionkeeper.ai/")]
    if sources != SESSION_LINKS:
        fail("session source links are missing or reordered")
    html = CHRONICLE.read_text(encoding="utf-8")
    if 'href="eternal-concord-session-chronicle.pdf"' not in html:
        fail("printable PDF download link is missing")
    if 'href="../index.html"' not in html:
        fail("link back to the project shelf is missing")
    if any(not award["description"] or not award["title"] for award in parsed.awards):
        fail("an achievement is missing its title or description")


def check_shelf() -> None:
    shelf = extract(ROOT / "index.html")
    destinations = [href for href in shelf.hrefs if not href.startswith("#")]
    if destinations != ["eternal-concord/"]:
        fail(f"shelf should link only to the chronicle, found {destinations}")


def main() -> None:
    check_files()
    check_no_remote_behavior(CHRONICLE.read_text(encoding="utf-8"), "chronicle")
    check_no_remote_behavior((ROOT / "index.html").read_text(encoding="utf-8"), "shelf")
    check_chronicle()
    check_shelf()
    check_relative(ROOT / "index.html", PROJECT)
    check_relative(CHRONICLE, PROJECT + "eternal-concord/")
    # Directory URLs and explicit index URLs must both stay inside the project base.
    for page in (PROJECT, PROJECT + "index.html"):
        target = urljoin(page, "eternal-concord/")
        if target != PROJECT + "eternal-concord/":
            fail(f"shelf link drifted from the project base: {target}")
    pdf_url = urljoin(PROJECT + "eternal-concord/", "eternal-concord-session-chronicle.pdf")
    back_url = urljoin(PROJECT + "eternal-concord/index.html", "../index.html")
    if pdf_url != PROJECT + "eternal-concord/eternal-concord-session-chronicle.pdf":
        fail(f"PDF link drifted: {pdf_url}")
    if back_url != PROJECT + "index.html":
        fail(f"back link drifted: {back_url}")
    print("OK chronicle: 8 source links, 24 quotes, 13 achievements, relative Pages links")


if __name__ == "__main__":
    main()
