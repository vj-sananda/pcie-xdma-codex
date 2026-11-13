# Build a separate volatile diagnostic image from the known baseline.
# No hardware-manager, programming, flash, or host-restart operations.
set root [file normalize [file join [file dirname [info script]] ..]]
set_param general.maxThreads 2
open_checkpoint $root/build/accelerator/accelerator.runs/impl_1/accelerator_wrapper_routed.dcp
source $root/scripts/inject_pcie_diagnostics.tcl
set pcie_audit_report $root/reports/pcie_diagnostic_preroute_constraints.rpt
source $root/scripts/audit_pcie_constraints.tcl
source $root/scripts/finish_pcie_diagnostics.tcl
