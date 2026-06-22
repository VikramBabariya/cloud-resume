#!/usr/bin/env python3
from pdfminer.high_level import extract_pages, extract_text
from pdfminer.layout import LTTextBox

pages = list(extract_pages("dist/resume.pdf"))
text = extract_text("dist/resume.pdf")

print(f"Pages: {len(pages)}")
for i, page in enumerate(pages):
    text_boxes = [el for el in page if isinstance(el, LTTextBox)]
    if not text_boxes:
        continue
    top_y = max(tb.y1 for tb in text_boxes)
    bot_y = min(tb.y0 for tb in text_boxes)
    print(f"  Page {i+1}: content {bot_y:.1f}–{top_y:.1f}pt  height={top_y-bot_y:.1f}pt")
    if i > 0:
        print(f"  Overflow content:")
        for tb in sorted(text_boxes, key=lambda t: -t.y1)[:5]:
            print(f"    {tb.get_text().strip()[:60]}")

print()
checks = {
    "Job summary (Infineon automation)":  "Engineered backend automation" in text,
    "Job summary (Infineon intern)":       "highly scalable" in text or "scalable data ingestion" in text or "Wafer Visualization" in text,
    "Project description (Zero-Trust)":   "production-grade Resume-as-Code" in text,
    "Project description (Inventory)":    "Containerized full-stack" in text,
    "Single page":                        len(pages) == 1,
}
all_pass = True
for label, ok in checks.items():
    print(f"  {'OK' if ok else 'FAIL'} {label}")
    if not ok:
        all_pass = False
print("\nRESULT:", "ALL PASS" if all_pass else "SOME FAILED")
import sys; sys.exit(0 if all_pass else 1)
