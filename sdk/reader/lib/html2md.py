#!/usr/bin/env python3
"""A web page's words as markdown, for the reader's fetch (seshat#46).

Reads an HTML file, writes JSON: {"title": ..., "text": ...}. Standard
library only, so it runs on the witness's Mac as it ships. No model reads
the page: the conversion is plain code, so nothing on the page can tell
it to do anything. Headings keep the page's own ids as `{#id}`, which an
anchor in a citation can name; scripts, styles, navigation, headers,
footers, forms and asides are left out; the main article, when the page
marks one, is taken alone.

Usage: html2md.py PAGE.html
"""
import json
import re
import sys
from html.parser import HTMLParser

SKIP = {"script", "style", "noscript", "svg", "nav", "footer", "header", "form", "aside",
        "button", "iframe", "template", "select", "canvas"}
BLOCK = {"p", "div", "section", "article", "main", "ul", "ol", "table", "tr", "figure",
         "figcaption", "dl", "dd", "dt", "hr", "br"}
VOID = {"br", "hr", "img", "meta", "link", "input", "source", "wbr", "area", "base", "col"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.title = ""
        self.in_title = False
        self.skip = 0
        self.pre = 0
        self.lists = []
        self.link = None
        self.heading = None
        self.quote = 0

    def emit(self, text):
        self.out.append(text)

    def block(self):
        self.emit("\n\n")

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in SKIP:
            if tag not in VOID:
                self.skip += 1
            return
        if self.skip:
            return
        if tag == "title":
            self.in_title = True
        elif re.fullmatch(r"h[1-6]", tag):
            self.block()
            self.heading = (int(tag[1]), a.get("id"))
            self.emit("#" * int(tag[1]) + " ")
        elif tag == "pre":
            self.block()
            self.emit("```\n")
            self.pre += 1
        elif tag == "code" and not self.pre:
            self.emit("`")
        elif tag in ("ul", "ol"):
            self.lists.append([tag, 0])
            self.block()
        elif tag == "li":
            depth = max(len(self.lists) - 1, 0)
            if self.lists and self.lists[-1][0] == "ol":
                self.lists[-1][1] += 1
                mark = f"{self.lists[-1][1]}. "
            else:
                mark = "- "
            self.emit("\n" + "  " * depth + mark)
        elif tag == "blockquote":
            self.block()
            self.quote += 1
            self.emit("> ")
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag in ("em", "i"):
            self.emit("*")
        elif tag == "a":
            self.link = a.get("href")
            self.emit("[")
        elif tag == "img" and a.get("alt"):
            self.emit(f"[image: {a.get('alt')}]")
        elif tag in BLOCK:
            self.block()

    def handle_endtag(self, tag):
        if tag in SKIP:
            if tag not in VOID:
                self.skip = max(self.skip - 1, 0)
            return
        if self.skip:
            return
        if tag == "title":
            self.in_title = False
        elif re.fullmatch(r"h[1-6]", tag) and self.heading:
            _level, ident = self.heading
            if ident:
                self.emit(" {#" + ident + "}")
            self.heading = None
            self.block()
        elif tag == "pre":
            self.emit("\n```")
            self.pre = max(self.pre - 1, 0)
            self.block()
        elif tag == "code" and not self.pre:
            self.emit("`")
        elif tag in ("ul", "ol"):
            if self.lists:
                self.lists.pop()
            self.block()
        elif tag == "blockquote":
            self.quote = max(self.quote - 1, 0)
            self.block()
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag in ("em", "i"):
            self.emit("*")
        elif tag == "a":
            href = self.link
            self.link = None
            self.emit(f"]({href})" if href and not href.startswith("javascript:") else "]")
        elif tag in BLOCK:
            self.block()

    def handle_data(self, data):
        if self.in_title:
            self.title += data
            return
        if self.skip:
            return
        if self.pre:
            self.emit(data)
        else:
            text = re.sub(r"\s+", " ", data)
            if self.heading:
                text = text.replace("\n", " ")
            self.emit(text)


def main_part(html):
    """The page's <article> or <main>, when it marks one; else the body."""
    for tag in ("article", "main"):
        m = re.search(rf"<{tag}\b.*?</{tag}>", html, re.S | re.I)
        if m:
            return m.group(0)
    return html


def tidy(text):
    """Whitespace tidied outside code fences; a fence keeps its own."""
    parts = re.split(r"(```\n.*?\n```)", text, flags=re.S)
    for i in range(0, len(parts), 2):
        t = parts[i]
        t = re.sub(r"[ \t]+\n", "\n", t)
        t = re.sub(r"\n[ \t]+(?=[^\s-])", "\n", t)
        t = re.sub(r"\n{3,}", "\n\n", t)
        parts[i] = re.sub(r"\[\s*\]\([^)]*\)", "", t)
    return "".join(parts).strip() + "\n"


def convert(html):
    head = Page()
    head.feed(html)
    title = re.sub(r"\s+", " ", head.title).strip()
    body = Page()
    body.feed(main_part(html))
    return {"title": title, "text": tidy("".join(body.out))}


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        print(json.dumps(convert(f.read()), ensure_ascii=False))
