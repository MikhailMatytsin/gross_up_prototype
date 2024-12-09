* PARAMETERS FOR SIMULATIONS

global pit_rate_b = 0.13
global sic_rate_b = 0.3

global pit_rate_r = 0.26
global sic_rate_r = 0.3

global pit_pt_b = 1
global sic_pt_b = 1

global pit_pt_r = 1
global sic_pt_r = 1

* We assume that statutory income includes PIT and excludes SIC

global market_income 				labor_inc self_inc other_inc
global direct_taxes					pit
global SSC							sic

global d = 10 ^ (-8)
global report = 1
*======================================================================

capture program drop SSC_direct_taxes_statutory
program define SSC_direct_taxes_statutory
syntax, pit_taxable_list(namelist) sic_taxable_list(namelist) 

foreach tax in pit sic {
	cap drop `tax'_base
	gen `tax'_base = 0
	foreach inc in ``tax'_taxable_list' {
		*qui mvencode `inc'_stat, mv(0) override
		qui replace `tax'_base = `tax'_base + `inc'_stat
	}

	foreach inc in ``tax'_taxable_list' {
		cap drop `tax'_sh_`inc'
		gen `tax'_sh_`inc' = `inc'_stat / `tax'_base
	}

	foreach inc in $market_income {
		cap gen `tax'_sh_`inc' = 0
	}

	cap drop `tax'_stat `tax'
	gen `tax'_stat = -1 * ${`tax'_rate} * `tax'_base
	gen `tax' = `tax'_stat * ${`tax'_pt}

}
end

set varabbrev off
clear
set obs 1
gen hh_id = _n
gen p_id = 1
gen labor_inc = 87 // this is net
gen self_inc = 25
gen other_inc = 50

* step 1. finding statutory (contract) wages
foreach inc in $market_income {
	rename `inc' `inc'_orig
	gen `inc'_stat = `inc'_orig // starting point
}

global sic_rate = ${sic_rate_b} // in the actual code this can be replaced by matrices
global pit_rate = ${pit_rate_b}

global sic_pt = ${sic_pt_b} // in the actual code this can be replaced by matrices
global pit_pt = ${pit_pt_b}

local s = 1
scalar max_gap = $d * 2 // to start the cycle
scalar min_gap = 0 // to start the cycle

* the iterartion is via statutory income
while (max_gap > $d | min_gap < -$d) {
	
	SSC_direct_taxes_statutory, pit_taxable_list(labor_inc self_inc) sic_taxable_list(labor_inc) 

	foreach inc in $market_income {
		
		* we calculate net income as statutory plus all taxes and SSC
		cap drop `inc'_net_it
		gen `inc'_net_it = `inc'_stat
		foreach tax in $direct_taxes {
			qui replace `inc'_net_it = `inc'_net_it + `tax'_sh_`inc' * `tax'_stat 
		}
		
		* we calculate gap between net and original
		cap drop `inc'_gap
		gen `inc'_gap =  `inc'_orig - `inc'_net_it
	}
	

	if floor(`s' / $report) * $report == `s' {
		disp "step `s'"
		su *_gap
	}
	
	scalar max_gap = 0
	scalar min_gap = 0
	
	foreach inc in $market_income {
		qui su `inc'_gap
		scalar max_gap = max(max_gap,`r(max)')
		scalar min_gap = min(min_gap,`r(min)')
	}	
	
	* we adjust statutory to decrease the gap
	foreach inc in $market_income {
		qui replace `inc'_stat = `inc'_stat + `inc'_gap 
	}
	local s = `s' + 1
}
disp "end at step `s'"
su *_gap

* step 2. we calculate equilibrium income as net minus all taxes and SSC
foreach inc in $market_income {
	gen `inc' = `inc'_orig
	foreach tax in $SSC $direct_taxes {
		replace `inc' = `inc' - `tax'_sh_`inc' * `tax'
	}
	assert  !mi(`inc') 
}

* This is for prototype only
*++++++++++++++++++++++++++++++++++++++++++
foreach inc in $market_income {
	rename `inc'_orig `inc'_net_b
	gen `inc'_eq_b = `inc'
	rename `inc'_stat `inc'_stat_b
}

foreach tax in $SSC $direct_tax {
	rename `tax' `tax'_b
	rename `tax'_stat `tax'_stat_b
	rename `tax'_base `tax'_base_b
	rename `tax'_sh_* `tax'_sh_*_b
}
*++++++++++++++++++++++++++++++++++++++++++


*keep hh_id p_id ${market_income}

* Step 3. Nowcasting
foreach inc in $market_income {
	replace `inc' = `inc' * 1  
}

* step 4. calculating the statutory wage for reform case via loop to make sure that the equilibrium wage matches.
foreach inc in $market_income {
	gen `inc'_stat = `inc' // starting point
}

global sic_rate = ${sic_rate_r} // in the actual code this can be replaced by matrices
global pit_rate = ${pit_rate_r}

global sic_pt = ${sic_pt_r} // in the actual code this can be replaced by matrices
global pit_pt = ${pit_pt_r}


local s = 1
scalar max_gap = $d * 2 // to start the cycle
scalar min_gap = 0 // to start the cycle

* the iterartion is via statutory income
while (max_gap > $d | min_gap < -$d) {
	
	SSC_direct_taxes_statutory, pit_taxable_list(labor_inc self_inc) sic_taxable_list(labor_inc)
	
	foreach inc in $market_income {
		
		* we calculate net income as statutory plus all taxes and SSC 
		cap drop `inc'_net
		gen `inc'_net = `inc'_stat
		foreach tax in $direct_taxes {
			qui replace `inc'_net = `inc'_net + `tax'_sh_`inc' * `tax'_stat
		}
		
		* we calculate equilibrium income as net minus all taxes and SSC
		cap drop `inc'_eq_it
		gen `inc'_eq_it = `inc'_net
		foreach tax in $SSC $direct_taxes {
			qui replace `inc'_eq_it = `inc'_eq_it - `tax'_sh_`inc' * `tax'
		}
		assert  !mi(`inc'_eq_it) 
	
		* we calculate gap between equlibrium and simulated equlibrium
		cap drop `inc'_gap
		gen `inc'_gap =  `inc' - `inc'_eq_it
	}
	
	if floor(`s' / $report) * $report == `s' {
		disp "step `s'"
		su *_gap
	}
	
	scalar max_gap = 0
	scalar min_gap = 0
	
	foreach inc in $market_income {
		qui su `inc'_gap
		scalar max_gap = max(max_gap,`r(max)')
		scalar min_gap = min(min_gap,`r(min)')
	}	
	
	* we adjust the statutory to decrease the gap
	foreach inc in $market_income {
		qui replace `inc'_stat = `inc'_stat + `inc'_gap 
	}
	local s = `s' + 1
}
disp "end at step `s'"
su *_gap


* This is for prototype only
*++++++++++++++++++++++++++++++++++++++++++
foreach inc in $market_income {
	rename `inc'_net `inc'_net_r
	gen `inc'_eq_r = `inc'
	rename `inc'_stat `inc'_stat_r
}

foreach tax in $SSC $direct_tax {
	rename `tax' `tax'_r
	rename `tax'_stat `tax'_stat_r
	rename `tax'_base `tax'_base_r
	rename `tax'_sh_* `tax'_sh_*_r
}


foreach inc in $market_income {
	su `inc'_net_b `inc'_net_r `inc'_eq_b `inc'_stat_b `inc'_stat_r
}
*++++++++++++++++++++++++++++++++++++++++++