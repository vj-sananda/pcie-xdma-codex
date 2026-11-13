# Shared implementation/check steps, sourced after diagnostic insertion.
place_design
route_design -preserve
# Preserve routing even if a later report/audit fails. Not a validated artifact.
write_checkpoint -force $root/build/accelerator_pcie_diagnostic_unvalidated.dcp
report_timing_summary -file $root/reports/pcie_diagnostic_timing.rpt
report_bus_skew -file $root/reports/pcie_diagnostic_bus_skew.rpt
report_drc -file $root/reports/pcie_diagnostic_drc.rpt
report_cdc -details -file $root/reports/pcie_diagnostic_cdc.rpt
set f [open $root/reports/pcie_diagnostic_cdc.rpt r]
set cdc_text [read $f]
close $f
if {[regexp {CDC-[0-9]+[ \t]+Critical[^\n]*pcie_diag_} $cdc_text]} {
    error "Critical CDC finding in added diagnostic logic"
}
foreach path [list $root/reports/pcie_diagnostic_timing.rpt $root/reports/pcie_diagnostic_bus_skew.rpt] {
    set f [open $path r]
    set contents [read $f]
    close $f
    if {[string first {VIOLATED} $contents] >= 0} {error "Timing violation in $path"}
    if {[string match *timing.rpt $path] && [string first {All user specified timing constraints are met.} $contents] < 0} {
        error "Timing summary did not pass"
    }
}
if {[llength [get_drc_violations -filter {SEVERITY == Error}]]} {error "DRC errors"}
set pcie_audit_report $root/reports/pcie_diagnostic_constraints.rpt
source $root/scripts/audit_pcie_constraints.tcl
source $root/scripts/audit_pcie_diagnostics.tcl
write_checkpoint -force $root/build/accelerator_pcie_diagnostic.dcp
write_bitstream -force $root/build/accelerator_pcie_diagnostic.bit
set hash_output [exec sha256sum $root/build/accelerator_pcie_diagnostic.bit \
    $root/build/accelerator_pcie_diagnostic.dcp \
    $root/build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_routed.dcp \
    $root/scripts/build_pcie_diagnostics.tcl $root/scripts/inject_pcie_diagnostics.tcl \
    $root/scripts/finish_pcie_diagnostics.tcl $root/scripts/audit_pcie_constraints.tcl \
    $root/scripts/audit_pcie_diagnostics.tcl]
set f [open $root/reports/pcie_diagnostic_artifacts.sha256 w]
puts $f $hash_output
close $f
puts "PCIE_DIAGNOSTIC_BUILD_PASS: $root/build/accelerator_pcie_diagnostic.bit"
exit
