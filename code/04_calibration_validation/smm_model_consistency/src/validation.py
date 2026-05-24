from __future__ import annotations

from typing import Any

import pandas as pd

from .iv import iv_2sls, result_to_moment
from .model import Theta
from .simulate import simulate_panel


def residual_iv_validation_from_sim(sim: pd.DataFrame, cfg: dict[str, Any]) -> pd.DataFrame:
    """Residual IV validation using an already simulated panel."""
    sim = sim.copy()
    sim["model_residual_dln_mu"] = sim["dln_mu"] - sim["dln_mu_model"]
    firm_controls = [c for c in cfg["controls"]["firm"] if c in sim.columns]
    fe = [c for c in cfg["controls"]["fixed_effects"] if c in sim.columns]
    cluster = cfg["controls"].get("cluster")
    cluster = cluster if cluster in sim.columns else None
    res = iv_2sls(
        sim,
        "model_residual_dln_mu",
        "change_IP",
        "output_IV",
        firm_controls,
        fe,
        cluster,
        name="acd_residual_iv",
    )
    out = pd.DataFrame([result_to_moment(res, "change_IP", "residual_iv_validation", "iv")])
    out["interpretation"] = (
        "Residual IV coefficient tests whether the causal-core incumbent-markup model absorbs the "
        "output-shock markup variation; small/insignificant values mean residuals no longer load on the excluded output shifter."
    )
    return out


def residual_iv_validation(panel: pd.DataFrame, theta: Theta, cfg: dict[str, Any]) -> pd.DataFrame:
    sim = simulate_panel(panel, theta, cfg, scenario="observed")
    return residual_iv_validation_from_sim(sim, cfg)
