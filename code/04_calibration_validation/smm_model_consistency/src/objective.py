from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd


def align_moments(data_moments: pd.DataFrame, model_moments: pd.DataFrame, cfg: dict[str, Any]) -> pd.DataFrame:
    objective = list(cfg.get("moments", {}).get("objective", []) or [])
    if not objective:
        raise ValueError("No causal-core objective moments configured at cfg['moments']['objective'].")

    data_names = set(data_moments["moment"]) if "moment" in data_moments.columns else set()
    model_names = set(model_moments["moment"]) if "moment" in model_moments.columns else set()
    missing_data = sorted(set(objective) - data_names)
    missing_model = sorted(set(objective) - model_names)
    if missing_data or missing_model:
        raise ValueError(f"Missing objective moments. data={missing_data}; model={missing_model}")

    data_cols = [c for c in ["moment", "kind", "value", "se", "role", "moment_group", "notes"] if c in data_moments.columns]
    model_cols = [c for c in ["moment", "kind", "value", "se", "role", "moment_group", "notes"] if c in model_moments.columns]
    d = data_moments[data_cols].rename(
        columns={"kind": "data_kind", "value": "data", "se": "data_se", "notes": "data_notes"}
    )
    m = model_moments[model_cols].rename(
        columns={
            "kind": "model_kind",
            "value": "model",
            "se": "model_se",
            "role": "model_role",
            "moment_group": "model_moment_group",
            "notes": "model_notes",
        }
    )
    table = d.merge(m, on="moment", how="outer")
    if "role" not in table.columns:
        table["role"] = table.get("model_role", "other_diagnostic")
    else:
        table["role"] = table["role"].fillna(table.get("model_role", "other_diagnostic"))
    if "moment_group" not in table.columns:
        table["moment_group"] = table["role"]
    else:
        table["moment_group"] = table["moment_group"].fillna(table.get("model_moment_group", table["role"]))
    table["in_objective"] = table["moment"].isin(objective)
    table["gap"] = table["data"] - table["model"]
    min_scale = float(cfg["estimation"].get("weight_min_scale", 0.05))
    scale = table["data_se"].abs()
    scale = scale.where(np.isfinite(scale) & (scale > min_scale), table["data"].abs())
    scale = scale.where(np.isfinite(scale) & (scale > min_scale), min_scale)
    table["weight"] = 1.0 / np.square(scale)
    multipliers = cfg["estimation"].get("moment_weight_multipliers", {})
    table["weight_multiplier"] = table["moment"].map(lambda m: float(multipliers.get(m, 1.0)))
    table["weight"] = table["weight"] * table["weight_multiplier"]
    table = table.replace([np.inf, -np.inf], np.nan)

    objective_rows = table.loc[table["in_objective"]].copy()
    bad_role = objective_rows.loc[objective_rows["role"].ne("causal_core"), "moment"].tolist()
    if bad_role:
        raise ValueError(f"Non-causal diagnostics entered the criterion: {bad_role}")
    missing_values = objective_rows.loc[objective_rows[["data", "model", "gap", "weight"]].isna().any(axis=1), "moment"].tolist()
    if missing_values:
        raise ValueError(f"Objective moments have missing data/model/gap/weight values: {missing_values}")
    return table


def criterion(moment_table: pd.DataFrame) -> float:
    if moment_table.empty or "in_objective" not in moment_table.columns:
        return 1.0e12
    use = moment_table.loc[moment_table["in_objective"]].copy()
    if use.empty:
        return 1.0e12
    bad_role = use.loc[use["role"].ne("causal_core"), "moment"].tolist()
    if bad_role:
        raise ValueError(f"Non-causal diagnostics entered the criterion: {bad_role}")
    q = float(np.sum(use["weight"] * np.square(use["gap"])))
    if not np.isfinite(q):
        return 1.0e12
    return q
