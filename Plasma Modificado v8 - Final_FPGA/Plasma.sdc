## Generated SDC file "Plasma.sdc"

## Copyright (C) 1991-2015 Altera Corporation. All rights reserved.
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, the Altera Quartus II License Agreement,
## the Altera MegaCore Function License Agreement, or other 
## applicable license agreement, including, without limitation, 
## that your use is for the sole purpose of programming logic 
## devices manufactured by Altera and sold by Altera or its 
## authorized distributors.  Please refer to the applicable 
## agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 15.0.0 Build 145 04/22/2015 Patches 0.01we SJ Web Edition"

## DATE    "Thu Jan 26 17:48:34 2017"

##
## DEVICE  "5CSEMA5F31C6"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk} -period 33.000 -waveform { 0.000 16.500 } [get_registers { clk }]
create_clock -name {CLOCK_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports { CLOCK_50 }]
create_clock -name {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag} -period 20.000 -waveform { 0.000 10.000 } [get_registers { plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag }]
create_clock -name {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3} -period 33.000 -waveform { 0.000 16.500 } [get_registers {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]
create_clock -name {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2} -period 33.000 -waveform { 0.000 16.500 } [get_registers {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]
create_clock -name {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag} -period 33.000 -waveform { 0.000 16.500 } [get_registers {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]
create_clock -name {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag} -period 33.000 -waveform { 0.000 16.500 } [get_registers {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.270  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.270  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}] -rise_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}] -fall_to [get_clocks {clk}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {CLOCK_50}] -setup 0.310  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {CLOCK_50}] -hold 0.270  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {CLOCK_50}] -setup 0.310  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {CLOCK_50}] -hold 0.270  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {clk}]  0.350  
set_clock_uncertainty -rise_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {clk}]  0.350  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {CLOCK_50}] -setup 0.310  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {CLOCK_50}] -hold 0.270  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {CLOCK_50}] -setup 0.310  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {CLOCK_50}] -hold 0.270  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -rise_to [get_clocks {clk}]  0.350  
set_clock_uncertainty -fall_from [get_clocks {CLOCK_50}] -fall_to [get_clocks {clk}]  0.350  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.330  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {CLOCK_50}]  0.350  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {CLOCK_50}]  0.350  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {clk}]  0.380  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {clk}]  0.380  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|wait_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|tick_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s2}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|restore_flag}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {plasma_RT:plasma1|microkernel:u7_microkernel|state.s3}]  0.330  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {CLOCK_50}]  0.350  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {CLOCK_50}]  0.350  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {clk}]  0.380  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {clk}]  0.380  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

