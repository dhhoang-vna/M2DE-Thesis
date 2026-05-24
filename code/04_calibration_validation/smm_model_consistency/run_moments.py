from __future__ import annotations

import argparse

from src.config import load_config
from src.data import load_panel
from src.moments_data import compute_data_moments


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()

    cfg = load_config(args.config)
    cfg["sample"]["max_firms"] = None
    cfg["moments"]["print_diagnostics"] = False
    panel = load_panel(cfg)
    moments = compute_data_moments(panel, cfg)
    cols = [c for c in ["moment", "role", "value", "se", "notes"] if c in moments.columns]
    print(moments[cols].to_string(index=False))


if __name__ == "__main__":
    main()
