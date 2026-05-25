capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
SYNTHETIC CONTROL COUNTERFACTUAL FOR ISIC4 2790

This final SCM do-file keeps only the two thesis specifications selected
from the exploratory runs:

    1. Preferred sensitivity:
       ISIC4 2790, treatment year 2015, baseline donor pool, full predictors.

    2. Conservative timing check:
       ISIC4 2790, treatment year 2016, baseline donor pool, full predictors,
       synth's nested optimization.

Outcome:
    Sector inverse markup = sum_i s_ijt * (1 / mu_ijt)

For inverse markups, the pro-competitive prediction is a positive gap:
    treated inverse markup - synthetic inverse markup > 0

Outputs:
    Data/scm_sector_panel.dta
    Data/scm_gaps.dta
    Data/scm_summary_raw.dta
    Data/scm_summary.dta
    Data/scm_weights.dta
    Tables/scm_summary.csv
    Tables/scm_summary.tex
    Tables/scm_weights.csv
    Tables/scm_weights_treated.csv
    Figs/scm_path_spec*.png
    Figs/scm_gap_spec*.png
***********************************************************************/

clear mata
capture log close
clear
set more off

global folder "$REPLICATION_ROOT"

capture mkdir "$LOGS"
capture mkdir "$DATA_DERIVED"
capture mkdir "$OUTPUT_TABLES"
capture mkdir "$OUTPUT_FIGURES"

log using "$LOGS\6_scm.log", replace

*==============================*
* 0. SETTINGS
*==============================*

local requested_start        2010
local requested_end          2019
local exposure_base_year     2010
local exposure_mid_year      2015
local exposure_end_year      2019
local treated_isic4          2790
local placebo_prefit_mult    5

local full_predictors "HHI_dom lnSize leverage liquidity_ratio_x_ age exporter ls_pre_filled n_firms"

local source_data "$DATA_DERIVED\data_ready_mec.dta"
capture confirm file "`source_data'"
if _rc {
    di as error "Missing data_ready_mec.dta; run the data construction steps first."
    exit 601
}

capture which synth
if _rc {
    display as text "synth is not installed; attempting: ssc install synth"
    capture noisily ssc install synth, replace
}

capture which synth
if _rc {
    display as error "The Stata package synth is required. Run: ssc install synth"
    exit 499
}

*==============================*
* 1. SYNTH RUNNER
*==============================*

capture program drop scm_run_one
program define scm_run_one, rclass
    syntax , Sectorpanel(string) Specid(integer) Specname(string) ///
        Target(integer) Isplacebo(integer) Donorvar(name) Treatyear(integer) ///
        Lastyear(integer) Gapfile(string) Weightfile(string) Summaryfile(string) ///
        [Predictors(string) Synthopts(string)]

    tempfile synthout one_gap one_summary one_weight

    local prestart = 2010
    local preend = `treatyear' - 1

    use "`sectorpanel'", clear

    quietly summarize isic4 if unit_id == `target', meanonly
    local target_isic4 = r(min)

    keep if unit_id == `target' | (`donorvar' == 1 & unit_id != `target')

    quietly levelsof unit_id if unit_id != `target', local(donors)
    local n_donors : word count `donors'
    if (`n_donors' < 2) {
        return scalar rc = 460
        exit
    }

    xtset unit_id year

    capture noisily synth y_invmu ///
        y_invmu(`prestart'(1)`preend') `predictors', ///
        trunit(`target') ///
        trperiod(`treatyear') ///
        xperiod(`prestart'(1)`preend') ///
        mspeperiod(`prestart'(1)`preend') ///
        resultsperiod(`prestart'(1)`lastyear') ///
        keep("`synthout'") replace `synthopts'

    local synth_rc = _rc
    if (`synth_rc' != 0) {
        return scalar rc = `synth_rc'
        exit
    }

    * Paths and gaps.
    use "`synthout'", clear

    capture confirm variable _time
    if _rc {
        return scalar rc = 498
        exit
    }
    capture confirm variable _Y_treated
    if _rc {
        return scalar rc = 498
        exit
    }
    capture confirm variable _Y_synthetic
    if _rc {
        return scalar rc = 498
        exit
    }

    rename _time year
    rename _Y_treated y_treated
    rename _Y_synthetic y_synth

    keep year y_treated y_synth
    keep if !missing(year)

    gen double gap = y_treated - y_synth
    gen byte pre = inrange(year, `prestart', `preend')
    gen byte post = inrange(year, `treatyear', `lastyear')
    gen int spec_id = `specid'
    gen str60 spec_name = "`specname'"
    gen long target_unit = `target'
    gen double target_isic4 = `target_isic4'
    gen byte is_placebo = `isplacebo'
    gen int treat_year = `treatyear'

    save `one_gap', replace

    capture confirm file "`gapfile'"
    if !_rc {
        append using "`gapfile'"
    }
    save "`gapfile'", replace

    use `one_gap', clear
    gen double gap_sq = gap^2

    quietly summarize gap_sq if pre, meanonly
    local pre_rmspe = .
    if (r(N) > 0) local pre_rmspe = sqrt(r(mean))

    quietly summarize gap_sq if post, meanonly
    local post_rmspe = .
    if (r(N) > 0) local post_rmspe = sqrt(r(mean))

    quietly summarize gap if post, meanonly
    local avg_post_gap = .
    if (r(N) > 0) local avg_post_gap = r(mean)

    local rmspe_ratio = .
    if (`pre_rmspe' > 0 & `pre_rmspe' < .) {
        local rmspe_ratio = `post_rmspe' / `pre_rmspe'
    }

    clear
    set obs 1
    gen int spec_id = `specid'
    gen str60 spec_name = "`specname'"
    gen long target_unit = `target'
    gen double target_isic4 = `target_isic4'
    gen byte is_placebo = `isplacebo'
    gen int treat_year = `treatyear'
    gen double pre_rmspe = `pre_rmspe'
    gen double post_rmspe = `post_rmspe'
    gen double rmspe_ratio = `rmspe_ratio'
    gen double avg_post_gap = `avg_post_gap'
    gen int n_donors = `n_donors'

    save `one_summary', replace

    capture confirm file "`summaryfile'"
    if !_rc {
        append using "`summaryfile'"
    }
    save "`summaryfile'", replace

    * Donor weights.
    use "`synthout'", clear
    capture confirm variable _Co_Number
    if !_rc {
        capture confirm variable _W_Weight
        if !_rc {
            rename _Co_Number unit_id
            rename _W_Weight weight
            keep unit_id weight
            keep if !missing(unit_id, weight)
            gen int spec_id = `specid'
            gen str60 spec_name = "`specname'"
            gen long target_unit = `target'
            gen double target_isic4 = `target_isic4'
            gen byte is_placebo = `isplacebo'
            gen int treat_year = `treatyear'
            save `one_weight', replace

            capture confirm file "`weightfile'"
            if !_rc {
                append using "`weightfile'"
            }
            save "`weightfile'", replace
        }
    }

    return scalar rc = 0
end

*==============================*
* 2. BUILD SECTOR-YEAR PANEL
*==============================*

use "`source_data'", clear
capture drop _merge

foreach v in H_china_dep exporter IP change_IP output_IV Z_input ls_pre_filled ///
    HHI_dom lnSize leverage liquidity_ratio_x_ age {
    capture confirm variable `v'
    if _rc gen double `v' = .
}

foreach required in dom_sales mu firm_id isic4 year {
    capture confirm variable `required'
    if _rc {
        display as error "`required' is required for the SCM exercise."
        exit 111
    }
}

capture confirm variable export_revenue
if !_rc {
    replace exporter = (export_revenue > 0) if missing(exporter) & !missing(export_revenue)
}

keep if inrange(year, `requested_start', `requested_end')
drop if missing(isic4, year, firm_id, mu, dom_sales)
drop if mu <= 0
drop if dom_sales < 0

gen double inv_mu = 1 / mu
gen byte one_firmobs = 1

* Rebuild domestic-sales shares on the surviving sample.
bys isic4 year: egen double dom_j = total(dom_sales)
gen double share_sales_scm = dom_sales / dom_j if dom_j > 0
bys isic4 year: egen double y_invmu = total(share_sales_scm * inv_mu)
gen double mu_j = 1 / y_invmu
gen double ln_mu_j = ln(mu_j)

collapse (mean) y_invmu mu_j ln_mu_j IP change_IP output_IV Z_input ///
    ls_pre_filled H_china_dep HHI_dom lnSize leverage liquidity_ratio_x_ ///
    age exporter dom_j ///
    (sum) n_firms = one_firmobs, by(isic4 year)

isid isic4 year
egen long unit_id = group(isic4), label
xtset unit_id year

label variable y_invmu "Sector inverse markup"
label variable mu_j "Sector harmonic markup"
label variable n_firms "Firm observations in sector-year"

tempfile sectorpanel
save `sectorpanel', replace

*==============================*
* 3. DONOR SCREEN
*==============================*

use `sectorpanel', clear

gen byte in_pre_screen = inrange(year, 2010, 2014)
gen byte in_panel = inrange(year, 2010, 2019)

bys unit_id: egen int n_y_pre = total(in_pre_screen & !missing(y_invmu))
bys unit_id: egen int n_y_panel = total(in_panel & !missing(y_invmu))

gen double n_firms_pre_tmp = n_firms if in_pre_screen
bys unit_id: egen double avg_n_pre = mean(n_firms_pre_tmp)
drop n_firms_pre_tmp

gen double y_pre_tmp = y_invmu if in_pre_screen
bys unit_id: egen double pre_sd_y = sd(y_pre_tmp)
drop y_pre_tmp

gen double H_tmp = H_china_dep if in_pre_screen
bys unit_id: egen double input_exposure = mean(H_tmp)
drop H_tmp
replace input_exposure = 0 if missing(input_exposure)

gen double ip_base_tmp = IP if year == `exposure_base_year'
gen double ip_mid_tmp  = IP if year == `exposure_mid_year'
gen double ip_end_tmp  = IP if year == `exposure_end_year'

bys unit_id: egen double IP_base = max(ip_base_tmp)
bys unit_id: egen double IP_mid  = max(ip_mid_tmp)
bys unit_id: egen double IP_end  = max(ip_end_tmp)

drop ip_base_tmp ip_mid_tmp ip_end_tmp

gen double dIP_base_mid = IP_mid - IP_base
gen double dIP_base_end = IP_end - IP_base

gen double dIP_flow_mid_tmp = change_IP if inrange(year, `exposure_base_year' + 1, `exposure_mid_year')
gen double dIP_flow_end_tmp = change_IP if inrange(year, `exposure_base_year' + 1, `exposure_end_year')
bys unit_id: egen double dIP_flow_mid = total(dIP_flow_mid_tmp)
bys unit_id: egen double dIP_flow_end = total(dIP_flow_end_tmp)
drop dIP_flow_mid_tmp dIP_flow_end_tmp

replace dIP_base_mid = dIP_flow_mid if missing(dIP_base_mid)
replace dIP_base_end = dIP_flow_end if missing(dIP_base_end)

gen double dIP_screen = dIP_base_end
replace dIP_screen = dIP_base_mid if missing(dIP_screen)

gen byte complete_pre = (n_y_pre == 5)
gen byte complete_panel = (n_y_panel == 10)

quietly _pctile dIP_screen if complete_pre & complete_panel & avg_n_pre >= 15 & !missing(dIP_screen), p(60)
local donor_exposure_cut = r(r1)

quietly _pctile input_exposure if complete_pre & complete_panel & avg_n_pre >= 15 & !missing(input_exposure), p(75)
local input_cut = r(r1)

quietly _pctile pre_sd_y if complete_pre & complete_panel & avg_n_pre >= 15 & !missing(pre_sd_y), p(90)
local prevol_cut = r(r1)

gen byte donor_base = complete_pre & complete_panel & avg_n_pre >= 15 ///
    & dIP_screen <= `donor_exposure_cut' ///
    & input_exposure <= `input_cut' ///
    & pre_sd_y <= `prevol_cut' ///
    & !missing(dIP_screen, pre_sd_y)

tempfile screens
preserve
    bys unit_id: keep if _n == 1
    keep unit_id isic4 donor_base dIP_base_mid dIP_base_end dIP_screen ///
        avg_n_pre pre_sd_y input_exposure
    save `screens', replace
restore

merge m:1 unit_id using `screens', nogen update replace

quietly levelsof unit_id if isic4 == `treated_isic4', local(treated_unit)
if "`treated_unit'" == "" {
    display as error "ISIC4 `treated_isic4' was not found in the SCM panel."
    exit 498
}

replace donor_base = 0 if unit_id == `treated_unit'

save "$DATA_DERIVED\scm_sector_panel.dta", replace
save `sectorpanel', replace

local scm_smoke : environment REPLICATION_SCM_SMOKE
if "`scm_smoke'" == "1" {
    display as text "Running SCM smoke mode: one treated nested SCM; no thesis outputs overwritten."
    tempfile smoke_gapfile smoke_weightfile smoke_summaryfile

    quietly scm_run_one, sectorpanel(`sectorpanel') specid(99) ///
        specname("smoke_T2016_nested_full") target(`treated_unit') isplacebo(0) ///
        donorvar(donor_base) treatyear(2016) lastyear(2019) ///
        gapfile(`smoke_gapfile') weightfile(`smoke_weightfile') summaryfile(`smoke_summaryfile') ///
        predictors("`full_predictors'") synthopts("nested")

    if (r(rc) != 0) {
        display as error "SCM smoke run failed with rc = " r(rc)
        local fail_rc = r(rc)
        exit `fail_rc'
    }

    use `smoke_summaryfile', clear
    list spec_id spec_name target_isic4 treat_year pre_rmspe post_rmspe rmspe_ratio avg_post_gap n_donors, noobs clean

    display as text "SCM smoke exercise complete."
    log close
    exit
}

*==============================*
* 4. RUN THE TWO FINAL SPECIFICATIONS
*==============================*

tempfile gapfile weightfile summaryfile

forvalues spec = 1/2 {
    if (`spec' == 1) {
        local spec_name "preferred_T2015_nested_full"
        local treat_year 2015
        local synth_opts "nested"
    }
    else {
        local spec_name "conservative_T2016_nested_full"
        local treat_year 2016
        local synth_opts "nested"
    }

    display as text "Running SCM spec `spec': `spec_name'"

    quietly scm_run_one, sectorpanel(`sectorpanel') specid(`spec') ///
        specname("`spec_name'") target(`treated_unit') isplacebo(0) ///
        donorvar(donor_base) treatyear(`treat_year') lastyear(2019) ///
        gapfile(`gapfile') weightfile(`weightfile') summaryfile(`summaryfile') ///
        predictors("`full_predictors'") synthopts("`synth_opts'")

    if (r(rc) != 0) {
        display as error "Treated SCM failed for spec `spec' with rc = " r(rc)
        local fail_rc = r(rc)
        exit `fail_rc'
    }

    use `sectorpanel', clear
    levelsof unit_id if donor_base == 1 & unit_id != `treated_unit', local(placebo_units)
    local n_placebos_all : word count `placebo_units'
    display as text "Running `n_placebos_all' placebo synths for spec `spec'."

    foreach p of local placebo_units {
        capture quietly scm_run_one, sectorpanel(`sectorpanel') specid(`spec') ///
            specname("`spec_name'") target(`p') isplacebo(1) ///
            donorvar(donor_base) treatyear(`treat_year') lastyear(2019) ///
            gapfile(`gapfile') weightfile(`weightfile') summaryfile(`summaryfile') ///
            predictors("`full_predictors'") synthopts("`synth_opts'")
    }
}

capture confirm file "`summaryfile'"
if _rc {
    display as error "No SCM runs were saved."
    exit 498
}

*==============================*
* 5. PLACEBO INFERENCE
*==============================*

use `summaryfile', clear
save "$DATA_DERIVED\scm_summary_raw.dta", replace

preserve
    keep if is_placebo == 0
    keep spec_id spec_name target_unit target_isic4 treat_year ///
        pre_rmspe post_rmspe rmspe_ratio avg_post_gap n_donors
    rename target_unit treated_unit
    rename target_isic4 treated_isic4
    rename pre_rmspe treated_pre_rmspe
    rename post_rmspe treated_post_rmspe
    rename rmspe_ratio treated_rmspe_ratio
    rename avg_post_gap treated_avg_post_gap
    rename n_donors treated_n_donors
    tempfile treated_summary
    save `treated_summary', replace
restore

keep if is_placebo == 1
merge m:1 spec_id using `treated_summary', keep(match) nogen

gen byte placebo_keep = pre_rmspe <= `placebo_prefit_mult' * treated_pre_rmspe ///
    if !missing(pre_rmspe, treated_pre_rmspe)
replace placebo_keep = 0 if missing(placebo_keep)

gen byte ratio_ge_treated = placebo_keep & (rmspe_ratio >= treated_rmspe_ratio) ///
    if !missing(rmspe_ratio, treated_rmspe_ratio)
replace ratio_ge_treated = 0 if missing(ratio_ge_treated)

gen byte avg_gap_ge_treated = placebo_keep & (avg_post_gap >= treated_avg_post_gap) ///
    if !missing(avg_post_gap, treated_avg_post_gap)
replace avg_gap_ge_treated = 0 if missing(avg_gap_ge_treated)

bys spec_id: egen int n_placebos = total(placebo_keep)
bys spec_id: egen int n_ratio_ge = total(ratio_ge_treated)
bys spec_id: egen int n_avg_gap_ge = total(avg_gap_ge_treated)

gen double p_rmspe_ratio = (n_ratio_ge + 1) / (n_placebos + 1) if n_placebos < .
gen double p_avg_gap_pos = (n_avg_gap_ge + 1) / (n_placebos + 1) if n_placebos < .

bys spec_id: keep if _n == 1
keep spec_id spec_name treated_unit treated_isic4 treat_year ///
    treated_pre_rmspe treated_post_rmspe treated_rmspe_ratio ///
    treated_avg_post_gap treated_n_donors n_placebos n_ratio_ge ///
    p_rmspe_ratio n_avg_gap_ge p_avg_gap_pos

gen byte preferred_spec = spec_id == 1
gen byte conservative_spec = spec_id == 2

order spec_id spec_name treated_isic4 treat_year treated_pre_rmspe ///
    treated_post_rmspe treated_rmspe_ratio treated_avg_post_gap ///
    n_placebos p_rmspe_ratio p_avg_gap_pos

sort spec_id
save "$DATA_DERIVED\scm_summary.dta", replace
export delimited using "$OUTPUT_TABLES\scm_summary.csv", replace

file open texout using "$OUTPUT_TABLES\scm_summary.tex", write replace
file write texout "\begin{tabular}{llrrrrr}" _n
file write texout "\hline" _n
file write texout "Spec. & Timing & Pre RMSPE & Post/Pre RMSPE & Avg. gap & Placebos & p-ratio \\" _n
file write texout "\hline" _n

forvalues i = 1/`=_N' {
    local c_spec = strtrim(string(spec_id[`i'], "%9.0f"))
    local c_time = strtrim(string(treat_year[`i'], "%9.0f"))
    local c_pre  = strtrim(string(treated_pre_rmspe[`i'], "%9.4f"))
    local c_rat  = strtrim(string(treated_rmspe_ratio[`i'], "%9.2f"))
    local c_gap  = strtrim(string(treated_avg_post_gap[`i'], "%9.4f"))
    local c_np   = strtrim(string(n_placebos[`i'], "%9.0f"))
    local c_p    = strtrim(string(p_rmspe_ratio[`i'], "%9.3f"))
    file write texout "`c_spec' & T0=`c_time' & `c_pre' & `c_rat' & `c_gap' & `c_np' & `c_p' \\" _n
}

file write texout "\hline" _n
file write texout "\end{tabular}" _n
file close texout

*==============================*
* 6. SAVE GAPS AND WEIGHTS
*==============================*

use `gapfile', clear
save "$DATA_DERIVED\scm_gaps.dta", replace

use `weightfile', clear
rename unit_id donor_unit
preserve
    use `screens', clear
    rename unit_id donor_unit
    keep donor_unit isic4 dIP_base_mid dIP_base_end dIP_screen input_exposure avg_n_pre
    tempfile donor_screen
    save `donor_screen', replace
restore
merge m:1 donor_unit using `donor_screen', keep(master match) nogen
rename isic4 donor_isic4
rename dIP_base_mid donor_dIP_base_mid
rename dIP_base_end donor_dIP_base_end
rename dIP_screen donor_dIP_screen
rename input_exposure donor_input_exposure
rename avg_n_pre donor_avg_n_pre
order spec_id spec_name target_isic4 is_placebo target_unit donor_unit donor_isic4 ///
    weight donor_dIP_base_mid donor_dIP_base_end donor_dIP_screen ///
    donor_input_exposure donor_avg_n_pre
save "$DATA_DERIVED\scm_weights.dta", replace

preserve
    keep if weight > 0.001
    export delimited using "$OUTPUT_TABLES\scm_weights.csv", replace
restore

preserve
    keep if is_placebo == 0 & weight > 0.001
    export delimited using "$OUTPUT_TABLES\scm_weights_treated.csv", replace
restore

*==============================*
* 7. FIGURES
*==============================*

forvalues spec = 1/2 {
    use "$DATA_DERIVED\scm_summary.dta", clear
    keep if spec_id == `spec'
    local ty = treat_year[1]
    local xline = `ty' - .5
    if (`spec' == 1) {
        local title_suffix "Preferred: ISIC4 2790, T0=2015"
    }
    else {
        local title_suffix "Conservative: ISIC4 2790, T0=2016 nested"
    }

    use "$DATA_DERIVED\scm_gaps.dta", clear
    keep if spec_id == `spec' & is_placebo == 0
    twoway ///
        (line y_treated year, sort lcolor(navy) lwidth(medthick)) ///
        (line y_synth year, sort lcolor(maroon) lpattern(dash) lwidth(medthick)), ///
        xline(`xline', lpattern(dash) lcolor(gs8)) ///
        ytitle("Sector inverse markup") ///
        xtitle("Year") ///
        title("SCM path: `title_suffix'") ///
        legend(order(1 "Treated" 2 "Synthetic") rows(1) size(small)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$OUTPUT_FIGURES\scm_path_spec`spec'.png", replace

    use "$DATA_DERIVED\scm_gaps.dta", clear
    preserve
        keep if spec_id == `spec' & is_placebo == 1
        collapse (p10) p10_gap = gap (p50) p50_gap = gap (p90) p90_gap = gap, by(year)
        tempfile placebo_band
        save `placebo_band', replace
    restore

    keep if spec_id == `spec' & is_placebo == 0
    merge 1:1 year using `placebo_band', nogen

    twoway ///
        (rarea p10_gap p90_gap year, sort color(gs12)) ///
        (line p50_gap year, sort lcolor(gs8) lpattern(dash)) ///
        (line gap year, sort lcolor(navy) lwidth(thick)), ///
        xline(`xline', lpattern(dash) lcolor(gs8)) ///
        yline(0, lpattern(solid) lcolor(gs10)) ///
        ytitle("Treated minus synthetic inverse markup") ///
        xtitle("Year") ///
        title("SCM gap: `title_suffix'") ///
        legend(order(3 "Treated gap" 2 "Placebo median" 1 "Placebo p10-p90") rows(3) size(small)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$OUTPUT_FIGURES\scm_gap_spec`spec'.png", replace
}

display as text "SCM exercise complete."
display as text "Summary: $OUTPUT_TABLES\scm_summary.csv"
display as text "Treated weights: $OUTPUT_TABLES\scm_weights_treated.csv"
display as text "Figures: $OUTPUT_FIGURES\scm_path_spec*.png and scm_gap_spec*.png"

log close

