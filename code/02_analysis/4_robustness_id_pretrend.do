capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
clear all
set more off
version 17

global folder      "$REPLICATION_ROOT"
global output_dir  "$OUTPUT_TABLES"
global data_out    "$DATA_DERIVED/BACI"

capture log close
log using "$LOGS/4_robustness_id_section11.log", replace

foreach cmd in eststo esttab {
    capture which `cmd'
    if _rc {
        di as error "`cmd' is not installed."
        exit 199
    }
}

/********************************************************************
 11. PRE-TREND BALANCE CHECKS
********************************************************************/

use "$data_out/main_panel_with_demand_controls.dta", clear

local pre_cutoff 2011
local post_start = `pre_cutoff' + 1

*------------------------------------------------------------
* Build list of available variables
*------------------------------------------------------------
local collapse_vars dln_mu change_IP output_IV Z_input

capture confirm variable sales_growth
if !_rc local collapse_vars `collapse_vars' sales_growth

capture confirm variable dln_sales
if !_rc local collapse_vars `collapse_vars' dln_sales

capture confirm variable dln_rev
if !_rc local collapse_vars `collapse_vars' dln_rev

capture confirm variable HHI_dom
if !_rc local collapse_vars `collapse_vars' HHI_dom

capture confirm variable CR4_dom
if !_rc local collapse_vars `collapse_vars' CR4_dom

capture confirm variable CR10_dom
if !_rc local collapse_vars `collapse_vars' CR10_dom

*------------------------------------------------------------
* Collapse to sector-year level
*------------------------------------------------------------
collapse (mean) `collapse_vars', by(isic4 year)

*------------------------------------------------------------
* Construct concentration growth if available
*------------------------------------------------------------
capture confirm variable HHI_dom
if !_rc {
    sort isic4 year
    by isic4: gen double dln_HHI_dom = log(HHI_dom) - log(HHI_dom[_n-1]) ///
        if year == year[_n-1] + 1 & HHI_dom > 0 & HHI_dom[_n-1] > 0
}

capture confirm variable CR4_dom
if !_rc {
    sort isic4 year
    by isic4: gen double dln_CR4_dom = log(CR4_dom) - log(CR4_dom[_n-1]) ///
        if year == year[_n-1] + 1 & CR4_dom > 0 & CR4_dom[_n-1] > 0
}

capture confirm variable CR10_dom
if !_rc {
    sort isic4 year
    by isic4: gen double dln_CR10_dom = log(CR10_dom) - log(CR10_dom[_n-1]) ///
        if year == year[_n-1] + 1 & CR10_dom > 0 & CR10_dom[_n-1] > 0
}

*------------------------------------------------------------
* Define pre/post
*------------------------------------------------------------
gen byte pre_period  = year <= `pre_cutoff'
gen byte post_period = year >= `post_start'

*------------------------------------------------------------
* Construct sector-level future China-shock intensity
* This is the object used to test pre-trends.
*------------------------------------------------------------
bys isic4: egen double outputIV_post_mean = mean(output_IV) if post_period == 1
bys isic4: egen double Zinput_post_mean   = mean(Z_input)  if post_period == 1

bys isic4: egen double outputIV_future = max(outputIV_post_mean)
bys isic4: egen double Zinput_future   = max(Zinput_post_mean)

drop outputIV_post_mean Zinput_post_mean

*------------------------------------------------------------
* Keep pre-period observations only
*------------------------------------------------------------
keep if pre_period == 1

eststo clear
local pre_models

*------------------------------------------------------------
* Helper logic:
* Use OLS with year FE, clustered by ISIC4.
* Do NOT absorb ISIC4.
*------------------------------------------------------------

* 1. Pre-period markup growth
capture confirm variable dln_mu
if !_rc {
    quietly count if !missing(dln_mu, outputIV_future, Zinput_future)
    if r(N) > 10 {
        capture noisily eststo pre_mu: reg dln_mu outputIV_future Zinput_future i.year, ///
            vce(cluster isic4)
        if !_rc local pre_models `pre_models' pre_mu
    }
}

* 2. Pre-period import-penetration growth
capture confirm variable change_IP
if !_rc {
    quietly count if !missing(change_IP, outputIV_future, Zinput_future)
    if r(N) > 10 {
        capture noisily eststo pre_ip: reg change_IP outputIV_future Zinput_future i.year, ///
            vce(cluster isic4)
        if !_rc local pre_models `pre_models' pre_ip
    }
}

* 3. Pre-period sales/revenue growth
capture confirm variable sales_growth
if !_rc {
    quietly count if !missing(sales_growth, outputIV_future, Zinput_future)
    if r(N) > 10 {
        capture noisily eststo pre_sales: reg sales_growth outputIV_future Zinput_future i.year, ///
            vce(cluster isic4)
        if !_rc local pre_models `pre_models' pre_sales
    }
}
else {
    capture confirm variable dln_sales
    if !_rc {
        quietly count if !missing(dln_sales, outputIV_future, Zinput_future)
        if r(N) > 10 {
            capture noisily eststo pre_sales: reg dln_sales outputIV_future Zinput_future i.year, ///
                vce(cluster isic4)
            if !_rc local pre_models `pre_models' pre_sales
        }
    }
    else {
        capture confirm variable dln_rev
        if !_rc {
            quietly count if !missing(dln_rev, outputIV_future, Zinput_future)
            if r(N) > 10 {
                capture noisily eststo pre_sales: reg dln_rev outputIV_future Zinput_future i.year, ///
                    vce(cluster isic4)
                if !_rc local pre_models `pre_models' pre_sales
            }
        }
    }
}

* 4. Pre-period concentration growth
capture confirm variable dln_HHI_dom
if !_rc {
    quietly count if !missing(dln_HHI_dom, outputIV_future, Zinput_future)
    if r(N) > 10 {
        capture noisily eststo pre_hhi: reg dln_HHI_dom outputIV_future Zinput_future i.year, ///
            vce(cluster isic4)
        if !_rc local pre_models `pre_models' pre_hhi
    }
}
else {
    capture confirm variable dln_CR4_dom
    if !_rc {
        quietly count if !missing(dln_CR4_dom, outputIV_future, Zinput_future)
        if r(N) > 10 {
            capture noisily eststo pre_hhi: reg dln_CR4_dom outputIV_future Zinput_future i.year, ///
                vce(cluster isic4)
            if !_rc local pre_models `pre_models' pre_hhi
        }
    }
    else {
        capture confirm variable dln_CR10_dom
        if !_rc {
            quietly count if !missing(dln_CR10_dom, outputIV_future, Zinput_future)
            if r(N) > 10 {
                capture noisily eststo pre_hhi: reg dln_CR10_dom outputIV_future Zinput_future i.year, ///
                    vce(cluster isic4)
                if !_rc local pre_models `pre_models' pre_hhi
            }
        }
    }
}

*------------------------------------------------------------
* Export table
*------------------------------------------------------------
if "`pre_models'" != "" {
    esttab `pre_models' using "$output_dir/pretrend_balance_outputIV.tex", replace ///
        se b(%9.3f) se(%9.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(outputIV_future Zinput_future) ///
        order(outputIV_future Zinput_future) ///
        stats(N r2, labels("Observations" "R-squared")) ///
        title("Pre-trend Balance Checks: Do Future China Shocks Predict Pre-period Outcomes?") ///
        addnotes("Each column is a sector-year pre-period outcome regression.", ///
                 "The main coefficient tests whether sectors more exposed to later China shocks already had differential pre-period trends.", ///
                 "Regressions include year fixed effects and cluster standard errors by ISIC4.")
}
else {
    di as txt "No pre-trend balance table exported: no eligible pre-period regressions were available."
}

log close

