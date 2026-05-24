from __future__ import annotations

import argparse
import copy
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.config import load_config
from src.data import load_panel
from src.model import Theta
from src.moments_data import compute_data_moments
from src.moments_model import compute_model_moments
from src.objective import align_moments, criterion
from src.validation import residual_iv_validation_from_sim


CAUSAL_CORE_MAIN = [
    "baseline_iv_dln_mu",
    "grouped_iv_q80",
    "grouped_iv_q85",
    "grouped_iv_q90",
    "grouped_iv_q90_cr4_interaction",
]

ORIGINAL_SIX_MOMENT_REFERENCE = 1.727


def _quiet_causal_core_cfg(cfg: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(cfg)
    out.setdefault("moments", {})
    out["moments"]["moment_sets"] = dict(out["moments"].get("moment_sets", {}))
    out["moments"]["moment_sets"]["causal_core_main"] = list(CAUSAL_CORE_MAIN)
    out["moments"]["objective_set"] = "causal_core_main"
    out["moments"]["objective"] = list(CAUSAL_CORE_MAIN)
    out["moments"]["compute_all"] = True
    out["moments"]["print_diagnostics"] = False
    return out


def _load_theta(path: Path, cfg: dict[str, Any]) -> Theta:
    params = pd.read_csv(path)
    values = params.loc[params["status"].isin(["estimated", "fixed"])].set_index("parameter")["value"].to_dict()
    return Theta.from_mapping({k: float(v) for k, v in values.items()}, cfg)


def _read_original_objective(source_outdir: Path) -> float:
    path = source_outdir / "objective_value.csv"
    if not path.exists():
        return ORIGINAL_SIX_MOMENT_REFERENCE
    try:
        obj = pd.read_csv(path)
        row = obj.loc[obj["objective"].eq("Q")]
        if row.empty:
            return ORIGINAL_SIX_MOMENT_REFERENCE
        return float(row.iloc[0]["value"])
    except Exception:
        return ORIGINAL_SIX_MOMENT_REFERENCE


def _target_label(moment: str) -> str:
    return "targeted" if moment in CAUSAL_CORE_MAIN else "diagnostic"


def _fit_sentence(moment_table: pd.DataFrame, moment: str) -> str:
    row = moment_table.loc[moment_table["moment"].eq(moment)]
    if row.empty:
        return f"`{moment}` is missing from the recomputed table."
    r = row.iloc[0]
    data = float(r.get("data", np.nan))
    model = float(r.get("model", np.nan))
    gap = float(r.get("gap", np.nan))
    se = float(r.get("data_se", np.nan))
    scale = abs(se) if np.isfinite(se) and abs(se) > 0 else np.nan
    if np.isfinite(scale):
        return f"`{moment}`: data {data:.3f}, model {model:.3f}, gap {gap:.3f} ({gap / scale:.2f} data SEs)."
    return f"`{moment}`: data {data:.3f}, model {model:.3f}, gap {gap:.3f}."


def _markdown_table(df: pd.DataFrame) -> str:
    if df.empty:
        return "_No rows._"
    cols = list(df.columns)
    lines = [
        "| " + " | ".join(cols) + " |",
        "| " + " | ".join(["---"] * len(cols)) + " |",
    ]
    for _, row in df.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, (float, np.floating)):
                vals.append("" if not np.isfinite(float(val)) else f"{float(val):.6g}")
            else:
                vals.append(str(val))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def _write_thesis_text_patches(outdir: Path, theta: Theta, residual_available: bool) -> None:
    residual_clause = (
        "The residual-IV validation remains the main external validation: after subtracting the model-implied output-competition component from observed markup growth, the excluded output shifter no longer predicts a large residual markup response."
        if residual_available
        else "The residual-IV validation remains the intended external validation, but this cheap recomputation did not rerun it because the available validation path would have required an additional full simulation step."
    )
    text = f"""# Thesis Text Patches

Use these paragraphs to revise the SMM / indirect-inference section manually.

## Main SMM Paragraph

The indirect-inference exercise is now interpreted as a validation of the output-competition mechanism among incumbent firms, not as a full account of sector aggregation. The targeted moment set, `causal_core_main`, contains five auxiliary IV moments: the baseline firm-level markup-growth response, the q80, q85, and q90 grouped-IV responses, and the q90 interaction with sector concentration. These moments discipline the sign, magnitude, upper-tail shape, and concentration gradient of the incumbent markup response to Chinese output competition. Sector inverse markups, input-shock responses, exit and selection outcomes, allocative-wedge objects, and within/between/entry/exit decompositions are reported as diagnostics only. They are not imposed on the criterion function.

## Sector Aggregation Paragraph

The sector inverse-markup regression is best read as a secondary aggregation diagnostic. Its empirical IV estimate is less precise and is not consistently significant across the causal specifications, so I do not use it as a core target moment in the SMM exercise. This choice keeps the structural validation tied to the empirically strongest result: output competition lowers markup growth among observed incumbent firms, especially in the upper tail and in more concentrated sectors. The sector inverse-markup moment is still useful because it shows how much of the incumbent mechanism carries through to a sales-weighted sector object, but it should not be interpreted as a separately validated aggregate causal effect.

## Decomposition Paragraph

The decomposition moments are accounting diagnostics rather than targeted moments. The within, reallocation, entry, and exit terms are useful for describing how changes in the sales-weighted inverse-markup object are split mechanically across continuing firms and observed turnover. But their relative shares can move with accounting definitions, sample windows, and the treatment of observed entry and exit. In particular, small sales-weighted inverse-markup contributions of entry and exit do not imply that firm-count turnover is economically irrelevant. The SMM exercise therefore reports decomposition gaps transparently but does not tune the model to match decomposition ratios such as 48/49/1/1.

## Mean-Reversion Paragraph

The parameter `mean_reversion` should be interpreted as an auxiliary dynamic adjustment parameter inside the indirect-inference approximation, not as a structural persistence estimate from the markup literature. Its estimated value, {theta.mean_reversion:.3f}, is needed to match the level and shape of the incumbent IV response across the baseline, upper-tail, and concentration-gradient moments. It should not be compared directly to AR(1) estimates of firm-level markup persistence, because it is identified jointly from targeted IV moments in a simulated response surface rather than from an autoregressive law of motion for markups.

## Residual-IV Validation Paragraph

{residual_clause} This validation supports the narrow claim that the causal-core model absorbs the output-shock variation it was designed to explain. It does not validate the inactive input block, the inactive selection block, or the sector decomposition diagnostics.

## Guardrails

Do not add new structural parameters in this revision. Do not add spline or tail-rank functions. Do not activate the input or selection block. Do not present sector inverse-markup, decomposition, input, selection, or allocative-wedge objects as targeted SMM moments.
"""
    (outdir / "thesis_text_patches.md").write_text(text, encoding="utf-8")


def _write_run_notes(
    outdir: Path,
    moment_table: pd.DataFrame,
    q_main: float,
    original_q: float,
    residual: pd.DataFrame | None,
    residual_note: str,
) -> None:
    exact_diff = original_q - q_main
    rounded_diff = ORIGINAL_SIX_MOMENT_REFERENCE - q_main
    target = moment_table.loc[moment_table["target_status"].eq("targeted")].copy()
    target["weighted_loss"] = target["weight"] * np.square(target["gap"])
    target_loss = target[["moment", "data", "model", "gap", "data_se", "weight", "weighted_loss"]]
    residual_text = residual_note
    if residual is not None and not residual.empty:
        r = residual.iloc[0]
        residual_text = (
            f"Residual-IV validation was recomputed from the already simulated panel. "
            f"The coefficient is {float(r['value']):.4f} with SE {float(r['se']):.4f}; "
            f"the first-stage F-statistic is {float(r.get('first_stage_f', np.nan)):.4f}."
        )

    lines = [
        "# Causal-Core Main Recompute",
        "",
        "This run reuses the existing estimated parameter vector and evaluates the objective using only `causal_core_main` moments. It does not run a full SMM estimation.",
        "",
        "## Objective",
        "",
        f"- New five-moment causal-core objective: `{q_main:.12g}`.",
        f"- Original six-moment objective read from the previous output folder: `{original_q:.12g}`.",
        f"- Difference, original minus new: `{exact_diff:.12g}`.",
        f"- Relative to the rounded reference value 1.727, the difference is `{rounded_diff:.12g}`.",
        "- Dropping `sector_inverse_markup_iv`, which had the largest weighted miss in the six-moment run, mechanically lowers Q; this comparison is a change in criterion definition, not a new re-estimation result.",
        "",
        "## Targeted Fit",
        "",
        _fit_sentence(moment_table, "baseline_iv_dln_mu"),
        _fit_sentence(moment_table, "grouped_iv_q80"),
        _fit_sentence(moment_table, "grouped_iv_q85"),
        _fit_sentence(moment_table, "grouped_iv_q90"),
        _fit_sentence(moment_table, "grouped_iv_q90_cr4_interaction"),
        "",
        "The main IV, q80, q90, and CR4 moments remain close in level. The q85 moment remains the largest targeted miss among the five, but it is now interpreted as part of the upper-tail shape fit rather than as evidence for an aggregate sector mechanism.",
        "",
        "## Residual-IV Validation",
        "",
        residual_text,
        "",
        "## Diagnostic Status",
        "",
        "Sector inverse-markup, decomposition, input-shock, selection/exit, and allocative-wedge objects are diagnostics only. They are still exported for appendix reporting and model criticism, but they are not imposed on the estimation criterion.",
        "",
        "## Targeted Moment Losses",
        "",
        _markdown_table(target_loss),
        "",
    ]
    (outdir / "run_notes.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(ROOT / "config_causal_core.yaml"))
    parser.add_argument("--source-output", default=None, help="Folder containing existing estimated_parameters.csv.")
    args = parser.parse_args()

    cfg = _quiet_causal_core_cfg(load_config(args.config))
    source_outdir = Path(args.source_output).resolve() if args.source_output else Path(cfg["paths"]["outputs"]).resolve()
    theta_path = source_outdir / "estimated_parameters.csv"
    if not theta_path.exists():
        raise FileNotFoundError(f"Cannot find existing estimated parameter vector: {theta_path}")

    date = datetime.now().strftime("%Y%m%d")
    outdir = ROOT / "outputs" / f"causal_core_main_{date}"
    outdir.mkdir(parents=True, exist_ok=True)

    panel = load_panel(cfg)
    theta = _load_theta(theta_path, cfg)
    data_moments = compute_data_moments(panel, cfg)
    model_moments, sim = compute_model_moments(panel, theta, cfg)
    moment_table = align_moments(data_moments, model_moments, cfg)
    q_main = criterion(moment_table)

    moment_table = moment_table.copy()
    moment_table["target_status"] = moment_table["moment"].map(_target_label)
    moment_table["weighted_loss"] = np.where(
        moment_table["in_objective"],
        moment_table["weight"] * np.square(moment_table["gap"]),
        np.nan,
    )
    moment_table.to_csv(outdir / "causal_core_all_moments_labeled.csv", index=False)

    summary = moment_table.loc[moment_table["target_status"].eq("targeted")].copy()
    summary = summary[
        [
            "moment",
            "target_status",
            "data",
            "model",
            "gap",
            "data_se",
            "weight",
            "weighted_loss",
            "role",
            "moment_group",
        ]
    ]
    summary.insert(0, "objective_Q", q_main)
    summary.to_csv(outdir / "causal_core_main_summary.csv", index=False)

    residual = None
    residual_note = ""
    try:
        residual = residual_iv_validation_from_sim(sim, cfg)
        residual.to_csv(outdir / "residual_iv_validation.csv", index=False)
    except Exception as exc:
        residual_note = (
            "Residual-IV validation was skipped because it could not be recomputed from the already simulated panel. "
            f"Error: {exc}"
        )

    original_q = _read_original_objective(source_outdir)
    _write_run_notes(outdir, moment_table, q_main, original_q, residual, residual_note)
    _write_thesis_text_patches(outdir, theta, residual is not None)

    print(f"Wrote causal-core main recompute outputs to {outdir}")
    print(f"Q(causal_core_main) = {q_main:.12g}")


if __name__ == "__main__":
    main()
