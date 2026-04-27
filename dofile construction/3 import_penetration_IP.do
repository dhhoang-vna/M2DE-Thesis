clear mata
capture log close
clear

*********************************
**** UNIDO INDSTAT4 DATABASE ****
*********************************

* Import INDSTAT4 domestic output (Y) dataset
log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\3 import_penetration_IP.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

cd "$folder\RawData\UNIDO"

import excel "UNIDO TR.xlsx", firstrow clear

rename Year year
rename ActivityCode isic4
rename Activity sector
rename ValueUSD output
keep year isic4 sector output

save "$folder\Data\UNIDO\domestic_output.dta", replace

* ISIC Rev 4 - NACE Rev 2 UNSD concordance
cd "$folder\RawData"
import delimited using "ISIC4_NACE2.txt", varnames(1) stringcols(1/4) clear
rename isic4code isic4
tostring nace2code, replace

gen nace2 = subinstr(nace2code, ".", "", .)
keep isic4 nace2

save "$folder\Data\Concordance\isic4_nace2.dta", replace

* Merge concordance with Domestic output dataset
cd "$folder\Data\UNIDO"
use "domestic_output.dta", clear
tostring isic, replace format(%04.0f)

joinby isic4 using "$folder\Data\Concordance\isic4_nace2.dta"

save "$folder\Data\UNIDO\domestic_output.dta", replace


********************************
**** CEPII BACI HS6 DATABASE****
********************************
 
cd "$folder\RawData\CEPII BACI HS96"


**** IMPORT VALUE (M_jt) - NOMINATOR ****
*****************************************

*------ Year 2011 -------*
import delimited "BACI_HS96_Y2011_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2011.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2011.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2011.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2011.dta", replace

use "$folder\Data\BACI\CHN_TR_2011.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2011.dta"

* Construct ISIC4 level import values (M) - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2011.dta", replace


*------ Year 2012 -------*
import delimited "BACI_HS96_Y2012_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2012.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2012.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2012.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2012.dta", replace

use "$folder\Data\BACI\CHN_TR_2012.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2012.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2012.dta", replace


*------ Year 2013 -------*
import delimited "BACI_HS96_Y2013_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2013.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2013.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2013.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2013.dta", replace

use "$folder\Data\BACI\CHN_TR_2013.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2013.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2013.dta", replace


*------ Year 2014 -------*
import delimited "BACI_HS96_Y2014_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2014.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2014.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2014.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2014.dta", replace

use "$folder\Data\BACI\CHN_TR_2014.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2014.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2014.dta", replace


*------ Year 2015 -------*
import delimited "BACI_HS96_Y2015_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2015.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2015.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2015.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2015.dta", replace

use "$folder\Data\BACI\CHN_TR_2015.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2015.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2015.dta", replace


*------ Year 2016 -------*
import delimited "BACI_HS96_Y2016_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2016.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2016.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2016.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2016.dta", replace

use "$folder\Data\BACI\CHN_TR_2016.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2016.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2016.dta", replace


*------ Year 2017 -------*
import delimited "BACI_HS96_Y2017_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2017.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2017.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2017.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2017.dta", replace

use "$folder\Data\BACI\CHN_TR_2017.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2017.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2017.dta", replace


*------ Year 2018 -------*
import delimited "BACI_HS96_Y2018_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2018.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2018.csv", replace



** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2018.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2018.dta", replace

use "$folder\Data\BACI\CHN_TR_2018.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2018.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2018.dta", replace


*------ Year 2019 -------*
import delimited "BACI_HS96_Y2019_V202501.csv",clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2019.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2019.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2019.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2019.dta", replace

use "$folder\Data\BACI\CHN_TR_2019.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2019.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

save "$folder\Data\BACI\CHN_TR_importvalue_2019.dta", replace


*** Append 2011-2019 import value tables

clear
use "$folder\Data\BACI\CHN_TR_importvalue_2011.dta", clear

forvalues y = 2012/2019 {
	append using "$folder\Data\BACI\CHN_TR_importvalue_`y'.dta"
}

save "$folder\Data\BACI\CHN_TR_importvalue_(2011-19).dta", replace

*******************************************************
**** ABSORPTION AT THE BASELINE YEAR - DENOMINATOR ****
*******************************************************

// Absorption = Y + M(W-TR) - X(TR-W)

* Year 2008 (CEPII BACI)

clear all

cd "$folder\RawData\CEPII BACI HS96"

import delimited "BACI_HS96_Y2008_V202501.csv", clear

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 792 | importer == 792

//
clear all
set more off
set maxvar 10000


cd "$folder\RawData\CEPII BACI HS96"

tempfile baci_combined
tempfile baci_turkey
tempfile concordance
tempfile combined_allocated
tempfile imports_isic4
tempfile exports_isic4
tempfile trade_combined
tempfile sectoral_output

clear
save `baci_combined', replace emptyok

forvalues year = 2008/2010 {
	import delimited "BACI_HS96_Y`year'_V202501.csv", clear
	keep if j == 792 | i == 792
	append using `baci_combined'
	save `baci_combined', replace
}


tostring k, replace format(%06.0f) 
gen length_k = length(k) //to ensure HS6 codes have leading zeros 
tab length_k

replace k = "0" + k if length_k == 5
replace k = "00" + k if length_k == 4 
replace k = "000" + k if length_k == 3
replace k = "0000" + k if length_k == 2
replace k = "00000" + k if length_k == 1

assert length(k) == 6
drop length_k

rename k hs6

// Create trade flow indicators
gen byte is_import = (j == 792)
gen byte is_export = (i == 792)

label variable is_import "=1 if Turkey is importer"
label variable is_export "=1 if Turkey is exporter"

tab is_import is_export

save `baci_turkey', replace
save "$folder\Data\BACI\mx_pre.dta", replace
preserve 
keep hs6
duplicates drop

export delimited using "hs6_pre.csv", replace

// Import concordance table 
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_pre.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_pre.dta", replace

use "$folder\Data\BACI\mx_pre.dta", clear

merge m:m hs6 using "$folder\Data\BACI\hs96_isic4_pre.dta"

keep if _merge == 3
drop _merge

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring v share, replace force

gen value_isic = v * share

collapse (sum) value_isic, by(t i j isic4)

save "$folder\Data\BACI\mx_2008-10.dta", replace

use "$folder\Data\BACI\mx_2008-10.dta", clear

tab t 
gen byte is_import = (j == 792)
gen byte is_export = (i == 792)

tab is_import is_export
tab t is_import
tab t is_export

* Aggregate imports from World to Turkey by ISIC4 and year
preserve
keep if is_import == 1
collapse (sum) import_value=value_isic ///
         (count) n_import_partners=i, ///
         by(t isic4)

save "$folder\Data\BACI\imports_pre.dta", replace
restore

* Aggregate exports from Turkey to the world by ISIC4 and year
preserve
keep if is_export == 1
collapse (sum) export_value=value_isic ///
         (count) n_export_partners=j, ///
         by(t isic4)
		 
save "$folder\Data\BACI\exports_pre.dta", replace
restore

use "$folder\Data\BACI\imports_pre.dta", clear
merge 1:1 t isic4 using "$folder\Data\BACI\exports_pre.dta"
tab _merge t
tab _merge

* Replace missing with zero 
replace import_value = 0 if missing(import_value)
replace export_value = 0 if missing(export_value)
replace n_import_partners = 0 if missing(n_import_partners)
replace n_export_partners = 0 if missing(n_export_partners)

drop _merge

save "$folder\Data\BACI\mx_pre2011.dta", replace

* Merge INDSTAT4 dataset for production output with import/export dataset
use "$folder\Data\UNIDO\domestic_output.dta", clear

destring year, replace

rename year t

keep t isic4 sector output

duplicates report t isic4
duplicates drop t isic4, force  // Keep first if duplicates exist

label variable t "Year"
label variable isic4 "ISIC Rev. 4 sector (4-digit)"
label variable sector "Sector description"
label variable output "Sectoral output (USD)"

* Summary by year
display _newline "=== UNIDO Production Data Summary ==="
table t, statistic(count isic4) statistic(sum output) statistic(mean output)

* Check completeness: how many sectors per year?
bysort t: gen n_sectors = _N
tab t n_sectors
destring t, replace

save "$folder\Data\UNIDO\output_pre.dta", replace

merge 1:1 t isic4 using "$folder\Data\BACI\mx_pre2011.dta"

drop if t == 2008

* Drop observations with missing in the core vars and keep manufacturing only

destring isic4, replace
drop if missing(t, isic4, output, import_value, export_value)
keep if inrange(isic4, 1000, 3399)

save "$folder\Data\BACI\ymx_pre.dta", replace

clear
*** A TWIST: UNIDO ISDB has the apparent consumption = absorption calculated already !!!

import excel "$folder\RawData\UNIDO\ISDB TR.xlsx", firstrow

rename Year year
rename ActivityCode isic4

keep year isic4 Value
destring year, replace
keep if year >= 2011 & year <= 2019

gen apparent_consumption = Value/1000
drop Value
destring isic4, replace

save "$folder\Data\UNIDO\apparent_consumption.dta", replace


* Merge

use "$folder\Data\BACI\CHN_TR_importvalue_(2011-19).dta", clear
destring isic4, replace
keep if inrange(isic4, 1000, 3399)
save "$folder\Data\BACI\CHN_TR_importvalue_(2011-19).dta", replace

merge m:1 isic4 year using "$folder\Data\UNIDO\apparent_consumption.dta"
gen IP = value_isic / apparent_consumption

drop _merge
drop if missing(apparent_consumption)
tab isic4

use "$folder\Data\BACI\IP.dta", clear

xtset isic4 year
gen change_IP = D.IP

save "$folder\Data\BACI\IP.dta", replace


log close
















