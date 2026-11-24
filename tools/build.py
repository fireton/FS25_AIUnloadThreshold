"""Build a reproducible FS25 archive with modDesc.xml at its root."""
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
FILES = ["modDesc.xml"]
FILES += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "scripts").glob("*.lua"))
FILES += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "gui").glob("*.xml"))
descriptor = ET.parse(ROOT / "modDesc.xml").getroot()
icon = descriptor.findtext("iconFilename")
assert icon and not Path(icon).is_absolute() and ".." not in Path(icon).parts, "Invalid icon path"
FILES.append(icon)
for source in descriptor.findall("./extraSourceFiles/sourceFile"):
    assert source.attrib["filename"] in FILES, "Unpackaged source file"
output = ROOT / "release" / "FS25_AIUnloadThreshold.zip"
output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix(".zip.tmp")
with ZipFile(temporary, "w", compression=ZIP_DEFLATED) as archive:
    for filename in FILES:
        info = ZipInfo(filename, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, (ROOT / filename).read_bytes())
with ZipFile(temporary) as archive:
    assert "modDesc.xml" in archive.namelist()
    assert archive.testzip() is None
    assert all(not p.startswith(("/", "FS25_AIUnloadThreshold/")) for p in archive.namelist())
temporary.replace(output)
print(f"Built {output} ({output.stat().st_size} bytes)")
