#!/usr/bin/env python3
"""Create five-page EPUB, PDF and CBZ books for the BS3 native reader matrix."""

import argparse
import struct
import zlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

COLORS = [(245, 159, 176), (142, 205, 250), (153, 222, 157), (245, 203, 128), (190, 164, 240)]
CHAPTERS = range(1, len(COLORS) + 1)


def epub(path):
    items = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in CHAPTERS)
    spine = "".join(f'<itemref idref="c{i}"/>' for i in CHAPTERS)
    links = "".join(f'<li><a href="c{i}.xhtml">BS3 Chapter {i}</a></li>' for i in CHAPTERS)
    container = """<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>"""
    package = f"""<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:yabr:bs3</dc:identifier>
        <dc:title>BS3 Chapters</dc:title>
        <dc:language>en</dc:language>
        <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
      </metadata>
      <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>{items}</manifest>
      <spine>{spine}</spine>
    </package>"""
    navigation = f"""<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <head><title>Contents</title></head>
      <body><nav epub:type="toc"><ol>{links}</ol></nav></body>
    </html>"""
    with ZipFile(path, "w", compression=ZIP_DEFLATED) as book:
        book.writestr("mimetype", "application/epub+zip", compress_type=ZIP_STORED)
        book.writestr("META-INF/container.xml", container)
        book.writestr("book.opf", package)
        book.writestr("nav.xhtml", navigation)
        for i in CHAPTERS:
            book.writestr(f"c{i}.xhtml", f"""<html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>BS3 Chapter {i}</title></head>
              <body><h1>BS3 Chapter {i}</h1><p>The silver kite crosses the river. The blue boat waits beyond the bridge.</p></body>
            </html>""")


def pdf(path):
    page_refs = " ".join(f"{i} 0 R" for i in range(4, 4 + 2 * len(COLORS), 2))
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{page_refs}] /Count {len(COLORS)} >>".encode(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    for index, color in enumerate(COLORS):
        rgb = " ".join(f"{component / 255:.5f}" for component in color)
        content = f"q {rgb} rg 0 0 612 792 re f Q\nBT /F1 32 Tf 50 370 Td (BS3 Page {index + 1}) Tj ET\n".encode()
        objects.append(
            ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> "
             f"/Contents {5 + 2 * index} 0 R >>").encode()
        )
        objects.append(f"<< /Length {len(content)} >>\nstream\n".encode() + content + b"endstream")
    data = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(data))
        data.extend(f"{i} 0 obj\n".encode() + obj + b"\nendobj\n")
    start = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for offset in offsets:
        data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode())
    path.write_bytes(data)


def png_chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def cbz(path):
    with ZipFile(path, "w", compression=ZIP_DEFLATED) as book:
        for i, color in enumerate(COLORS, start=1):
            header = struct.pack(">2I5B", 480, 640, 8, 2, 0, 0, 0)
            pixels = zlib.compress((b"\x00" + bytes(color) * 480) * 640)
            image = (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
                     + png_chunk(b"IDAT", pixels) + png_chunk(b"IEND", b""))
            book.writestr(f"{i:03}.png", image)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--pdf-only", action="store_true", help="Generate only the contract book's PDF")
    arguments = parser.parse_args()
    output = arguments.directory
    output.mkdir(parents=True, exist_ok=True)
    pdf(output / "BS3-PDF.pdf")
    if not arguments.pdf_only:
        epub(output / "BS3-Folio.epub")
        epub(output / "BS3-Readium.epub")
        pdf(output / "BS3-Legacy-PDF.pdf")
        cbz(output / "BS3-Comic.cbz")
