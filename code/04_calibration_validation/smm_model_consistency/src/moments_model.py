from __future__ import annotations

from typing import Any

import pandas as pd

from .model import Theta
from .moments_data import compute_moments
from .simulate import simulate_panel


def compute_model_moments(panel: pd.DataFrame, theta: Theta, cfg: dict[str, Any]) -> tuple[pd.DataFrame, pd.DataFrame]:
    sim = simulate_panel(panel, theta, cfg, scenario="observed")
    moments = compute_moments(
        sim,
        cfg,
        y_col="dln_mu_model",
        inv_col="inv_mu_model",
        share_col="share_model",
        exit_col="exit_prob_model",
        label="model",
        use_stata_sector_moments=False,
    )
    return moments, sim

