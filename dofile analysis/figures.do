clear mata
capture log close
clear


log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\3 figures.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"



*--------------------------------------
* Average Chinese Import penetration
*--------------------------------------
use "$folder\Data\BACI\IP.dta", clear

collapse (mean) IP, by(year)
twoway line IP year, ///
	title("Average Chinese Import Penetration in Turkish Manufacturing") ///
	ytitle("Import Penetration Ratio") ///
	xtitle("Year") ///
	
graph export "$folder\Figs\1 mean_IP_year.jpg", as(jpg) replace

* Distribution p25, p50, p75

use "$folder\Data\BACI\IP.dta", clear

collapse (p10) p10_IP=IP (p50) p50_IP=IP (p90) p90_IP=IP, by(year)

twoway ///
(rarea p10_IP p90_IP year, sort color(gs12)) ///
(line p50_IP year, lwidth(medthick)), ///
title("Distribution of Chinese Import Penetration Across Turkish Sectors") ///
ytitle("Import Penetration Ratio") ///
xtitle("Year") ///
legend(order(2 "Median" 1 "p10–p90"))

graph export "$folder\Figs\2 IP_distribution_year_10_90.jpg", as(jpg) replace



*-----------------------------
* Distribution of Change of import penetration
*-----------------------------
use "$folder\Data\data_ready.dta", clear

collapse (mean) change_IP, by(isic4 year)
collapse (p10) p10=change_IP (p50) p50=change_IP (p90) p90=change_IP, by(year)

twoway ///
 (line p10 year) ///
 (line p50 year) ///
 (line p90 year), ///
 legend(order(1 "P10" 2 "P50" 3 "P90")) ///
 ytitle("China import penetration (ISIC4)") xtitle("Year")
 
graph export "$folder\Figs\change_IP_p10_90.jpg", as(jpg) replace


*--------------------------------
* Lorenz curve of market shares
*--------------------------------

use "$folder\Data\data_ready.dta", clear
sort share_sales
gen firm = _n 
gen cum_firms = firm/_N
gen cum_sales = sum(share_sales)
replace cum_sales = cum_sales / cum_sales[_N]

twoway ///
(line cum_sales cum_firms, sort lwidth(medthick)) ///
(function y=x, range(0 1) lpattern(dash)), ///
xlabel(0(.2)1) ylabel(0(.2)1) ///
xtitle("Cumulative share of firms") ///
ytitle("Cumulative share of domestic sales")

graph export "$folder\Figs\lorenz_1.jpg", as(jpg) replace


*=======================
* Summary statistics
*=======================

*------- Main text

use "$folder\Data\data_ready.dta", clear
gen exporter = (export_revenue>0)

cap drop sample_main
gen sample_main = inrange(year, 2011, 2019)

* keep obs with baseline variables observed
replace sample_main = 0 if missing(dln_mu, exit, ebit_margin_, lnSize, leverage, liquidity_ratio_x_, age, exporter, change_IP, output_IV, Z_input, ls_pre_filled, HHI_dom)

* label
label variable dln_mu              "Markup adjustment (\$\Delta \ln \mu_{ijt}\$)"
label variable exit                "Exit"
label variable ebit_margin_        "EBIT margin"
label variable lnSize              "Log firm size"
label variable leverage            "Leverage"
label variable liquidity_ratio_x_  "Liquidity ratio"
label variable age                 "Firm age"
label variable exporter            "Exporter dummy"

label variable change_IP           "Change in Chinese import penetration (\$\Delta IP_{jt}\$)"
label variable output_IV           "Output-competition IV"
label variable Z_input             "Input-supply control"
label variable ls_pre_filled       "Pre-period labor share"
label variable HHI_dom                 "HHI"

* panel A: firm-level variables
eststo clear

estpost tabstat dln_mu exit ebit_margin_ lnSize leverage liquidity_ratio_x_ age exporter ///
	if sample_main == 1, statistics(n mean sd p50 min max) columns(statistics)
	
eststo mainA

* panel B: sector-year variables 
preserve 
keep if sample_main == 1
collapse (mean) change_IP output_IV Z_input ls_pre_filled HHI_dom, by(isic4 year)

estpost tabstat change_IP output_IV Z_input ls_pre_filled HHI_dom, statistics(n mean sd p50 min max) columns(statistics)

eststo mainB
restore

* export table 
esttab mainA mainB using "$folder\Tables\stats_main.tex", ///
    cells("count(fmt(0)) mean(fmt(3)) sd(fmt(3)) p50(fmt(3)) min(fmt(3)) max(fmt(3))") ///
    mtitle("Panel A: Firm-level" "Panel B: Sector-level") ///
    nonumber noobs replace ///
    title("Summary Statistics")
	
	
*--------- Sample structure

* firm
cap drop tag_firm 
egen tag_firm = tag(firm_id) if sample_main == 1
count if tag_firm == 1
local n_firms = r(N)

* firm-year
count if sample_main == 1
local n_firmyear = r(N)

* sector-year
cap drop tag_sector
egen tag_sector = tag(isic4) if sample_main == 1
count if tag_sector == 1
local n_sectors = r(N)

display "Number of firms = `n_firms'"
display "Number of firm-years = `n_firmyear'"
display "Number of sectors = `n_sectors'"
display "Period covered = 2011--2019"


*===============
* First stage
*===============

use "$folder\Data\data_ready_robust.dta", clear
*----- first stage sample
cap drop sample_fs
gen sample_fs = inrange(year, 2011, 2019)
replace sample_fs = 0 if missing(change_IP, output_IV, Z_input, ls_pre_filled, post2016, isic4, year)

drop if missing(firm_id) | missing(year) | missing(isic4)
xtset firm_id year

gen llnsize = L.lnSize 
gen lleverage = L.leverage 
gen lliquidity = L.liquidity_ratio_x_ 
gen l_age = L.age 
gen l_exporter = L.exporter

replace sample_fs = 0 if missing(llnsize, lleverage, lliquidity, l_age, l_exporter, change_IP, output_IV, Z_input, ls_pre_filled, post2016, isic4, year)

* sector and observations
cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if sample_fs == 1
count if tag_sector_fs == 1
local n_sectors = r(N)

count if sample_fs == 1
local n_obs = r(N)

* correlation output and input shocks
corr output_IV Z_input if sample_fs==1
matrix C = r(C)
local corr_oz = C[1,2]

display "Number of sectors = `n_sectors'"
display "Observations = `n_obs'"
display "Corr(output_IV, Z_input) = `corr_oz'"


*------- First stage regressions

eststo clear

* Column 1
reghdfe change_IP output_IV Z_input c.ls_pre_filled##i.post2016 ///
    if sample_fs == 1, absorb(isic4 year) vce(cluster isic4)
eststo fs1

test output_IV
local F_excl1 = r(F)

cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if e(sample)
count if tag_sector_fs == 1
local n_sectors = r(N)

count if e(sample)
local n_obs = r(N)

corr output_IV Z_input if e(sample)
matrix C = r(C)
local corr_oz = C[1,2]

estadd scalar F_excl    = `F_excl1'   : fs1
estadd scalar N_sectors = `n_sectors' : fs1
estadd scalar Corr_OZ   = `corr_oz'   : fs1
estadd scalar N_obs     = `n_obs'     : fs1

* Column 2
reghdfe change_IP output_IV Z_input ///
    llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 ///
    if sample_fs == 1, absorb(isic4 year) vce(cluster isic4)
eststo fs2

test output_IV
local F_excl2 = r(F)

cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if e(sample)
count if tag_sector_fs == 1
local n_sectors2 = r(N)

count if e(sample)
local n_obs2 = r(N)

corr output_IV Z_input if e(sample)
matrix C = r(C)
local corr_oz2 = C[1,2]

estadd scalar F_excl    = `F_excl2'    : fs2
estadd scalar N_sectors = `n_sectors2' : fs2
estadd scalar Corr_OZ   = `corr_oz2'   : fs2
estadd scalar N_obs     = `n_obs2'     : fs2

* export table
estadd local LagCtrls "No"  : fs1
estadd local LagCtrls "Yes" : fs2
estadd local SectorFE "Yes" : fs1
estadd local SectorFE "Yes" : fs2
estadd local YearFE   "Yes" : fs1
estadd local YearFE   "Yes" : fs2

esttab fs1 fs2 using "$folder\Tables\first_stage_diagnostics.tex", ///
    keep(output_IV Z_input) ///
    order(output_IV Z_input) ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    stats(LagCtrls SectorFE YearFE F_excl Corr_OZ N_sectors N, ///
        fmt(0 0 0 2 3 0 0) ///
        labels("Lagged firm controls" ///
               "Sector FE" ///
               "Year FE" ///
               "Excluded-instrument F-stat" ///
               "Corr.($Z^{Output}_{jt}, Z^{Input}_{jt}$)" ///
               "Number of sectors" ///
               "Observations")) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitle("Parsimonious" "Baseline") ///
    replace label nonumber ///
    title("First Stage and Identification Diagnostics")


*------------------------------------
* Number of firms over time
*------------------------------------
use "$folder\Data\data_ready_mec.dta", clear
keep if inrange(year, 2011, 2019)
bysort year firm_id: gen byte tag_firm_year = _n == 1
collapse (sum) n_firms = tag_firm_year, by(year)

twoway line n_firms year, sort ///
    ytitle("Number of firms") ///
    xtitle("Year") ///
    lwidth(medthick)

graph export "$folder\Figs\number_firms_over_time.jpg", as(jpg) replace

*------------------------------------
* Distribution of sector size
*------------------------------------
use "$folder\Data\data_ready_mec.dta", clear
keep if inrange(year, 2011, 2019)
bysort isic4 year firm_id: gen byte tag_firm_sector = _n == 1
bysort isic4 year: egen sector_size = total(tag_firm_sector)
bysort isic4 year: keep if _n == 1

histogram sector_size, discrete percent ///
    ytitle("Percent") ///
    xtitle("Number of firms in sector-year") ///
    fcolor(gs12) lcolor(black)

graph export "$folder\Figs\sector_size_distribution.jpg", as(jpg) replace




*-----------------------------
* Distribution of Change of import penetration
*-----------------------------
use "$folder\Data\data_ready.dta", clear
keep if inrange(year, 2011, 2019)

collapse (mean) change_IP, by(isic4 year)
collapse (p10) p10=change_IP (p50) p50=change_IP (p90) p90=change_IP, by(year)

twoway ///
    (rarea p10 p90 year, sort color(gs12%50)) ///
    (line p50 year, sort lwidth(medthick) msymbol(O) msize(medsmall)), ///
    title("Distribution of Change in Chinese Import Penetration, 2011-2019") ///
    ytitle("Change in import penetration") ///
    xtitle("Year") ///
    xlabel(2011(1)2019) ///
    legend(order(2 "Median" 1 "P10-P90")) ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$folder\Figs\change_IP_p10_90.png", replace




















 

log close
 
 
 
 
 
 
 
 
 
 
 
 
 
