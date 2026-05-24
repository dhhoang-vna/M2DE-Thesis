version 17
clear all
capture log close
set more off

do "code/00_setup/config.do"

log using "$LOGS/master_construct.log", replace text

do "$CODE_CONSTRUCT/1 orbis_data.do"
do "$CODE_CONSTRUCT/3 import_penetration_IP.do"
do "$CODE_CONSTRUCT/4 bartik_instrument.do"
do "$CODE_CONSTRUCT/4_chinese_granularity.do"
do "$CODE_CONSTRUCT/5 markup_estimation.do"
do "$CODE_CONSTRUCT/6 labor_share.do"
do "$CODE_CONSTRUCT/7 data_ready.do"

log close
