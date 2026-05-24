version 17

local packages reghdfe ftools ivreg2 ranktest ivreghdfe boottest estout winsor2 synth prodest

foreach pkg of local packages {
    capture which `pkg'
    if _rc {
        display as text "Installing `pkg' from SSC"
        ssc install `pkg', replace
    }
}
