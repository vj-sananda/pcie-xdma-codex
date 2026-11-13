# Audit the baseline, or an explicitly supplied diagnostic checkpoint.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc > 1} {error "Usage: check_pcie_constraints.tcl ?checkpoint?"}
set checkpoint $root/build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_routed.dcp
set pcie_audit_report $root/reports/pcie_constraints_audit.rpt
if {$argc == 1} {
    set checkpoint [file normalize [lindex $argv 0]]
    set pcie_audit_report $root/reports/pcie_constraints_[file rootname [file tail $checkpoint]].rpt
}
open_checkpoint $checkpoint
source $root/scripts/audit_pcie_constraints.tcl
exit
