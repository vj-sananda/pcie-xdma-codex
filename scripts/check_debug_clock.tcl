set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_opt.dcp
set pin [get_pins dbg_hub/clk]
set clocks [get_clocks -of_objects $pin]
puts "DEBUG_HUB_NET: [get_nets -of_objects $pin]"
puts "DEBUG_HUB_CLOCK: $clocks"
if {[llength $clocks] != 1 || [get_property NAME $clocks] ne "sys_clk"} {
    error "Debug hub must use the independent sys_clk"
}
puts "DEBUG_CLOCK_PASS"
exit
