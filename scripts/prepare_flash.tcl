# Produce a conservative BPI x16 boot image from the already routed design.
# This script writes local files only; it does not access the board.
set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_routed.dcp
set_property CONFIG_MODE BPI16 [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Disable [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 3 [current_design]
set_property BITSTREAM.STARTUP.STARTUPCLK CCLK [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
foreach p {CONFIG_MODE BITSTREAM.CONFIG.BPI_SYNC_MODE BITSTREAM.CONFIG.CONFIGRATE BITSTREAM.STARTUP.STARTUPCLK BITSTREAM.GENERAL.COMPRESS} {
    puts "BOOT_SETTING: $p=[get_property $p [current_design]]"
}
write_bitstream -force $root/build/accelerator_boot.bit
write_cfgmem -force -format mcs -size 64 -interface BPIx16 \
    -loadbit "up 0x00000000 $root/build/accelerator_boot.bit" \
    $root/build/accelerator_boot.mcs
puts "FLASH_IMAGE_PASS: $root/build/accelerator_boot.mcs"
exit
