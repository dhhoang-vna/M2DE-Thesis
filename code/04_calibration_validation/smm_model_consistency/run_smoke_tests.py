from __future__ import annotations

import argparse

import numpy as np

from src.config import load_config
from src.data import load_panel
from src.model import Theta, vector_from_config
from src.moments_model import compute_model_moments
from src.simulate import simulate_panel


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()

    cfg = load_config(args.config)
    panel = load_panel(cfg)
    start, _, order = vector_from_config(cfg)
    theta = Theta.from_vector(start, order, cfg)
    sim = simulate_panel(panel, theta, cfg, scenario="observed")

    required = [
        "dln_mu_model",
        "share_model",
        "inv_mu_model",
        "output_markup_effect_model",
        "high_markup_output_effect_model",
        "concentration_output_effect_model",
    ]
    missing = [col for col in required if col not in sim.columns]
    if missing:
        raise AssertionError(f"Missing simulated columns: {missing}")

    share_sums = sim.groupby(["isic4", "year"])["share_model"].sum()
    if not np.allclose(share_sums.to_numpy(dtype=float), 1.0, atol=1.0e-8):
        raise AssertionError("Model shares do not sum to one within sector-year.")

    inv = sim["inv_mu_model"].to_numpy(dtype=float)
    if not np.isfinite(inv).all() or np.nanmin(inv) <= 0.0 or np.nanmax(inv) >= 1.0:
        raise AssertionError("Model inverse markups must remain inside the unit interval.")

    moments, _ = compute_model_moments(panel, theta, cfg)
    baseline = moments.loc[moments["moment"] == "baseline_iv_dln_mu", "value"].iloc[0]
    q90 = moments.loc[moments["moment"] == "grouped_iv_q90", "value"].iloc[0]
    print(f"Smoke tests passed on {len(panel):,} firm-years.")
    print(f"Starting-vector model IV: baseline={baseline:.3f}, q90={q90:.3f}.")


if __name__ == "__main__":
    main()
