#!/usr/bin/env python3
"""
Resume as Code: Static Site Compiler
Generates a static HTML portfolio and a print-ready PDF by merging YAML data
with Jinja2 templates.
Engineered with strict SRE error boundaries, absolute path resolution, and TTFCP optimization.
"""

import re
import sys
import time
import logging
from datetime import datetime
from pathlib import Path

# Third-party dependencies
import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from jinja2.exceptions import TemplateError, UndefinedError
from markupsafe import Markup  # Import Markup to bypass escaping safely

# WeasyPrint — PDF rendering engine (HTML → PDF via CSS Paged Media)
import weasyprint

# -----------------------------------------------------------------------------
# Configuration & Path Resolution
# -----------------------------------------------------------------------------
# Resolving absolute paths relative to the script's location ensures idempotent
# execution regardless of the CI/CD runner's working directory.
BASE_DIR = Path(__file__).resolve().parent
DATA_PATH = BASE_DIR / "data" / "resume.yaml"
TEMPLATE_DIR = BASE_DIR / "src" / "templates"
STATIC_DIR = BASE_DIR / "src" / "static"
OUTPUT_DIR = BASE_DIR / "dist"
CSS_PATH = STATIC_DIR / "style.css"
PDF_CSS_PATH = STATIC_DIR / "pdf-style.css"
OUTPUT_HTML = OUTPUT_DIR / "index.html"
OUTPUT_PDF = OUTPUT_DIR / "resume.pdf"


def setup_logging() -> logging.Logger:
    """Configures structured logging for CI/CD observability."""
    logger = logging.getLogger("BuildEngine")
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter(
        "%(asctime)s - %(levelname)s - [%(module)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger


logger = setup_logging()

# -----------------------------------------------------------------------------
# Jinja2 custom filters
# -----------------------------------------------------------------------------

# Month abbreviation map avoids locale dependency on CI runners
_MONTH_ABBR = {
    1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr",
    5: "May", 6: "Jun", 7: "Jul", 8: "Aug",
    9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec",
}


def _filter_format_date(value: str) -> str:
    """
    Converts an ISO-8601 date string ("YYYY-MM-DD") to "Mon YYYY" format
    for human-readable display in the PDF.
    Falls through unchanged for non-date strings like "Present".
    """
    if not isinstance(value, str):
        return str(value)
    try:
        dt = datetime.strptime(value.strip(), "%Y-%m-%d")
        return f"{_MONTH_ABBR[dt.month]} {dt.year}"
    except ValueError:
        return value  # "Present" or any custom string passes through


def _filter_strip_md(value: str) -> str:
    """
    Strips lightweight Markdown syntax from plain-text strings so that
    raw YAML fields like '**FinOps**' or '`ajv-cli`' don't leak literal
    punctuation into the PDF.

    Handles:
      **bold**  →  bold
      *italic*  →  italic
      `code`    →  code
      .dev      → .dev  (dot-prefixed words left alone)
    """
    if not isinstance(value, str):
        return str(value)
    # Bold: **text** or __text__
    value = re.sub(r"\*\*(.+?)\*\*", r"\1", value)
    value = re.sub(r"__(.+?)__", r"\1", value)
    # Italic: *text* or _text_  (single, not already consumed)
    value = re.sub(r"\*(.+?)\*", r"\1", value)
    value = re.sub(r"(?<!\w)_(.+?)_(?!\w)", r"\1", value)
    # Inline code: `text`
    value = re.sub(r"`(.+?)`", r"\1", value)
    return value


# -----------------------------------------------------------------------------
# Core Build Functions (Modular & DRY)
# -----------------------------------------------------------------------------


def load_yaml_data(filepath: Path) -> dict:
    """Parses the YAML data contract securely."""
    try:
        with filepath.open("r", encoding="utf-8") as file:
            # SRE Security Constraint: Always use safe_load to prevent arbitrary code execution
            data = yaml.safe_load(file)
            logger.info(
                f"Successfully loaded data layer: {filepath.name} ({filepath.stat().st_size} bytes)"
            )
            return data
    except FileNotFoundError:
        logger.critical(f"Data Source Missing: Cannot locate {filepath}")
        sys.exit(1)
    except yaml.YAMLError as exc:
        logger.critical(
            f"Data Contract Violation: Malformed YAML detected in {filepath.name}.\n{exc}"
        )
        sys.exit(1)


def load_static_asset(filepath: Path) -> str:
    """Reads static assets (like CSS) as raw strings for build-time injection."""
    try:
        content = filepath.read_text(encoding="utf-8")
        logger.info(
            f"Successfully loaded static asset: {filepath.name} ({len(content.splitlines())} lines)"
        )
        return content
    except FileNotFoundError:
        logger.critical(
            f"Asset Missing: Cannot locate critical path CSS at {filepath}"
        )
        sys.exit(1)


def _make_jinja_env(template_dir: Path, extra_filters: dict | None = None) -> Environment:
    """
    Creates a hardened Jinja2 environment with shared security settings
    and optional extra filters.
    """
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        undefined=StrictUndefined,
        autoescape=True,
    )
    if extra_filters:
        env.filters.update(extra_filters)
    return env


def compile_site(
    data: dict, inline_css: str, template_dir: Path, output_file: Path
) -> None:
    """
    Merges data and styles into the Jinja2 template and writes the final HTML artifact.
    """
    try:
        env = _make_jinja_env(template_dir)
        template = env.get_template("resume.html.j2")

        # Declare the CSS string as structurally safe to bypass auto-escaping
        safe_css = Markup(inline_css)

        rendered_html = template.render(**data, inline_css=safe_css)

        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text(rendered_html, encoding="utf-8")
        logger.info(
            f"Artifact compiled successfully: {output_file.relative_to(BASE_DIR)} ({output_file.stat().st_size} bytes)"
        )

    except UndefinedError as exc:
        logger.critical(f"Template Rendering Failure (Missing Data): {exc}")
        sys.exit(1)
    except TemplateError as exc:
        logger.critical(f"Template Compilation Error: {exc}")
        sys.exit(1)
    except Exception as exc:
        logger.critical(f"Unexpected compilation fault: {exc}")
        sys.exit(1)


def compile_pdf(data: dict, pdf_css: str, template_dir: Path, output_file: Path) -> None:
    """
    Renders the Overleaf-style PDF artifact via WeasyPrint.
    Uses resume-pdf.html.j2 + pdf-style.css with custom filters for
    date formatting and Markdown stripping.
    """
    try:
        env = _make_jinja_env(
            template_dir,
            extra_filters={
                "format_date": _filter_format_date,
                "strip_md": _filter_strip_md,
            },
        )

        template = env.get_template("resume-pdf.html.j2")
        safe_pdf_css = Markup(pdf_css)
        rendered_html = template.render(**data, pdf_css=safe_pdf_css)

        output_file.parent.mkdir(parents=True, exist_ok=True)

        document = weasyprint.HTML(
            string=rendered_html,
            base_url=str(template_dir),
        )
        document.write_pdf(str(output_file))

        logger.info(
            f"PDF artifact compiled successfully: {output_file.relative_to(BASE_DIR)} ({output_file.stat().st_size} bytes)"
        )

    except UndefinedError as exc:
        logger.critical(f"PDF Template Rendering Failure (Missing Data): {exc}")
        sys.exit(1)
    except TemplateError as exc:
        logger.critical(f"PDF Template Compilation Error: {exc}")
        sys.exit(1)
    except Exception as exc:
        logger.critical(f"Unexpected PDF compilation fault: {exc}")
        sys.exit(1)


# -----------------------------------------------------------------------------
# Execution Orchestrator
# -----------------------------------------------------------------------------


def main():
    """Main execution pipeline."""
    start_time = time.perf_counter()
    logger.info("Initializing Resume as Code Build Engine...")

    # 1. Load the structured content
    resume_data = load_yaml_data(DATA_PATH)

    # 2. Extract Critical Path CSS for zero-round-trip TTFCP
    critical_css = load_static_asset(CSS_PATH)

    # 3. Extract PDF stylesheet
    pdf_css = load_static_asset(PDF_CSS_PATH)

    # 4. Compile the HTML artifact
    compile_site(
        data=resume_data,
        inline_css=critical_css,
        template_dir=TEMPLATE_DIR,
        output_file=OUTPUT_HTML,
    )

    # 5. Compile the PDF artifact (Overleaf/LaTeX style)
    compile_pdf(
        data=resume_data,
        pdf_css=pdf_css,
        template_dir=TEMPLATE_DIR,
        output_file=OUTPUT_PDF,
    )

    duration = time.perf_counter() - start_time
    logger.info(f"Build pipeline completed successfully in {duration:.4f} seconds.")


if __name__ == "__main__":
    main()
