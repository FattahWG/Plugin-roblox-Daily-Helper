"""Packs src/ into DailyHelper.rbxmx and copies it to the Studio local Plugins folder.

src/init.server.luau becomes the plugin Script. Other .luau files become ModuleScripts under it,
and a folder becomes a Folder. Run: python build.py [--no-install]
"""
import os
import shutil
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "dist", "DailyHelper.rbxmx")
PLUGINS = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "Plugins")

counter = [0]


def ref():
    counter[0] += 1
    return f"RBX{counter[0]}"


def cdata(text):
    # "]]>" cannot sit inside CDATA, so it is split over two sections.
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(cls, name, source, children=""):
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
            f'</Properties>{children}</Item>')


def folder_items(path):
    parts = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            parts.append(f'<Item class="Folder" referent="{ref()}"><Properties>'
                         f'<string name="Name">{escape(entry)}</string></Properties>'
                         f'{folder_items(full)}</Item>')
        elif entry.endswith(".luau") and not entry.startswith("init."):
            with open(full, encoding="utf-8") as handle:
                parts.append(script_item("ModuleScript", entry[:-5], handle.read()))
    return "".join(parts)


def main():
    with open(os.path.join(SRC, "init.server.luau"), encoding="utf-8") as handle:
        main_source = handle.read()
    body = script_item("Script", "DailyHelper", main_source, folder_items(SRC))
    xml = f'<roblox version="4">{body}</roblox>'
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(xml)
    print("built", OUT, len(xml), "bytes,", counter[0], "items")
    if "--no-install" not in sys.argv:
        os.makedirs(PLUGINS, exist_ok=True)
        target = os.path.join(PLUGINS, "DailyHelper.rbxmx")
        shutil.copyfile(OUT, target)
        print("installed", target)


if __name__ == "__main__":
    main()
