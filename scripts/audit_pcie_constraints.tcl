# Audit the open design. Caller supplies pcie_audit_report.
# Keep audit temporaries local: diagnostic insertion uses a global signal array.
proc pcie_audit_record {channel line} {puts $channel $line; puts $line}
proc audit_pcie_constraints {destination} {
    set report [open $destination w]
    try {
        foreach {signal pins} {
            txp {F2 H2 K2 M2 N4 P2 T2 U4}
            txn {F1 H1 K1 M1 N3 P1 T1 U3}
            rxp {H6 J4 K6 L4 M6 P6 R4 T6}
            rxn {H5 J3 K5 L3 M5 P5 R3 T5}
        } {
            for {set lane 0} {$lane < 8} {incr lane} {
                set name [format {pci_express_x8_%s[%d]} $signal $lane]
                set port [get_ports -filter "NAME == $name"]
                set actual [get_property PACKAGE_PIN $port]
                set expected [lindex $pins $lane]
                if {$actual ne $expected} {error "$name pin $actual, expected $expected"}
                pcie_audit_record $report "PIN_PASS: $name=$actual"
            }
        }
        foreach {name expected} {pcie_refclk_clk_p J8 pcie_refclk_clk_n J7 pcie_perstn Y26} {
            set actual [get_property PACKAGE_PIN [get_ports $name]]
            if {$actual ne $expected} {error "$name pin $actual, expected $expected"}
            pcie_audit_record $report "PIN_PASS: $name=$actual"
        }
        set channels [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL}]
        if {[llength $channels] != 8} {error "Expected eight GTX channels"}
        foreach cell $channels {
            if {![regexp {pipe_lane\[([0-7])\]} $cell dummy lane]} {error "Cannot identify lane in $cell"}
            # The author's pcie_port.xdc overrides the generic IP placement: this
            # board uses banks 116/115, channels X0Y23 down through X0Y16.
            set expected_loc GTXE2_CHANNEL_X0Y[expr {23-$lane}]
            set loc [get_property LOC $cell]
            if {$loc ne $expected_loc} {error "Lane $lane placed at $loc instead of $expected_loc"}
            foreach {pin signal} {GTXTXP txp GTXTXN txn GTXRXP rxp GTXRXN rxn} {
                set p [get_pins -of_objects $cell -filter "REF_PIN_NAME == $pin"]
                set nets [get_nets -segments -of_objects $p]
                set ports [get_ports -quiet -of_objects $nets]
                # The routed netlist retains the pad IBUF/OBUF representation. Follow
                # that transparent pad cell to the top port, without crossing logic.
                if {![llength $ports]} {
                    set buffers [get_cells -of_objects [get_pins -leaf -of_objects $nets] \
                        -filter {REF_NAME == OBUF || REF_NAME == IBUF}]
                    if {[llength $buffers] != 1} {error "Expected one pad buffer for lane $lane $pin"}
                    set ports [get_ports -of_objects [get_nets -segments -of_objects [get_pins -of_objects $buffers]]]
                }
                set expected [format {pci_express_x8_%s[%d]} $signal $lane]
                if {[llength $ports] != 1 || [get_property NAME $ports] ne $expected} {
                    error "Lane $lane $pin connects to $ports instead of $expected"
                }
            }
            pcie_audit_record $report "GTX_PASS: lane=$lane loc=$loc all four pads connect to this lane"
        }
        set pcie [get_cells -hier -filter {REF_NAME == PCIE_2_1}]
        if {[llength $pcie] != 1 || [get_property LOC $pcie] ne "PCIE_X0Y0"} {error "Unexpected PCIe block placement"}
        pcie_audit_record $report "PCIE_BLOCK_PASS: PCIE_X0Y0"
        set refclock [get_clocks -of_objects [get_ports pcie_refclk_clk_p]]
        if {[llength $refclock] != 1 || [get_property PERIOD $refclock] != 10.0} {error "Expected 100 MHz PCIe reference constraint"}
        pcie_audit_record $report "REFCLK_PASS: J8/J7 constrained to 100 MHz; this is not a physical clock measurement"
        pcie_audit_record $report "PCIE_CONSTRAINTS_PASS: 32 lane pins, reference clock, PERST, eight GTX channels, PCIe block"
    } finally {
        close $report
    }
}
audit_pcie_constraints $pcie_audit_report
