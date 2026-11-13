set root [file normalize [file join [file dirname [info script]] ..]]
create_project accelerator $root/build/accelerator -part xc7k480tffg1156-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_param general.maxThreads 4
add_files $root/rtl/board_status.v
add_files -fileset constrs_1 $root/constraints/board.xdc
create_bd_design accelerator
proc ip {name type props} {
    set cell [create_bd_cell -type ip -vlnv xilinx.com:ip:$type:* $name]
    foreach {key value} $props {
        if {$key ni [list_property $cell]} {error "Unsupported IP property $name/$key"}
    }
    if {[llength $props]} {set_property -dict $props $cell}
    return $cell
}
proc net {args} {
    set pins {}
    foreach p $args {lappend pins [get_bd_pins $p]}
    connect_bd_net {*}$pins
}
ip xdma_0 xdma [list CONFIG.pl_link_cap_max_link_width X8 CONFIG.pl_link_cap_max_link_speed 5.0_GT/s CONFIG.axi_data_width 128_bit CONFIG.axilite_master_en true CONFIG.axilite_master_scale Megabytes CONFIG.axilite_master_size 1 CONFIG.xdma_axi_intf_mm AXI_Stream CONFIG.xdma_rnum_chnl 1 CONFIG.xdma_wnum_chnl 1 CONFIG.pf0_device_id 7021 CONFIG.pf0_class_code_base 05 CONFIG.pf0_class_code_sub 80 CONFIG.pf0_class_code_interface 00 CONFIG.pcie_blk_locn X0Y0]
ip refclk_buf util_ds_buf [list CONFIG.C_BUF_TYPE IBUFDSGTE CONFIG.C_SIZE 1]
ip stream_fifo axis_data_fifo [list CONFIG.TDATA_NUM_BYTES 16 CONFIG.FIFO_DEPTH 4096 CONFIG.HAS_TKEEP 1 CONFIG.HAS_TLAST 1]
ip gpio axi_gpio [list CONFIG.C_GPIO_WIDTH 3 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1]
ip temperature axi_iic [list CONFIG.IIC_FREQ_KHZ 100]
ip jtag_axi jtag_axi [list CONFIG.PROTOCOL 2]
ip interconnect axi_interconnect [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 2]
ip zero xlconstant [list CONFIG.CONST_VAL 0 CONFIG.CONST_WIDTH 1]
create_bd_cell -type module -reference board_status status

set sysclk [create_bd_port -dir I -type clk -freq_hz 50000000 sys_clk]
set_property CONFIG.FREQ_HZ 50000000 $sysclk
connect_bd_net $sysclk [get_bd_pins status/clk] [get_bd_pins jtag_axi/aclk] [get_bd_pins interconnect/ACLK] [get_bd_pins interconnect/S01_ACLK] [get_bd_pins interconnect/M00_ACLK] [get_bd_pins interconnect/M01_ACLK] [get_bd_pins gpio/s_axi_aclk] [get_bd_pins temperature/s_axi_aclk]
net status/resetn jtag_axi/aresetn interconnect/ARESETN interconnect/S01_ARESETN interconnect/M00_ARESETN interconnect/M01_ARESETN gpio/s_axi_aresetn temperature/s_axi_aresetn
net xdma_0/axi_aclk stream_fifo/s_axis_aclk interconnect/S00_ACLK
net xdma_0/axi_aresetn stream_fifo/s_axis_aresetn interconnect/S00_ARESETN status/dma_resetn
net xdma_0/user_lnk_up status/link_up
net status/status gpio/gpio2_io_i
net gpio/gpio_io_o status/leds
set leds [create_bd_port -dir O -from 2 -to 0 led_3bits_tri_o]
connect_bd_net $leds [get_bd_pins gpio/gpio_io_o]
net zero/dout xdma_0/usr_irq_req
net refclk_buf/IBUF_OUT xdma_0/sys_clk
set perst [create_bd_port -dir I -type rst pcie_perstn]
set_property CONFIG.POLARITY ACTIVE_LOW $perst
connect_bd_net $perst [get_bd_pins xdma_0/sys_rst_n] [get_bd_pins status/pcie_resetn]
foreach {pin port} {xdma_0/pcie_mgt pci_express_x8 refclk_buf/CLK_IN_D pcie_refclk temperature/IIC iic_lm73} {
    make_bd_intf_pins_external [get_bd_intf_pins $pin]
    set_property name $port [get_bd_intf_ports [file tail $pin]_0]
}
set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports pcie_refclk]
foreach {a b} {xdma_0/M_AXIS_H2C_0 stream_fifo/S_AXIS stream_fifo/M_AXIS xdma_0/S_AXIS_C2H_0 xdma_0/M_AXI_LITE interconnect/S00_AXI jtag_axi/M_AXI interconnect/S01_AXI interconnect/M00_AXI gpio/S_AXI interconnect/M01_AXI temperature/S_AXI} {
    connect_bd_intf_net [get_bd_intf_pins $a] [get_bd_intf_pins $b]
}
foreach master {xdma_0/M_AXI_LITE jtag_axi/Data} {
    assign_bd_address -target_address_space [get_bd_addr_spaces $master] -offset 0x00000000 -range 64K [get_bd_addr_segs gpio/S_AXI/Reg] -force
    assign_bd_address -target_address_space [get_bd_addr_spaces $master] -offset 0x00010000 -range 64K [get_bd_addr_segs temperature/S_AXI/Reg] -force
}
validate_bd_design
save_bd_design
write_bd_tcl -force $root/reports/accelerator_bd.tcl
generate_target all [get_files accelerator.bd]
make_wrapper -files [get_files accelerator.bd] -top
add_files $root/build/accelerator/accelerator.gen/sources_1/bd/accelerator/hdl/accelerator_wrapper.v
set_property top accelerator_wrapper [current_fileset]
update_compile_order -fileset sources_1
# Build the small design as a single synthesis run to limit memory use.
set_property synth_checkpoint_mode None [get_files accelerator.bd]
puts "DESIGN_CREATED"
