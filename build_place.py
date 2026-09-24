#!/usr/bin/env python3
# ============================================================
#  build_place.py — собирает src/ в единый файл «БЕСПИЛОТНИКИ.rbxlx»,
#  который открывается напрямую в Roblox Studio.
#  Использование:  python3 build_place.py
# ============================================================
import os
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "БЕСПИЛОТНИКИ.rbxlx")

_ref = 0
def next_ref():
    global _ref
    _ref += 1
    return f"RBX{_ref}"

def item_props(name):
    return f'<Properties><string name="Name">{escape(name)}</string></Properties>'

def script_item(class_name, name, source):
    r = next_ref()
    src = escape(source)
    return (f'<Item class="{class_name}" referent="{r}">'
            f'<Properties><string name="Name">{escape(name)}</string>'
            f'<ProtectedString name="Source">{src}</ProtectedString>'
            f'</Properties></Item>')

def folder_item(name, children_xml):
    r = next_ref()
    return (f'<Item class="Folder" referent="{r}">'
            f'{item_props(name)}{children_xml}</Item>')

def build_dir(dirpath):
    """Рекурсивно строит XML для каталога src."""
    children = []
    for fn in sorted(os.listdir(dirpath)):
        path = os.path.join(dirpath, fn)
        if os.path.isdir(path):
            children.append(folder_item(fn, build_dir(path)))
        elif fn.endswith(".lua"):
            base = fn[:-4]
            if base.endswith(".server"):
                class_name, name = "Script", base[:-7]
            elif base.endswith(".client"):
                class_name, name = "LocalScript", base[:-7]
            else:
                class_name, name = "ModuleScript", base
            with open(path, encoding="utf-8") as f:
                children.append(script_item(class_name, name, f.read()))
    return "".join(children)

def main():
    sss = build_dir(os.path.join(SRC, "ServerScriptService"))
    rs = build_dir(os.path.join(SRC, "ReplicatedStorage"))
    sps = build_dir(os.path.join(SRC, "StarterPlayer", "StarterPlayerScripts"))

    rbxlx = f'''<roblox xmlns:xmime="http://schemas.microsoft.com/appx/2010/manifest" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
  <Item class="Workspace" referent="{next_ref()}">
    <Properties><string name="Name">Workspace</string></Properties>
  </Item>
  <Item class="ReplicatedStorage" referent="{next_ref()}">
    <Properties><string name="Name">ReplicatedStorage</string></Properties>
    {rs}
  </Item>
  <Item class="ServerScriptService" referent="{next_ref()}">
    <Properties><string name="Name">ServerScriptService</string></Properties>
    {sss}
  </Item>
  <Item class="StarterPlayer" referent="{next_ref()}">
    <Properties><string name="Name">StarterPlayer</string></Properties>
    <Item class="StarterPlayerScripts" referent="{next_ref()}">
      <Properties><string name="Name">StarterPlayerScripts</string></Properties>
      {sps}
    </Item>
  </Item>
</roblox>
'''
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(rbxlx)

    # валидация XML
    import xml.etree.ElementTree as ET
    ET.parse(OUT)
    size_mb = os.path.getsize(OUT) / 1e6
    print(f"OK: {OUT} ({size_mb:.2f} MB), XML валиден")

if __name__ == "__main__":
    main()
