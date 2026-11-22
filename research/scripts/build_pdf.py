"""Compile Research_Results_Visual_Summary.md into an executive PDF via Pandoc/XeLaTeX."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from generate_diagrams import generate_all_diagrams, generate_report_diagrams

DEFAULT_HEADER_LEFT = r"Roblox Deep Market Research \& Product Validation (Nov 2026)"
DEFAULT_HEADER_RIGHT = r"Solo Indie Visual Results"

LATEX_HEADER_TEMPLATE = r"""
\usepackage{geometry}
\geometry{letterpaper, margin=0.65in}
\usepackage{pdflscape}
\usepackage{ragged2e}
\usepackage{url}
\urlstyle{same}
\usepackage{xcolor}
\definecolor{Navy}{HTML}{1B2A4A}
\definecolor{Teal}{HTML}{0D9488}
\definecolor{Slate}{HTML}{475569}
\usepackage{titlesec}
\titleformat{\section}{\raggedright\Large\bfseries\color{Navy}}{\thesection}{0.5em}{}[\color{Teal}\titlerule]
\titleformat{\subsection}{\raggedright\large\bfseries\color{Teal}}{\thesubsection}{0.5em}{}
\titleformat{\subsubsection}{\raggedright\normalsize\bfseries\color{Navy}}{\thesubsubsection}{0.5em}{}
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

local function escape_latex(str)
  local map = {
    ["\\"] = "\\textbackslash{}",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["$"] = "\\$",
    ["&"] = "\\&",
    ["#"] = "\\#",
    ["_"] = "\\_",
    ["^"] = "\\textasciicircum{}",
    ["~"] = "\\textasciitilde{}",
    ["%"] = "\\%",
  }
  return (str:gsub("[\\{}$&#_^~%%]", map))
end

local function add_breakpoints(str)
  local esc = escape_latex(str)
  esc = esc:gsub("([/_.:-])", "%1\\allowbreak{}")
  esc = esc:gsub("([a-z])([A-Z])", "%1\\allowbreak{}%2")
  return esc
end

local function wrap_long_tokens(blocks)
  return pandoc.walk_block(pandoc.Div(blocks), {
    Code = function(el)
      if #el.text >= 14 and el.text:find("[/_.:%-]") or (#el.text >= 16 and el.text:find("[a-z][A-Z]")) then
        return pandoc.RawInline("latex", "\\texttt{" .. add_breakpoints(el.text) .. "}")
      end
      return el
    end,
    Str = function(el)
      if #el.text >= 18 and el.text:find("[/_.:]") then
        return pandoc.RawInline("latex", add_breakpoints(el.text))
      end
      return el
    end,
  }).content
end

local function compute_table_style(ncols)
  if ncols >= 11 then
    return "\\scriptsize", 2.5, true, 701.0, 0.045, 0.65
  elseif ncols >= 9 then
    return "\\scriptsize", 3.0, true, 701.0, 0.055, 0.60
  elseif ncols >= 8 then
    return "\\scriptsize", 3.0, false, 520.3, 0.065, 0.55
  elseif ncols >= 6 then
    return "\\footnotesize", 4.0, false, 520.3, 0.096, 0.50
  end
  return "\\small", 5.0, false, 520.3, 0.090, 0.50
end

function Table(tbl)
  local ncols = #tbl.colspecs
  if ncols == 0 then return tbl end
  local size_cmd, colsep_pt, use_landscape, avail_pt, min_w, pow = compute_table_style(ncols)
  local weights = {}
  for i = 1, ncols do weights[i] = 8 end

  local function process_rows(rows)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        local n = math.min(64, cell_len(cell))
        if n > (weights[i] or 8) then weights[i] = n end
        cell.contents = wrap_long_tokens(cell.contents)
      end
    end
  end

  if tbl.head and tbl.head.rows then process_rows(tbl.head.rows) end
  for _, body in ipairs(tbl.bodies) do
    process_rows(body.head)
    process_rows(body.body)
  end

  local total = 0
  for i = 1, ncols do
    weights[i] = weights[i] ^ pow
    total = total + weights[i]
  end

  local sum_w = 0
  for i = 1, ncols do
    weights[i] = math.max(min_w, weights[i] / total)
    sum_w = sum_w + weights[i]
  end

  local usable_ratio = math.max(0.55, (avail_pt - (2 * ncols * colsep_pt) - 6.0) / avail_pt)
  for i = 1, ncols do
    local align = tbl.colspecs[i][1]
    tbl.colspecs[i] = {align, (weights[i] / sum_w) * usable_ratio}
  end

  local out = {}
  if use_landscape then table.insert(out, pandoc.RawBlock("latex", "\\begin{landscape}")) end
  table.insert(out, pandoc.RawBlock("latex", "\\begingroup" .. size_cmd .. "\\RaggedRight\\setlength{\\tabcolsep}{" .. colsep_pt .. "pt}"))
  table.insert(out, tbl)
  table.insert(out, pandoc.RawBlock("latex", "\\endgroup"))
  if use_landscape then table.insert(out, pandoc.RawBlock("latex", "\\end{landscape}")) end
  return out
end
"""

MERMAID_BLOCK_RE = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+\.(?:md|py|csv|json|txt))\)")
SECTION_BREAK_RE = re.compile(r"\n---\n\n(## \d+\.)")
DELIVERABLE_BREAK_RE = re.compile(r"\n---\n\n(# (?:Deliverable |Appendix:))")
INLINE_MATH_RE = re.compile(r"(?<!\\)\$(?!\d)((?:\\\$|[^$\n])+)(?<!\\)\$")
MATH_CMD_RE = re.compile(r"\\(?:text|frac|times|div|lceil|rceil|sum|approx)|_\{")
MANUAL_TOC_RE = re.compile(
    r"^# ([^\n]+)\n\n"
    r"\*\*Collection Date:\*\* ([^\n]+)\n"
    r"\*\*Primary Anchor Profile:\*\* ([^\n]+)\n"
    r"\*\*Scope:\*\* ([^\n]+)\n\n"
    r"## Table of Contents\n\n(?:- \[[^\]]+\]\(#[^)]+\)\n)+\s*",
    re.MULTILINE,
)
DEEP_DIVE_RE = re.compile(r"^\*\*(Deep-Dive Reading|Source Research Backing):\*\* (.+)$", re.MULTILINE)


def preprocess_markdown_for_pdf(
    md_text: str,
    charts_dir: Path,
    page_break_sections: bool = True,
    page_break_level: str = "h2",
    include_toc: bool = False,
) -> str:
    """Replace Mermaid blocks with PNG diagrams and normalize GitHub/emoji/TOC syntax."""
    text = _replace_mermaid_blocks(md_text, charts_dir)
    text = text.replace("### Interactive Score Summary (Text-Native View)\n\n", "")
    text = _normalize_github_alerts(text)
    text = _normalize_pdf_symbols(text)
    text = _convert_inline_latex_math(text)
    text = MD_LINK_RE.sub(r"\1", text)
    text = DEEP_DIVE_RE.sub(
        r"\\begingroup\\raggedright\\small\n\n**\1:** \2\n\n\\endgroup",
        text,
    )
    text = text.replace("(research/charts/", f"({charts_dir.as_posix()}/")
    if include_toc or page_break_level == "h1":
        text = text.replace("## Appendix: Verified Sources Registry", "# Appendix: Verified Sources Registry")
    text = _apply_page_breaks(text, page_break_sections, page_break_level)
    text = text.replace("\n---\n", "\n\n")
    if include_toc:
        text = _apply_master_toc_frontmatter(text)
    return text


def _convert_inline_latex_math(md_text: str) -> str:
    """Wrap explicit LaTeX math formulas as raw LaTeX while keeping currency $ intact."""
    def _replace(match: re.Match[str]) -> str:
        expr = match.group(1)
        if MATH_CMD_RE.search(expr):
            return f"`\\({expr}\\)`{{=latex}}"
        return match.group(0)

    return INLINE_MATH_RE.sub(_replace, md_text)


def _apply_master_toc_frontmatter(md_text: str) -> str:
    """Convert leading report header and manual TOC into Pandoc YAML title metadata."""
    match = MANUAL_TOC_RE.match(md_text)
    if not match:
        return md_text
    title, date_val, anchor, scope = (g.strip() for g in match.groups())
    frontmatter = (
        "---\n"
        f"title: {title!r}\n"
        f"subtitle: {scope!r}\n"
        f"author: {('Primary Anchor: ' + anchor)!r}\n"
        f"date: {('Collection Date: ' + date_val)!r}\n"
        "---\n\n"
    )
    return frontmatter + md_text[match.end() :]


def _apply_page_breaks(md_text: str, enabled: bool, level: str) -> str:
    """Insert LaTeX page breaks before top-level sections or deliverables."""
    if not enabled or level == "none":
        return md_text
    if level == "h1":
        updated = DELIVERABLE_BREAK_RE.sub(r"\n\\newpage\n\n\1", md_text)
        return re.sub(r"\A(# Deliverable )", r"\\newpage\n\n\1", updated)
    return SECTION_BREAK_RE.sub(r"\n\\newpage\n\n\1", md_text)


def _replace_mermaid_blocks(md_text: str, charts_dir: Path) -> str:
    """Swap each Mermaid fence for its corresponding rendered PNG diagram."""
    mappings = (
        ("Preliminary Concept (GameIdea.txt", "07_loop_comparison_diagram.png", "Gameplay Loop Audit: GameIdea.txt vs C2 Egg Heist"),
        ("Cold-Start Seed", "08_rfy_discovery_funnel.png", "Late-2026 Home RFY Two-Stage Discovery Funnel"),
        ("Gate 1 Decision", "09_30day_validation_roadmap.png", "30-Day Solo Validation and Gate 1 Pivot Roadmap"),
        ("Personal Vault Hub", "10_c2_core_gameplay_loop.png", "C2 Egg Heist Core 6-Step Gameplay Loop"),
        ("Any Traffic Source", "11_master_rfy_pipeline.png", "Late-2026 Home RFY Retrieval and 28-Day Ranking Pipeline"),
        ("Stationary Training Range", "12_gameidea_broken_loop.png", "Audit of Preliminary GameIdea.txt Broken Gameplay Loop"),
        ("Core Throw/Orb & Carry Physics", "13_c2_mvp_dependency_dag.png", "C2 Egg Heist 145-Hour Solo MVP Module Dependency DAG"),
    )

    def _swap(match: re.Match[str]) -> str:
        block = match.group(1)
        for key, filename, caption in mappings:
            if key in block:
                return f"![{caption}]({(charts_dir / filename).as_posix()})\n"
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
    page_break_level: str = "h2",
    include_toc: bool = False,
) -> Path:
    """Generate companion diagrams, preprocess Markdown, and compile PDF via Pandoc."""
    if not input_md.exists():
        raise FileNotFoundError(f"Input Markdown not found: {input_md}")
    generate_all_diagrams(charts_dir)
    generate_report_diagrams(charts_dir)
    processed = preprocess_markdown_for_pdf(
        input_md.read_text(encoding="utf-8"),
        charts_dir,
        page_break_sections=page_break_sections,
        page_break_level=page_break_level,
        include_toc=include_toc,
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
        _run_pandoc(tmp_md, tmp_tex, tmp_lua, output_pdf, include_toc=include_toc)
    return output_pdf


def _run_pandoc(
    input_md: Path, header_tex: Path, lua_filter: Path, output_pdf: Path, include_toc: bool = False
) -> None:
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
        "-V", "mainfont=Carlito",
        "-V", "monofont=Adwaita Mono",
        "-V", "fontsize=10pt",
        "-V", "colorlinks=true",
        "-V", "linkcolor=Navy",
        "-V", "urlcolor=Teal",
    ]
    if include_toc:
        cmd.extend(["--toc", "--toc-depth=2", "-V", "toccolor=Navy"])
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
    parser.add_argument("--page-break-level", choices=("h1", "h2", "none"), default="h2")
    parser.add_argument("--toc", action="store_true")
    args = parser.parse_args()
    try:
        out = build_pdf(
            args.input,
            args.charts_dir,
            args.output,
            header_left=args.header_left,
            header_right=args.header_right,
            page_break_sections=not args.no_page_break_sections,
            page_break_level=args.page_break_level,
            include_toc=args.toc,
        )
        print(f"BUILT PDF: {out} ({out.stat().st_size:,} bytes)")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"PDF BUILD ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
