source [file join [file dirname [info script]] hardware_common.tcl]
if {$argc > 1} {error "Usage: program.tcl ?bitstream?"}
set bit $root/build/accelerator.bit
if {$argc == 1} {set bit [file normalize [lindex $argv 0]]}
if {![file exists $bit]} {error "Build bitstream first: $bit"}
puts "PROGRAM_IMAGE: $bit"
puts "PROGRAM_SHA256: [exec sha256sum $bit]"
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE {} $dev
program_hw_devices $dev
refresh_hw_device $dev
if {![get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]} {error "FPGA DONE is low"}
if {[get_property REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR $dev]} {error "FPGA configuration CRC error"}
puts "PROGRAM_PASS: DONE=1 CRC_ERROR=0"
close_hw_manager
exit
