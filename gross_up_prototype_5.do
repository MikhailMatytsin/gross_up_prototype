capture program drop SSC_grossing_up
program define SSC_grossing_up
syntax, labor_inc_stat(varname) other_inc_stat(varname) sic_rate(real) sic(string) labor_inc_gross(string) other_inc_gross(string)

cap drop `sic'
gen `sic' = -1 * `sic_rate' * `labor_inc_stat'

cap drop `labor_inc_gross'
gen `labor_inc_gross' = `labor_inc_stat' - `sic'

cap drop `other_inc_gross'
gen `other_inc_gross' = `other_inc_stat'
end

capture program drop direct_taxes_netting_down
program define direct_taxes_netting_down
syntax, labor_inc_stat(varname) other_inc_stat(varname) pit_rate(real) pit(string) labor_inc_net(string) other_inc_net(string)

cap drop `pit'
gen `pit' = -1 * `pit_rate' * `labor_inc_stat'

cap drop `labor_inc_net'
gen `labor_inc_net' = `labor_inc_stat' + `pit'

cap drop `other_inc_net'
gen `other_inc_net' = `other_inc_stat'

end


capture program drop list_to_sum
program define list_to_sum
syntax, varlist(string) suffix(string)

gen `varlist'_`suffix' = 0
foreach var in ${`varlist'} {
	replace `varlist'_`suffix' = `varlist'_`suffix' + `var'_`suffix'
	assert !mi(`varlist'_`suffix')
}

end


global market_income 				labor_inc other_inc
global direct_taxes					PIT
global SSC							SIC

global PIT_rate_b = 0.13
global SIC_rate_b = 0.3

global PIT_rate_r = ${PIT_rate_b}
global SIC_rate_r = ${SIC_rate_b}


global PIT_pt_b = 1
global SIC_pt_b = 1

global PIT_pt_r = ${PIT_pt_b}
global SIC_pt_r = ${SIC_pt_b}

global d = 10 ^ (-10)
global report = 1

set varabbrev off
clear
set obs 1
gen hh_id = _n
gen p_id = 1
gen labor_inc_net_b = 87 // this is net
gen other_inc_net_b = 0


list_to_sum, varlist(market_income) suffix(net_b)
/* same as above
gen market_income_net_b = 0
foreach var in $market_income {
	mvencode `var'_net_b, mv(0) override
	replace market_income_net_b = market_income_net_b + `var'_net_b
}
assert !mi(market_income_net_b)
*/

foreach var in $market_income {
	gen `var'_stat_b = `var'_net_b // starting point
}


* step 1. finding contract wages (gross for PIT and SSC)
local s = 1
scalar max_gap = $d * 2 // to start the cycle

while max_gap > $d | min_gap < -$d {
	
	foreach var in $direct_taxes labor_inc_net other_inc_net  {
		cap drop `var'
	}
	
	direct_taxes_netting_down, labor_inc_stat(labor_inc_stat_b) other_inc_stat(other_inc_stat_b) pit_rate(${PIT_rate_b}) pit(PIT_b) labor_inc_net(labor_inc_it) other_inc_net(other_inc_it)

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap =  `var'_net_b - `var'_it
	}
	

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
	

	foreach var in $market_income {
		qui replace `var'_stat_b = `var'_stat_b + `var'_gap 
	}
	local s = `s' + 1
}
disp "end at step `s'"
su *_gap



* step 2. Calculating SSC using contract wages
SSC_grossing_up, labor_inc_stat(labor_inc_stat_b) other_inc_stat(other_inc_stat_b) sic_rate(${SIC_rate_b}) sic(SIC_b) labor_inc_gross(labor_inc_gross_b) other_inc_gross(other_inc_gross_b)

* step 3. Calculating equilibrium incomes:
gen labor_inc_eq_b = labor_inc_net_b - ${PIT_pt_b} * PIT_b - ${SIC_pt_b} * SIC_b
gen other_inc_eq_b = labor_inc_net_b

	foreach var in $market_income {
		assert  !mi(`var'_eq_b) 
	}

* Step 4. Nowcasting
foreach var in $market_income {
	gen `var'_eq_r = `var'_eq_b 
}

* step 5. 





* Reform case
foreach var in $market_income {
	gen `var'_orig2 = `var'
	gen `var'_stat = 0 // starting point
}

forvalues s = 1 / $s_max {
	
	foreach var in $SSC labor_inc_gross other_inc_gross {
		cap drop `var'
	}
	
	SSC_grossing_up

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap = `var'_orig2 - `var'_gross
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
		qui replace `var'_stat = `var'_stat + `var'_gap 
	}
	local s = `s' + 1

}	
		
	direct_taxes_netting_down


mvencode ${SSC} ${direct_taxes}, mv(0) override 

egen net_market_income = rowtotal(${market_income} ${SSC} ${direct_taxes})
egen market_income = rowtotal(${market_income} )
assert round(net_market_income_orig - net_market_income, ${d} * 10) == 0 // this is to check that in baseline the original (survey based) and simulated net market incomes are identical

foreach var in $market_income {
	cap drop gap_`var'
	gen gap_`var' = `var'_net - `var'_orig
}
su gap_*

su ${market_income} ${SSC} ${direct_taxes}
order hh_id p_id market_income net_market_income_orig net_market_income labor_inc_orig labor_inc other_inc_orig other_inc $SSC $direct_taxes
xxxxxxxxxxxxxxxxxx
/*