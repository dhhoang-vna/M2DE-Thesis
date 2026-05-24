from __future__ import annotations

import argparse

import pandas as pd

from src.config import get_path, load_config
from src.data import load_panel
from src.model import Theta
from src.validation import residual_iv_validation


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
    table = residual_iv_validation(panel, theta, cfg)
    table.to_csv(get_path(cfg, "outputs") / "residual_iv_validation.csv", index=False)
    print(table.to_string(index=False))


if __name__ == "__main__":
    main()
