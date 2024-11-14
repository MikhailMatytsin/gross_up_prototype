capture program drop Dir_tax
program define Dir_tax
syntax, 

gen IMSS = - labor_market_income * 0.1

foreach var in $SSC $direct_taxes {
	cap gen `var' = 0
}


end

global market_income 				labor_market_income other_income
global direct_taxes					PIT
global SSC							IMSS

global d = 0.0001
global s_max = 10 ^ 6

global SY_consistency_check = 1

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

gen diff = .


* finding gross_labor_market_income
forvalues s = 1 / $s_max {
	
	foreach var in $direct_taxes $SSC {
		cap drop `var'
	}

	qui Dir_tax
	assert !mi(net_market_income_orig)

	qui egen net_market_income = rowtotal(${market_income} ${SSC} ${direct_taxes})
	qui replace diff = (net_market_income / net_market_income_orig - 1) if net_market_income_orig > 0 & !inrange(diff,-${d},${d})
	drop net_market_income
		
	if floor(`s' / 100) * 100 == `s' {
		disp "step `s'"
		cap drop x y z
		qui gen x = !inrange(diff,-${d},${d})
		qui gen y = diff < -${d}
		qui gen z = diff > ${d}
		su diff x y z
	}
	
	qui su diff
	if `r(max)' <= ${d} & `r(min)' >= -${d} {
		disp "IMSS_p end at step `s'"
		cap drop x y z
		qui gen x = !inrange(diff,-${d},${d})
		qui gen y = diff < -${d}
		qui gen z = diff > ${d}
		su diff x y z
		continue, break
	}

	foreach var in $market_income {
		qui replace `var' = `var' * (1 + ${d}) if diff < -${d}		 & !inrange(diff,-${d},${d})
		qui replace `var' = `var' * (1 - ${d}) if diff >  ${d}		 & !inrange(diff,-${d},${d})
	}
	local s = `s' + 1

}

keep hh_id p_id ${market_income} net_market_income_orig *_orig
mvencode ${market_income} net_market_income_orig, mv(0) override  

qui Dir_tax


mvencode ${SSC} ${direct_taxes}, mv(0) override 
**********************************************************
* Consitency checks. If the policy year equals to survey year the net market income should be identical. 
**********************************************************
if $SY_consistency_check == 1 { 
	egen net_market_income = rowtotal(${market_income} ${SSC} ${direct_taxes})
	assert round((net_market_income / net_market_income_orig - 1) , 10 ^ (-2)) == 0 if net_market_income_orig > 0
	*assert round(net_market_income_orig - net_market_income, 1) == 0 // this is to check that in baseline the original (survey based) and simulated net market incomes are identical
}
replace labor_market_income = labor_market_income + IMSS

foreach var in net_market_income $market_income {
	gen gap_`var' = `var' - `var'_orig
}
su gap_*

order hh_id p_id net_market_income_orig net_market_income labor_market_income_orig labor_market_income other_income_orig other_income $SSC $direct_taxes
xxxxxxxxxxxxxxxxxx
/*