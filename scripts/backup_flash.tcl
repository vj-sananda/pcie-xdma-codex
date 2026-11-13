# Read-only flash backup. The temporary JTAG helper replaces FPGA SRAM only;
# the accelerator SRAM image is restored even if flash readback fails.
source [file join [file dirname [info script]] hardware_common.tcl]
set parts [get_cfgmem_parts {mt28gu512aax1e-bpi-x16}]
if {![llength $parts]} {error "MT28GU512 BPI x16 programming support is missing"}
create_hw_cfgmem -hw_device $dev [lindex $parts 0]
set flash [get_property PROGRAM.HW_CFGMEM $dev]
report_property $flash
foreach property {PROGRAM.ERASE PROGRAM.BLANK_CHECK PROGRAM.CFG_PROGRAM PROGRAM.VERIFY} {
    set_property $property 0 $flash
}
set backup_dir [file join $root backups]
file mkdir $backup_dir
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set backup [file join $backup_dir flash_before_${stamp}.bin]
set sample [file join $backup_dir flash_sample_${stamp}.bin]
if {[file exists $backup] || [file exists $sample]} {error "Refusing to overwrite an existing backup"}
set code [catch {
    create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
    program_hw_devices $dev
    readback_hw_cfgmem -all -format bin -file $backup $flash
    if {[file size $backup] != 67108864} {error "Expected a complete 64 MiB flash backup"}
    readback_hw_cfgmem -offset 0 -datacount 4096 -format bin -file $sample $flash
    set f [open $backup rb]; set prefix [read $f 4096]; close $f
    set f [open $sample rb]; set repeated [read $f]; close $f
    if {$prefix ne $repeated} {error "Repeated flash header read disagrees with backup"}
    puts "FLASH_BACKUP_PASS: $backup bytes=[file size $backup] repeated_header=match"
} result options]
# No call to program_hw_cfgmem occurs anywhere in this script.
set_property PROGRAM.FILE $root/build/accelerator.bit $dev
set_property PROBES.FILE {} $dev
program_hw_devices $dev
refresh_hw_device $dev
if {![get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev] || [get_property REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR $dev]} {
    error "Accelerator SRAM restoration failed"
}
puts "SRAM_RESTORE_PASS: DONE=1 CRC_ERROR=0"
close_hw_manager
if {$code} {return -options $options $result}
exit
