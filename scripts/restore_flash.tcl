# Restore only the 16 erase blocks replaced by accelerator_boot.mcs.
# Requires prepare_flash_recovery.py and safe, powered JTAG access.
if {$argc != 1 || [lindex $argv 0] ni {--check --write}} {
    error "Usage: restore_flash.tcl --check|--write"
}
set action [lindex $argv 0]
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
puts [exec sha256sum --check reports/flash_recovery.sha256]
set image $root/build/restore_original_boot_blocks.mcs
set expected 9edb7e9074b4063f0802e98b22526c4f05331909dbb9d63ad50df5e581f15b90
source $root/scripts/hardware_common.tcl
create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts {mt28gu512aax1e-bpi-x16}] 0]
set flash [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES [list $image] $flash
set_property PROGRAM.ADDRESS_RANGE use_file $flash
foreach property {PROGRAM.ERASE PROGRAM.BLANK_CHECK PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
    set_property $property 0 $flash
}
puts "RESTORE_TARGET: device=$dev part=[get_property CFGMEM_PART $flash] range=0x00000000-0x003FFFFF"
if {$action eq "--check"} {
    puts "FLASH_RESTORE_PREFLIGHT_PASS: no flash operations performed"
    close_hw_manager
    exit
}
foreach property {PROGRAM.ERASE PROGRAM.BLANK_CHECK PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
    set_property $property 1 $flash
}
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem $flash
puts "FLASH_RESTORE_PROGRAM_PASS: original first 4 MiB programmed and verified"
# Check the entire device, including the 60 MiB outside the restored blocks.
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set readback $root/backups/flash_after_restore_${stamp}.bin
if {[file exists $readback]} {error "Refusing to overwrite previous recovery evidence"}
readback_hw_cfgmem -all -format bin -file $readback $flash
if {[file size $readback] != 67108864} {error "Incomplete post-restore readback"}
set actual [lindex [exec sha256sum $readback] 0]
if {$actual ne $expected} {error "Post-restore full-flash hash differs from the original backup: $actual"}
puts "FLASH_RESTORE_PASS: all 64 MiB match original backup sha256=$actual readback=$readback"
# Leave the flash-access helper in SRAM. Do not boot the accelerator image.
close_hw_manager
exit
