capture program drop direct_taxes_netting_down
program define direct_taxes_netting_down
syntax, 

gen PIT = -0.13 * labor_market_income
gen labor_market_income_it = labor_market_income + PIT

foreach var in $direct_taxes {
	cap gen `var' = 0
}
end

capture program drop SSC_netting_down
program define SSC_netting_down
syntax, 

gen SIC = -0.3 * (labor_market_income_it ) / (1 + 0.3) // we need to convert this to net base. In worst case we can do a separate iterative procedure. 
replace labor_market_income_it = labor_market_income_it + SIC
gen other_income_it = other_income

foreach var in $SSC {
	cap gen `var' = 0
}
end

// MAKE THE cycle working with *_it

global market_income 				labor_market_income other_income
global direct_taxes					PIT
global SSC							SIC

global d = 10 ^ (-10)
global s_max = 10 ^ 2

/*
clear 
set obs 1000
gen hh_id = _n
gen p_id = 1
gen labor_market_income = 100 + 10 * _n
gen other_income = 5000 - 3 * _n
*/
set varabbrev off
clear
set obs 1
gen hh_id = _n
gen p_id = 1
gen labor_market_income = 87 // this is net
gen other_income = 0


mvencode ${market_income}, mv(0) override
egen net_market_income_orig = rowtotal(${market_income})
assert !mi(net_market_income_orig)


foreach var in $market_income {
	gen `var'_orig = `var'
}

*gen diff = .


* finding gross_labor_market_income
forvalues s = 1 / $s_max {
	
	foreach var in $direct_taxes $SSC labor_market_income_it other_income_it {
		cap drop `var'
	}
	
	direct_taxes_netting_down
	SSC_netting_down
	assert !mi(net_market_income_orig)

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap = `var'_it - `var'_orig
	}
	
	global report = 1
	if floor(`s' / $report) * $report == `s' {
		disp "step `s'"
		su *_gap
	}
	
	scalar max_gap = 0
	scalar min_gap = 0
	
	foreach var in $market_income {
		qui su `var'_gap
		scalar max_gap = max(max_gap,`r(max)')
		scalar min_gap = min(min_gap,`r(min)')
	}	
	
	if max_gap <= ${d} & min_gap >= -${d} {
		disp "end at step `s'"
		su *_gap
		continue, break
	}
	
	foreach var in $market_income {
		qui replace `var' = `var' - `var'_gap 
	}
	local s = `s' + 1

}

keep hh_id p_id ${market_income} net_market_income_orig *_orig
mvencode ${market_income} net_market_income_orig, mv(0) override  

	direct_taxes_netting_down
	SSC_netting_down


mvencode ${SSC} ${direct_taxes}, mv(0) override 

egen net_market_income = rowtotal(${market_income} ${SSC} ${direct_taxes})
egen market_income = rowtotal(${market_income} )
assert round(net_market_income_orig - net_market_income, ${d} * 10) == 0 // this is to check that in baseline the original (survey based) and simulated net market incomes are identical

foreach var in $market_income {
	cap drop gap_`var'
	gen gap_`var' = `var'_it - `var'_orig
}
su gap_*

order hh_id p_id market_income net_market_income_orig net_market_income labor_market_income_orig labor_market_income other_income_orig other_income $SSC $direct_taxes
xxxxxxxxxxxxxxxxxx
/*