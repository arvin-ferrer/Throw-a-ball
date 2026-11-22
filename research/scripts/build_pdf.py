"""Compile Research_Results_Visual_Summary.md into an executive PDF via Pandoc/XeLaTeX."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from generate_diagrams import generate_all_diagrams

DEFAULT_HEADER_LEFT = r"Roblox Deep Market Research \& Product Validation (Nov 2026)"
DEFAULT_HEADER_RIGHT = r"Solo Indie Visual Results"

LATEX_HEADER_TEMPLATE = r"""
\usepackage{geometry}
\geometry{letterpaper, margin=0.65in}
\usepackage{xcolor}
\definecolor{Navy}{HTML}{1B2A4A}
\definecolor{Teal}{HTML}{0D9488}
\definecolor{Slate}{HTML}{475569}
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries\color{Navy}}{\thesection}{0.5em}{}[\color{Teal}\titlerule]
\titleformat{\subsection}{\large\bfseries\color{Teal}}{\thesubsection}{0.5em}{}
\titleformat{\subsubsection}{\normalsize\bfseries\color{Navy}}{\thesubsubsection}{0.5em}{}
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\color{Slate}__HEADER_LEFT__}
\fancyhead[R]{\small\color{Slate}__HEADER_RIGHT__}
\fancyfoot[C]{\small\color{Slate}Page \thepage}
\renewcommand{\headrulewidth}{0.4pt}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{array}
\usepackage{calc}
\usepackage{float}
\let\origfigure\figure
\let\endorigfigure\endfigure
\renewenvironment{figure}[1][2]{\expandafter\origfigure\expandafter[H]}{\endorigfigure}
\renewcommand{\arraystretch}{1.22}
\setlength{\parskip}{5pt}
\setlength{\parindent}{0pt}
\emergencystretch=3em
"""

TABLE_LUA_FILTER = r"""
local function cell_len(cell)
  local txt = pandoc.utils.stringify(cell.contents)
  return math.max(4, #txt)
end

function Table(tbl)
  local ncols = #tbl.colspecs
  if ncols == 0 then return tbl end
  local weights = {}
  for i = 1, ncols do weights[i] = 8 end

  local function scan_rows(rows)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        local n = math.min(52, cell_len(cell))
        if n > (weights[i] or 8) then weights[i] = n end
      end
    end
  end

  if tbl.head and tbl.head.rows then scan_rows(tbl.head.rows) end
  for _, body in ipairs(tbl.bodies) do
    scan_rows(body.head)
    scan_rows(body.body)
  end

  local total = 0
  for i = 1, ncols do
    weights[i] = math.sqrt(weights[i])
    total = total + weights[i]
  end

  local min_w = (ncols >= 8) and 0.065 or 0.09
  local sum_w = 0
  for i = 1, ncols do
    weights[i] = math.max(min_w, weights[i] / total)
    sum_w = sum_w + weights[i]
  end

  for i = 1, ncols do
    local align = tbl.colspecs[i][1]
    tbl.colspecs[i] = {align, (weights[i] / sum_w) * 0.96}
  end

  local size_cmd = "\\small"
  local colsep = "5pt"
  if ncols >= 8 then
    size_cmd = "\\scriptsize"
    colsep = "3pt"
  elseif ncols >= 6 then
    size_cmd = "\\footnotesize"
    colsep = "4pt"
  end

  return {
    pandoc.RawBlock("latex", "\\begingroup" .. size_cmd .. "\\setlength{\\tabcolsep}{" .. colsep .. "}"),
    tbl,
    pandoc.RawBlock("latex", "\\endgroup"),
  }
end
"""

MERMAID_BLOCK_RE = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+\.(?:md|py|csv|json|txt))\)")
SECTION_BREAK_RE = re.compile(r"\n---\n\n(## \d+\.)")
DEEP_DIVE_RE = re.compile(r"^\*\*(Deep-Dive Reading|Source Research Backing):\*\* (.+)$", re.MULTILINE)


def preprocess_markdown_for_pdf(
    md_text: str, charts_dir: Path, page_break_sections: bool = True
) -> str:
    """Replace Mermaid blocks with PNG diagrams and normalize GitHub/emoji syntax."""
    text = _replace_mermaid_blocks(md_text, charts_dir)
    text = text.replace("### Interactive Score Summary (Text-Native View)\n\n", "")
    text = _normalize_github_alerts(text)
    text = _normalize_pdf_symbols(text)
    text = MD_LINK_RE.sub(r"\1", text)
    text = DEEP_DIVE_RE.sub(
        r"\\begingroup\\raggedright\\small\n\n**\1:** \2\n\n\\endgroup",
        text,
    )
    text = text.replace("(research/charts/", f"({charts_dir.as_posix()}/")
    if page_break_sections:
        text = SECTION_BREAK_RE.sub(r"\n\\newpage\n\n\1", text)
    text = text.replace("\n---\n", "\n\n")
    return text


def _replace_mermaid_blocks(md_text: str, charts_dir: Path) -> str:
    """Swap each Mermaid fence for its corresponding rendered PNG diagram."""
    def _swap(match: re.Match[str]) -> str:
        block = match.group(1)
        if "xychart-beta" in block:
            return ""
        if "Preliminary Concept (GameIdea.txt" in block:
            img = (charts_dir / "07_loop_comparison_diagram.png").as_posix()
            return f"![Gameplay Loop Audit: GameIdea.txt vs C2 Egg Heist]({img})\n"
        if "Cold-Start Seed" in block:
            img = (charts_dir / "08_rfy_discovery_funnel.png").as_posix()
            return f"![Late-2026 Home RFY Two-Stage Discovery Funnel]({img})\n"
        if "Gate 1 Decision" in block:
            img = (charts_dir / "09_30day_validation_roadmap.png").as_posix()
            return f"![30-Day Solo Validation and Gate 1 Pivot Roadmap]({img})\n"
        if "Personal Vault Hub" in block:
            img = (charts_dir / "10_c2_core_gameplay_loop.png").as_posix()
            return f"![C2 Egg Heist Core 6-Step Gameplay Loop]({img})\n"
        return ""

    return MERMAID_BLOCK_RE.sub(_swap, md_text)


def _normalize_pdf_symbols(md_text: str) -> str:
    """Replace color emoji unavailable in Carlito with crisp Unicode/text tags."""
    replacements = (
        ("🎯 ", "[Target] "),
        ("❄️ ", "[Freeze] "),
        ("🚪 ", "[Exit] "),
        ("🆘 ", "[SOS] "),
        ("(`⚡`)", "(Dash Icon)"),
        ("⚡", "Dash"),
        ("❌ ", "[CUT] "),
    )
    updated = md_text
    for src, dst in replacements:
        updated = updated.replace(src, dst)
    return updated


def _normalize_github_alerts(md_text: str) -> str:
    """Convert GitHub blockquote alert tags into clean bold callout labels."""
    replacements = (
        ("> [!IMPORTANT]", "> **IMPORTANT:**"),
        ("> [!TIP]", "> **TIP:**"),
        ("> [!WARNING]", "> **WARNING:**"),
        ("> [!CAUTION]", "> **CAUTION:**"),
        ("> [!NOTE]", "> **NOTE:**"),
    )
    updated = md_text
    for src, dst in replacements:
        updated = updated.replace(src, dst)
    return updated


def build_pdf(
    input_md: Path,
    charts_dir: Path,
    output_pdf: Path,
    header_left: str = DEFAULT_HEADER_LEFT,
    header_right: str = DEFAULT_HEADER_RIGHT,
    page_break_sections: bool = True,
) -> Path:
    """Generate companion diagrams, preprocess Markdown, and compile PDF via Pandoc."""
    if not input_md.exists():
        raise FileNotFoundError(f"Input Markdown not found: {input_md}")
    generate_all_diagrams(charts_dir)
    processed = preprocess_markdown_for_pdf(
        input_md.read_text(encoding="utf-8"), charts_dir, page_break_sections
    )
    header_tex = LATEX_HEADER_TEMPLATE.replace("__HEADER_LEFT__", header_left).replace(
        "__HEADER_RIGHT__", header_right
    )
    output_pdf.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        tmp_md = tmp_dir / "prepared.md"
        tmp_tex = tmp_dir / "header.tex"
        tmp_lua = tmp_dir / "fit_tables.lua"
        tmp_md.write_text(processed, encoding="utf-8")
        tmp_tex.write_text(header_tex, encoding="utf-8")
        tmp_lua.write_text(TABLE_LUA_FILTER, encoding="utf-8")
        _run_pandoc(tmp_md, tmp_tex, tmp_lua, output_pdf)
    return output_pdf


def _run_pandoc(input_md: Path, header_tex: Path, lua_filter: Path, output_pdf: Path) -> None:
    """Invoke pandoc with xelatex, Carlito Unicode font, and table auto-fit filter."""
    cmd = [
        "pandoc",
        str(input_md),
        "-o",
        str(output_pdf),
        "--from=markdown+pipe_tables+raw_tex+strikeout-tex_math_dollars-implicit_figures",
        "--pdf-engine=xelatex",
        f"--include-in-header={header_tex}",
        f"--lua-filter={lua_filter}",
        "-V",
        "mainfont=Carlito",
        "-V",
        "monofont=Adwaita Mono",
        "-V",
        "fontsize=10pt",
        "-V",
        "colorlinks=true",
        "-V",
        "linkcolor=Navy",
        "-V",
        "urlcolor=Teal",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Pandoc PDF compile failed:\n{proc.stderr}\n{proc.stdout}")


def main() -> int:
    """CLI entrypoint for building executive PDF reports from Markdown."""
    parser = argparse.ArgumentParser(description="Build Roblox research/GDD PDF.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--charts-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--header-left", default=DEFAULT_HEADER_LEFT)
    parser.add_argument("--header-right", default=DEFAULT_HEADER_RIGHT)
    parser.add_argument("--no-page-break-sections", action="store_true")
    args = parser.parse_args()
    try:
        out = build_pdf(
            args.input,
            args.charts_dir,
            args.output,
            header_left=args.header_left,
            header_right=args.header_right,
            page_break_sections=not args.no_page_break_sections,
        )
        print(f"BUILT PDF: {out} ({out.stat().st_size:,} bytes)")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"PDF BUILD ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
