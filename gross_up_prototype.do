/* EXAMPLE:

WN - net wages
WC - contract wages (wages before PIT)
WG - wages gross

NLN - non-labor income net
NLG - non-labor income gross

* PIT = PIT(WC + NLG)
* SSC = SSC(WC)
*/

*------------------------------------------------------------------------------------------------------------------------
* This program calculates progressive tax
capture program drop progressive_tax_gross_to_net
program define progressive_tax_gross_to_net
syntax, tax_base_gross(varname) tax_variable(string) tax_name(string)

	cap drop `tax_variable'
	gen `tax_variable' = 0
	
	forvalues i = 1 / `=N_brack_`tax_name'' {
		local ii = `i' - 1
			
		qui gen double tax_b_`i' = 0 if `tax_base_gross' <= ${gc_`tax_name'_`ii'}
		qui replace tax_b_`i' = -1 * ${r_`tax_name'_`i'} * (`tax_base_gross' - ${gc_`tax_name'_`ii'}) if `tax_base_gross' >  ${gc_`tax_name'_`ii'} & `tax_base_gross' <= ${gc_`tax_name'_`i'}
		qui replace tax_b_`i' = -1 * ${r_`tax_name'_`i'} * (${gc_`tax_name'_`i'} - ${gc_`tax_name'_`ii'}) if `tax_base_gross' >  ${gc_`tax_name'_`i'} 
		
		qui replace `tax_variable' = `tax_variable' + tax_b_`i'
		drop tax_b_`i'
	}

end

capture program drop progressive_tax_net_to_gross
program define progressive_tax_net_to_gross
syntax, tax_base_net(varname) tax_variable(string) tax_name(string)

	cap drop `tax_variable'
	gen `tax_variable' = 0
	
	global nc_`tax_name'_0 = ${gc_`tax_name'_0}
	global cum_previous_brackets = 0
	
	forvalues i = 1 / `=N_brack_`tax_name'' {
		local ii = `i' - 1
						
		global cum_previous_brackets = ${cum_previous_brackets} + (${gc_`tax_name'_`i'} - ${gc_`tax_name'_`ii'}) * ${r_`tax_name'_`i'}
		global nc_`tax_name'_`i' = ${gc_`tax_name'_`i'} - ${cum_previous_brackets}
			
		qui gen tax_b_`i' = 0 if `tax_base_net' <= ${nc_`tax_name'_`ii'}
		qui replace tax_b_`i' = -1 * ${r_`tax_name'_`i'} / (1 - ${r_`tax_name'_`i'}) * (`tax_base_net' - ${nc_`tax_name'_`ii'}) if `tax_base_net' >  ${nc_`tax_name'_`ii'} & `tax_base_net' <= ${nc_`tax_name'_`i'}
		qui replace tax_b_`i' = -1 * ${r_`tax_name'_`i'} / (1 - ${r_`tax_name'_`i'}) * (${nc_`tax_name'_`i'} - ${nc_`tax_name'_`ii'}) if `tax_base_net' >  ${nc_`tax_name'_`i'} 
		
		qui replace `tax_variable' = `tax_variable' + tax_b_`i'
		drop tax_b_`i'
	}

end
*------------------------------------------------------------------------------------------------------------------------

clear
global N = 100
set obs ${N}

gen WN = .
gen NLN = .

forvalues i = 1 / $N {
	qui replace WN = 100 + `i' * 10 in `i'
	qui replace NLN = 600 - `i' * 5 in `i'
} 
assert WN > 0
assert NLN > 0

global max_cut_off = 10 ^ 10 // very big number

* Stage 1. We define marginal rates and cut-offs for two taxes.

* Tax 1 (PIT).
// rates by brackets
global r_PIT_1 = 0.05
global r_PIT_2 = 0.15
global r_PIT_3 = 0.25
global r_PIT_4 = 0.35
global r_PIT_5 = 0.45

// cutoffs for gross income
global gc_PIT_0 = 0
global gc_PIT_1 = 100
global gc_PIT_2 = 200
global gc_PIT_3 = 500
global gc_PIT_4 = 1000
global gc_PIT_5 = ${max_cut_off}

scalar N_brack_PIT = 5 // I did not find the way to put into the loop $N_brack_`t'

* Tax 2 (SSC).
// rates by brackets
global r_SSC_1 = 0.10
global r_SSC_2 = 0.20
global r_SSC_3 = 0.30

// cutoffs for gross income
global gc_SSC_0 = 0
global gc_SSC_1 = 250
global gc_SSC_2 = 500
global gc_SSC_3 = ${max_cut_off}

scalar N_brack_SSC = 3

local i_PIT = 1 // index of the bracket for the first tax
local i_SSC = 1 // index of the bracket for the second tax

* Stage 2. We calculate the rates and the cut-offs for the joint tax such that the value of joint tax is equivalent to the sum of the two taxes separately (we check it later)
global gc_joint_0 = 0
forvalues s = 1 / 100 { // we put here high number, but when we reach the maximum, we end the cycle
	
	global gc_joint_`s' = min(${gc_PIT_`i_PIT'}, ${gc_SSC_`i_SSC'}) // the cutoff for the joint tax is the minimum of the lowest among the two.
	global r_joint_`s' = ${r_PIT_`i_PIT'} + ${r_SSC_`i_SSC'} // (1 + ${r_PIT_`i_PIT'}) * (1 + ${r_SSC_`i_SSC'}) - 1 // the rate is combination of the two rates

	disp "bracket `s'. The rate for income under ${gc_joint_`s'} is ${r_joint_`s'}"
	*disp "`i_PIT' `i_SSC'"
	*disp " "
	
	if ${gc_joint_`s'} == ${max_cut_off} { // we can do this better, but it is fine for now. 
		scalar def N_brack_joint = `s'
		continue, break
	}
	
	foreach t in PIT SSC {
		if ${gc_joint_`s'} == ${gc_`t'_`i_`t''} {
			local i_`t' = `i_`t'' + 1 // if the cutoff for the joint tax equals to the cutoff of either tax1 or tax2, we switch to the next bracket. 
		}
	}
}

* Stage 3. Actual calculator. Defining the net income
gen tax_base_orig = WN + NLN 
gen tax_base_net = tax_base_orig
su tax_base_orig tax_base_net 

* Stage 4. from net to gross using the joint tax.
progressive_tax_net_to_gross, tax_base_net(tax_base_net) tax_variable(tax_joint) tax_name(joint)
gen tax_base_gross = tax_base_net - tax_joint // tax is negative here
su tax_base_orig tax_base_net tax_base_gross tax_joint

* Stage 5. from gross to net using two separate taxes
progressive_tax_gross_to_net, tax_base_gross(tax_base_gross) tax_variable(PIT) tax_name(PIT)
progressive_tax_gross_to_net, tax_base_gross(tax_base_gross) tax_variable(SSC) tax_name(SSC)

* Stage 6. from gross to net using the joint taxes (to check if this is identical)
progressive_tax_gross_to_net, tax_base_gross(tax_base_gross) tax_variable(tax_joint) tax_name(joint)
su tax_base_orig tax_base_net tax_base_gross tax_joint

* Stage 7. Checking the consistncy: two taxes should equal joint tax. Going from net to gross and then back should lead to the same result. 
assert round(PIT + SSC - tax_joint, 10 ^ (-10)) == 0

replace tax_base_net = tax_base_gross + tax_joint

su tax_base_orig tax_base_net tax_base_gross PIT SSC tax_joint
assert tax_base_net == tax_base_orig
* END OF TESTING

* 1. Algebraic
progressive_tax_net_to_gross, tax_base_net(WN) tax_variable(PIT_wage) tax_name(PIT)
gen WC = WN - PIT_wage

progressive_tax_gross_to_net, tax_base_gross(WC) tax_variable(SSC) tax_name(SSC)

gen PIT_base_net = WN + NLN
progressive_tax_net_to_gross, tax_base_net(PIT_base_net) tax_variable(PIT) tax_name(PIT)

gen WG = WC - SSC
gen NLG = NLN - PIT + PIT_wage

	assert round(WN + NLN - PIT - SSC - (WG + NLG), 10 ^ (-10)) == 0

	gen PIT_base_gross = WC + NLG
	progressive_tax_gross_to_net, tax_base_gross(PIT_base_gross) tax_variable(PIT_test) tax_name(PIT)
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
	
	progressive_tax_gross_to_net, tax_base_gross(WC_it) tax_variable(PIT_wage_it) tax_name(PIT)
	
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
	
	progressive_tax_gross_to_net, tax_base_gross(PIT_base_gross_it) tax_variable(PIT_it) tax_name(PIT)

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
	
progressive_tax_gross_to_net, tax_base_gross(WC_it) tax_variable(SSC_it) tax_name(SSC)

gen WG_it = WC_it - SSC_it
gen NLG_it = NLN - PIT_it + PIT_wage_it

assert round(WN + NLN - PIT_it - SSC_it - (WG_it + NLG_it), ${d} * 10) == 0
	
sum WN NLN WC WC_it WG WG_it NLG NLG_it PIT_wage PIT_wage_it PIT PIT_it SSC SSC_it 
	