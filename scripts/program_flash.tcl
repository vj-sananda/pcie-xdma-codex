# --check validates the prepared files and memory selection without writing.
# --write replaces the flash sectors occupied by accelerator_boot.mcs.
if {$argc != 1 || [lindex $argv 0] ni {--check --write}} {
    error "Usage: program_flash.tcl --check|--write"
}
set action [lindex $argv 0]
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set f [open $root/backups/verified_backup.txt r]
set backup [string trim [read $f]]
close $f
if {![file exists $backup] || [file size $backup] != 67108864} {
    error "A verified full 64 MiB backup is required"
}
puts [exec sha256sum --check reports/flash_artifacts.sha256]
set image $root/build/accelerator_boot.mcs
if {![file exists $image]} {error "Prepare the BPI image first"}
source $root/scripts/hardware_common.tcl
create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts {mt28gu512aax1e-bpi-x16}] 0]
set flash [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES [list $image] $flash
set_property PROGRAM.ADDRESS_RANGE use_file $flash
foreach property {PROGRAM.ERASE PROGRAM.BLANK_CHECK PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
    set_property $property 0 $flash
}
puts "FLASH_TARGET: device=$dev part=[get_property CFGMEM_PART $flash] image=$image backup=$backup"
if {$action eq "--check"} {
    puts "FLASH_PREFLIGHT_PASS: no flash operations performed"
    close_hw_manager
    exit
}
foreach property {PROGRAM.ERASE PROGRAM.BLANK_CHECK PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
    set_property $property 1 $flash
}
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem $flash
puts "FLASH_PROGRAM_PASS: erased programmed and verified the image sectors"
# Exercise the actual boot path immediately, without restarting the PC.
boot_hw_device -timeout 30 $dev
refresh_hw_device $dev
if {![get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev] || [get_property REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR $dev]} {
    error "Flash verification succeeded but FPGA boot did not pass DONE/CRC checks"
}
if {[llength [get_hw_axis]] != 1} {error "Flash boot did not expose the expected JTAG AXI master"}
puts "FLASH_BOOT_PASS: DONE=1 CRC_ERROR=0 JTAG_AXI=1"
close_hw_manager
exit
