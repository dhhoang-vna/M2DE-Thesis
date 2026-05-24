version 17
clear all
capture log close
set more off

/*
Focused runner for the exhibits reported in tex/M2Thesis_ver24.tex.

This runner starts from the derived analysis datasets listed in README.md and
data_availability.md. It is the preferred fast reproducibility target when a
replicator has licensed ORBIS/AMADEUS extracts or locally recreated derived
Stata files but does not need to rebuild every raw-data concordance.
*/

do "code/00_setup/config.do"

log using "$LOGS/run_ver24_results.log", replace text

* Main empirical tables, diagnostics, and thesis figures.
do "$CODE_FIGTAB/figures.do"
do "$CODE_ANALYSIS/2 selection_correction.do"
do "$CODE_ANALYSIS/3 decomposition (2).do"
do "$CODE_ANALYSIS/3_manufacturing_wide_fixed.do"
do "$CODE_ANALYSIS/4_robustness.do"
do "$CODE_ANALYSIS/4_robustness_id.do"
do "$CODE_ANALYSIS/4_robustness_id_pretrend.do"
do "$CODE_ANALYSIS/4_robustness_resid.do"
do "$CODE_ANALYSIS/4_robustness_chn_gran.do"
do "$CODE_ANALYSIS/5_mechanism.do"
local skip_scm : environment REPLICATION_SKIP_SCM
if "`skip_scm'" == "1" {
    di as txt "Skipping SCM because REPLICATION_SKIP_SCM=1."
}
else {
    do "$CODE_ANALYSIS/6_scm.do"
}
do "$CODE_ANALYSIS/7_dispersion.do"
do "$CODE_ANALYSIS/kirov.do"

capture log close
