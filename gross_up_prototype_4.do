capture program drop SSC_grossing_up
program define SSC_grossing_up
syntax, 

gen SIC = -0.3 * (labor_market_income_contr)  // we need to convert this to net base. In worst case we can do a separate iterative procedure. 
gen labor_market_income_gross = labor_market_income_contr - SIC
gen other_income_gross = other_income

foreach var in $SSC {
	cap gen `var' = 0
}
end

capture program drop direct_taxes_netting_down
program define direct_taxes_netting_down
syntax, 

gen PIT = -0.13 * labor_market_income_contr
gen labor_market_income_net = labor_market_income_contr + PIT
gen other_income_net = other_income

foreach var in $direct_taxes {
	cap gen `var' = 0
}
end


global market_income 				labor_market_income other_income
global direct_taxes					PIT
global SSC							SIC

global d = 10 ^ (-10)
global s_max = 10 ^ 2

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
	gen `var'_contr = 0 // starting point
}

*gen diff = .


* step 1. finding contrat wages (gross for PIT and SSC)
forvalues s = 1 / $s_max {
	
	foreach var in $direct_taxes labor_market_income_net other_income_net  {
		cap drop `var'
	}
	
	direct_taxes_netting_down

	assert !mi(net_market_income_orig)

	foreach var in $market_income {
		cap drop `var'_gap
		gen `var'_gap =  `var'_orig - `var'_net
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
		qui replace `var'_contr = `var'_contr + `var'_gap 
	}
	local s = `s' + 1

}

* step 2. Calculating gross incomes
SSC_grossing_up
replace labor_market_income = labor_market_income_contr - SIC
assert round(labor_market_income + SIC + PIT - labor_market_income_orig, 10 ^ (-10)) == 0
assert other_income == other_income_orig

keep hh_id p_id ${market_income} net_market_income_orig *_orig
mvencode ${market_income} net_market_income_orig, mv(0) override  

* step 3. Calculating contract wages via iterative process
foreach var in $market_income {
	gen `var'_orig2 = `var'
	gen `var'_contr = 0 // starting point
}

forvalues s = 1 / $s_max {
	
	foreach var in $SSC labor_market_income_gross other_income_gross {
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
		qui replace `var'_contr = `var'_contr + `var'_gap 
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
order hh_id p_id market_income net_market_income_orig net_market_income labor_market_income_orig labor_market_income other_income_orig other_income $SSC $direct_taxes
xxxxxxxxxxxxxxxxxx
/*