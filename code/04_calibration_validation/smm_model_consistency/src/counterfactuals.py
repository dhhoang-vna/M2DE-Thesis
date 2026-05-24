from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from .data import manufacturing_panel, sector_panel
from .decomposition import decompose_inverse_markup, manufacturing_decomposition
from .model import Theta
from .simulate import simulate_panel


def allocative_wedge(panel: pd.DataFrame, mu_col: str = "mu_model", share_col: str = "share_model") -> pd.DataFrame:
    work = panel.copy()
    work["_w"] = work[share_col].where(work[share_col] > 0, np.nan)
    work["_lnmu"] = np.log(work[mu_col].where(work[mu_col] > 0, np.nan))

    def _weighted_var(g: pd.DataFrame) -> float:
        w = g["_w"].to_numpy(dtype=float)
        x = g["_lnmu"].to_numpy(dtype=float)
        ok = np.isfinite(w) & np.isfinite(x) & (w > 0)
        if ok.sum() == 0:
            return np.nan
        w = w[ok] / w[ok].sum()
        x = x[ok]
        mean = float(np.sum(w * x))
        return float(np.sum(w * np.square(x - mean)))

    out = work.groupby(["isic4", "year"]).apply(_weighted_var, include_groups=False).reset_index(name="markup_dispersion_wedge")
    return out


def run_counterfactuals(panel: pd.DataFrame, theta: Theta, cfg: dict[str, Any]) -> dict[str, pd.DataFrame]:
    scenarios = cfg["counterfactuals"].get("scenarios", ["observed", "no_output"])
    aggregate_rows: list[pd.DataFrame] = []
    sector_rows: list[pd.DataFrame] = []
    decomp_rows: list[pd.DataFrame] = []
    mdecomp_rows: list[pd.DataFrame] = []
    wedge_rows: list[pd.DataFrame] = []

    for scenario in scenarios:
        sim = simulate_panel(panel, theta, cfg, scenario=scenario)
        sec = sector_panel(sim, inv_col="inv_mu_model", share_col="share_model", dln_col="dln_mu_model")

        # Simple aggregation layer only: sector domestic-sales weights respond mechanically
        # to counterfactual output-competition shock removal, not through a solved GE system.
        if scenario != "observed":
            eo = float(cfg["counterfactuals"].get("sector_sales_output_elasticity", -0.20))
            ei = float(cfg["counterfactuals"].get("sector_sales_input_elasticity", 0.10))
            shock_sec = sim.groupby(["isic4", "year"], as_index=False).agg(
                observed_output_shock=("change_IP", "mean"),
                observed_input_shock=("Z_input", "mean"),
                output_shock_model=("output_shock_model", "mean"),
                input_shock_model=("input_shock_model", "mean"),
            )
            sec = sec.merge(shock_sec, on=["isic4", "year"], how="left")
            delta_output = sec["output_shock_model"].fillna(0.0) - sec["observed_output_shock"].fillna(0.0)
            delta_input = sec["input_shock_model"].fillna(0.0) - sec["observed_input_shock"].fillna(0.0)
            sec["dom_j"] = sec["dom_j"] * np.exp(eo * delta_output + ei * delta_input)
            sec["S_jt"] = sec["dom_j"] / sec.groupby("year")["dom_j"].transform("sum").replace(0.0, np.nan)
        agg = manufacturing_panel(sec)
        agg["counterfactual_label"] = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
        agg["scenario"] = scenario
        sec["counterfactual_label"] = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
        sec["scenario"] = scenario
        comp = decompose_inverse_markup(sim, inv_col="inv_mu_model", share_col="share_model")
        comp["counterfactual_label"] = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
        comp["scenario"] = scenario
        mcomp = manufacturing_decomposition(sec)
        mcomp["counterfactual_label"] = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
        mcomp["scenario"] = scenario
        wedge = allocative_wedge(sim)
        wedge["counterfactual_label"] = cfg.get("counterfactuals", {}).get("label", "output-competition counterfactuals")
        wedge["scenario"] = scenario

        aggregate_rows.append(agg)
        sector_rows.append(sec)
        decomp_rows.append(comp)
        mdecomp_rows.append(mcomp)
        wedge_rows.append(wedge)

    aggregate = pd.concat(aggregate_rows, ignore_index=True)
    sector = pd.concat(sector_rows, ignore_index=True)
    decomposition = pd.concat(decomp_rows, ignore_index=True)
    manufacturing_decomp = pd.concat(mdecomp_rows, ignore_index=True)
    wedge = pd.concat(wedge_rows, ignore_index=True)
    return {
        "aggregate": aggregate,
        "sector": sector,
        "decomposition": decomposition,
        "manufacturing_decomposition": manufacturing_decomp,
        "allocative_wedge": wedge,
    }
