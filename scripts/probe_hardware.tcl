open_hw_manager
connect_hw_server -allow_non_jtag
puts "TARGETS: [get_hw_targets]"
open_hw_target
foreach dev [get_hw_devices] {
    puts "DEVICE: $dev"
    report_property $dev
}
close_hw_manager
exit
