capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
MECHANISM TESTS
- Residual demand and pro-competitive effects
- Marginal cost and input-supply effects
- Market share reallocation toward incumbents
- Auxiliary outcomes (revenue, export, domestic sales)
***********************************************************************/
clear mata
capture log close
clear

log using "$LOGS\5_mechanism", replace

global folder "$REPLICATION_ROOT"

use "$DATA_DERIVED\data_ready_mec.dta", clear

xtset firm_id year
sort firm_id year
global X_lag "lleverage lliquidity llnsize l_age l_exporter"

*===============================================
* 1. RESIDUAL DEMAND AND PRO-COMPETITIVE EFFECTS
*===============================================

*--------------------------------------------
* 1.1: Interaction with lagged firm markup and lagged firm market share
*--------------------------------------------
preserve
collapse(mean) dln_mu change_IP output_IV Z_input $X_lag ls_pre_filled mu isic4 dom_sales HHI_dom post2016 [aw=dom_sales], by(firm_id year)
tsset firm_id year

gen lln_mu = ln(L.mu)
sum lln_mu if inrange(year,2011,2019), meanonly
gen clln_mu = lln_mu - r(mean)

// interacted with lagged firm markup
ivreghdfe dln_mu (c.change_IP c.change_IP#c.clln_mu = c.output_IV c.output_IV#c.clln_mu) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar F_first = e(widstat)
est store mec11_mu

sum clln_mu if e(sample), detail
local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)
lincom _b[c.change_IP] + `p25' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p25 = r(estimate)
lincom _b[c.change_IP] + `p50' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p50 = r(estimate)
lincom _b[c.change_IP] + `p75' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p75 = r(estimate)

/* interacted with lagged HHI
ivreghdfe dln_mu (c.change_IP c.change_IP#c.cl_HHI = c.output_IV c.output_IV#c.cl_HHI) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store mec11_mktshare

sum cl_share if e(sample), detail
local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)
lincom _b[c.change_IP] + `p25' * _b[c.change_IP#c.cl_share]
estadd scalar share_p25 = r(estimate)
lincom _b[c.change_IP] + `p50' * _b[c.change_IP#c.cl_share]
estadd scalar share_p50 = r(estimate)
lincom _b[c.change_IP] + `p75' * _b[c.change_IP#c.cl_share]
estadd scalar share_p75 = r(estimate)
estadd scalar mu_p25 = .
estadd scalar mu_p50 = .
estadd scalar mu_p75 = . 

// joint specification
ivreghdfe dln_mu (c.change_IP c.change_IP#c.clln_mu c.change_IP#c.cl_share = c.output_IV c.output_IV#c.clln_mu c.output_IV#c.cl_share) Z_input lln_mu l_share $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
est store mec11_joint

sum clln_mu if e(sample), detail
local mu25 = r(p25)
local mu50 = r(p50)
local mu75 = r(p75)

sum cl_share if e(sample), detail
local sh25 = r(p25)
local sh50 = r(p50)
local sh75 = r(p75)

lincom _b[c.change_IP] + `mu25' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p25 = r(estimate)
lincom _b[c.change_IP] + `mu50' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p50 = r(estimate)
lincom _b[c.change_IP] + `mu75' * _b[c.change_IP#c.clln_mu]
estadd scalar mu_p75 = r(estimate)
lincom _b[c.change_IP] + `sh25' * _b[c.change_IP#c.cl_share]
estadd scalar share_p25 = r(estimate)
lincom _b[c.change_IP] + `sh50' * _b[c.change_IP#c.cl_share]
estadd scalar share_p50 = r(estimate)
lincom _b[c.change_IP] + `sh75' * _b[c.change_IP#c.cl_share]
estadd scalar share_p75 = r(estimate) */


esttab mec11_mu using "$OUTPUT_TABLES\mec11_mu.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP c.change_IP#c.clln_mu Z_input) ///
    stats(mu_p25 mu_p50 mu_p75 N F_first, fmt(3 3 3 3 3 3 0 2) labels( ///
        "Marginal effect of import competition at p25 lagged markup" ///
        "Marginal effect of import competition at p50 lagged markup" ///
        "Marginal effect of import competition at p75 lagged markup" ///
        "Observations" "F-stat")) ///
    title("Interaction with lagged firm markup")
	
// Marginal effects from the interactions

restore

*--------------------------------------------------------------------------
* 1.2: Grouped IV Quantile Regression (GIVQ) for upper-tail discipline
*--------------------------------------------------------------------------
preserve
keep firm_id isic4 year dln_mu change_IP output_IV Z_input lleverage l_exporter l_age lliquidity llnsize ls_pre_filled post2016
drop if missing(isic4, year, dln_mu, change_IP, output_IV, Z_input)

bys isic4 year: egen n_jt = count(dln_mu)

bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

forvalues p = 5(5)95 {
	bys isic4 year: egen q`p' = pctile(dln_mu), p(`p')
}

gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

bys isic4 year: keep if _n==1
isid isic4 year

// Run IV for each quantile
matrix results = J(19, 5, .)
matrix colnames results = beta_IP se_IP lb ub N
local percentiles "5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95"
local row = 1
foreach p of local percentiles {
    ivreghdfe q`p' (c.change_IP = c.output_IV) Z_input $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)

	matrix results[`row',1] = _b[change_IP]
    matrix results[`row',2] = _se[change_IP]
    matrix results[`row',3] = _b[change_IP] - 1.96*_se[change_IP]
    matrix results[`row',4] = _b[change_IP] + 1.96*_se[change_IP]
    matrix results[`row',5] = e(N)

    eststo q`p'

    local row = `row' + 1
}
matrix rownames results = `percentiles'
matrix list results, format(%9.3f)

// Table
esttab q5 q10 q15 q20 q25 q30 q35 q40 q45 q50 q55 q60 q65 q70 q75 q80 q85 q90 q95 ///
    using "$OUTPUT_TABLES\mec12_givq.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input) ///
    stats(N, labels("Sector-year observations")) ///
    title("Grouped IV quantiles of markup adjustment")

restore

*============================================
* 2. MARGINAL COST AND INPUT-SUPPLY EFFECTS
*============================================

*------------------------------------------------
* 2.1. Imported-input dependence 2000-2004
*------------------------------------------------
import excel "$DATA_RAW\WIOD\TUR_NIOT_nov16.xlsx", sheet(National IO-tables) firstrow clear

keep if inrange(Year, 2000, 2004)

// Keep only intermediate-flow rows
keep if inlist(Origin, "Domestic", "Imports")
drop if inlist(Code,"II_fob","TXSP","EXP_adj","PURR","PURNR","VA","IntTTM","GO")

// Drop final demand/totals columns
drop CONS_* GFCF INVEN EXP GO

// Reshape to long: one cell per (Year, input_k=Code, industry_j=column)
ds Year Code Origin Description, not 
local indcols `r(varlist)'
foreach v of local indcols {
	rename `v' x`v'
}
reshape long x, i(Year Code Origin) j(industry_j) string
rename Code input_k
rename x Zij

destring Zij, replace
drop if missing(Zij)
keep if substr(industry_j,1,1)=="C"

// Total imported intermediate use by sector-year j
gen imp_use = Zij if Origin=="Imports"
gen tot_use = Zij

collapse (sum) imp_use tot_use, by(Year industry_j)

// Imported-input dependence by sector-year
gen H_jt = imp_use / tot_use 
drop if missing(H_jt) | tot_use==0
collapse (mean) H_j = H_jt, by(industry_j)

save "$DATA_DERIVED\IV\H_j_mec2.dta", replace

// Harmonize sector labels
replace industry_j = "C10C12" if industry_j=="C10-C12"
replace industry_j = "C13C15" if industry_j=="C13-C15"
replace industry_j = "C31_C32" if industry_j=="C31_C32"

use "$DATA_DERIVED\IV\output_IV.dta", clear
merge m:1 industry_j using "$DATA_DERIVED\IV\H_j_mec2.dta", keep(match master) nogen
save "$DATA_DERIVED\IV\output_IV_H.dta", replace

use "$DATA_DERIVED\data_ready.dta", clear
capture drop _merge

merge m:1 isic4 year using "$DATA_DERIVED\IV\output_IV_H.dta"

save "$DATA_DERIVED\data_ready_H.dta", replace


*-------------------
* 2.2. Regressions 
*-------------------
use "$DATA_DERIVED\data_ready_H.dta", clear
drop if missing(firm_id) | missing(year) | missing(isic4)
xtset firm_id year
sort firm_id year

**** (1) Hetero in the input-supply channel
gen Z_input_H = Z_input * H_j
gen outputIV_H = output_IV * H_j
gen changeIP_H = change_IP * H_j

ivreghdfe dln_mu (change_IP = output_IV) Z_input Z_input_H $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec21


**** (2) Offsetting output competition?
ivreghdfe dln_mu (change_IP changeIP_H = output_IV outputIV_H) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec22

**** (3) Auxiliary outcomes 
// Revenue growth
ivreghdfe dln_rev (change_IP = output_IV) Z_input Z_input_H $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec31

ivreghdfe dln_rev (change_IP changeIP_H = output_IV outputIV_H) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec32

// Domestic sales growth
xtset firm_id year
sort firm_id year
gen ln_dom_sales = ln(dom_sales) if dom_sales>0
gen dln_dom_sales = D.ln_dom_sales

ivreghdfe dln_dom_sales (change_IP = output_IV) Z_input Z_input_H $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec33

ivreghdfe dln_dom_sales (change_IP changeIP_H = output_IV outputIV_H) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec34

// Export growth
gen ln_export = ln(export_revenue) if export_revenue>0
xtset firm_id year
sort firm_id year
gen dln_export = D.ln_export

ivreghdfe dln_export (change_IP = output_IV) Z_input Z_input_H lleverage lliquidity llnsize l_age c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec35

ivreghdfe dln_export (change_IP changeIP_H = output_IV outputIV_H) Z_input lleverage lliquidity llnsize l_age c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
est store mec36

* Table
esttab mec21 mec22 mec31 mec32 mec33 mec34 mec35 mec36 using "$OUTPUT_TABLES\mec4.tex", replace se star(* 0.10 ** 0.05 *** 0.01) keep(change_IP Z_input changeIP_H Z_input_H) stats(N kpF, labels("Observations" "KP rk Wald F")) ///
	title("Imported-input dependence heterogeneity")


*========================================================
* 3. DO LARGE INCUMBENTS GAIN SHARE WHEN IMPORT COMPETITION RISES? - REALLOCATION CHANNEL VALIDATION
*========================================================
use "$DATA_DERIVED\data_ready_mec.dta", clear

xtset firm_id year
sort firm_id year
global X_lag "lleverage lliquidity llnsize l_age l_exporter"

gen ln_share = ln(share_sales) if share_sales & !missing(share_sales)
gen dln_share = D.ln_share

gen l_change_IP = L.change_IP
gen l_output_IV = L.output_IV
gen l_Z_input = L.Z_input

*-----------------------------------------------
* 3.1. Interact with lagged log size
*-----------------------------------------------
gen ip_size = l_change_IP * llnsize
gen iv_size = l_output_IV * llnsize
gen input_size = l_Z_input * llnsize

ivreghdfe dln_share (ip_size = iv_size) $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
estadd scalar F_first = e(widstat)
est store mec31_ip

reghdfe dln_share Z_input input_size $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4) //5% sig if add Z_input
est store mec31_input

*----------------------------------------------
* 3.2: Interact with large-incumbent dummy (above median lagged size within year)
*----------------------------------------------
bys year: egen median_size = median(llnsize)
gen H_large = (llnsize > median_size) if !missing(llnsize, median_size)
gen H_small = (llnsize < median_size) if !missing(llnsize, median_size)

gen ip_large = l_change_IP * H_large
gen iv_large = l_output_IV * H_large
gen input_large = l_Z_input * H_large
gen input_small = l_Z_input * H_small

ivreghdfe dln_share (change_IP ip_large = output_IV iv_large) $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
estadd scalar F_first = e(widstat)
est store mec32_ip

reghdfe dln_share input_small Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)

reghdfe dln_share input_large Z_input $X_lag c.ls_pre_filled##i.post2016 c.year#i.isic4 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4) //c.year#i.isic4 lambda_j*t
est store mec32_input

*----------------------------------------------
* 3.3. Interact with lagged CR4 membership
*----------------------------------------------
bys isic4 year: egen rank_dom = rank(-dom_sales)
gen cr4 = (rank_dom <= 4) if !missing(rank_dom)
sort firm_id year
xtset firm_id year
gen H_cr4 = L.cr4
gen ip_cr4 = l_change_IP * H_cr4
gen iv_cr4 = l_output_IV * H_cr4
gen input_cr4 = l_Z_input * H_cr4

ivreghdfe dln_share (change_IP ip_cr4 = output_IV iv_cr4) $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial (i.year)
estadd scalar F_first = e(widstat)
est store mec33_ip

reghdfe dln_share input_cr4 Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
est store mec33_input

*---------
* Table
*---------
esttab mec31_ip mec31_input mec32_ip mec32_input mec33_ip mec33_input using "$OUTPUT_TABLES\mec3.tex", replace se star(* 0.10 ** 0.05 *** 0.01) keep(ip_size ip_large ip_cr4 input_size input_large input_cr4) stats(N F_first, labels("Observations" "F-stat")) ///
	title("Market-share reallocation toward large incumbents: output competition and input supply")


*========================================================
* 4. AUXILIARY OUTCOMES
*========================================================

*----------------------------------------------
* 4.1: Revenue growth (total firm expansion) 
*----------------------------------------------
ivreghdfe dln_rev (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store mec41

*-------------------------------------------------------------
* 4.2: Export revenue growth (access to global markets)
*-------------------------------------------------------------
gen ln_export = ln(export_revenue) if export_revenue>0
xtset firm_id year
sort firm_id year
gen dln_export = D.ln_export

ivreghdfe dln_export (change_IP = output_IV) Z_input lleverage lliquidity llnsize l_age c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store mec42

*---------------------------------------------------
* 4.3: Domestic sales growth (focus on home market)
*---------------------------------------------------

xtset firm_id year
sort firm_id year
gen ln_dom_sales = ln(dom_sales) if dom_sales>0
gen dln_dom_sales = D.ln_dom_sales

ivreghdfe dln_dom_sales (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store mec43

*---------
* Table
*---------
esttab mec41 mec42 mec43 using "$OUTPUT_TABLES\mec4.tex", replace se star(* 0.10 ** 0.05 *** 0.01) keep(change_IP Z_input $X_lag) stats(N kpF, labels("Observations" "KP rk Wald F")) ///
	title("Auxiliary Outcomes")





log close






















