#!/usr/bin/env python3
"""Сборка .gma (GMAD v3) по формату Facepunch/gmad.

Steam и gmad.exe не нужны: формат описан в Facepunch/gmad
(include/AddonFormat.h, src/create_gmad.cpp, include/AddonReader.h).

Использование:
    python3 make_gma.py <папка аддона> <файл.gma> [--verify]
"""

import json
import os
import struct
import sys
import time
import zlib

IDENT = b"GMAD"
VERSION = 3
AUTHOR = "Author Name"
ADDON_VERSION = 1


def read_tree(folder):
    """Все файлы папки: (путь в нижнем регистре, полный путь), по алфавиту.

    addon.json не пакуется: gmad использует его только как метаданные.
    """
    files = []

    for root, _, names in os.walk(folder):
        for name in names:
            if name.lower() == "addon.json":
                continue

            full = os.path.join(root, name)
            rel = os.path.relpath(full, folder).replace("\\", "/").lower()
            files.append((rel, full))

    files.sort(key=lambda item: item[0])
    return files


def build(folder, out):
    folder = folder.rstrip("/\\")

    with open(os.path.join(folder, "addon.json"), encoding="utf-8") as handle:
        meta = json.load(handle)

    title = meta.get("title") or "addon"
    desc = json.dumps({
        "description": meta.get("description", "Description"),
        "type": meta.get("type", ""),
        "tags": meta.get("tags", []),
    }, ensure_ascii=False, indent="\t")

    files = read_tree(folder)
    if not files:
        raise SystemExit("в папке нет файлов")

    payload = []
    index = bytearray()

    for number, (rel, full) in enumerate(files, start=1):
        with open(full, "rb") as handle:
            data = handle.read()

        if not data:
            raise SystemExit("пустой файл: " + rel)

        payload.append(data)
        index += struct.pack("<I", number)
        index += rel.encode("utf-8") + b"\x00"
        index += struct.pack("<q", len(data))
        index += struct.pack("<I", zlib.crc32(data) & 0xFFFFFFFF)

    index += struct.pack("<I", 0)

    buf = bytearray()
    buf += IDENT
    buf += bytes([VERSION])
    buf += struct.pack("<Q", 0)                 # SteamID, не используется
    buf += struct.pack("<Q", int(time.time()))  # timestamp
    buf += b"\x00"                              # required content: пусто

    for text in (title, desc, AUTHOR):
        buf += text.encode("utf-8") + b"\x00"

    buf += struct.pack("<i", ADDON_VERSION)
    buf += index

    for data in payload:
        buf += data

    buf += struct.pack("<I", zlib.crc32(bytes(buf)) & 0xFFFFFFFF)

    with open(out, "wb") as handle:
        handle.write(buf)

    print("файлов: %d, размер: %d б, записан: %s" % (len(files), len(buf), out))
    return files


def verify(path):
    """Читаем файл обратно по правилам AddonReader.h и сверяем CRC."""
    with open(path, "rb") as handle:
        buf = handle.read()

    body = buf[:-4]
    stored = struct.unpack("<I", buf[-4:])[0]

    if (zlib.crc32(body) & 0xFFFFFFFF) != stored:
        raise SystemExit("не сходится CRC всего архива")

    if body[:4] != IDENT:
        raise SystemExit("нет идентификатора GMAD")

    version = body[4]
    if version != VERSION:
        raise SystemExit("версия не 3: %d" % version)

    pos = 5 + 8 + 8  # steamid + timestamp

    def read_str(at):
        end = body.index(b"\x00", at)
        return body[at:end].decode("utf-8"), end + 1

    # required content: пустая строка-терминатор
    text, pos = read_str(pos)
    while text:
        text, pos = read_str(pos)

    title, pos = read_str(pos)
    desc, pos = read_str(pos)
    author, pos = read_str(pos)
    pos += 4  # версия аддона

    entries = []
    while True:
        number = struct.unpack("<I", body[pos:pos + 4])[0]
        pos += 4
        if number == 0:
            break

        name, pos = read_str(pos)
        size = struct.unpack("<q", body[pos:pos + 8])[0]
        pos += 8
        crc = struct.unpack("<I", body[pos:pos + 4])[0]
        pos += 4
        entries.append((number, name, size, crc))

    block = pos
    offset = 0

    for number, name, size, crc in entries:
        data = body[block + offset:block + offset + size]
        if len(data) != size:
            raise SystemExit("обрезан файл: " + name)
        if (zlib.crc32(data) & 0xFFFFFFFF) != crc:
            raise SystemExit("CRC не сходится: " + name)
        offset += size

    if block + offset != len(body):
        raise SystemExit("лишние байты после файлов")

    print("проверка OK: %s | название: %s | файлов: %d"
          % (path, title, len(entries)))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if "--verify" in sys.argv:
        if len(args) != 1:
            raise SystemExit(__doc__)
        verify(args[0])
        return

    if len(args) != 2:
        raise SystemExit(__doc__)

    build(args[0], args[1])
    verify(args[1])


if __name__ == "__main__":
    main()
