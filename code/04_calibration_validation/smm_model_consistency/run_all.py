from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import pandas as pd

from src.config import get_path, load_config
from src.counterfactuals import run_counterfactuals
from src.data import load_panel
from src.estimate import estimate_theta
from src.objective import criterion
from src.plots import plot_counterfactual_aggregate, plot_decomposition, plot_moment_fit
from src.validation import residual_iv_validation


def _markdown_table(df: pd.DataFrame, cols: list[str], float_digits: int = 4) -> str:
    if df.empty:
        return "_No rows._"
    work = df.loc[:, [c for c in cols if c in df.columns]].copy()
    for col in work.columns:
        if pd.api.types.is_numeric_dtype(work[col]):
            work[col] = work[col].map(lambda x: "" if pd.isna(x) else f"{float(x):.{float_digits}f}")
        else:
            work[col] = work[col].fillna("").astype(str)
    header = "| " + " | ".join(work.columns) + " |"
    sep = "| " + " | ".join(["---"] * len(work.columns)) + " |"
    rows = ["| " + " | ".join(map(str, row)) + " |" for row in work.to_numpy()]
    return "\n".join([header, sep] + rows)


def _write_estimation_outputs(est: dict[str, Any], cfg: dict[str, Any]) -> tuple[pd.DataFrame, pd.DataFrame, float]:
    outdir = get_path(cfg, "outputs")
    figdir = get_path(cfg, "figures")
    theta = est["theta"]
    q = criterion(est["moment_table"])
    mt_all = est["moment_table"].assign(objective=q)
    mt_objective = mt_all.loc[mt_all["in_objective"]].copy()

    theta.to_frame(cfg).to_csv(outdir / "estimated_parameters.csv", index=False)
    est["data_moments"].to_csv(outdir / "data_moments_all.csv", index=False)
    est["model_moments"].to_csv(outdir / "model_moments_all.csv", index=False)
    mt_all.to_csv(outdir / "moment_gaps_all.csv", index=False)
    mt_objective.to_csv(outdir / "moment_gaps_objective.csv", index=False)
    est["data_moments"].to_csv(outdir / "data_moments.csv", index=False)
    est["model_moments"].to_csv(outdir / "model_moments.csv", index=False)
    mt_all.to_csv(outdir / "moment_gaps.csv", index=False)
    est["history"].to_csv(outdir / "objective_history.csv", index=False)
    Path(outdir / "objective_value.csv").write_text(f"objective,value\nQ,{q:.12g}\n", encoding="utf-8")

    keep = [
        "firm_id",
        "isic4",
        "year",
        "dln_mu",
        "dln_mu_model",
        "output_markup_effect_model",
        "high_markup_output_effect_model",
        "concentration_output_effect_model",
        "mu_model",
        "inv_mu_model",
        "share_model",
        "exit_prob_model",
        "survival_prob_model",
        "change_IP",
        "output_IV",
        "Z_input",
    ]
    est["simulated_panel"][[c for c in keep if c in est["simulated_panel"].columns]].to_csv(
        outdir / "model_panel_estimated.csv", index=False
    )
    plot_moment_fit(mt_objective, figdir / "data_vs_model_objective_moments.png")
    plot_moment_fit(mt_all, figdir / "data_vs_model_all_moments.png")
    return mt_all, mt_objective, q


def _write_counterfactual_outputs(results: dict[str, pd.DataFrame], cfg: dict[str, Any]) -> None:
    outdir = get_path(cfg, "outputs")
    figdir = get_path(cfg, "figures")
    results["aggregate"].to_csv(outdir / "counterfactual_aggregate_results.csv", index=False)
    results["sector"].to_csv(outdir / "counterfactual_sector_results.csv", index=False)
    results["decomposition"].to_csv(outdir / "counterfactual_decomposition_tables.csv", index=False)
    results["manufacturing_decomposition"].to_csv(outdir / "counterfactual_manufacturing_decomposition.csv", index=False)
    results["allocative_wedge"].to_csv(outdir / "counterfactual_allocative_wedge.csv", index=False)
    plot_counterfactual_aggregate(results["aggregate"], figdir / "counterfactual_manufacturing_inverse_markup.png")
    plot_decomposition(results["decomposition"], figdir / "counterfactual_decomposition_components.png")


def _write_report(
    panel: pd.DataFrame,
    cfg: dict[str, Any],
    mt_all: pd.DataFrame,
    mt_objective: pd.DataFrame,
    q: float,
    params: pd.DataFrame,
    validation: pd.DataFrame,
) -> None:
    outdir = get_path(cfg, "outputs")
    diagnostics = mt_all.loc[~mt_all["in_objective"]].copy()
    lines = [
        "# Causal-Core SMM Run Report",
        "",
        "This run estimates a causal-core incumbent markup mechanism model. The SMM objective uses only output-competition IV moments.",
        "",
        "Input, decomposition, and exit moments are diagnostics only. They are not causal-core SMM targets.",
        "",
        "## Sample",
        "",
        f"- Firm-years: {len(panel):,}",
        f"- Firms: {panel['firm_id'].nunique():,}" if "firm_id" in panel.columns else "- Firms: unavailable",
        f"- Sectors: {panel['isic4'].nunique():,}" if "isic4" in panel.columns else "- Sectors: unavailable",
        f"- Years: {int(panel['year'].min())}-{int(panel['year'].max())}" if "year" in panel.columns else "- Years: unavailable",
        "",
        "## Objective Moments",
        "",
        _markdown_table(mt_objective, ["moment", "data", "model", "gap", "weight"]),
        "",
        "## Diagnostic Moments",
        "",
        _markdown_table(diagnostics, ["moment", "role", "data", "model", "gap"]),
        "",
        "## Objective Value",
        "",
        f"`Q = {q:.6g}`",
        "",
        "## Estimated Parameters",
        "",
        _markdown_table(params, ["parameter", "value", "status"]),
        "",
        "## Residual IV Validation",
        "",
        _markdown_table(validation, ["moment", "value", "se", "nobs", "nclusters", "first_stage_f", "interpretation"]),
        "",
        "## Interpretation Warning",
        "",
        "The counterfactuals are output-competition counterfactuals, not welfare effects. Do not interpret input, decomposition, or exit diagnostics as causal SMM targets until a richer share-transition or selection block is built.",
        "",
    ]
    Path(outdir / "run_report.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config_causal_core.yaml")
    args = parser.parse_args()

    cfg = load_config(args.config)
    panel = load_panel(cfg)
    print(f"Loaded panel: {len(panel):,} firm-years, {panel['isic4'].nunique():,} sectors.")

    est = estimate_theta(panel, cfg)
    mt_all, mt_objective, q = _write_estimation_outputs(est, cfg)

    validation = residual_iv_validation(panel, est["theta"], cfg)
    validation.to_csv(get_path(cfg, "outputs") / "residual_iv_validation.csv", index=False)

    counterfactuals = run_counterfactuals(panel, est["theta"], cfg)
    _write_counterfactual_outputs(counterfactuals, cfg)

    params = est["theta"].to_frame(cfg)
    _write_report(panel, cfg, mt_all, mt_objective, q, params, validation)
    print(f"Completed causal-core run. Objective = {q:.6g}. Report written to {get_path(cfg, 'outputs') / 'run_report.md'}.")


if __name__ == "__main__":
    main()
