set root [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -allow_non_jtag
set targets [get_hw_targets]
if {[llength $targets] != 1} {error "Expected one JTAG target, found: $targets"}
current_hw_target [lindex $targets 0]
set_property PARAM.FREQUENCY 6000000 [current_hw_target]
open_hw_target
set devices [get_hw_devices -filter {PART == xc7k480t}]
if {[llength $devices] != 1} {error "Expected one XC7K480T, found: $devices"}
set dev [lindex $devices 0]
current_hw_device $dev
