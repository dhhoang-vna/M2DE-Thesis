from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from scipy.optimize import minimize

from .model import Theta, vector_from_config
from .moments_data import compute_data_moments
from .moments_model import compute_model_moments
from .objective import align_moments, criterion


def estimate_theta(panel: pd.DataFrame, cfg: dict[str, Any]) -> dict[str, Any]:
    data_moments = compute_data_moments(panel, cfg)
    start, bounds, order = vector_from_config(cfg)
    history: list[dict[str, float]] = []

    def obj(vec: np.ndarray) -> float:
        theta = Theta.from_vector(vec, order, cfg)
        try:
            model_moments, _ = compute_model_moments(panel, theta, cfg)
            mt = align_moments(data_moments, model_moments, cfg)
            q = criterion(mt)
        except Exception as exc:
            print(f"Objective failed at {vec}: {exc}")
            q = 1.0e12
        history.append({"objective": q, **{name: float(vec[i]) for i, name in enumerate(order)}})
        print(f"SMM objective {q:.6g}")
        return q

    result = minimize(
        obj,
        start,
        method="L-BFGS-B",
        bounds=bounds,
        options={
            "maxiter": int(cfg["estimation"]["maxiter"]),
            "maxfun": int(cfg["estimation"].get("maxfun", 80)),
            "ftol": float(cfg["estimation"]["ftol"]),
        },
    )
    theta = Theta.from_vector(result.x, order, cfg)
    model_moments, sim = compute_model_moments(panel, theta, cfg)
    mt = align_moments(data_moments, model_moments, cfg)
    return {
        "theta": theta,
        "result": result,
        "history": pd.DataFrame(history),
        "data_moments": data_moments,
        "model_moments": model_moments,
        "moment_table": mt,
        "simulated_panel": sim,
    }
