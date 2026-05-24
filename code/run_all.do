version 17
clear all
capture log close
set more off

/*
Master Stata runner for the thesis replication package.

Run from the repository root:

    stata-mp -b do code/run_all.do

The full empirical pipeline requires licensed ORBIS/AMADEUS data and the public
raw inputs listed in data_availability.md. Without those files, this runner
stops with Stata's normal "file not found" diagnostics.
*/

do "code/00_setup/config.do"

log using "$LOGS/run_all_stata.log", replace text

* 1. Construct analysis datasets.
do "$CODE_CONSTRUCT/1 orbis_data.do"
do "$CODE_CONSTRUCT/3 import_penetration_IP.do"
do "$CODE_CONSTRUCT/4 bartik_instrument.do"
do "$CODE_CONSTRUCT/4_chinese_granularity.do"
do "$CODE_CONSTRUCT/5 markup_estimation.do"
do "$CODE_CONSTRUCT/6 labor_share.do"
do "$CODE_CONSTRUCT/7 data_ready.do"

* 2. Estimate main and appendix tables.
do "$CODE_ANALYSIS/1 baseline_regressions.do"
do "$CODE_ANALYSIS/2 selection_correction.do"
do "$CODE_ANALYSIS/3 decomposition (2).do"
do "$CODE_ANALYSIS/3_manufacturing_wide_fixed.do"
do "$CODE_ANALYSIS/4_robustness.do"
do "$CODE_ANALYSIS/4_robustness_id.do"
do "$CODE_ANALYSIS/4_robustness_id_pretrend.do"
do "$CODE_ANALYSIS/4_robustness_resid.do"
do "$CODE_ANALYSIS/4_robustness_chn_gran.do"
do "$CODE_ANALYSIS/5_mechanism.do"
do "$CODE_ANALYSIS/5.2_import_control.do"
do "$CODE_ANALYSIS/6_scm.do"
do "$CODE_ANALYSIS/7_dispersion.do"
do "$CODE_ANALYSIS/kirov.do"

* 3. Build thesis figures and auxiliary diagnostics.
do "$CODE_FIGTAB/figures.do"

log close


