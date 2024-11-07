/* EXAMPLE:

WN - net wages
WC - contract wages (wages before PIT)
WG - wages gross

NLN - non-labor income net
NLG - non-labor income gross

* PIT = PIT(WC + NLG)
* SSC = SSC(WC)
*/

clear
global N = 100
set obs ${N}

gen WN = .
gen NLN = .

forvalues i = 1 / $N {
	replace WN = 100 + `i' * 10 in `i'
	replace NLN = 600 - `i' * 5 in `i'
} 
assert WN > 0
assert NLN > 0

global max_cut_off = 10 ^ 10 // very big number

* Stage 1. We define marginal rates and cut-offs for two taxes.

* Tax 1 (PIT).
// rates by brackets
global r_1_1 = 0.05
global r_1_2 = 0.15
global r_1_3 = 0.25
global r_1_4 = 0.35
global r_1_5 = 0.45

// cutoffs for gross income
global gc_1_0 = 0
global gc_1_1 = 100
global gc_1_2 = 200
global gc_1_3 = 500
global gc_1_4 = 1000
global gc_1_5 = ${max_cut_off}

scalar N_brack_1 = 5 // I did not find the way to put into the loop $N_brack_`t'

* Tax 2 (SSC).
// rates by brackets
global r_2_1 = 0.10
global r_2_2 = 0.20
global r_2_3 = 0.30

// cutoffs for gross income
global gc_2_0 = 0
global gc_2_1 = 250
global gc_2_2 = 500
global gc_2_3 = ${max_cut_off}

scalar N_brack_2 = 3

local i1 = 1 // index of the bracket for the first tax
local i2 = 1 // index of the bracket for the second tax

* Stage 2. We calculate the rates and the cut-offs for the joint tax such that the value of joint tax is equivalent to the sum of the two taxes separately (we check it later)
global gc_j_0 = 0
forvalues s = 1 / 100 { // we put here high number, but when we reach the maximum, we end the cycle
	
	global gc_j_`s' = min(${gc_1_`i1'}, ${gc_2_`i2'}) // the cutoff for the joint tax is the minimum of the lowest among the two.
	global r_j_`s' = ${r_1_`i1'} + ${r_2_`i2'} // (1 + ${r_1_`i1'}) * (1 + ${r_2_`i2'}) - 1 // the rate is combination of the two rates

	disp "bracket `s'. The rate for income under ${gc_j_`s'} is ${r_j_`s'}"
	*disp "`i1' `i2'"
	*disp " "
	
	if ${gc_j_`s'} == ${max_cut_off} { // we can do this better, but it is fine for now. 
		scalar def N_brack_j = `s'
		continue, break
	}
	
	forvalues t = 1 / 2 {
		if ${gc_j_`s'} == ${gc_`t'_`i`t''} {
		local i`t' = `i`t'' + 1 // if the cutoff for the joint tax equals to the cutoff of either tax1 or tax2, we switch to the next bracket. 
		}
	}
}

* Stage 3. Actual calculator. Defining the net income
gen tax_base_orig = WN + NLN 
gen tax_base_net = tax_base_orig

* Stage 5. from net to gross using the joint tax.
cap drop tax_j
gen tax_j = 0
global nc_j_0 = ${gc_j_0}
global cum_previous_brackets = 0
forvalues i = 1 / `=N_brack_j' { 
	local ii = `i' - 1

	global cum_previous_brackets = ${cum_previous_brackets} + (${gc_j_`i'} - ${gc_j_`ii'}) * ${r_j_`i'}
	global nc_j_`i' = ${gc_j_`i'} - ${cum_previous_brackets}
	disp "net cutoff for bracket `i' is " ${nc_j_`i'}

	qui gen tax_j_`i' = 0 if inrange(tax_base_net, . , ${nc_j_`ii'})
	qui replace tax_j_`i' = -1 * (tax_base_net - ${nc_j_`ii'}) / (1 - ${r_j_`i'}) * ${r_j_`i'} if inrange(tax_base_net, ${nc_j_`ii'}, ${nc_j_`i'})
	qui replace tax_j_`i' = -1 * (${nc_j_`i'}  - ${nc_j_`ii'}) / (1 - ${r_j_`i'}) * ${r_j_`i'} if inrange(tax_base_net, ${nc_j_`i'},.)
	qui replace tax_j = tax_j + tax_j_`i'
	drop tax_j_`i'
}

gen tax_base_gross = tax_base_net - tax_j // tax is negative here

* Stage 6. from gross to net using two separate taxes

*------------------------------------------------------------------------------------------------------------------------
* This program calculates progressive tax
capture program drop progressive_tax_gross_to_net
program define progressive_tax_gross_to_net
syntax, tax_base_gross(varname) tax(string) n_br(real)

	cap drop `tax'
	gen `tax' = 0
	
	forvalues i = 1 / `n_br' {
		local ii = `i' - 1
			
		qui gen double tax_b_`i' = 0 if `tax_base_gross' <= ${gc_${t}_`ii'}
		qui replace tax_b_`i' = -1 * ${r_${t}_`i'} * (`tax_base_gross' - ${gc_${t}_`ii'}) if `tax_base_gross' >  ${gc_${t}_`ii'} & `tax_base_gross' <= ${gc_${t}_`i'}
		qui replace tax_b_`i' = -1 * ${r_${t}_`i'} * (${gc_${t}_`i'} - ${gc_${t}_`ii'}) if `tax_base_gross' >  ${gc_${t}_`i'} 
		
		qui replace `tax' = `tax' + tax_b_`i'
		drop tax_b_`i'
	}

end

capture program drop progressive_tax_net_to_gross
program define progressive_tax_net_to_gross
syntax, tax_base_net(varname) tax(string) n_br(real)

	cap drop `tax'
	gen `tax' = 0
	
	global nc_${t}_0 = ${gc_${t}_0}
	global cum_previous_brackets = 0
	
	forvalues i = 1 / `n_br' {
		local ii = `i' - 1
						
		global cum_previous_brackets = ${cum_previous_brackets} + (${gc_${t}_`i'} - ${gc_${t}_`ii'}) * ${r_${t}_`i'}
		global nc_${t}_`i' = ${gc_${t}_`i'} - ${cum_previous_brackets}
			
		qui gen tax_b_`i' = 0 if `tax_base_net' <= ${nc_${t}_`ii'}
		qui replace tax_b_`i' = -1 * ${r_${t}_`i'} / (1 - ${r_${t}_`i'}) * (`tax_base_net' - ${nc_${t}_`ii'}) if `tax_base_net' >  ${nc_${t}_`ii'} & `tax_base_net' <= ${nc_${t}_`i'}
		qui replace tax_b_`i' = -1 * ${r_${t}_`i'} / (1 - ${r_${t}_`i'}) * (${nc_${t}_`i'} - ${nc_${t}_`ii'}) if `tax_base_net' >  ${nc_${t}_`i'} 
		
		qui replace `tax' = `tax' + tax_b_`i'
		drop tax_b_`i'
	}

end

* Checking is these two are consistent
global t = 1

progressive_tax_net_to_gross, tax_base_net(WN) tax(tax_1) n_br(`=N_brack_${t}')
gen WC = WN - tax_1

progressive_tax_gross_to_net, tax_base_gross(WC) tax(tax_2) n_br(`=N_brack_${t}')
assert round(tax_1 - tax_2, 10 ^ (10)) == 0
drop WC tax_1 tax_2
*------------------------------------------------------------------------------------------------------------------------

forvalues t = 1 / 2 {
	global t = `t'
	progressive_tax_gross_to_net, tax_base_gross(tax_base_gross) tax(tax_${t}) n_br(`=N_brack_${t}')
}

* Stage 7. from gross to net using the joint taxes (to check if this is identical)
global t = "j"
progressive_tax_gross_to_net, tax_base_gross(tax_base_gross) tax(tax_${t}) n_br(`=N_brack_${t}')

* Stage 8. Checking the consistncy: two taxes should equal joint tax. Going from net to gross and then back should lead to the same result. 
assert round(tax_1 + tax_2 - tax_j, 10 ^ (-10)) == 0

replace tax_base_net = tax_base_gross + tax_j

su tax_base_orig tax_base_net tax_base_gross tax_1 tax_2 tax_j
assert tax_base_net == tax_base_orig
* END OF TESTING

* 1. Algebraic
global t = 1
progressive_tax_net_to_gross, tax_base_net(WN) tax(PIT_wage) n_br(`=N_brack_${t}')
gen WC = WN - PIT_wage

global t = 2
progressive_tax_gross_to_net, tax_base_gross(WC) tax(SSC) n_br(`=N_brack_${t}')

gen PIT_base_net = WN + NLN
global t = 1
progressive_tax_net_to_gross, tax_base_net(PIT_base_net) tax(PIT) n_br(`=N_brack_${t}')

gen WG = WC - SSC
gen NLG = NLN - PIT + PIT_wage

	assert round(WN + NLN - PIT - SSC - (WG + NLG), 10 ^ (-10)) == 0

	gen PIT_base_gross = WC + NLG
	global t = 1
	progressive_tax_gross_to_net, tax_base_gross(PIT_base_gross) tax(PIT_test) n_br(`=N_brack_${t}')
	su PIT PIT_test
	assert round(PIT - PIT_test, 10 ^ (-10)) == 0


* 2. Iterative procedure
set seed 1
gen rand = uniform()
gen WC_it = 100 + rand * (1100 - 100)

local s = 1
global d = 0.1
global s_max = 10 ^ 6

* finding wage_contract
forvalues s = 1 / $s_max {
	
	global t = 1
	progressive_tax_gross_to_net, tax_base_gross(WC_it) tax(PIT_wage_it) n_br(`=N_brack_${t}')
	
	cap drop WN_it
	gen WN_it = WC_it + PIT_wage_it

	cap drop diff
	gen diff = WN_it - WN

	if floor(`s' / 1000) * 1000 == `s' {
		disp "step `s'"
		su WN_it WN diff
	}

	
	qui su diff
	if `r(max)' <= ${d} & `r(min)' >= -${d} {
		disp `s'
		continue, break
	}
	
	qui replace WC_it = WC_it + ${d} if diff < -${d}
	qui replace WC_it = WC_it - ${d} if diff >  ${d}
	
	local s = `s' + 1
	global s = `s'
}
	su WN_it WN diff
	disp ${s}
	assert round(WN_it - WN, ${d} * 10) == 0
	
	* total PIT
	gen PIT_base_gross_it = 1800 + rand * (3800 - 1800)
	
forvalues s = 1 / $s_max {
	
	global t = 1
	progressive_tax_gross_to_net, tax_base_gross(PIT_base_gross_it) tax(PIT_it) n_br(`=N_brack_${t}')

	cap drop PIT_base_net_it
	gen PIT_base_net_it = PIT_base_gross_it + PIT_it

	cap drop diff
	gen diff = PIT_base_net_it - PIT_base_net

	if floor(`s' / 1000) * 1000 == `s' {
		disp "step `s'"
		su PIT_base_net_it PIT_base_net diff
	}

	
	qui su diff
	if `r(max)' <= ${d} & `r(min)' >= -${d} {
		disp `s'
		continue, break
	}
	
	qui replace PIT_base_gross_it = PIT_base_gross_it + ${d} if diff < -${d}
	qui replace PIT_base_gross_it = PIT_base_gross_it - ${d} if diff >  ${d}
	
	local s = `s' + 1
	global s = `s'
}
su PIT_base_net_it PIT_base_net diff
disp ${s}
assert round(PIT_base_net_it - PIT_base_net, ${d} * 10) == 0
	
global t = 2
progressive_tax_gross_to_net, tax_base_gross(WC_it) tax(SSC_it) n_br(`=N_brack_${t}')

gen WG_it = WC_it - SSC_it
gen NLG_it = NLN - PIT_it + PIT_wage_it

assert round(WN + NLN - PIT_it - SSC_it - (WG_it + NLG_it), ${d} * 10) == 0
	
sum WN NLN WC WC_it WG WG_it NLG NLG_it PIT_wage PIT_wage_it PIT PIT_it SSC SSC_it 
	