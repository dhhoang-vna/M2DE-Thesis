from __future__ import annotations

import argparse

import pandas as pd

from src.config import get_path, load_config
from src.counterfactuals import run_counterfactuals
from src.data import load_panel
from src.model import Theta
from src.plots import plot_counterfactual_aggregate, plot_decomposition


def load_theta(cfg) -> Theta:
    path = get_path(cfg, "outputs") / "estimated_parameters.csv"
    params = pd.read_csv(path)
    values = params.loc[params["status"] == "estimated"].set_index("parameter")["value"].to_dict()
    missing = sorted(set(cfg["estimation"]["estimated_parameters"]) - set(values))
    if missing:
        raise ValueError(f"Estimated parameters are stale or incomplete. Missing {missing}. Run run_estimation.py first.")
    return Theta.from_mapping({k: float(v) for k, v in values.items()}, cfg)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()
    cfg = load_config(args.config)
    panel = load_panel(cfg)
    theta = load_theta(cfg)
    results = run_counterfactuals(panel, theta, cfg)
    outdir = get_path(cfg, "outputs")
    figdir = get_path(cfg, "figures")
    results["aggregate"].to_csv(outdir / "counterfactual_aggregate_results.csv", index=False)
    results["sector"].to_csv(outdir / "counterfactual_sector_results.csv", index=False)
    results["decomposition"].to_csv(outdir / "counterfactual_decomposition_tables.csv", index=False)
    results["manufacturing_decomposition"].to_csv(outdir / "counterfactual_manufacturing_decomposition.csv", index=False)
    results["allocative_wedge"].to_csv(outdir / "counterfactual_allocative_wedge.csv", index=False)
    plot_counterfactual_aggregate(results["aggregate"], figdir / "counterfactual_manufacturing_inverse_markup.png")
    plot_decomposition(results["decomposition"], figdir / "counterfactual_decomposition_components.png")
    label = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
    print(f"{label.capitalize()} written to {outdir}.")


if __name__ == "__main__":
    main()
