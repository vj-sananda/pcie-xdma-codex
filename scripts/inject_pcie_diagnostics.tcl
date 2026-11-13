# Source into the baseline routed design. Adds ordinary logic (no ILA license).
# LED/GPIO output selects one of eight 18-bit diagnostic pages at status[23:6].
# Page 0 preserves the original counter. Other status fields are untouched.
proc diag_one {objects description} {
    if {[llength $objects] != 1} {error "Expected one $description, got $objects"}
    return [lindex $objects 0]
}
proc diag_pin {cell refpin} {
    return [diag_one [get_pins -of_objects $cell -filter "REF_PIN_NAME == $refpin"] "$cell/$refpin"]
}
proc diag_wire {net pin} {
    diag_one $net "net to connect"
    diag_one $pin "pin to connect"
    connect_net -hierarchical -net $net -objects $pin
}
proc diag_source {cell refpin} {
    set pin [diag_pin $cell $refpin]
    set nets [get_nets -of_objects $pin]
    if {![llength $nets]} {
        # Some hard-block observation outputs had no original load.
        set name pcie_diag_source_[incr ::diag_serial]
        create_net $name
        diag_wire [get_nets $name] $pin
        set nets [get_nets -of_objects $pin]
    }
    return [diag_one $nets "net at $pin"]
}
proc diag_sync {label cell refpin} {
    set source [diag_source $cell $refpin]
    puts $::diag_report "SOURCE $label [diag_pin $cell $refpin]"
    incr ::diag_observations
    # The eight TXDETECTRX pins share one launch flop. Synchronize each
    # distinct source once, so copies cannot resolve on different cycles.
    set driver [diag_one [get_pins -leaf -of_objects [get_nets -segments -of_objects [diag_pin $cell $refpin]] \
        -filter {DIRECTION == OUT}] "driver of $label"]
    if {[dict exists $::diag_sync_cache $driver]} {
        set data [dict get $::diag_sync_cache $driver]
        puts $::diag_report "SHARED_SYNC $label $data"
        return $data
    }
    set data $source
    foreach stage {0 1} {
        set name pcie_diag_${label}_sync${stage}
        set ff [create_cell -reference FDRE $name]
        set_property INIT 1'b0 $ff
        set_property ASYNC_REG true $ff
        set_property DONT_TOUCH true $ff
        create_net ${name}_q
        set q [get_nets ${name}_q]
        diag_wire $data [diag_pin $ff D]
        diag_wire $::diag_clock [diag_pin $ff C]
        diag_wire $::diag_zero [diag_pin $ff R]
        diag_wire $::diag_one_net [diag_pin $ff CE]
        diag_wire $q [diag_pin $ff Q]
        if {$stage == 0} {
            # The only new timing exceptions are first-stage synchronizer D pins.
            set_false_path -to [diag_pin $ff D]
            lappend ::diag_async_pins [diag_pin $ff D]
        }
        set data $q
    }
    dict set ::diag_sync_cache $driver $data
    return $data
}
proc diag_lut {name inputs init} {
    set cell [create_cell -reference LUT[llength $inputs] $name]
    set_property INIT $init $cell
    set i 0
    foreach net $inputs {
        diag_wire $net [diag_pin $cell I$i]
        incr i
    }
    create_net ${name}_o
    set out [get_nets ${name}_o]
    diag_wire $out [diag_pin $cell O]
    return $out
}

set diag_serial 0
set diag_observations 0
set diag_sync_cache {}
set diag_async_pins {}
set diag_clock [diag_one [get_nets sys_clk_IBUF_BUFG] "independent 50 MHz net"]
set clock [get_clocks -of_objects $diag_clock]
if {[llength $clock] != 1 || [get_property PERIOD $clock] != 20.0} {
    error "Diagnostic logic needs the independent 50 MHz clock"
}
foreach {name reference pin} {zero GND G one VCC P} {
    set cell [create_cell -reference $reference pcie_diag_${name}_driver]
    create_net pcie_diag_$name
    diag_wire [get_nets pcie_diag_$name] [diag_pin $cell $pin]
}
set diag_zero [get_nets pcie_diag_zero]
set diag_one_net [get_nets pcie_diag_one]
set diag_report [open $root/reports/pcie_diagnostic_map.rpt w]
puts $diag_report "CLOCK $diag_clock PERIOD_NS 20"
puts $diag_report "PAGE 0 counter; 1 LTSSM/clock/link; 2 CPLL/TX-reset; 3 RX-reset/RX-idle; 4 detect/TX-idle; 5 RX-status lanes0-3; 6 RX-status lanes4-7; 7 signature 0x2D15B"

set gpio [diag_one [get_cells -hier -filter {NAME == accelerator_i/gpio/U0/gpio_core_1}] GPIO]
set diag_targets {}
set page0 {}
for {set i 6} {$i < 24} {incr i} {
    # AXI GPIO's internal VHDL vector is ascending (0 to 31).
    # CPU bit i therefore uses internal register 31-i.
    set name [format {%s/Dual.gpio2_Data_In_reg[%d]} $gpio [expr {31-$i}]]
    set reg [diag_one [get_cells -hier -filter "NAME == $name"] "status bit $i register"]
    set pin [diag_pin $reg D]
    lappend diag_targets $pin
    set original [diag_one [get_nets -of_objects $pin] "original counter bit $i"]
    set driver [diag_one [get_pins -leaf -of_objects [get_nets -segments -of_objects $pin] -filter {DIRECTION == OUT}] "counter driver $i"]
    set expected [format {accelerator_i/status/inst/ticks_reg[%d]/Q} $i]
    set chain [list $driver]
    # AXI GPIO inserts its own four-stage input pipeline before Data_In.
    # Follow only those known registers to prove the external CPU bit identity.
    for {set stage 0} {$stage < 8 && $driver ne $expected} {incr stage} {
        set upstream [diag_one [get_cells -of_objects $driver] "GPIO pipeline cell"]
        if {![string match "$gpio/Dual.INPUT_DOUBLE_REGS5/syncstages_ff_reg*" $upstream] ||
            [get_property REF_NAME $upstream] ne "FDRE"} {
            error "Unexpected GPIO input pipeline at CPU bit $i: $upstream"
        }
        set driver [diag_one [get_pins -leaf -of_objects [get_nets -segments -of_objects [diag_pin $upstream D]] -filter {DIRECTION == OUT}] "GPIO pipeline source"]
        lappend chain $driver
    }
    if {$driver ne $expected} {error "GPIO bit ordering: CPU bit $i traces to $driver, expected $expected"}
    lappend page0 $original
    puts $diag_report "COUNTER_MAPPING_PASS cpu_bit=$i source_chain=$chain gpio_register=$reg"
}
set select {}
for {set i 0} {$i < 3} {incr i} {
    set port [get_ports -filter "NAME == led_3bits_tri_o\[$i\]"]
    set padnet [get_nets -segments -of_objects $port]
    set buf [diag_one [get_cells -of_objects [get_pins -leaf -of_objects $padnet] -filter {REF_NAME == OBUF}] "LED $i buffer"]
    lappend select [diag_source $buf I]
}
set pc [diag_one [get_cells -hier -filter {REF_NAME == PCIE_2_1}] "PCIe hard block"]
set mmcm [diag_one [get_cells -hier -filter {REF_NAME == MMCME2_ADV}] "PCIe MMCM"]
set page1 {}
for {set i 0} {$i < 6} {incr i} {
    lappend page1 [diag_sync ltssm$i $pc [format {PLLTSSMSTATE[%d]} $i]]
}
lappend page1 [diag_sync mmcm_lock $mmcm LOCKED]
lappend page1 [diag_sync phy_link_n $pc PLPHYLNKUPN]
lappend page1 [diag_sync rate $pc PLSELLNKRATE]
foreach i {0 1} {lappend page1 [diag_sync width$i $pc [format {PLSELLNKWIDTH[%d]} $i]]}
# This hard-block reset is driven by PHY readiness, not directly by PERST#.
set core_resetn [diag_sync core_resetn $pc SYSRSTN]
lappend page1 $core_resetn

set channels [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL}]
if {[llength $channels] != 8} {error "Expected eight GTX channels"}
foreach channel $channels {
    if {![regexp {pipe_lane\[([0-7])\]} $channel ignored lane]} {error "Unknown GTX lane $channel"}
    set gt($lane) $channel
}
foreach {label refpin} {cpll CPLLLOCK txdone TXRESETDONE rxdone RXRESETDONE rxidle RXELECIDLE detect TXDETECTRX txidle TXELECIDLE} {
    set signal($label) {}
    for {set lane 0} {$lane < 8} {incr lane} {
        lappend signal($label) [diag_sync ${label}${lane} $gt($lane) $refpin]
    }
}
set pages [list $page0 $page1 [concat $signal(cpll) $signal(txdone)] [concat $signal(rxdone) $signal(rxidle)] [concat $signal(detect) $signal(txidle)]]
foreach first {0 4} {
    set page {}
    for {set lane $first} {$lane < $first+4} {incr lane} {
        for {set i 0} {$i < 3} {incr i} {
            lappend page [diag_sync rxstatus${lane}_$i $gt($lane) [format {RXSTATUS[%d]} $i]]
        }
    }
    lappend pages $page
}
# Sticky observations in the independent domain record short training activity
# that the slower JTAG snapshots may miss. They clear on FPGA configuration.
set nonzero [diag_lut pcie_diag_ltssm_nonzero [lrange $page1 0 5] 64'hFFFFFFFFFFFFFFFE]
set sticky_signals {}
foreach {label enable} [list detect [lindex $signal(detect) 0] ltssm $nonzero resetn $core_resetn] {
    set cell [create_cell -reference FDRE pcie_diag_${label}_seen]
    set_property INIT 1'b0 $cell
    set_property DONT_TOUCH true $cell
    create_net pcie_diag_${label}_seen_q
    set out [get_nets pcie_diag_${label}_seen_q]
    diag_wire $diag_clock [diag_pin $cell C]
    diag_wire $diag_zero [diag_pin $cell R]
    diag_wire $enable [diag_pin $cell CE]
    diag_wire $diag_one_net [diag_pin $cell D]
    diag_wire $out [diag_pin $cell Q]
    lappend sticky_signals $out
}
lset pages 5 [concat [lindex $pages 5] $sticky_signals]
set magic {}
for {set i 0} {$i < 18} {incr i} {
    lappend magic [expr {(0x2D15B >> $i) & 1 ? $diag_one_net : $diag_zero}]
}
lappend pages $magic
for {set p 0} {$p < 8} {incr p} {
    set page [lindex $pages $p]
    if {[llength $page] > 18} {error "Page $p overflow"}
    while {[llength $page] < 18} {lappend page $diag_zero}
    lset pages $p $page
}
for {set i 0} {$i < 18} {incr i} {
    set mux4 {}
    foreach first {0 4} {
        set inputs {}
        for {set p $first} {$p < $first+4} {incr p} {lappend inputs [lindex $pages $p $i]}
        lappend inputs [lindex $select 0] [lindex $select 1]
        lappend mux4 [diag_lut pcie_diag_mux${i}_${first} $inputs 64'hFF00F0F0CCCCAAAA]
    }
    lappend mux4 [lindex $select 2]
    set out [diag_lut pcie_diag_mux${i}_out $mux4 8'hCA]
    set target [lindex $diag_targets $i]
    disconnect_net -net [lindex $page0 $i] -objects $target
    diag_wire $out $target
    puts $diag_report "DESTINATION status_bit=[expr {$i+6}] $target"
}
puts $diag_report "OBSERVATION_BITS $diag_observations SYNCHRONIZER_BITS [llength $diag_async_pins]"
if {$diag_observations != 84 || [llength $diag_async_pins] != 77} {error "Unexpected diagnostic signal count"}
foreach pin [get_pins -of_objects [get_cells -hier -filter {NAME =~ pcie_diag_* && IS_PRIMITIVE}]] {
    if {[llength [get_nets -quiet -of_objects $pin]] != 1} {error "Unconnected diagnostic pin $pin"}
}
puts $diag_report "CONNECTIVITY_PASS all primitive pins connected"
close $diag_report
puts "PCIE_DIAGNOSTICS_INSERTED: $diag_observations observations, [llength $diag_async_pins] distinct synchronized sources; eight pages"
