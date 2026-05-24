capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
6. MANUFACTURING-WIDE MARKUP DISCIPLINE AND ALLOCATIVE-EFFICIENCY ACCOUNTING

Purpose
-------
This do-file extends the sectoral decomposition in "3 decomposition.do" to
manufacturing-wide objects. It is deliberately conservative: it produces
BF/BFS-inspired accounting objects and local IV contribution regressions. It
DOES NOT claim a full GE welfare effect.

Main blocks
-----------
1. Rebuild sector-level harmonic markups and within/between/entry/exit terms.
2. Aggregate sectoral inverse markups to manufacturing-wide inverse markups.
3. Construct BF-style direct markup-wedge contribution objects.
4. Estimate local IV effects on manufacturing-wide contribution components.
5. Construct BFS-style covariance/reallocation diagnostics.
6. Optionally compute a descriptive residual technical-efficiency component.

Interpretation
--------------
The IV estimates below are local to sector-year cells moved by output_IV.
They are contribution coefficients, not aggregate average treatment effects and
not full welfare counterfactuals.
***********************************************************************/

clear mata
capture log close
clear all
set more off
version 17.0

*=============================*
* 0. USER SETTINGS
*=============================*

global folder "$REPLICATION_ROOT"

capture mkdir "$LOGS"
capture mkdir "$OUTPUT_TABLES"
capture mkdir "$OUTPUT_FIGURES"
capture mkdir "$DATA_DERIVED\derived"

log using "$LOGS\3_manufacturing_wide.log", replace text

* Main estimation window. Keep this aligned with the main thesis tables.
local y0 2011
local y1 2019

* Technical-efficiency residual block: optional and descriptive only.
* Leave shares as "." to skip the block. Set them manually if you want it.
local alpha_L .
local alpha_K .
local alpha_M .

foreach cmd in reghdfe ivreghdfe eststo esttab estadd {
    capture which `cmd'
    if _rc {
        di as error "`cmd' is not installed. Install it before running this do-file."
        exit 199
    }
}

*=============================*
* 1. LOAD AND CLEAN DATA
*=============================*

use "$DATA_DERIVED\data_ready_mec.dta", clear

capture confirm file "$DATA_DERIVED\UNIDO\apparent_consumption.dta"
if !_rc {
    capture confirm variable apparent_consumption
    if _rc {
        merge m:1 isic4 year using "$DATA_DERIVED\UNIDO\apparent_consumption.dta", ///
            keep(master match) nogen
    }
}

foreach v in isic4 year firm_id share_sales mu dom_sales change_IP output_IV {
    capture confirm variable `v'
    if _rc {
        di as error "Required variable `v' not found."
        exit 111
    }
}

capture confirm variable post2016
if _rc gen byte post2016 = (year >= 2016) if !missing(year)

* Basic sample restrictions. These mimic the original decomposition code.
drop if missing(isic4, year, firm_id)
drop if missing(share_sales, mu, dom_sales)
drop if mu <= 0
drop if share_sales < 0
drop if dom_sales < 0

* Keep a clean copy for later firm-level diagnostics.
tempfile base_clean
save `base_clean', replace

*=============================*
* 2. SECTOR HARMONIC MARKUPS
*=============================*

isid firm_id year
sort firm_id year

gen double inv_mu = 1/mu

bys isic4 year: egen double inv_mu_j = total(share_sales * inv_mu)
gen double mu_j    = 1 / inv_mu_j
gen double ln_mu_j = ln(mu_j)

preserve
    keep isic4 year inv_mu_j mu_j ln_mu_j
    bys isic4 year: keep if _n == 1
    isid isic4 year
    tsset isic4 year
    gen double d_inv_mu_j = D.inv_mu_j
    gen double d_ln_mu_j  = D.ln_mu_j
    tempfile sector_series
    save `sector_series', replace
restore

merge m:1 isic4 year using `sector_series', nogen

*=============================*
* 3. FOUR-TERM SECTOR DECOMPOSITION
*=============================*

sort firm_id year

by firm_id (year): gen double l_share  = share_sales[_n-1]
by firm_id (year): gen double l_inv_mu = inv_mu[_n-1]
by firm_id (year): gen int    l_year   = year[_n-1]
by firm_id (year): gen        l_isic4  = isic4[_n-1]

by firm_id (year): gen int f_year  = year[_n+1]
by firm_id (year): gen     f_isic4 = isic4[_n+1]

quietly summarize year, meanonly
local minyear = r(min)
local maxyear = r(max)

gen byte continuer = (l_year == year-1) & (l_isic4 == isic4)

gen byte entrant = (year > `minyear') & !continuer
replace entrant = 0 if missing(year) | missing(isic4) | missing(share_sales) | missing(inv_mu)

gen byte exiter_next = 0
replace exiter_next = 1 if !missing(year, isic4, share_sales, inv_mu) ///
    & (missing(f_year) | f_year != year + 1 | f_isic4 != isic4)
replace exiter_next = 0 if year == `maxyear'

gen double d_share    = share_sales - l_share if continuer
gen double d_inv_mu   = inv_mu - l_inv_mu if continuer
gen double s_bar      = 0.5*(share_sales + l_share) if continuer
gen double inv_mu_bar = 0.5*(inv_mu + l_inv_mu) if continuer

gen double contrib_within  = s_bar      * d_inv_mu if continuer
gen double contrib_between = inv_mu_bar * d_share  if continuer

gen double contrib_entry = share_sales * inv_mu if entrant

gen double contrib_exit_tmp = share_sales * inv_mu if exiter_next
gen int    year_exit        = year + 1 if exiter_next

preserve
    keep if exiter_next
    keep isic4 year_exit contrib_exit_tmp
    collapse (sum) exit_inv_mu = contrib_exit_tmp, by(isic4 year_exit)
    rename year_exit year
    tempfile exitterm
    save `exitterm', replace
restore

bys isic4 year: egen double within_inv_mu  = total(contrib_within)
bys isic4 year: egen double between_inv_mu = total(contrib_between)
bys isic4 year: egen double entry_inv_mu   = total(contrib_entry)

preserve
    keep isic4 year within_inv_mu between_inv_mu entry_inv_mu
    bys isic4 year: keep if _n == 1
    merge 1:1 isic4 year using `exitterm', nogen
    replace exit_inv_mu = 0 if missing(exit_inv_mu)
    tempfile decomp4
    save `decomp4', replace
restore

*=============================*
* 4. SECTOR-YEAR REGRESSION DATASET
*=============================*

preserve

bys isic4 year: gen int n_firms = _N
bys isic4 year: egen double dom_j = total(dom_sales)

bys isic4 year: keep if _n == 1

local keepvars "isic4 year inv_mu_j mu_j ln_mu_j d_inv_mu_j d_ln_mu_j change_IP output_IV post2016 n_firms dom_j"
foreach opt in Z_input ls_pre_filled HHI_dom ppi apparent_consumption {
    capture confirm variable `opt'
    if !_rc local keepvars "`keepvars' `opt'"
}
keep `keepvars'

isid isic4 year

merge 1:1 isic4 year using `decomp4', nogen
foreach v in within_inv_mu between_inv_mu entry_inv_mu exit_inv_mu {
    replace `v' = 0 if missing(`v')
}

gen double neg_exit_inv_mu = -exit_inv_mu

gen double decomp_total_j = within_inv_mu + between_inv_mu + entry_inv_mu - exit_inv_mu
gen double decomp_gap_j   = d_inv_mu_j - decomp_total_j
summarize decomp_gap_j, detail

tempfile sector_regdata
save `sector_regdata', replace
restore

*=============================*
* 5. MANUFACTURING-WIDE AGGREGATION
*=============================*

use `sector_regdata', clear

* Manufacturing expenditure/sales share. This is a practical proxy for BF-style weights;
* it is not a cost-based Domar weight unless dom_j is replaced by cost/value-added data.
bys year: egen double dom_M = total(dom_j)
gen double S_j = dom_j / dom_M if dom_M > 0

isid isic4 year
tsset isic4 year

gen double L_S_j       = L.S_j
gen double dS_j        = S_j - L_S_j
gen double S_bar_j     = 0.5*(S_j + L_S_j)
gen double inv_mu_bar_j= 0.5*(inv_mu_j + L.inv_mu_j)
gen double ln_mu_lag_j = L.ln_mu_j

gen double dln_dom_j = .
replace dln_dom_j = ln(dom_j) - ln(L.dom_j) if dom_j > 0 & L.dom_j > 0

* Manufacturing-wide inverse markup: mu_M^{-1} = sum_j S_j mu_j^{-1}
bys year: egen double inv_mu_M = total(S_j * inv_mu_j)
gen double mu_M    = 1 / inv_mu_M
gen double ln_mu_M = ln(mu_M)

preserve
    keep year inv_mu_M mu_M ln_mu_M dom_M
    bys year: keep if _n == 1
    tsset year
    gen double d_inv_mu_M = D.inv_mu_M
    gen double d_ln_mu_M  = D.ln_mu_M
    tempfile mfg_series
    save `mfg_series', replace
restore

merge m:1 year using `mfg_series', nogen

*------------------------------------------------------------*
* 5A. Manufacturing-wide inverse-markup decomposition
*------------------------------------------------------------*

* Total contribution of sector j to Delta mu_M^{-1}
gen double c_mfg_total_invmu = S_bar_j * d_inv_mu_j + dS_j * inv_mu_bar_j

* Decompose the within-sector term into the four sectoral components.
gen double c_mfg_within_firm    = S_bar_j * within_inv_mu
gen double c_mfg_between_firm   = S_bar_j * between_inv_mu
gen double c_mfg_entry          = S_bar_j * entry_inv_mu
gen double c_mfg_exit           = -S_bar_j * exit_inv_mu

* Cross-sector reallocation: sectors gaining manufacturing share with high inverse markup.
gen double c_mfg_between_sector = dS_j * inv_mu_bar_j

gen double c_mfg_decomp_sum = ///
    c_mfg_within_firm + c_mfg_between_firm + c_mfg_entry + ///
    c_mfg_exit + c_mfg_between_sector

gen double c_mfg_decomp_gap = c_mfg_total_invmu - c_mfg_decomp_sum
summarize c_mfg_decomp_gap, detail

*------------------------------------------------------------*
* 5B. BF-style direct markup-wedge contribution
*------------------------------------------------------------*

* Approximate direct markup-wedge component:
* Delta AE_mu,t ~= - sum_j S_{j,t-1} Delta log(mu_jt)
* This is the direct markup term only, not the full GE allocative-efficiency term.
gen double c_BF_AE_mu = -L_S_j * d_ln_mu_j

* Sign convention: positive means lower markup wedge / higher inverse markup.
label var c_BF_AE_mu          "BF direct markup-wedge contribution"
label var c_mfg_total_invmu   "Contribution to d inverse manufacturing markup"
label var c_mfg_within_firm   "Within-firm contribution"
label var c_mfg_between_firm  "Within-sector reallocation contribution"
label var c_mfg_entry         "Entry contribution"
label var c_mfg_exit          "Exit contribution"
label var c_mfg_between_sector "Between-sector reallocation contribution"

* Save sector-year contribution dataset before diagnostics.
tempfile mfg_regdata_pre_bfs
save `mfg_regdata_pre_bfs', replace

*------------------------------------------------------------*
* 5C. Manufacturing-wide time-series checks and exports
*------------------------------------------------------------*

preserve
    collapse (sum) ///
        c_mfg_total_invmu c_mfg_within_firm c_mfg_between_firm ///
        c_mfg_entry c_mfg_exit c_mfg_between_sector c_mfg_decomp_sum ///
        c_BF_AE_mu, by(year)

    merge 1:1 year using `mfg_series', nogen
    gen double mfg_identity_gap = d_inv_mu_M - c_mfg_decomp_sum
    gen double mfg_total_gap    = d_inv_mu_M - c_mfg_total_invmu

    order year inv_mu_M mu_M ln_mu_M d_inv_mu_M d_ln_mu_M ///
        c_mfg_decomp_sum c_mfg_total_invmu mfg_identity_gap mfg_total_gap ///
        c_BF_AE_mu c_mfg_within_firm c_mfg_between_firm ///
        c_mfg_entry c_mfg_exit c_mfg_between_sector

    export delimited using "$OUTPUT_TABLES\manufacturing_wide_ae_timeseries.csv", replace
    save "$DATA_DERIVED\derived\manufacturing_wide_ae_timeseries.dta", replace

    twoway ///
        (line inv_mu_M year if inrange(year,`y0',`y1'), lwidth(medthick)) ///
        (line mu_M year     if inrange(year,`y0',`y1'), lpattern(dash) lwidth(medthick)), ///
        xlabel(`y0'(1)`y1', labsize(small)) ///
        ytitle("Index", size(medsmall)) ///
        xtitle("Year", size(medsmall)) ///
        legend(order(1 "Manufacturing inverse markup" 2 "Manufacturing markup") ///
               rows(1) size(small) region(lstyle(none))) ///
        graphregion(color(white)) plotregion(color(white)) ///
        title("Manufacturing-wide markup aggregation", size(medium)) ///
        name(mfg_markup_series, replace)
    graph export "$OUTPUT_FIGURES\manufacturing_wide_markup_series.png", replace width(2400)

    twoway ///
        (bar c_mfg_within_firm year if inrange(year,`y0',`y1')) ///
        (bar c_mfg_between_firm year if inrange(year,`y0',`y1')) ///
        (bar c_mfg_entry year if inrange(year,`y0',`y1')) ///
        (bar c_mfg_exit year if inrange(year,`y0',`y1')) ///
        (line c_mfg_decomp_sum year if inrange(year,`y0',`y1'), lwidth(medthick)), ///
        xlabel(`y0'(1)`y1', labsize(small)) ///
        ytitle("Contribution to Delta inverse markup", size(medsmall)) ///
        xtitle("Year", size(medsmall)) ///
        legend(order(1 "Within firm" 2 "Within-sector realloc." 3 "Entry" 4 "Exit" 5 "Total") ///
               rows(2) size(small) region(lstyle(none))) ///
        graphregion(color(white)) plotregion(color(white)) ///
        title("Manufacturing-wide contribution components", size(medium)) ///
        name(mfg_contrib_components, replace)
    graph export "$OUTPUT_FIGURES\manufacturing_wide_contribution_components.png", replace width(2400)
restore

*=============================*
* 6. BFS-STYLE COVARIANCE DIAGNOSTICS
*=============================*

* Sector-level covariance contribution:
* Cov_{S_{j,t-1}}(log mu_{j,t-1}, Delta log domestic sales_jt)
use `mfg_regdata_pre_bfs', clear

gen double valid_sector_bfs = !missing(L_S_j, ln_mu_lag_j, dln_dom_j)
gen double w_sector_valid = L_S_j if valid_sector_bfs
bys year: egen double wden_sector = total(w_sector_valid)
gen double wS_bfs = L_S_j / wden_sector if valid_sector_bfs & wden_sector > 0

bys year: egen double mean_lnmu_sec = total(wS_bfs * ln_mu_lag_j)
bys year: egen double mean_dlny_sec = total(wS_bfs * dln_dom_j)

gen double bfs_sector_cov_contrib = ///
    wS_bfs * (ln_mu_lag_j - mean_lnmu_sec) * (dln_dom_j - mean_dlny_sec)
label var bfs_sector_cov_contrib "BFS sector covariance contribution"

tempfile regdata_with_sector_bfs
save `regdata_with_sector_bfs', replace

* Firm-level covariance contribution:
* Cov_{firm lagged domestic sales share}(log mu_{i,t-1}, Delta log domestic sales_it)
use `base_clean', clear
sort firm_id year

gen double ln_mu_f = ln(mu)
by firm_id (year): gen double L_dom_sales_f = dom_sales[_n-1] if year == year[_n-1] + 1
by firm_id (year): gen double L_ln_mu_f     = ln_mu_f[_n-1]   if year == year[_n-1] + 1
by firm_id (year): gen        L_isic4_f     = isic4[_n-1]     if year == year[_n-1] + 1

gen byte firm_continuer = !missing(L_dom_sales_f, L_ln_mu_f, L_isic4_f) & L_isic4_f == isic4
gen double dln_dom_sales_f = .
replace dln_dom_sales_f = ln(dom_sales) - ln(L_dom_sales_f) ///
    if firm_continuer & dom_sales > 0 & L_dom_sales_f > 0

gen byte valid_firm_bfs = firm_continuer & !missing(dln_dom_sales_f, L_ln_mu_f, L_dom_sales_f)

* Manufacturing-wide firm covariance contribution.
gen double L_dom_valid_M = L_dom_sales_f if valid_firm_bfs
bys year: egen double L_dom_M_valid = total(L_dom_valid_M)
gen double w_firm_M = L_dom_sales_f / L_dom_M_valid if valid_firm_bfs & L_dom_M_valid > 0

bys year: egen double mean_lnmu_f_M = total(w_firm_M * L_ln_mu_f)
bys year: egen double mean_dlny_f_M = total(w_firm_M * dln_dom_sales_f)

gen double bfs_firm_cov_contrib_raw = ///
    w_firm_M * (L_ln_mu_f - mean_lnmu_f_M) * (dln_dom_sales_f - mean_dlny_f_M)

* Within-sector firm covariance, then weighted by lagged sector size in manufacturing.
gen double L_dom_valid_j = L_dom_sales_f if valid_firm_bfs
bys isic4 year: egen double L_dom_j_valid = total(L_dom_valid_j)
gen double w_firm_j = L_dom_sales_f / L_dom_j_valid if valid_firm_bfs & L_dom_j_valid > 0
gen double S_lag_j_from_firms = L_dom_j_valid / L_dom_M_valid if valid_firm_bfs & L_dom_M_valid > 0

bys isic4 year: egen double mean_lnmu_f_j = total(w_firm_j * L_ln_mu_f)
bys isic4 year: egen double mean_dlny_f_j = total(w_firm_j * dln_dom_sales_f)

gen double bfs_firm_within_sector_cov_raw = ///
    S_lag_j_from_firms * w_firm_j * ///
    (L_ln_mu_f - mean_lnmu_f_j) * (dln_dom_sales_f - mean_dlny_f_j)

collapse (sum) ///
    bfs_firm_cov_contrib = bfs_firm_cov_contrib_raw ///
    bfs_firm_within_sector_cov = bfs_firm_within_sector_cov_raw, by(isic4 year)

label var bfs_firm_cov_contrib        "BFS firm covariance contribution, manufacturing means"
label var bfs_firm_within_sector_cov  "BFS firm covariance contribution, within-sector means"

tempfile firm_bfs
save `firm_bfs', replace

use `regdata_with_sector_bfs', clear
merge 1:1 isic4 year using `firm_bfs', nogen
foreach v in bfs_firm_cov_contrib bfs_firm_within_sector_cov {
    replace `v' = 0 if missing(`v')
}

tempfile mfg_regdata
save `mfg_regdata', replace
save "$DATA_DERIVED\derived\manufacturing_wide_ae_sector_year.dta", replace
export delimited using "$OUTPUT_TABLES\manufacturing_wide_ae_sector_year.csv", replace

*=============================*
* 7. LOCAL IV CONTRIBUTION REGRESSIONS
*=============================*

use `mfg_regdata', clear

* Controls follow the main decomposition specification but are constructed safely.
local rhs "i.year"

capture confirm variable Z_input
if !_rc local rhs "Z_input `rhs'"

capture confirm variable ls_pre_filled
if !_rc local rhs "c.ls_pre_filled##i.post2016 `rhs'"

capture confirm variable ppi
if !_rc {
    tsset isic4 year
    gen double ln_ppi  = ln(ppi) if ppi > 0
    gen double dln_ppi = D.ln_ppi
    local rhs "dln_ppi `rhs'"
}

capture confirm variable HHI_dom
if !_rc {
    tsset isic4 year
    gen double dHHI = D.HHI_dom
    local rhs "dHHI `rhs'"
}

capture confirm variable apparent_consumption
if !_rc {
    tsset isic4 year
    gen double ln_abs  = ln(apparent_consumption) if apparent_consumption > 0
    gen double dln_abs = D.ln_abs
    local rhs "dln_abs `rhs'"
}

capture confirm variable n_firms
if !_rc local rhs "n_firms `rhs'"

local sample if inrange(year, `y0', `y1')
local fe absorb(isic4) vce(cluster isic4) partial(i.year)

eststo clear

eststo bf_direct: ///
    ivreghdfe c_BF_AE_mu ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_total: ///
    ivreghdfe c_mfg_total_invmu ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_within: ///
    ivreghdfe c_mfg_within_firm ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_realloc: ///
    ivreghdfe c_mfg_between_firm ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_entry: ///
    ivreghdfe c_mfg_entry ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_exit: ///
    ivreghdfe c_mfg_exit ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfg_btwsec: ///
    ivreghdfe c_mfg_between_sector ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

esttab bf_direct mfg_total mfg_within mfg_realloc mfg_entry mfg_exit mfg_btwsec ///
    using "$OUTPUT_TABLES\manufacturing_wide_ae_iv.tex", ///
    replace booktabs label fragment compress nogaps ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("BF direct" "Mfg total" "Within" "Firm realloc." "Entry" "Exit" "Sector realloc.") ///
    stats(N, fmt(0) labels("Observations")) ///
    varlabels(change_IP "Import penetration change" Z_input "Input-supply control")

* BFS covariance diagnostic regressions.
eststo clear

eststo bfs_sec: ///
    ivreghdfe bfs_sector_cov_contrib ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo bfs_firmM: ///
    ivreghdfe bfs_firm_cov_contrib ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo bfs_firmJ: ///
    ivreghdfe bfs_firm_within_sector_cov ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

esttab bfs_sec bfs_firmM bfs_firmJ ///
    using "$OUTPUT_TABLES\bfs_covariance_diagnostics_iv.tex", ///
    replace booktabs label fragment compress nogaps ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Sector covariance" "Firm covariance" "Within-sector firm covariance") ///
    stats(N, fmt(0) labels("Observations")) ///
    varlabels(change_IP "Import penetration change" Z_input "Input-supply control")

*=============================*
* 8. AGGREGATION LADDER: FIRM, SECTOR, MANUFACTURING CONTRIBUTION
*=============================*

* This is for comparison only. Units differ across columns.
use `base_clean', clear
sort firm_id year
gen double ln_mu_base = ln(mu)
by firm_id (year): gen int L_year_base = year[_n-1]
by firm_id (year): gen     L_isic4_base = isic4[_n-1]
by firm_id (year): gen double L_ln_mu_base = ln_mu_base[_n-1]
gen byte cont_base = (L_year_base == year-1) & (L_isic4_base == isic4)
gen double dln_mu_base = ln_mu_base - L_ln_mu_base if cont_base

capture confirm variable post2016
if _rc gen byte post2016 = (year >= 2016) if !missing(year)

local rhs_firm "i.year"
capture confirm variable Z_input
if !_rc local rhs_firm "Z_input `rhs_firm'"
capture confirm variable ls_pre_filled
if !_rc local rhs_firm "c.ls_pre_filled##i.post2016 `rhs_firm'"

eststo clear
capture noisily eststo firm: ///
    ivreghdfe dln_mu_base ///
        (change_IP = output_IV) ///
        `rhs_firm' if inrange(year, `y0', `y1'), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

use `mfg_regdata', clear
eststo sector: ///
    ivreghdfe d_ln_mu_j ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

eststo mfgcontrib: ///
    ivreghdfe c_BF_AE_mu ///
        (change_IP = output_IV) ///
        `rhs' `sample', `fe'

capture noisily esttab firm sector mfgcontrib ///
    using "$OUTPUT_TABLES\aggregation_ladder_iv.tex", ///
    replace booktabs label fragment compress nogaps ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Firm dln mu" "Sector dln mu" "Mfg BF contribution") ///
    stats(N, fmt(0) labels("Observations")) ///
    varlabels(change_IP "Import penetration change" Z_input "Input-supply control")

*=============================*
* 9. OPTIONAL DESCRIPTIVE TECHNICAL-EFFICIENCY RESIDUAL
*=============================*

* This block only runs if user supplies input shares and the variables exist.
* It is descriptive. It does not identify causal technical efficiency.

use `base_clean', clear

local yvar ""
foreach cand in real_dom_sales dom_sales output value_added operating_revenue_turnover sales revenue {
    capture confirm variable `cand'
    if !_rc {
        if "`yvar'" == "" local yvar `cand'
    }
}

local lvar ""
foreach cand in employees number_employees emp employment labor l {
    capture confirm variable `cand'
    if !_rc {
        if "`lvar'" == "" local lvar `cand'
    }
}

local kvar ""
foreach cand in capital fixed_assets tangible_fixed_assets total_fixed_assets k {
    capture confirm variable `cand'
    if !_rc {
        if "`kvar'" == "" local kvar `cand'
    }
}

local mvar ""
foreach cand in materials material_costs cost_materials intermediate_inputs inputs m {
    capture confirm variable `cand'
    if !_rc {
        if "`mvar'" == "" local mvar `cand'
    }
}

if "`alpha_L'" != "." & "`alpha_K'" != "." & "`alpha_M'" != "." ///
   & "`yvar'" != "" & "`lvar'" != "" & "`kvar'" != "" & "`mvar'" != "" {

    collapse (sum) Y_M = `yvar' L_M = `lvar' K_M = `kvar' INT_M = `mvar', by(year)
    foreach v in Y_M L_M K_M INT_M {
        replace `v' = . if `v' <= 0
        gen double ln_`v' = ln(`v')
    }
    tsset year
    gen double dlnY_M   = D.ln_Y_M
    gen double dlnL_M   = D.ln_L_M
    gen double dlnK_M   = D.ln_K_M
    gen double dlnINT_M = D.ln_INT_M

    gen double dTFP_D_M = dlnY_M - `alpha_L'*dlnL_M - `alpha_K'*dlnK_M - `alpha_M'*dlnINT_M

    merge 1:1 year using "$DATA_DERIVED\derived\manufacturing_wide_ae_timeseries.dta", nogen
    gen double dTE_residual_M = dTFP_D_M - c_BF_AE_mu

    export delimited using "$OUTPUT_TABLES\technical_efficiency_residual_descriptive.csv", replace
    save "$DATA_DERIVED\derived\technical_efficiency_residual_descriptive.dta", replace
}
else {
    di as txt "Technical-efficiency residual block skipped. Set alpha_L/alpha_K/alpha_M and verify input variables."
}

*=============================*
* 10. INTERPRETATION NOTES
*=============================*

file open notes using "$OUTPUT_TABLES\manufacturing_wide_ae_notes.txt", write replace
file write notes "Manufacturing-wide AE do-file notes" _n _n
file write notes "1. mu_M^{-1} = sum_j S_j mu_j^{-1}, where S_j is the sector share in manufacturing domestic sales." _n
file write notes "2. c_BF_AE_mu = - S_{j,t-1} Delta log(mu_jt) is only the direct markup-wedge component." _n
file write notes "3. The IV coefficients are local contribution effects along output_IV-induced import penetration variation." _n
file write notes "4. They are not full GE welfare effects and do not identify spillovers across sectors." _n
file write notes "5. If sector j's shock affects sector k through IO links, wages, prices, or demand substitution, SUTVA fails." _n
file write notes "6. BFS covariance diagnostics test whether activity reallocates toward or away from high-markup firms/sectors." _n
file write notes "7. Positive inverse-markup contributions mean lower aggregate markup wedges; they are not automatically welfare gains." _n
file close notes

log close


