"""Compile modular Deliverables A-N and sources bibliography into one master report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from common import ResearchDataError, load_json_file

DELIVERABLE_MANIFEST: tuple[tuple[str, str], ...] = (
    ("A_Executive_Summary.md", "Deliverable A — Executive Summary"),
    ("B_Roblox_Market_Report.md", "Deliverable B — Roblox Market Report & Opportunities"),
    ("C_Competitive_Analysis_Database.md", "Deliverable C — Competitive Analysis Database"),
    ("D_Successful_Game_Feature_Matrix.md", "Deliverable D — Successful Game Feature Matrix"),
    ("E_Roblox_Discovery_Playbook.md", "Deliverable E — Roblox Discovery Playbook"),
    ("F_Viral_Game_Case_Studies.md", "Deliverable F — Viral Game Case Studies"),
    (
        "G_Retention_and_Monetization_Framework.md",
        "Deliverable G — Player Retention & Monetization Framework",
    ),
    (
        "H_Preliminary_Game_Idea_Evaluation.md",
        "Deliverable H — Preliminary Game Idea Evaluation",
    ),
    ("I_Alternative_Game_Concepts.md", "Deliverable I — Alternative Game Concepts"),
    ("J_Concept_Decision_Matrix.md", "Deliverable J — Concept Decision Matrix"),
    (
        "K_Prototype_Roadmap_Validation_and_Risks.md",
        "Deliverable K — Prototype Roadmap, Validation, Analytics & Risk Assessment",
    ),
    ("L_Financial_Feasibility_Report.md", "Deliverable L — Financial Feasibility Report"),
    ("M_Launch_and_Growth_Strategy.md", "Deliverable M — Launch and Growth Strategy"),
    (
        "N_Founder_Cheat_Sheet_and_Recommendations.md",
        "Deliverable N — Founder Cheat Sheet & Final Strategic Recommendation",
    ),
)


def _slugify(title: str) -> str:
    """Create GitHub-compatible Markdown anchor slug."""
    cleaned = "".join(ch.lower() if ch.isalnum() or ch in (" ", "-") else "" for ch in title)
    return "-".join(cleaned.split())


def verify_deliverables_present(deliverables_dir: Path) -> list[tuple[Path, str]]:
    """Verify all 14 deliverable Markdown files exist and are non-empty."""
    resolved: list[tuple[Path, str]] = []
    for filename, label in DELIVERABLE_MANIFEST:
        path = deliverables_dir / filename
        if not path.exists():
            raise ResearchDataError(f"Missing required deliverable file: {path}")
        if not path.read_text(encoding="utf-8").strip():
            raise ResearchDataError(f"Deliverable file is empty: {path}")
        resolved.append((path, label))
    return resolved


def render_sources_appendix(sources_path: Path | None) -> str:
    """Render centralized sources_registry.json as a Markdown appendix table."""
    if sources_path is None or not sources_path.exists():
        return ""
    sources = load_json_file(sources_path)
    lines = [
        "## Appendix: Verified Sources Registry",
        "",
        "| ID | Tier | Publisher | Title | Published | Collected | Reference |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for src in sources:
        pub_date = src.get("publication_date", "Undated")
        lines.append(
            f"| {src['source_id']} | {src['tier']} | {src['publisher']} | "
            f"{src['title']} | {pub_date} | {src['collection_date']} | {src['reference']} |"
        )
    return "\n".join(lines)


def compile_master_report(
    deliverables_dir: Path, output_path: Path, sources_path: Path | None = None
) -> str:
    """Assemble Deliverables A-N and optional sources appendix into one Markdown file."""
    entries = verify_deliverables_present(deliverables_dir)
    toc_lines = [
        "# Roblox Deep Market Research, Discovery Algorithm, Game Design & Commercial Feasibility Report",
        "",
        "**Collection Date:** 2026-11-22  ",
        "**Primary Anchor Profile:** Solo Indie Developer (Zero / Small Budget) + Multi-Scenario Comparisons  ",
        "**Scope:** Independent Market Discovery (Blind Phase) → Critical Evaluation of `GameIdea.txt` → Alternative Concepts, Validation & Financial Feasibility",
        "",
        "## Table of Contents",
        "",
    ]
    for _, label in entries:
        toc_lines.append(f"- [{label}](#{_slugify(label)})")
    if sources_path and sources_path.exists():
        toc_lines.append("- [Appendix: Verified Sources Registry](#appendix-verified-sources-registry)")

    sections = ["\n".join(toc_lines)]
    for path, _ in entries:
        sections.append("\n---\n\n" + path.read_text(encoding="utf-8").strip())
    appendix = render_sources_appendix(sources_path)
    if appendix:
        sections.append("\n---\n\n" + appendix)

    compiled = "\n\n".join(sections) + "\n"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(compiled, encoding="utf-8")
    return compiled


def main() -> int:
    """CLI entrypoint for compiling the master research report."""
    parser = argparse.ArgumentParser(description="Compile Roblox research deliverables.")
    parser.add_argument("--deliverables-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sources", type=Path, default=None)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        text = compile_master_report(args.deliverables_dir, args.output, args.sources)
        if args.verify:
            for _, label in DELIVERABLE_MANIFEST:
                if label.split("—")[0].strip() not in text:
                    raise ResearchDataError(f"Compiled output missing heading for {label}")
        print(f"COMPILED: {args.output} ({len(text):,} chars across {len(DELIVERABLE_MANIFEST)} deliverables).")
        return 0
    except ResearchDataError as exc:
        print(f"COMPILE ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
