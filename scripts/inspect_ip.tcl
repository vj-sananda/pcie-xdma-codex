create_project -in_memory -part xc7k480tffg1156-2
create_bd_design inspect
foreach name {xdma jtag_axi axis_data_fifo} {
 set ip [create_bd_cell -type ip -vlnv xilinx.com:ip:$name:* $name]
 report_property $ip
}
exit
