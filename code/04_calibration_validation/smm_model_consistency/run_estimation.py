from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from src.config import get_path, load_config
from src.data import load_panel
from src.estimate import estimate_theta
from src.objective import criterion
from src.plots import plot_moment_fit


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()

    cfg = load_config(args.config)
    outdir = get_path(cfg, "outputs")
    figdir = get_path(cfg, "figures")

    if cfg["estimation"].get("reuse_existing", False):
        moment_path = outdir / "moment_gaps_all.csv"
        theta_path = outdir / "estimated_parameters.csv"
        if moment_path.exists() and theta_path.exists():
            params = pd.read_csv(theta_path)
            existing = set(params.loc[params["status"] == "estimated", "parameter"])
            required = set(cfg["estimation"]["estimated_parameters"])
            if existing == required:
                mt = pd.read_csv(moment_path)
                plot_moment_fit(mt.loc[mt["in_objective"]], figdir / "data_vs_model_objective_moments.png")
                plot_moment_fit(mt, figdir / "data_vs_model_all_moments.png")
                print(f"Existing estimation outputs found in {outdir}; regenerated diagnostics. Set reuse_existing: false to re-estimate.")
                return
            missing = sorted(required - existing)
            extra = sorted(existing - required)
            print(f"Existing estimates are stale for this specification. Missing={missing}; extra={extra}. Re-estimating.")

    panel = load_panel(cfg)
    print(f"Loaded panel: {len(panel):,} firm-years, {panel['isic4'].nunique():,} sectors.")
    est = estimate_theta(panel, cfg)
    theta = est["theta"]
    q = criterion(est["moment_table"])
    mt_all = est["moment_table"].assign(objective=q)
    mt_objective = mt_all.loc[mt_all["in_objective"]].copy()

    theta.to_frame(cfg).to_csv(outdir / "estimated_parameters.csv", index=False)
    est["data_moments"].to_csv(outdir / "data_moments_all.csv", index=False)
    est["model_moments"].to_csv(outdir / "model_moments_all.csv", index=False)
    mt_all.to_csv(outdir / "moment_gaps_all.csv", index=False)
    mt_objective.to_csv(outdir / "moment_gaps_objective.csv", index=False)
    # Backward-compatible aliases for older notebooks/scripts.
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
    plot_moment_fit(mt_all, figdir / "data_vs_model_moments.png")
    print(f"Finished SMM. Objective = {q:.6g}. Outputs written to {outdir}.")


if __name__ == "__main__":
    main()
