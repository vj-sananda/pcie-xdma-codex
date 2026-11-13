# Check the added synchronizers in the open routed diagnostic design.
set diag_audit [open $root/reports/pcie_diagnostic_synchronizers.rpt w]
set firsts [get_cells -hier -filter {NAME =~ pcie_diag_*_sync0}]
set seconds [get_cells -hier -filter {NAME =~ pcie_diag_*_sync1}]
if {[llength $firsts] != 77 || [llength $seconds] != 77} {
    error "Expected 77 two-stage diagnostic synchronizers for 84 observations"
}
foreach first $firsts {
    set second [get_cells [string replace $first end end 1]]
    if {[llength $second] != 1} {error "Missing second stage for $first"}
    foreach cell [list $first $second] {
        if {![get_property ASYNC_REG $cell]} {error "ASYNC_REG missing: $cell"}
        set clk [get_clocks -of_objects [get_pins $cell/C]]
        if {[llength $clk] != 1 || [get_property NAME $clk] ne "sys_clk"} {
            error "Wrong diagnostic clock: $cell $clk"
        }
    }
    set nets [get_nets -segments -of_objects [get_pins $second/D]]
    set driver [get_pins -leaf -of_objects $nets -filter {DIRECTION == OUT}]
    if {[llength $driver] != 1 || $driver ne "$first/Q"} {error "Broken synchronizer chain: $second"}
    set path [get_timing_paths -from [get_pins $first/Q] -to [get_pins $second/D] -max_paths 1]
    if {[llength $path] != 1 || [get_property SLACK $path] < 0} {
        error "Second synchronizer stage is untimed or failing: $second"
    }
    puts $diag_audit "SYNC_PASS $first -> $second clock=sys_clk second_stage_slack=[get_property SLACK $path]"
}
puts $diag_audit "PCIE_DIAGNOSTIC_SYNC_PASS: 77 chains; second stages timed"
close $diag_audit
puts "PCIE_DIAGNOSTIC_SYNC_PASS: 77 chains; second stages timed"

# Audit CPU bit numbering and mux destination after routing, not just LUT math.
set gpio [get_cells -hier -filter {NAME == accelerator_i/gpio/U0/gpio_core_1}]
for {set i 0} {$i < 18} {incr i} {
    set bit [expr {$i+6}]
    set name [format {%s/Dual.gpio2_Data_In_reg[%d]/D} $gpio [expr {31-$bit}]]
    set target [get_pins -hier -filter "NAME == $name"]
    set drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects $target] -filter {DIRECTION == OUT}]
    if {[llength $drivers] != 1 || $drivers ne "pcie_diag_mux${i}_out/O"} {
        error "Wrong diagnostic mux destination for CPU bit $bit: $drivers"
    }
}
puts "PCIE_DIAGNOSTIC_GPIO_MAPPING_PASS: CPU bits 23:6, descending GPIO internal indices 8:25"
