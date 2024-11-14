capture program drop Dir_tax
program define Dir_tax
syntax, 

gen IMSS = - labor_market_income * 0.1
gen labor_market_income_net = labor_market_income + IMSS
gen other_income_net = other_income

foreach var in $SSC $direct_taxes {
	cap gen `var' = 0
}


end

global market_income 				labor_market_income other_income
global direct_taxes					PIT
global SSC							IMSS

global d = 0.1
global s_max = 10 ^ 6


clear 
set obs 1000
gen hh_id = _n
gen p_id = 1
gen labor_market_income = 100 + 10 * _n
gen other_income = 5000 - 3 * _n



mvencode ${market_income}, mv(0) override
egen net_market_income_orig = rowtotal(${market_income})
assert !mi(net_market_income_orig)


foreach var in $market_income {
	gen `var'_orig = `var'
}

*gen diff = .


* finding gross_labor_market_income
forvalues s = 1 / $s_max {
	
	foreach var in $direct_taxes $SSC labor_market_income_net other_income_net {
		cap drop `var'
	}
	
	qui Dir_tax
	assert !mi(net_market_income_orig)

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap = `var'_net - `var'_orig
	}
	
	
	if floor(`s' / 1000) * 1000 == `s' {
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
		qui replace `var' = `var' + ${d} if `var'_gap < -${d}	//	 & !inrange(diff,-${d},${d})
		qui replace `var' = `var' - ${d} if `var'_gap >  ${d}	//	 & !inrange(diff,-${d},${d})
	}
	local s = `s' + 1

}

keep hh_id p_id ${market_income} net_market_income_orig *_orig
mvencode ${market_income} net_market_income_orig, mv(0) override  

qui Dir_tax


mvencode ${SSC} ${direct_taxes}, mv(0) override 

egen net_market_income = rowtotal(${market_income} ${SSC} ${direct_taxes})
*assert round((net_market_income / net_market_income_orig - 1) , 10 ^ (-2)) == 0 if net_market_income_orig > 0
assert round(net_market_income_orig - net_market_income, 10 ^ (0)) == 0 // this is to check that in baseline the original (survey based) and simulated net market incomes are identical

foreach var in $market_income {
	cap drop gap_`var'
	gen gap_`var' = `var'_net - `var'_orig
}
su gap_*

order hh_id p_id net_market_income_orig net_market_income labor_market_income_orig labor_market_income other_income_orig other_income $SSC $direct_taxes
xxxxxxxxxxxxxxxxxx
/*