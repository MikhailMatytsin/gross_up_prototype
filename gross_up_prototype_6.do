capture program drop list_to_sum
program define list_to_sum
syntax, varlist(string) scen(string)

gen `varlist'_`scen' = 0
foreach var in ${`varlist'} {
	replace `varlist'_`scen' = `varlist'_`scen' + `var'_`scen'
	assert !mi(`varlist'_`scen')
}

end

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

capture program drop SSC_direct_taxes_statutory
program define SSC_direct_taxes_statutory
syntax, pit_taxable_list(namelist) pit_rate(real) sic_taxable_list(namelist) sic_rate(real) scen(string) 

foreach tax in pit sic {
	cap drop `tax'_base_`scen'
	gen `tax'_base_`scen' = 0
	foreach var in ``tax'_taxable_list' {
		mvencode `var'_stat_`scen', mv(0) override
		replace `tax'_base_`scen' = `tax'_base_`scen' + `var'_stat_`scen'
	}

	foreach var in ``tax'_taxable_list' {
		cap drop `tax'_sh_`var'_`scen'
		gen `tax'_sh_`var'_`scen' = `var'_stat_`scen' / `tax'_base_`scen'
	}

	foreach var in $market_income {
		cap gen `tax'_sh_`var'_`scen' = 0
	}

	cap drop `tax'_`scen'
	gen `tax'_`scen' = -1 * ``tax'_rate' * `tax'_base_`scen'

}
end




global market_income 				labor_inc self_inc other_inc
global direct_taxes					pit
global SSC							sic

global pit_rate_b = 0.13
global sic_rate_b = 0.3

global pit_rate_r = 0.13
global sic_rate_r = 0.6


global pit_pt_b = 1
global sic_pt_b = 1

global pit_pt_r = ${pit_pt_b}
global sic_pt_r = ${sic_pt_b}

global d = 10 ^ (-10)
global report = 1

set varabbrev off
clear
set obs 1
gen hh_id = _n
gen p_id = 1
gen labor_inc_net_b = 87 // this is net
gen self_inc_net_b = 25
gen other_inc_net_b = 50


list_to_sum, varlist(market_income) scen(net_b)



* step 1. finding statutory (contract) wages
foreach var in $market_income {
	gen `var'_stat_b = `var'_net_b // starting point
}

local s = 1
scalar max_gap = $d * 2 // to start the cycle

while max_gap > $d | min_gap < -$d {
	
	SSC_direct_taxes_statutory, pit_taxable_list(labor_inc) pit_rate(${pit_rate_b}) sic_taxable_list(labor_inc) sic_rate(${sic_rate_b}) scen(b) 

	foreach var in $market_income {
		cap drop `var'_net_it 
		gen `var'_net_it = `var'_stat_b + pit_b * pit_sh_`var'_b
		
		cap drop `var'_gap
		gen `var'_gap =  `var'_net_b - `var'_net_it
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

* step 2. Calculating equilibrium incomes:
foreach var in $market_income {
	gen `var'_eq_b = `var'_net_b
	foreach tax in $SSC $direct_taxes {
		replace `var'_eq_b = `var'_eq_b - ${pit_pt_b} * `tax'_sh_`var'_b * `tax'_b
	}
	assert  !mi(`var'_eq_b) 
}

* Step 3. Nowcasting
foreach var in $market_income {
	gen `var'_eq_r = `var'_eq_b 
}
xxxxxxxxxxx
* step 4. calculating the statutory wage for reform case via loop to make sure that the equilibrium wage matches.
foreach var in $market_income {
	gen `var'_stat_r = `var'_eq_r // starting point
}

local s = 1
scalar max_gap = $d * 2 // to start the cycle

while max_gap > $d | min_gap < -$d {
	
	SSC_direct_taxes_statutory, pit_taxable_list(labor_inc) pit_rate(${pit_rate_b}) sic_taxable_list(labor_inc) sic_rate(${sic_rate_b}) scen(r)
	
	foreach var in $market_income {
		
	cap drop `var'_net_r
	gen `var'_eq_r = 0
	foreach tax in $direct_taxes {
		replace `var'_net_r = `var'_net_r - ${pit_pt_r} * `tax'_sh_`var'_r * `tax'_r
	}
		
	cap drop `var'_eq_r
	gen `var'_eq_r = `var'_net_r
	foreach tax in $SSC $direct_taxes {
		replace `var'_eq_r = `var'_eq_r - ${pit_pt_r} * `tax'_sh_`var'_r * `tax'_r
	}
	assert  !mi(`var'_eq_r) 
}
	
	cap drop labor_inc_eq_it
	gen labor_inc_eq_it = labor_inc_net_r - ${pit_pt_r} * pit_r - ${sic_pt_r} * sic_r
	
	cap drop other_inc_eq_it
	gen other_inc_eq_it = other_inc_net_r

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap =  `var'_eq_r - `var'_eq_it
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
		qui replace `var'_stat_r = `var'_stat_r + `var'_gap 
	}
	local s = `s' + 1
}
disp "end at step `s'"
su *_gap

su labor_inc_net_b labor_inc_net_r other_inc_net_b other_inc_net_r labor_inc_eq_r other_inc_eq_r
