# Read only after programming accelerator_pcie_diagnostic.bit and arranging
# exclusive JTAG access. Selecting pages changes the three user LEDs.
# The 21:55:10 development image used GPIO internal indices 6..23, which
# correspond to CPU bits 25..8 in reversed order. Explicit compatibility mode
# allows evidence capture; never silently accept that layout as the final map.
set legacy_gpio_order 0
if {$argc == 1 && [lindex $argv 0] eq "--legacy-reversed-gpio"} {
    set legacy_gpio_order 1
} elseif {$argc != 0} {
    error "Usage: read_pcie_diagnostics.tcl ?--legacy-reversed-gpio?"
}
puts "PCIE_DIAGNOSTIC_LEGACY_GPIO_ORDER: $legacy_gpio_order"
proc diag_payload {status} {
    global legacy_gpio_order
    if {!$legacy_gpio_order} {return [expr {($status >> 6) & 0x3FFFF}]}
    set bits [expr {($status >> 8) & 0x3FFFF}]
    set result 0
    for {set bit 0} {$bit < 18} {incr bit} {
        set result [expr {($result << 1) | (($bits >> $bit) & 1)}]
    }
    return $result
}
source [file join [file dirname [info script]] hardware_common.tcl]
refresh_hw_device $dev
set axes [get_hw_axis]
if {[llength $axes] != 1} {error "Expected one JTAG AXI master"}
set axis [lindex $axes 0]
reset_hw_axi $axis
proc diag_read32 {address} {
    global axis
    create_hw_axi_txn diag_rd $axis -type read -address [format %08X $address] -len 1 -force
    run_hw_axi -quiet [get_hw_axi_txns diag_rd]
    set data [get_property DATA [get_hw_axi_txns diag_rd]]
    if {[scan $data %x value] != 1} {error "Invalid AXI read data: $data"}
    return $value
}
proc diag_select {page} {
    global axis
    create_hw_axi_txn diag_wr $axis -type write -address 00000000 -data [format %08X $page] -len 1 -force
    run_hw_axi -quiet [get_hw_axi_txns diag_wr]
    after 10
}
proc diag_page {page} {
    diag_select $page
    set status [diag_read32 8]
    global legacy_gpio_order
    set id_ok [expr {$legacy_gpio_order ? (($status & 0xFC000000) == 0xC4000000) : (($status >> 24) == 0xC7)}]
    if {!$id_ok || (($status >> 3) & 7) != $page} {
        error [format "Wrong design/page readback: page=%d status=%08X" $page $status]
    }
    return $status
}
try {
    # A fixed signature on page 7 distinguishes this image from the baseline.
    for {set repeat 0} {$repeat < 3} {incr repeat} {
        if {[diag_payload [diag_page 7]] != ($legacy_gpio_order ? 0x2D15A : 0x2D15B)} {
            error "Diagnostic image signature absent; program the diagnostic bitstream first"
        }
    }
    set counter0 [diag_page 0]
    after 100
    set counter1 [diag_page 0]
    if {(($counter0 ^ $counter1) & 0x00FFFFC0) == 0} {error "Independent clock counter did not advance"}
    set filename $root/reports/pcie_diagnostics_[clock format [clock seconds] -format %Y%m%d_%H%M%S].tsv
    set report [open $filename w]
    puts $report "sample\tepoch_ms\tpage\tstatus_hex\tpayload_hex"
    for {set sample 0} {$sample < 20} {incr sample} {
        set payloads {}
        for {set page 1} {$page < 7} {incr page} {
            set raw [diag_page $page]
            set payload [diag_payload $raw]
            dict set payloads $page $payload
            puts $report [format "%d\t%d\t%d\t%08X\t%05X" $sample [clock milliseconds] $page $raw $payload]
        }
        flush $report
        set p1 [dict get $payloads 1]
        set p2 [dict get $payloads 2]
        set p3 [dict get $payloads 3]
        set p4 [dict get $payloads 4]
        puts [format "PCIE_DIAG sample=%d ltssm=0x%02X mmcm_lock=%d phy_link_n=%d cpll=%02X txdone=%02X rxdone=%02X rxidle=%02X detectrx=%02X txidle=%02X" \
            $sample [expr {$p1 & 63}] [expr {($p1 >> 6) & 1}] [expr {($p1 >> 7) & 1}] \
            [expr {$p2 & 255}] [expr {($p2 >> 8) & 255}] [expr {$p3 & 255}] [expr {($p3 >> 8) & 255}] \
            [expr {$p4 & 255}] [expr {($p4 >> 8) & 255}]]
        if {!$legacy_gpio_order} {
            set p5 [dict get $payloads 5]
            puts [format "PCIE_DIAG_ACTIVITY sample=%d core_resetn=%d detect_seen=%d ltssm_nonzero_seen=%d core_resetn_seen=%d" \
                $sample [expr {($p1 >> 11) & 1}] [expr {($p5 >> 12) & 1}] \
                [expr {($p5 >> 13) & 1}] [expr {($p5 >> 14) & 1}]]
        }
        set rxstatus {}
        foreach page {5 6} {
            set value [dict get $payloads $page]
            for {set lane 0} {$lane < 4} {incr lane} {
                lappend rxstatus [expr {($value >> (3*$lane)) & 7}]
            }
        }
        puts [format "PCIE_DIAG_DETAIL sample=%d link=%d perstn=%d dma_resetn=%d rate_raw=%d width_raw=%d rxstatus_lanes_0_to_7=%s" \
            $sample [expr {$raw & 1}] [expr {($raw >> 1) & 1}] [expr {($raw >> 2) & 1}] \
            [expr {($p1 >> 8) & 1}] [expr {($p1 >> 9) & 3}] [join $rxstatus ,]]
    }
    close $report
    unset report
    puts "PCIE_DIAGNOSTIC_READ_PASS: $filename"
    puts "This marker confirms diagnostic reads, not PCIe link or DMA success."
} finally {
    if {[info exists report]} {close $report}
    # Return to the original counter page and LEDs-off state, including on error.
    diag_select 0
    close_hw_manager
}
exit
