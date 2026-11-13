source [file join [file dirname [info script]] hardware_common.tcl]
refresh_hw_device $dev
set axes [get_hw_axis]
if {[llength $axes] != 1} {error "Expected one JTAG AXI master, found: $axes"}
set axis [lindex $axes 0]
reset_hw_axi $axis
proc read32 {address} {
    global axis
    create_hw_axi_txn rd $axis -type read -address [format %08X $address] -len 1 -force
    run_hw_axi -quiet [get_hw_axi_txns rd]
    set data [get_property DATA [get_hw_axi_txns rd]]
    scan $data %x value
    return $value
}
proc write32 {address value} {
    global axis
    create_hw_axi_txn wr $axis -type write -address [format %08X $address] -data [format %08X $value] -len 1 -force
    run_hw_axi -quiet [get_hw_axi_txns wr]
}
proc check {condition message} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL: $message"}
    puts "PASS: $message"
}
set initial [read32 8]
check {($initial >> 24) == 0xC7} "design signature C7"
after 100
set later [read32 8]
check {(($initial ^ $later) & 0x00ffffc0) != 0} "independent 50 MHz clock counter advances"
foreach pattern {0 1 2 4 7 5 2 0} {
    write32 0 $pattern
    after 100
    set status [read32 8]
    check {(($status >> 3) & 7) == $pattern} "LED output register pattern $pattern"
}
puts [format "PCIE_STATUS: link_up=%d perstn=%d dma_resetn=%d status=%08X" [expr {$status & 1}] [expr {($status >> 1) & 1}] [expr {($status >> 2) & 1}] $status]

# AXI IIC dynamic controller. All accesses are to LM73 read-only registers.
proc sensor_read {address reg} {
    set base 0x10000
    write32 [expr {$base + 0x40}] 0xA
    write32 [expr {$base + 0x120}] 0xF
    write32 [expr {$base + 0x108}] [expr {0x100 | ($address << 1)}]
    write32 [expr {$base + 0x108}] $reg
    write32 [expr {$base + 0x108}] [expr {0x101 | ($address << 1)}]
    write32 [expr {$base + 0x108}] 0x202
    # Queue the whole SMBus transaction before enabling: JTAG latency must not
    # leave gaps on the physical bus that exceed the LM73 SMBus timeout.
    write32 [expr {$base + 0x100}] 1
    set bytes {}
    for {set retry 0} {$retry < 30 && [llength $bytes] < 2} {incr retry} {
        set sr [read32 [expr {$base + 0x104}]]
        if {!($sr & 0x40)} {
            lappend bytes [expr {[read32 [expr {$base + 0x10C}]] & 255}]
        } else {after 2}
    }
    if {[llength $bytes] != 2} {error [format "No sensor response at 0x%02X (status 0x%02X)" $address $sr]}
    return [expr {([lindex $bytes 0] << 8) | [lindex $bytes 1]}]
}
set found -1
foreach address {0x48 0x49 0x4a 0x4c 0x4d 0x4e} {
    if {![catch {sensor_read $address 7} id] && $id == 0x0190} {
        set found $address
        puts [format "PASS: LM73 address=0x%02X identification=0x%04X" $address $id]
        break
    }
}
check {$found >= 0} "LM73 identification register"
for {set sample 0} {$sample < 3} {incr sample} {
    set raw [sensor_read $found 0]
    set signed [expr {$raw >= 32768 ? $raw - 65536 : $raw}]
    set celsius [expr {$signed / 128.0}]
    check {$celsius >= -40 && $celsius <= 125} "temperature in LM73 operating range"
    puts [format "TEMPERATURE: sample=%d raw=%04X celsius=%.3f" $sample $raw $celsius]
    after 100
}
puts "JTAG_TEST_PASS"
close_hw_manager
exit
