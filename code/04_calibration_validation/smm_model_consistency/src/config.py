from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def _deep_update(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_update(out[key], value)
        else:
            out[key] = value
    return out


DEFAULT_CONFIG: dict[str, Any] = {
    "paths": {
        "data": "../../../data/restricted_placeholder/derived/data_ready_mec.dta",
        "outputs": "../../../output/struct2/outputs",
        "figures": "../../../output/struct2/figures",
        "tables": "../../../output/struct2/tables",
        "logs": "../../../output/struct2/logs",
        "thesis_source": "../../../tex/m2de_thesis.tex",
        "thesis_struct": "../../../tex/m2de_thesis.tex",
    },
    "sample": {
        "year_min": 2011,
        "year_max": 2019,
        "min_sector_year_firms": 5,
        "max_firms": None,
        "random_seed": 20260510,
    },
    "columns": {
        "firm_id": "firm_id",
        "sector": "isic4",
        "year": "year",
        "markup": "mu",
        "log_markup": "ln_mu",
        "dlog_markup": "dln_mu",
        "share": "share_sales",
        "sales": "dom_sales",
        "import_penetration": "IP",
        "treatment": "change_IP",
        "instrument": "output_IV",
        "input_shock": "Z_input",
        "exit": "exit",
        "hhi": "HHI_dom",
        "cr10": "CR10_dom",
        "cr4": "CR4_dom",
    },
    "controls": {
        "firm": [
            "Z_input",
            "l_age",
            "l_leverage",
            "l_lnSize",
            "l_liquidity_ratio_x_",
            "ls_pre_filled",
            "ls_pre_x_post2016",
        ],
        "sector": [
            "Z_input",
            "ls_pre_filled",
            "ls_pre_x_post2016",
            "n_firms",
        ],
        "fixed_effects": ["isic4", "year"],
        "cluster": "isic4",
    },
    "elasticities": {
        "eta": 1.25,
        "nu": 4.0,
        "rho": 10.0,
        "lambda_min": 0.05,
        "lambda_max": 0.98,
        "default_lambda": 0.85,
    },
    "estimation": {
        "maxiter": 8,
        "maxfun": 80,
        "reuse_existing": True,
        "ftol": 1.0e-7,
        "estimated_parameters": [
            "output_scale",
            "output_markup",
            "high_markup_output",
            "concentration_output",
            "share_output",
            "share_input",
            "input_markup",
            "mean_reversion",
            "drift",
            "exit_intercept",
            "exit_ip",
            "exit_markup",
        ],
        "fixed_parameters": {},
        "parameter_order": [
            "output_scale",
            "output_markup",
            "high_markup_output",
            "concentration_output",
            "share_output",
            "share_input",
            "input_markup",
            "mean_reversion",
            "drift",
            "exit_intercept",
            "exit_ip",
            "exit_markup",
        ],
        "start": {
            "output_scale": 1.0,
            "output_markup": -0.40,
            "high_markup_output": -0.25,
            "concentration_output": -0.50,
            "share_output": -0.15,
            "share_input": 0.20,
            "input_markup": 0.00,
            "mean_reversion": -0.05,
            "drift": 0.00,
            "exit_intercept": -2.30,
            "exit_ip": 0.50,
            "exit_markup": 0.00,
        },
        "bounds": {
            "output_scale": [0.0, 8.0],
            "output_markup": [-5.0, 5.0],
            "high_markup_output": [-8.0, 8.0],
            "concentration_output": [-20.0, 20.0],
            "share_output": [-5.0, 5.0],
            "share_input": [-5.0, 5.0],
            "input_markup": [-4.0, 4.0],
            "mean_reversion": [-1.5, 1.5],
            "drift": [-0.5, 0.5],
            "exit_intercept": [-8.0, 2.0],
            "exit_ip": [-8.0, 8.0],
            "exit_markup": [-4.0, 4.0],
        },
        "weight_min_scale": 0.05,
        "moment_weight_multipliers": {
            "baseline_iv_dln_mu": 3.0,
            "grouped_iv_q80": 2.0,
            "grouped_iv_q85": 2.5,
            "grouped_iv_q90": 3.0,
        },
    },
    "moments": {
        "compute_all": False,
        "moment_sets": {
            "causal_core_main": [
                "baseline_iv_dln_mu",
                "grouped_iv_q80",
                "grouped_iv_q85",
                "grouped_iv_q90",
                "grouped_iv_q90_cr4_interaction",
            ],
        },
        "objective_set": "causal_core_main",
        "objective": [
            "baseline_iv_dln_mu",
            "grouped_iv_q80",
            "grouped_iv_q85",
            "grouped_iv_q90",
            "grouped_iv_q90_cr4_interaction",
        ],
        "diagnostics": {
            "aggregation": [
                "sector_inverse_markup_iv",
            ],
            "accounting": [
                "within_decomp_abs_share",
                "between_decomp_abs_share",
                "entry_decomp_abs_share",
                "exit_decomp_abs_share",
            ],
            "correlated_input": [
                "input_shock_between_reallocation",
            ],
            "selection": [
                "exit_iv",
            ],
            "decomposition_iv": [
                "decomp_total_output_iv",
                "decomp_within_output_iv",
                "decomp_reallocation_output_iv",
            ],
        },
        "active": [
            "baseline_iv_dln_mu",
            "grouped_iv_q80",
            "grouped_iv_q85",
            "grouped_iv_q90",
            "grouped_iv_q90_cr4_interaction",
            "sector_inverse_markup_iv",
            "exit_iv",
        ],
        "quantiles": [0.75, 0.80, 0.85, 0.90],
        "cr4_interaction_quantiles": [0.90],
        "include_exit": True,
        "include_interaction": True,
    },
    "counterfactuals": {
        "scenarios": ["observed", "no_output"],
        "label": "output-competition counterfactuals",
        "sector_sales_output_elasticity": -0.20,
        "sector_sales_input_elasticity": 0.10,
    },
}


def _normalize_estimation_config(cfg: dict[str, Any]) -> None:
    est = cfg["estimation"]
    if "estimated_parameters" not in est or est["estimated_parameters"] is None:
        est["estimated_parameters"] = list(est.get("parameter_order", []))
    est["estimated_parameters"] = list(est["estimated_parameters"])
    est["parameter_order"] = list(est["estimated_parameters"])
    est.setdefault("fixed_parameters", {})


def _normalize_moment_config(cfg: dict[str, Any]) -> None:
    moments = cfg["moments"]
    moments.setdefault("moment_sets", {})
    objective_set = moments.get("objective_set")
    if objective_set:
        sets = moments.get("moment_sets", {})
        if objective_set not in sets:
            raise KeyError(f"Unknown moments.objective_set: {objective_set}")
        moments["objective"] = list(sets[objective_set])
    if "objective" not in moments or moments["objective"] is None:
        moments["objective"] = list(moments.get("active", []) or [])
    moments["objective"] = list(moments["objective"])
    active = list(moments.get("active", []) or [])
    for name in moments["objective"]:
        if name not in active:
            active.append(name)
    moments["active"] = active
    moments.setdefault("compute_all", False)
    moments.setdefault("diagnostics", {})


def load_config(path: str | Path) -> dict[str, Any]:
    config_path = Path(path).resolve()
    with config_path.open("r", encoding="utf-8") as fh:
        user_cfg = yaml.safe_load(fh) or {}
    cfg = _deep_update(DEFAULT_CONFIG, user_cfg)
    _normalize_estimation_config(cfg)
    _normalize_moment_config(cfg)
    cfg["_config_path"] = str(config_path)
    cfg["_base_dir"] = str(config_path.parent)

    for key, value in list(cfg["paths"].items()):
        p = Path(value)
        if not p.is_absolute():
            p = (config_path.parent / p).resolve()
        cfg["paths"][key] = str(p)

    for key in ["outputs", "figures", "tables", "logs"]:
        Path(cfg["paths"][key]).mkdir(parents=True, exist_ok=True)

    return cfg


def get_path(cfg: dict[str, Any], key: str) -> Path:
    return Path(cfg["paths"][key])
