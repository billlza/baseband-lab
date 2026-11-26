"""Build the self-contained file viewer from the same table reader as the live receiver."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
template = (root / "source/offline-view.html").read_text(encoding="utf-8")
table = (root / "Receiver/table.js").read_text(encoding="utf-8").replace("export ", "")
css = (root / "Receiver/panel.css").read_text(encoding="utf-8")
assert all(template.count(marker) == 1 for marker in ("/* PANEL_STYLE */", "/* TABLE_MODULE */"))
html = template.replace("/* PANEL_STYLE */", css).replace("/* TABLE_MODULE */", table)
with (root / "离线分析.html").open("w", encoding="utf-8", newline="\n") as out:
    out.write(html)
