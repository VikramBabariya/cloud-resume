#!/usr/bin/env python3
"""
Resume as Code: Static Site Compiler
Generates a static HTML portfolio by merging YAML data with a Jinja2 template.
Engineered with strict SRE error boundaries, absolute path resolution, and TTFCP optimization.
"""

import sys
import time
import logging
from pathlib import Path

# Third-party dependencies
import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from jinja2.exceptions import TemplateError, UndefinedError
from markupsafe import Markup  # Import Markup to bypass escaping safely

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
OUTPUT_HTML = OUTPUT_DIR / "index.html"


def setup_logging() -> logging.Logger:
    """Configures structured logging for CI/CD observability."""
    logger = logging.getLogger("BuildEngine")
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter(
        "%(asctime)s - %(levelname)s - [%(module)s] %(message)s", 
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger

logger = setup_logging()

# -----------------------------------------------------------------------------
# Core Build Functions (Modular & DRY)
# -----------------------------------------------------------------------------

def load_yaml_data(filepath: Path) -> dict:
    """Parses the YAML data contract securely."""
    try:
        with filepath.open("r", encoding="utf-8") as file:
            # SRE Security Constraint: Always use safe_load to prevent arbitrary code execution
            data = yaml.safe_load(file)
            logger.info(f"Successfully loaded data layer: {filepath.name} ({filepath.stat().st_size} bytes)")
            return data
    except FileNotFoundError:
        logger.critical(f"Data Source Missing: Cannot locate {filepath}")
        sys.exit(1)
    except yaml.YAMLError as exc:
        logger.critical(f"Data Contract Violation: Malformed YAML detected in {filepath.name}.\n{exc}")
        sys.exit(1)

def load_static_asset(filepath: Path) -> str:
    """Reads static assets (like CSS) as raw strings for build-time injection."""
    try:
        content = filepath.read_text(encoding="utf-8")
        logger.info(f"Successfully loaded static asset: {filepath.name} ({len(content.splitlines())} lines)")
        return content
    except FileNotFoundError:
        logger.critical(f"Asset Missing: Cannot locate critical path CSS at {filepath}")
        sys.exit(1)

def compile_site(data: dict, inline_css: str, template_dir: Path, output_file: Path) -> None:
    """
    Merges data and styles into the Jinja2 template and writes the final artifact.
    """
    try:
        # SRE Reliability Constraint: StrictUndefined prevents silent UI regressions.
        # If the template references {{ basics.non_existent }}, the build crashes instead of rendering a blank space.
        env = Environment(
            loader=FileSystemLoader(str(template_dir)),
            undefined=StrictUndefined,
            autoescape=True  # Ensure XSS protection on variable rendering
        )
        
        template = env.get_template("resume.html.j2")

        # Declare the CSS string as structurally safe
        # This bypasses auto-escaping strictly for the CSS, preventing &#39; injection
        safe_css = Markup(inline_css)
        
        # Inject the parsed YAML dictionary natively, plus our raw CSS string
        rendered_html = template.render(**data, inline_css=safe_css)
        
        # Ensure the output directory exists before writing
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        output_file.write_text(rendered_html, encoding="utf-8")
        logger.info(f"Artifact compiled successfully: {output_file.relative_to(BASE_DIR)} ({output_file.stat().st_size} bytes)")
        
    except UndefinedError as exc:
        logger.critical(f"Template Rendering Failure (Missing Data): {exc}")
        sys.exit(1)
    except TemplateError as exc:
        logger.critical(f"Template Compilation Error: {exc}")
        sys.exit(1)
    except Exception as exc:
        logger.critical(f"Unexpected compilation fault: {exc}")
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
    
    # 3. Compile the artifact
    compile_site(
        data=resume_data,
        inline_css=critical_css,
        template_dir=TEMPLATE_DIR,
        output_file=OUTPUT_HTML
    )
    
    duration = time.perf_counter() - start_time
    logger.info(f"Build pipeline completed successfully in {duration:.4f} seconds.")

if __name__ == "__main__":
    main()