version 17

/*
Replication path configuration for the M2 Development Economics thesis.

Run Stata from the repository root, or set the environment variable
REPLICATION_ROOT before calling any do-file. The code intentionally writes only
inside this repository.
*/

capture confirm global REPLICATION_ROOT
if _rc {
    local envroot : environment REPLICATION_ROOT
    if "`envroot'" != "" {
        global REPLICATION_ROOT "`envroot'"
    }
    else {
        global REPLICATION_ROOT "`c(pwd)'"
    }
}
else if "${REPLICATION_ROOT}" == "" {
    local envroot : environment REPLICATION_ROOT
    if "`envroot'" != "" {
        global REPLICATION_ROOT "`envroot'"
    }
    else {
        global REPLICATION_ROOT "`c(pwd)'"
    }
}

global CODE              "${REPLICATION_ROOT}/code"
global CODE_SETUP        "${CODE}/00_setup"
global CODE_CONSTRUCT    "${CODE}/01_construct"
global CODE_ANALYSIS     "${CODE}/02_analysis"
global CODE_FIGTAB       "${CODE}/03_figures_tables"
global CODE_VALIDATION   "${CODE}/04_calibration_validation"
global CODE_BUILD        "${CODE}/99_build_paper"

global DATA_ROOT         "${REPLICATION_ROOT}/data"

local envraw : environment REPLICATION_DATA_RAW
local envderived : environment REPLICATION_DATA_DERIVED
local envpublic : environment REPLICATION_DATA_PUBLIC

if "`envraw'" != "" {
    global DATA_RAW "`envraw'"
}
else {
    global DATA_RAW "${DATA_ROOT}/restricted_placeholder/raw"
}

if "`envderived'" != "" {
    global DATA_DERIVED "`envderived'"
}
else {
    global DATA_DERIVED "${DATA_ROOT}/restricted_placeholder/derived"
}

if "`envpublic'" != "" {
    global DATA_PUBLIC "`envpublic'"
}
else {
    global DATA_PUBLIC "${DATA_ROOT}/derived_public"
}
global OUTPUT_ROOT       "${REPLICATION_ROOT}/output"
global OUTPUT_TABLES     "${OUTPUT_ROOT}/tables"
global OUTPUT_FIGURES    "${OUTPUT_ROOT}/figures"
global LOGS              "${OUTPUT_ROOT}/logs"
global TEX               "${REPLICATION_ROOT}/tex"

global folder            "${REPLICATION_ROOT}"

foreach d in ///
    "$DATA_RAW" ///
    "$DATA_RAW/Orbis" ///
    "$DATA_RAW/CEPII BACI HS96" ///
    "$DATA_RAW/UNIDO" ///
    "$DATA_RAW/TURKSTAT" ///
    "$DATA_RAW/WIOD" ///
    "$DATA_DERIVED" ///
    "$DATA_DERIVED/Orbis" ///
    "$DATA_DERIVED/BACI" ///
    "$DATA_DERIVED/UNIDO" ///
    "$DATA_DERIVED/Concordance" ///
    "$DATA_DERIVED/IV" ///
    "$DATA_DERIVED/WIOD" ///
    "$DATA_PUBLIC" ///
    "$OUTPUT_TABLES" ///
    "$OUTPUT_FIGURES" ///
    "$LOGS" {
    capture mkdir "`d'"
}

set more off


