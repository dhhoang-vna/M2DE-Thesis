from __future__ import annotations

from dataclasses import dataclass
from dataclasses import fields
from typing import Any

import numpy as np
import pandas as pd


@dataclass
class Theta:
    output_scale: float
    output_markup: float
    high_markup_output: float
    concentration_output: float
    share_output: float
    share_input: float
    input_markup: float
    mean_reversion: float
    drift: float
    exit_intercept: float
    exit_ip: float
    exit_markup: float

    @classmethod
    def from_vector(cls, values: np.ndarray, order: list[str], cfg: dict[str, Any] | None = None) -> "Theta":
        mapping = {name: float(values[i]) for i, name in enumerate(order)}
        if cfg is None:
            return cls(**mapping)
        return cls.from_mapping(mapping, cfg)

    @classmethod
    def from_mapping(cls, values: dict[str, float], cfg: dict[str, Any]) -> "Theta":
        est = cfg.get("estimation", {})
        starts = est.get("start", {})
        fixed = est.get("fixed_parameters", {})
        mapped: dict[str, float] = {}
        for field in fields(cls):
            if field.name in values:
                mapped[field.name] = float(values[field.name])
            elif field.name in fixed:
                mapped[field.name] = float(fixed[field.name])
            elif field.name in starts:
                mapped[field.name] = float(starts[field.name])
            else:
                raise KeyError(f"Missing structural parameter: {field.name}")
        return cls(**mapped)

    def to_frame(self, cfg: dict[str, Any]) -> pd.DataFrame:
        estimated = set(cfg.get("estimation", {}).get("estimated_parameters", cfg.get("estimation", {}).get("parameter_order", [])))
        fixed = set(cfg.get("estimation", {}).get("fixed_parameters", {}).keys())
        rows = []
        for k, v in self.__dict__.items():
            status = "estimated" if k in estimated else "fixed"
            if k in fixed:
                status = "fixed"
            rows.append({"parameter": k, "value": v, "status": status})
        for k, v in cfg["elasticities"].items():
            rows.append({"parameter": k, "value": v, "status": "fixed_elasticity"})
        return pd.DataFrame(rows)


def vector_from_config(cfg: dict[str, Any]) -> tuple[np.ndarray, list[tuple[float, float]], list[str]]:
    order = list(cfg["estimation"].get("estimated_parameters", cfg["estimation"]["parameter_order"]))
    start = np.array([cfg["estimation"]["start"][name] for name in order], dtype=float)
    bounds = [tuple(cfg["estimation"]["bounds"][name]) for name in order]
    return start, bounds, order


def nested_ces_inverse_markup(
    share_total: np.ndarray,
    lambda_d: np.ndarray,
    eta: float,
    nu: float,
    rho: float,
) -> np.ndarray:
    lambda_safe = np.clip(lambda_d, 1.0e-4, 1.0)
    base = 1.0 - 1.0 / rho
    slope = (1.0 / lambda_safe) * (1.0 / nu - 1.0 / rho) + (1.0 / eta - 1.0 / nu)
    inv = base - slope * share_total
    return np.clip(inv, 0.02, 0.98)


def logistic(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, -40.0, 40.0)
    return 1.0 / (1.0 + np.exp(-x))
