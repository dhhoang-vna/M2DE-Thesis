capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
ROBUSTNESS CHECK: CHINESE PRODUCT GRANULARITY
- Refinement 2: add Chinese product-granularity controls and interactions
- Refinement 3: separate domestic concentration from Chinese product granularity
- Uses BACI HS6 -> ISIC4 product-HHI proxy from 4_chinese_granularity.do
***********************************************************************/

clear mata
capture log close
clear all
set more off

global folder "$REPLICATION_ROOT"
log using "$LOGS\4_robustness_chn_gran.log", replace

foreach cmd in reghdfe ivreghdfe eststo esttab estadd {
    capture which `cmd'
    if _rc {
        di as error "`cmd' is not installed. Install it before running this do-file."
        exit 199
    }
}

capture program drop _decorate_chn_gran_table
program define _decorate_chn_gran_table
    syntax, Texfile(string asis) Label(string) Caption(string asis)
    local texfile : subinstr local texfile `"""' "", all
    local label : subinstr local label `"""' "", all
    local caption : subinstr local caption `"""' "", all

    tempfile rawtex
    copy `"`texfile'"' `"`rawtex'"', replace

    file open fin using `"`rawtex'"', read text
    file open fout using `"`texfile'"', write text replace

    file read fin line
    while r(eof) == 0 {
        if `"`line'"' == `"\caption{`caption'}"' {
            file write fout `"`line'"' _n
            file write fout `"\label{`label'}"' _n
            file write fout `"\scriptsize"' _n
            file write fout `"\setlength{\tabcolsep}{3pt}"' _n
            file write fout `"\begin{adjustbox}{max width=\textwidth}"' _n
        }
        else if `"`line'"' == `"\end{tabular}"' {
            file write fout `"`line'"' _n
            file write fout `"\end{adjustbox}"' _n
        }
        else {
            file write fout `"`line'"' _n
        }
        file read fin line
    }

    file close fin
    file close fout
end

capture confirm file "$DATA_DERIVED\BACI\IP_chinese_granularity.dta"
if _rc {
    di as error "Missing $DATA_DERIVED\BACI\IP_chinese_granularity.dta"
    di as error "Run dofile construction\4_chinese_granularity.do first."
    exit 601
}

use "$DATA_DERIVED\data_ready_mec.dta", clear

drop if missing(firm_id) | missing(year) | missing(isic4)
capture drop _merge

merge m:1 isic4 year using "$DATA_DERIVED\BACI\IP_chinese_granularity.dta", ///
    keep(master match) nogen ///
    keepusing(hhi_prod_chn G_chn_prod L_hhi_prod_chn L_G_chn_prod ///
              n_hs6_chn max_hs6_share_chn eff_n_hs6_chn entropy_hs6_chn ///
              IP_bfns_c_s4 IP_bfns_c_s5 IP_bfns_c_s6 ///
              IP_bfns_p_s4 IP_bfns_p_s5 IP_bfns_p_s6)

xtset firm_id year
sort firm_id year

* Rebuild lagged controls defensively in case the working dataset changed.
capture confirm variable exporter
if _rc {
    gen byte exporter = export_revenue > 0 if !missing(export_revenue)
}

capture confirm variable l_exporter
if _rc {
    gen byte l_exporter = L.exporter
}

capture confirm variable llnsize
if _rc {
    gen double llnsize = L.lnSize
}

capture confirm variable lleverage
if _rc {
    gen double lleverage = L.leverage
}

capture confirm variable lliquidity
if _rc {
    gen double lliquidity = L.liquidity_ratio_x_
}

capture confirm variable l_age
if _rc {
    gen double l_age = L.age
}

global X_lag "lleverage lliquidity llnsize l_age l_exporter"

* Construct sector-year lag of domestic concentration.
preserve
keep isic4 year HHI_dom
collapse (mean) HHI_dom, by(isic4 year)
isid isic4 year
xtset isic4 year
gen double L_HHI_dom = L.HHI_dom
keep isic4 year L_HHI_dom
tempfile sector_lag_hhi
save `sector_lag_hhi', replace
restore

merge m:1 isic4 year using `sector_lag_hhi', keep(master match) nogen

* Baseline estimation sample for standardizing heterogeneity variables.
gen byte sample_main = inrange(year, 2011, 2019) ///
    & !missing(dln_mu, change_IP, output_IV, Z_input, ///
               lleverage, lliquidity, llnsize, l_age, l_exporter, ///
               ls_pre_filled, post2016, L_hhi_prod_chn, L_HHI_dom)

quietly summarize L_hhi_prod_chn if sample_main
gen double z_L_hhi_prod_chn = (L_hhi_prod_chn - r(mean)) / r(sd)
label var z_L_hhi_prod_chn "Lagged Chinese product HHI, standardized"

quietly summarize L_HHI_dom if sample_main
gen double z_L_HHI_dom = (L_HHI_dom - r(mean)) / r(sd)
label var z_L_HHI_dom "Lagged domestic HHI, standardized"

quietly summarize L_G_chn_prod if sample_main & !missing(L_G_chn_prod)
gen double z_L_G_chn_prod = (L_G_chn_prod - r(mean)) / r(sd) if !missing(L_G_chn_prod)
label var z_L_G_chn_prod "Lagged Chinese IP x product HHI, standardized"

* Interactions for IV specifications. Standardization makes interaction
* coefficients interpretable as the change in the IP effect for a 1 s.d. shift.
gen double changeIP_chnhhi = change_IP * z_L_hhi_prod_chn
gen double outputIV_chnhhi = output_IV * z_L_hhi_prod_chn

gen double changeIP_Gprod = change_IP * z_L_G_chn_prod
gen double outputIV_Gprod = output_IV * z_L_G_chn_prod

gen double changeIP_domHHI = change_IP * z_L_HHI_dom
gen double outputIV_domHHI = output_IV * z_L_HHI_dom

gen double changeIP_dom_chn = change_IP * z_L_HHI_dom * z_L_hhi_prod_chn
gen double outputIV_dom_chn = output_IV * z_L_HHI_dom * z_L_hhi_prod_chn

label var changeIP_chnhhi "China IP x lagged Chinese product HHI"
label var changeIP_Gprod  "China IP x lagged Chinese IP-HHI"
label var changeIP_domHHI "China IP x lagged domestic HHI"
label var changeIP_dom_chn "China IP x domestic HHI x Chinese product HHI"

save "$DATA_DERIVED\data_ready_mec_chn_gran.dta", replace


/***********************************************************************
ROBUSTNESS CHECK TABLE BLOCK: CHINESE PRODUCT GRANULARITY
Drop-in replacement from Section 1 through Section 2 table exports.
Assumes all variables and interactions have already been constructed.
***********************************************************************/

*====================================================
* 0. Clean labels for all tables
*====================================================

label var dln_mu              "Markup growth, $\Delta \log \mu$"
label var change_IP           "Chinese import-penetration growth"
label var output_IV           "Output-competition IV"
label var Z_input             "Chinese input-supply exposure"

label var z_L_hhi_prod_chn    "Lagged Chinese product HHI, standardized"
label var z_L_G_chn_prod      "Lagged Chinese IP-HHI exposure, standardized"
label var z_L_HHI_dom         "Lagged domestic HHI, standardized"

label var changeIP_chnhhi     "China IP $\times$ Chinese product HHI"
label var changeIP_Gprod      "China IP $\times$ Chinese IP-HHI exposure"
label var changeIP_domHHI     "China IP $\times$ domestic HHI"
label var changeIP_dom_chn    "China IP $\times$ domestic HHI $\times$ Chinese product HHI"

label var outputIV_chnhhi     "Output IV $\times$ Chinese product HHI"
label var outputIV_Gprod      "Output IV $\times$ Chinese IP-HHI exposure"
label var outputIV_domHHI     "Output IV $\times$ domestic HHI"
label var outputIV_dom_chn    "Output IV $\times$ domestic HHI $\times$ Chinese product HHI"

label var lleverage           "Lagged leverage"
label var lliquidity          "Lagged liquidity"
label var llnsize             "Lagged log size"
label var l_age               "Lagged firm age"
label var l_exporter          "Lagged exporter status"

* Common esttab options.
local tabopts replace se label booktabs compress nogaps nonotes collabels(none) ///
    star(* 0.10 ** 0.05 *** 0.01)

*====================================================
* 1. Mean IV regressions: refinements 2 and 3
*====================================================

eststo clear

* Baseline from data_ready_mec, restricted to the sample with granularity support.
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main, ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "Baseline"
estadd scalar me_m1 = .
scalar me0_tmp = _b[change_IP]
estadd scalar me_0 = me0_tmp
estadd scalar me_p1 = .
eststo chg_base

* Refinement 2a: foreign granularity control only.
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    z_L_hhi_prod_chn Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main, ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "+ China product HHI"
estadd scalar me_m1 = .
scalar me0_tmp = _b[change_IP]
estadd scalar me_0 = me0_tmp
estadd scalar me_p1 = .
eststo chg_ctrl_hhi

* Refinement 2b: foreign granularity interaction.
ivreghdfe dln_mu ///
    (change_IP changeIP_chnhhi = output_IV outputIV_chnhhi) ///
    z_L_hhi_prod_chn Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main, ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "China product HHI interaction"

lincom change_IP - changeIP_chnhhi
estadd scalar me_m1 = r(estimate)

lincom change_IP
estadd scalar me_0 = r(estimate)

lincom change_IP + changeIP_chnhhi
estadd scalar me_p1 = r(estimate)

eststo chg_int_hhi

* Alternative refinement 2: exposure-weighted BFNS proxy IP x HHI.
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    z_L_G_chn_prod Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main & !missing(z_L_G_chn_prod), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "+ China IP-HHI"
estadd scalar me_m1 = .
scalar me0_tmp = _b[change_IP]
estadd scalar me_0 = me0_tmp
estadd scalar me_p1 = .
eststo chg_ctrl_G

ivreghdfe dln_mu ///
    (change_IP changeIP_Gprod = output_IV outputIV_Gprod) ///
    z_L_G_chn_prod Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main & !missing(z_L_G_chn_prod), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "China IP-HHI interaction"

lincom change_IP - changeIP_Gprod
estadd scalar me_m1 = r(estimate)

lincom change_IP
estadd scalar me_0 = r(estimate)

lincom change_IP + changeIP_Gprod
estadd scalar me_p1 = r(estimate)

eststo chg_int_G

* Refinement 3: domestic concentration and foreign product granularity together.
ivreghdfe dln_mu ///
    (change_IP changeIP_domHHI changeIP_chnhhi = ///
        output_IV outputIV_domHHI outputIV_chnhhi) ///
    z_L_HHI_dom z_L_hhi_prod_chn ///
    Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main, ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

capture estadd scalar kpF = e(widstat)
estadd local spec "Domestic HHI + China product HHI"

lincom change_IP - changeIP_chnhhi
estadd scalar me_m1 = r(estimate)

lincom change_IP
estadd scalar me_0 = r(estimate)

lincom change_IP + changeIP_chnhhi
estadd scalar me_p1 = r(estimate)

eststo chg_dom_for

esttab chg_base chg_ctrl_hhi chg_int_hhi chg_ctrl_G chg_int_G chg_dom_for ///
    using "$OUTPUT_TABLES\rob_chn_gran_mean.tex", ///
    `tabopts' ///
    mtitles("Baseline" ///
            "+ China product HHI" ///
            "China product HHI $\times$ IP" ///
            "+ China IP-HHI" ///
            "China IP-HHI $\times$ IP" ///
            "Domestic + foreign granularity") ///
    keep(change_IP changeIP_chnhhi changeIP_Gprod changeIP_domHHI ///
         z_L_hhi_prod_chn z_L_G_chn_prod z_L_HHI_dom Z_input) ///
    order(change_IP changeIP_chnhhi changeIP_Gprod changeIP_domHHI ///
          z_L_hhi_prod_chn z_L_G_chn_prod z_L_HHI_dom Z_input) ///
    stats(me_m1 me_0 me_p1 N kpF spec, ///
          fmt(3 3 3 0 2 %s) ///
          labels("IP effect at Chinese granularity $-1$ s.d." ///
                 "IP effect at Chinese granularity mean" ///
                 "IP effect at Chinese granularity $+1$ s.d." ///
                 "Observations" ///
                 "Kleibergen-Paap rk Wald F" ///
                 "Specification")) ///
    addnotes("All specifications include ISIC4 sector fixed effects, year fixed effects, lagged firm controls, the input-supply exposure control, and pre-period size $\times$ post-2016 controls." ///
             "Chinese import penetration and its interaction terms are instrumented by the corresponding output-IV terms." ///
             "Heterogeneity variables are standardized using the baseline Chinese-granularity estimation sample. Standard errors are clustered by ISIC4 sector.") ///
    title("Chinese product granularity and incumbent markup adjustment")

_decorate_chn_gran_table, texfile("$OUTPUT_TABLES\rob_chn_gran_mean.tex") ///
    label("tab:rob_chn_gran_mean") ///
    caption("Chinese product granularity and incumbent markup adjustment")


*====================================================
* Optional strict relative-oligopoly triple interaction
*====================================================

capture noisily ivreghdfe dln_mu ///
    (change_IP changeIP_domHHI changeIP_chnhhi changeIP_dom_chn = ///
        output_IV outputIV_domHHI outputIV_chnhhi outputIV_dom_chn) ///
    z_L_HHI_dom z_L_hhi_prod_chn ///
    Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_main, ///
    absorb(isic4) vce(cluster isic4) partial(i.year)

if !_rc {
    capture estadd scalar kpF = e(widstat)
    estadd local spec "Triple interaction"
    eststo chg_triple

    esttab chg_triple using "$OUTPUT_TABLES\rob_chn_gran_triple.tex", ///
        `tabopts' ///
        mtitles("Triple interaction") ///
        keep(change_IP changeIP_domHHI changeIP_chnhhi changeIP_dom_chn ///
             z_L_HHI_dom z_L_hhi_prod_chn Z_input) ///
        order(change_IP changeIP_domHHI changeIP_chnhhi changeIP_dom_chn ///
              z_L_HHI_dom z_L_hhi_prod_chn Z_input) ///
        stats(N kpF spec, ///
              fmt(0 2 %s) ///
              labels("Observations" ///
                     "Kleibergen-Paap rk Wald F" ///
                     "Specification")) ///
        addnotes("This specification estimates whether the China import-competition effect varies jointly with domestic concentration and Chinese product granularity." ///
                 "Chinese import penetration and all interaction terms are instrumented by the corresponding output-IV terms." ///
                 "Standard errors are clustered by ISIC4 sector.") ///
        title("Relative oligopoly triple interaction")

    _decorate_chn_gran_table, texfile("$OUTPUT_TABLES\rob_chn_gran_triple.tex") ///
        label("tab:rob_chn_gran_triple") ///
        caption("Relative oligopoly triple interaction")
}


*====================================================
* 2. Grouped IV quantiles: distributional effects
*====================================================

preserve

keep firm_id isic4 year dln_mu change_IP output_IV Z_input ///
     changeIP_chnhhi outputIV_chnhhi changeIP_domHHI outputIV_domHHI ///
     z_L_hhi_prod_chn z_L_HHI_dom ///
     lleverage lliquidity llnsize l_age l_exporter ///
     ls_pre_filled post2016 sample_main

keep if sample_main

bys isic4 year: egen n_jt = count(dln_mu)

bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen l_exporter_j = mean(l_exporter)

label var n_jt          "Sector-year firm count"
label var lleverage_j   "Mean lagged leverage"
label var lliquidity_j  "Mean lagged liquidity"
label var llnsize_j     "Mean lagged log size"
label var l_age_j       "Mean lagged firm age"
label var l_exporter_j  "Mean lagged exporter status"

foreach p in 25 50 75 90 {
    bys isic4 year: egen q`p' = pctile(dln_mu), p(`p')
    label var q`p' "Q`p' of markup growth, $\Delta \log \mu$"
}

gen double n2 = n_jt^2
gen double n3 = n_jt^3

label var n2 "Sector-year firm count squared"
label var n3 "Sector-year firm count cubed"

global n_poly "n_jt n2 n3"
global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

bys isic4 year: keep if _n == 1
isid isic4 year


*----------------------------------------------------
* 2a. Grouped-IV quantiles: Chinese product granularity
*----------------------------------------------------

eststo clear

foreach p in 25 50 75 90 {
    ivreghdfe q`p' ///
        (change_IP changeIP_chnhhi = output_IV outputIV_chnhhi) ///
        z_L_hhi_prod_chn Z_input $n_poly $X_lag_j ///
        c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    capture estadd scalar kpF = e(widstat)
    estadd local pct "Q`p'"
    eststo qhhi_`p'
}

esttab qhhi_25 qhhi_50 qhhi_75 qhhi_90 ///
    using "$OUTPUT_TABLES\rob_chn_gran_givq_foreign.tex", ///
    `tabopts' ///
    mtitles("Q25" "Q50" "Q75" "Q90") ///
    keep(change_IP changeIP_chnhhi z_L_hhi_prod_chn Z_input) ///
    order(change_IP changeIP_chnhhi z_L_hhi_prod_chn Z_input) ///
    stats(N kpF pct, ///
          fmt(0 2 %s) ///
          labels("Sector-year observations" ///
                 "Kleibergen-Paap rk Wald F" ///
                 "Quantile")) ///
    addnotes("The dependent variable is the indicated sector-year quantile of firm-level markup growth." ///
             "All specifications include ISIC4 sector fixed effects, year fixed effects, sector-year cell-size polynomial controls, averaged lagged firm controls, the input-supply exposure control, and pre-period size $\times$ post-2016 controls." ///
             "Chinese import penetration and its interaction with Chinese product granularity are instrumented by the corresponding output-IV terms. Standard errors are clustered by ISIC4 sector.") ///
    title("Grouped IV quantiles: Chinese product granularity interaction")

_decorate_chn_gran_table, texfile("$OUTPUT_TABLES\rob_chn_gran_givq_foreign.tex") ///
    label("tab:rob_chn_gran_givq_foreign") ///
    caption("Grouped IV quantiles: Chinese product granularity interaction")


*----------------------------------------------------
* 2b. Grouped-IV quantiles: domestic and Chinese granularity
*----------------------------------------------------

eststo clear

foreach p in 25 50 75 90 {
    ivreghdfe q`p' ///
        (change_IP changeIP_domHHI changeIP_chnhhi = ///
            output_IV outputIV_domHHI outputIV_chnhhi) ///
        z_L_HHI_dom z_L_hhi_prod_chn ///
        Z_input $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    capture estadd scalar kpF = e(widstat)
    estadd local pct "Q`p'"
    eststo qdf_`p'
}

esttab qdf_25 qdf_50 qdf_75 qdf_90 ///
    using "$OUTPUT_TABLES\rob_chn_gran_givq_dom_foreign.tex", ///
    `tabopts' ///
    mtitles("Q25" "Q50" "Q75" "Q90") ///
    keep(change_IP changeIP_domHHI changeIP_chnhhi ///
         z_L_HHI_dom z_L_hhi_prod_chn Z_input) ///
    order(change_IP changeIP_domHHI changeIP_chnhhi ///
          z_L_HHI_dom z_L_hhi_prod_chn Z_input) ///
    stats(N kpF pct, ///
          fmt(0 2 %s) ///
          labels("Sector-year observations" ///
                 "Kleibergen-Paap rk Wald F" ///
                 "Quantile")) ///
    addnotes("The dependent variable is the indicated sector-year quantile of firm-level markup growth." ///
             "All specifications include ISIC4 sector fixed effects, year fixed effects, sector-year cell-size polynomial controls, averaged lagged firm controls, the input-supply exposure control, and pre-period size $\times$ post-2016 controls." ///
             "Chinese import penetration and its interactions with domestic concentration and Chinese product granularity are instrumented by the corresponding output-IV terms. Standard errors are clustered by ISIC4 sector.") ///
    title("Grouped IV quantiles: domestic and Chinese granularity")

_decorate_chn_gran_table, texfile("$OUTPUT_TABLES\rob_chn_gran_givq_dom_foreign.tex") ///
    label("tab:rob_chn_gran_givq_dom_foreign") ///
    caption("Grouped IV quantiles: domestic and Chinese granularity")

restore

log close


