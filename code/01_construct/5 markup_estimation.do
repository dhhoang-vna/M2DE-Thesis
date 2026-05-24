capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
clear mata
capture log close
clear

log using "$LOGS\5 markup_estimation.log", replace

global folder "$REPLICATION_ROOT"

*-------------------------
* 1. Data cleaning 
*-------------------------

/* LABOR DATA CHECKS: tab number_of_employees if manuf == 1

gen byte lobs = !missing(number_of_employees) & number_of_employees != "NA"

bys firm_id: egen byte anyL = max(lobs)
bys firm_id: egen shareL = mean(lobs)

tab anyL
sum shareL, detail

bys firm_id: gen byte firmtag = (_n==1)
sum shareL if firmtag & anyL==1, detail

bys firm_id: egen nL = total(lobs)
tab nL if firmtag, m
tab nL if firmtag & anyL==1, m */

* 1.1. Basics
use "$DATA_DERIVED\ORBIS\orbis_ppi.dta", clear

gen turnover = operating_revenue_turnover_ / (ppi/100)
gen cogs = costs_of_goods_sold / (ppi/100)
gen tfa = tangible_fixed_assets / (ppi/100)
gen itfa = intangible_fixed_assets / (ppi/100)

drop if turnover<=0 | cogs<=0 | tfa<=0

/* Light trim extreme outliers to reduce accounting noise (!!)
gen rx = turnover/cogs
drop if rx > r(p99) | rx < r(p1) */

* 1.2. Logs
gen lnR = ln(turnover)
gen lnM = ln(cogs)
gen lnK = ln(tfa)

xtset firm_id year

*-----------------------
* 2. Baseline markup estimation
*-----------------------

* Create translog terms
gen M2 = lnM^2
gen K2 = lnK^2
gen MK = lnM*lnK 

* Estimate translog production function
destring nace4, replace
reg lnR c.lnM c.lnK c.M2 c.K2 c.MK i.nace4 i.year

* Recover firm-year elasticity of COGS
gen a_M = _b[lnM] + 2*_b[M2]*lnM + _b[MK]*lnK

* Markup
gen mu = a_M * (turnover/cogs)
gen ln_mu = ln(mu)
by firm_id (year): gen dln_mu = ln_mu - ln_mu[_n-1]

summarize mu ln_mu dln_mu

* Checks
sum a_M, detail
sum mu, detail

tabstat ln_mu dln_mu, by(year) stat(n mean p50 sd)

destring isic4, replace

save "$DATA_DERIVED\ORBIS\orbis_ppi.dta", replace
log close

*---------------
* 3. Robustness
*---------------
cap which prodest
if _rc ssc install prodest, replace

prodest lnR, free(lnM) state(lnK) proxy(lnM) method(wrdg) id(firm_id) t(year) poly(3)







/* 1.3. Total capital stock 
gen K_total = tangible_fixed_assets + intangible_fixed_assets
gen log_K = log(K_total)


// Estimate both TFA and ITFA, compare sensitivity

* 1.4. Material
gen M_adj_1 = costs_of_goods_sold * (1 - labor_share - 0.10)
gen M_adj = costs_of_goods_sold * (1 - labor_share - 0.05)
gen M_adj = costs_of_goods_sold * (1 - labor_share - 0.15)

gen log_M = log(M_adj)

*-------------------------------------------
* 2. Revenue production function estimation
*-------------------------------------------
prodest log_Y, free(log_M_adj) state(log_K) proxy(log_M_adj) method(wrdg) id(firm_id) t(year) va acf

*--------------------------
* 3. Revenue-based markup
*--------------------------

matrix b = e(b) 
scalar output_elas_M = b[1, "log_M"]

gen cost_share_M = M_adj / operating_revenue_turnover_

gen markup_revenue = output_elas_M / cost_share_M

winsor2 markup_revenue, cut(1 99) replace 

** 4. Import competition 


























