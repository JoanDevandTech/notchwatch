#!/usr/bin/env python3
"""Añade un <item> al principio del appcast de Sparkle.

Uso:
  update_appcast.py --appcast appcast.xml --tag v0.3.0 --build 142 \
      --url https://github.com/.../Notchwatch-0.3.0.dmg \
      --notes-url https://github.com/.../releases/tag/v0.3.0 \
      --signature 'BASE64==' --length 12345 [--min-system 14.6]

Si ya existe un item con la misma sparkle:version se sustituye (re-ejecución de una release).
"""
import argparse
import email.utils
import re
import sys
from xml.sax.saxutils import escape, quoteattr

parser = argparse.ArgumentParser()
parser.add_argument("--appcast", required=True)
parser.add_argument("--tag", required=True)
parser.add_argument("--build", required=True, help="CFBundleVersion de la app publicada")
parser.add_argument("--url", required=True, help="URL de descarga del DMG")
parser.add_argument("--notes-url", required=True, help="URL de la GitHub Release")
parser.add_argument("--signature", required=True, help="sparkle:edSignature que devuelve sign_update")
parser.add_argument("--length", required=True, type=int, help="Tamaño del DMG en bytes")
parser.add_argument("--min-system", default="14.6")
args = parser.parse_args()

if not re.fullmatch(r"[A-Za-z0-9+/=]+", args.signature):
    sys.exit("Firma EdDSA con formato inesperado")
if not re.fullmatch(r"\d+", args.build):
    sys.exit("CFBundleVersion debe ser numérico")

short_version = args.tag[1:] if args.tag.startswith("v") else args.tag
pub_date = email.utils.formatdate(usegmt=True)

item = f"""    <item>
      <title>{escape("Notchwatch " + short_version)}</title>
      <link>{escape(args.notes_url)}</link>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{escape(short_version)}</sparkle:shortVersionString>
      <sparkle:fullReleaseNotesLink>{escape(args.notes_url)}</sparkle:fullReleaseNotesLink>
      <pubDate>{pub_date}</pubDate>
      <sparkle:minimumSystemVersion>{escape(args.min_system)}</sparkle:minimumSystemVersion>
      <enclosure url={quoteattr(args.url)} sparkle:edSignature={quoteattr(args.signature)} length="{args.length}" type="application/octet-stream"/>
    </item>
"""

with open(args.appcast, encoding="utf-8") as fh:
    xml = fh.read()

# Re-ejecución de la misma build: se quita el item anterior con esa sparkle:version.
xml = re.sub(
    r"[ \t]*<item>(?:(?!</item>).)*?<sparkle:version>" + re.escape(args.build) + r"</sparkle:version>.*?</item>\n?",
    "",
    xml,
    flags=re.S,
)

match = re.search(r"[ \t]*<item>", xml)
if match:
    xml = xml[: match.start()] + item + xml[match.start():]
else:
    close = xml.rfind("</channel>")
    if close == -1:
        sys.exit("appcast.xml sin </channel>")
    line_start = xml.rfind("\n", 0, close) + 1
    xml = xml[:line_start] + item + xml[line_start:]

with open(args.appcast, "w", encoding="utf-8") as fh:
    fh.write(xml)

print(item)
