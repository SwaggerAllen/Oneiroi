#!/usr/bin/env python3
"""A PDF's words as markdown, page by page, for the reader's fetch (seshat#77).

Reads a PDF file, writes JSON: {"title": ..., "text": ..., "pages": n,
"ocr": [page numbers read by OCR]}. Each page is a heading of its own,
`## Page 7 {#p7}`, so a citation can name the page as it names a
section (`web/<key>#p7`). A page with a text layer is read from it
(poppler's pdftotext); a page with none is read by OCR (ocrmypdf over
tesseract, deskewed and rotated, pages with text left alone), and the
copy says which pages were. No model reads the file: plain programs
only, so nothing in it can tell them to do anything.

Needs poppler (pdfinfo, pdftotext); OCR needs ocrmypdf and tesseract.
Without ocrmypdf, the text layer is kept and pages without one say so.

Usage: pdf2md.py FILE.pdf
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# A page with fewer letters than this has no text layer worth the name:
# scans often carry a stray page number or a stamp.
MIN_LETTERS = 20


def run(args, timeout=600):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def info(path):
    out = run(["pdfinfo", path])
    if out.returncode != 0:
        raise SystemExit("the PDF could not be opened")
    fields = {}
    for line in out.stdout.splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return int(fields.get("Pages", "0") or 0), fields.get("Title", "")


def page_text(path, n):
    out = run(["pdftotext", "-f", str(n), "-l", str(n), "-layout", "-enc", "UTF-8", path, "-"])
    return out.stdout if out.returncode == 0 else ""


def letters(text):
    return len(re.findall(r"[^\W\d_]", text))


def ocr(path, pages, work):
    """The pages without a text layer, OCR'd into a copy of the file; its path, or None."""
    if not pages or shutil.which("ocrmypdf") is None:
        return None
    out = os.path.join(work, "ocr.pdf")
    done = run(
        [
            "ocrmypdf",
            "--skip-text",
            "--deskew",
            "--rotate-pages",
            "--pages",
            ",".join(str(p) for p in pages),
            "--output-type",
            "pdf",
            "--quiet",
            path,
            out,
        ],
        timeout=3600,
    )
    return out if done.returncode == 0 and os.path.exists(out) else None


def tidy(text):
    # pdftotext's form feed ends each page; trailing spaces from -layout.
    lines = [line.rstrip() for line in text.replace("\f", "").splitlines()]
    while lines and not lines[-1]:
        lines.pop()
    while lines and not lines[0]:
        lines.pop(0)
    return "\n".join(lines)


def main(path):
    count, title = info(path)
    if count == 0:
        raise SystemExit("the PDF has no pages")

    texts = {n: page_text(path, n) for n in range(1, count + 1)}
    bare = [n for n, t in texts.items() if letters(t) < MIN_LETTERS]

    with tempfile.TemporaryDirectory() as work:
        read = ocr(path, bare, work)
        ocred = []
        if read:
            for n in bare:
                t = page_text(read, n)
                if letters(t) >= MIN_LETTERS:
                    texts[n] = t
                    ocred.append(n)

    unread = [n for n in bare if n not in ocred]
    head = [f"_From a PDF of {count} page{'s' if count != 1 else ''}"]
    if ocred:
        head.append(f"; read by OCR (tesseract), so check names and figures against the page: {spans(ocred)}")
    if unread:
        head.append(f"; no words could be read on {spans(unread)}")
    head.append("._")

    body = ["".join(head)]
    for n in range(1, count + 1):
        words = tidy(texts[n]) if n not in unread else "_No words could be read on this page._"
        body.append(f"## Page {n} {{#p{n}}}\n\n{words}")

    json.dump(
        {"title": title or "", "text": "\n\n".join(body) + "\n", "pages": count, "ocr": ocred},
        sys.stdout,
        ensure_ascii=False,
    )


def spans(pages):
    """[1, 2, 3, 7] as "pages 1–3, 7"."""
    runs, start, prev = [], None, None
    for p in sorted(pages):
        if start is None:
            start = prev = p
        elif p == prev + 1:
            prev = p
        else:
            runs.append((start, prev))
            start = prev = p
    runs.append((start, prev))
    parts = [f"{a}" if a == b else f"{a}–{b}" for a, b in runs]
    return ("page " if len(pages) == 1 else "pages ") + ", ".join(parts)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
