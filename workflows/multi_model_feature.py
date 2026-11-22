"""Cross-platform Antigravity multi-model feature workflow for Ball Brawl: Boss Eggs.

Run via Antigravity's `run_workflow` tool:
  ScriptPath="/abs/path/to/workflows/multi_model_feature.py"
  Args={"feature": "Implement ArenaCycleService 3-phase state machine"}
"""

import sys

PY = sys.executable or "python3"
feature = args.get("feature", "").strip()
if not feature:
    raise ValueError("args['feature'] is required")

phase("1. Tech Director Plan (Gemini)")
plan = await agent(
    f"Read docs/GameIdea_Evolved_GDD.md and AGENTS.md. Produce a concise implementation plan for:\n"
    f"{feature}\n"
    f"Specify exact files under game/src/ and game/tests/ plus edge cases to test.",
    schema={
        "type": "object",
        "properties": {
            "summary": {"type": "string"},
            "luau_files": {"type": "array", "items": {"type": "string"}},
            "test_files": {"type": "array", "items": {"type": "string"}},
            "blender_assets": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["summary", "luau_files", "test_files"],
    },
    role="Tech Director (Gemini)",
    model="pro",
)
log("Plan:", plan["summary"])

phase("2. Test-First & Implementation (Codex + Claude)")
test_prompt = (
    f"Follow AGENTS.md. Write failing-then-passing Lune specs in {plan['test_files']} "
    f"for feature: {feature}. Plan: {plan['summary']}"
)
impl_prompt = (
    f"Follow CLAUDE.md and AGENTS.md. Implement strict server-authoritative Luau modules "
    f"in {plan['luau_files']} for feature: {feature}. Plan: {plan['summary']}. "
    f"Run `python scripts/check.py` before finishing."
)

codex_out = await call_tool(
    "run_command",
    CommandLine=f"{PY} scripts/dispatch_cli.py codex {test_prompt!r}",
    WaitMsBeforeAsync=10000,
    toolSummary="Codex Lune spec authoring",
)
log("Codex tests output:", codex_out[:600])

claude_out = await call_tool(
    "run_command",
    CommandLine=f"{PY} scripts/dispatch_cli.py claude {impl_prompt!r}",
    WaitMsBeforeAsync=10000,
    toolSummary="Claude server Luau implementation",
)
log("Claude impl output:", claude_out[:600])

phase("3. Automated Gate & Visual/Security QA (Gemini)")
gate_out = await call_tool(
    "run_command",
    CommandLine=f"{PY} scripts/check.py",
    WaitMsBeforeAsync=10000,
    toolSummary="Run automated Roblox check gate",
)
log("Gate result:", gate_out)

review = await agent(
    f"Audit the modified files for '{feature}' against AGENTS.md security invariants "
    f"(server authority, PvP phase guard, PolicyService) and confirm `python scripts/check.py` passed.",
    schema={"type": "string"},
    role="Security & QA Reviewer (Gemini)",
    model="pro",
)
log("QA Review:", review)
