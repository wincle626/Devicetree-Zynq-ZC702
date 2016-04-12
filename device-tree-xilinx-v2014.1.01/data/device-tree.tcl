#
# Xilinx BSP board generation for device trees supporting Microblaze and Zynq
#
# (C) Copyright 2007-2014 Xilinx, Inc.
# Based on original code:
# (C) Copyright 2007-2014 Michal Simek
# (C) Copyright 2007-2012 PetaLogix Qld Pty Ltd
#
# Michal SIMEK <monstr@monstr.eu>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307 USA

# Debug mechanism.
variable debug_level {}
# Uncomment the line below to get general progress messages.
lappend debug_level [list "info"]
# Uncomment the line below to get warnings about IP core usage.
lappend debug_level [list "warning"]
# Uncomment the line below to get a summary of clock analysis.
lappend debug_level [list "clock"]
# Uncomment the line below to get verbose IP information.
lappend debug_level [list "ip"]
# Uncomment the line below to get debugging information about EDK handles.
# lappend debug_level [list "handles"]


# Globals variable
variable device_tree_generator_version "1.1"
variable cpunumber 0
variable periphery_array ""
variable buses {}
variable bus_count 0
variable mac_count 0
variable gpio_names {}
variable overrides {}

variable serial_count 0
variable sysace_count 0
variable ethernet_count 0
variable i2c_count 0
variable spi_count 0
variable alias_node_list {}
variable phy_count 0
variable trafgen_count 0

variable vdma_device_id 0
variable dma_device_id 0
variable cdma_device_id 0
variable no_reg_id 0

# FIXME it will be better not to use it
variable ps7_cortexa9_1x_clk 0

variable ps7_smcc_list {}

variable simple_version 0

# For calling from top level BSP
proc bsp_drc {os_handle} {
	debug info "\#--------------------------------------"
	debug info "\# device-tree BSP DRC..."
	debug info "\#--------------------------------------"
}

# If standalone purpose
proc device_tree_drc {os_handle} {
	bsp_drc $os_handle
}

proc generate {os_handle} {
	variable  device_tree_generator_version
	variable simple_version

	debug info "\#--------------------------------------"
	debug info "\# device-tree BSP generate..."
	debug info "\#--------------------------------------"

	set bootargs [get_property CONFIG.bootargs $os_handle ]
	global consoleip
	set consoleip [get_property CONFIG.stdout $os_handle ]
	if {[llength $consoleip] == 0} {
		set consoleip [get_property "CONFIG.console device" $os_handle ]
		variable simple_version
		set simple_version "1"
	}

	global overrides
	set overrides [get_property CONFIG.periph_type_overrides $os_handle ]
	# Format override string to list format
	set overrides [string map { "\}\{" "\} \{" } $overrides]
	edk_override_update

	global main_memory
	set main_memory [get_property CONFIG.main_memory $os_handle ]

	global main_memory_bank
	set main_memory_bank [get_property CONFIG.main_memory_bank $os_handle ]
	if {[llength $main_memory_bank] == 0} {
		set main_memory_bank 0
	}
	global main_memory_start
	set main_memory_start [get_property CONFIG.main_memory_start $os_handle ]
	global main_memory_size
	set main_memory_size [get_property CONFIG.main_memory_size $os_handle ]
	global main_memory_offset
	set main_memory_offset [get_property CONFIG.main_memory_offset $os_handle ]
	global flash_memory
	set flash_memory [get_property CONFIG.flash_memory $os_handle ]
	global flash_memory_bank
	set flash_memory_bank [get_property CONFIG.flash_memory_bank $os_handle ]
	global timer
	set timer [get_property CONFIG.timer $os_handle ]

	if { "$simple_version" == "1" } {
		set main_memory_start -1
		set main_memory_size 0
	}

	global buses
	set buses {}

	generate_device_tree "xilinx.dts" $bootargs $consoleip
}

proc edk_override_update {} {
	global overrides

	set allover $overrides
	set overrides ""
	foreach over $allover {
		if { "[string first "-" [lindex $over 1]]" == "0" } {
			set ipname [string tolower [lindex $over 2]]
			lset over 2 $ipname
		} else {
			set ipname [string tolower [lindex $over 1]]
			lset over 1 $ipname
		}
		lappend overrides $over
	}
}

proc generate_device_tree {filepath bootargs {consoleip ""}} {
	variable  device_tree_generator_version
	global board_name
	debug info "--- device tree generator version: v$device_tree_generator_version ---"
	debug info "generating $filepath"

	set toplevel {}
	set ip_tree {}

	set proc_handle [get_sw_processor]
	set hwproc_handle [get_cells -filter "NAME==[get_property HW_INSTANCE $proc_handle]"]

	set proctype [get_property IP_NAME $hwproc_handle ]
	switch $proctype {
		"microblaze" {
			# Microblaze linux system requires dual-channel timer
			global timer
			variable simple_version

			if { "$simple_version" != "1" } {
				if { [string match "" $timer] || [string match "none" $timer] } {
					error "No timer is specified in the system. Linux requires dual channel timer."
				}
			}

			set buses {}
			set intc [get_handle_to_intc $proc_handle "Interrupt"]

			# Microblaze v8 has AXI. xget_hw_busif_handle returns
			# a valid handle for both these bus ifs, even if they are not
			# connected. The better way of checking if a bus is connected
			# or not is to check it's value.
			set bus_intf [get_intf_pins -of_objects $hwproc_handle M_AXI_DC]
			set bus_name [get_intf_nets -of_objects $bus_intf]
			if { [string compare -nocase $bus_name ""] != 0 } {
				set tree [bus_bridge $hwproc_handle $intc 0 "M_AXI_DC"]
				if { [llength $tree] != 0 } {
					set tree [tree_append $tree [list ranges empty empty]]
					lappend ip_tree $tree
					lappend buses $bus_name
				}
			}
			set bus_intf [get_intf_pins -of_objects $hwproc_handle "M_AXI_DP"]
			set bus_name [get_intf_nets -of_objects $bus_intf]
			if { [string compare -nocase $bus_name ""] != 0 } {
				set tree [bus_bridge $hwproc_handle $intc 0 "M_AXI_DP"]
				if { [llength $tree] != 0 } {
					set tree [tree_append $tree [list ranges empty empty]]
					lappend ip_tree $tree
					lappend buses $bus_name
				}
			}

			set clk [get_clock_frequency $hwproc_handle "CLK"]
			set subclk_tree_cpu [list "clk_cpu: cpu" tree {}]
			set subclk_tree_cpu [tree_append $subclk_tree_cpu [list "#clock-cells" int "0"]]
			set subclk_tree_cpu [tree_append $subclk_tree_cpu [list "reg" int "0"]]
			set subclk_tree_cpu [tree_append $subclk_tree_cpu [list "compatible" stringtuple "fixed-clock"]]
			set subclk_tree_cpu [tree_append $subclk_tree_cpu [list "clock-frequency" int "$clk" ]]
			set subclk_tree_cpu [tree_append $subclk_tree_cpu [list "clock-output-names" stringtuple "cpu"]]

			# FIXME Let assume IPs on bus have also the same clk as cpu which is not truth all the time
			set subclk_tree_bus [list "clk_bus: bus" tree {}]
			set subclk_tree_bus [tree_append $subclk_tree_bus [list "#clock-cells" int "0"]]
			set subclk_tree_bus [tree_append $subclk_tree_bus [list "reg" int "1"]]
			set subclk_tree_bus [tree_append $subclk_tree_bus [list "compatible" stringtuple "fixed-clock"]]
			set subclk_tree_bus [tree_append $subclk_tree_bus [list "clock-frequency" int "$clk" ]]
			set subclk_tree_bus [tree_append $subclk_tree_bus [list "clock-output-names" stringtuple "bus"]]

			set clock_tree [list "clocks" tree {}]
			set clock_tree [tree_append $clock_tree [list "#address-cells" int "1"]]
			set clock_tree [tree_append $clock_tree [list "#size-cells" int "0"]]

			set clock_tree [tree_append $clock_tree $subclk_tree_cpu]
			set clock_tree [tree_append $clock_tree $subclk_tree_bus]
			lappend ip_tree $clock_tree

			set toplevel [gen_microblaze $toplevel $hwproc_handle [default_parameters $hwproc_handle] $intc $buses]

			lappend toplevel [list "compatible" stringtuple [list "xlnx,microblaze"] ]
			if { ![info exists board_name] } {
				lappend toplevel [list model string "Xilinx MicroBlaze"]
			}

			variable microblaze_system_timer
			if { "$simple_version" != "1" } {
				if { [llength $microblaze_system_timer] == 0 } {
					error "Microblaze requires to setup system timer. Please setup it!"
				}
			}
		}
		"ps7_cortexa9" {
			global timer
			set timer ""

			# MS: This is nasty hack how to get all slave IPs
			# What I do is that load all IPs from M_AXI_DP and then pass all IPs
			# in bus_bridge then handle the rest of IPs
			set ips [xget_hw_proc_slave_periphs $hwproc_handle]

			# FIXME uses axi_ifs instead of ips and remove that param from bus_bridge
			global axi_ifs
			set axi_ifs ""

			# Find out GIC
			foreach i $ips {
				if { "[get_property IP_NAME $i]" == "ps7_scugic" } {
					set intc "$i"
				}
			}

			variable ps7_cortexa9_1x_clk
			set ps7_cortexa9_1x_clk [get_ip_param_value $hwproc_handle "C_CPU_1X_CLK_FREQ_HZ"]

			set bus_intf [get_intf_pins -of_objects $hwproc_handle "M_AXI_DP"]
			set bus_name [get_intf_nets -of_objects $bus_intf]
			if { [string compare -nocase $bus_name ""] != 0 } {
				set tree [bus_bridge $hwproc_handle $intc 0 "M_AXI_DP" "" $ips "ps7_pl310 ps7_xadc ps7_globaltimer"]
				set tree [tree_append $tree [list ranges empty empty]]
				lappend ip_tree $tree
				lappend buses $bus_name
			}

			set toplevel [gen_cortexa9 $toplevel $hwproc_handle $intc [default_parameters $hwproc_handle] $buses]

			lappend toplevel [list "compatible" stringtuple "xlnx,zynq-7000" ]
			if { ![info exists board_name] } {
				lappend toplevel [list model string "Xilinx Zynq"]
			}
		}
		default {
			error "unsupported CPU"
		}
	}

	variable alias_node_list
	debug info "$alias_node_list"

	if {[llength $bootargs] == 0} {
		# generate default string for uart16550 or uartlite if specified
		if {![string match "" $consoleip] && ![string match -nocase "none" $consoleip] } {
			set uart_handle [get_cells $consoleip]
			switch -exact [get_property IP_NAME $uart_handle] {
				"axi_uart16550" {
					# for uart16550 is default string 115200
					set bootargs "console=ttyS0,115200"
				}
				"axi_uartlite" {
					set bootargs "console=ttyUL0,[get_ip_param_value $uart_handle C_BAUDRATE]"
				}
				"mdm" {
					set bootargs "console=ttyUL0,115200"
				}
				"ps7_uart" {
					set bootargs "console=ttyPS0,115200"
				}
				default {
					debug warning "WARNING: Unsupported console ip $consoleip. Can't generate bootargs."
				}
			}
		}
	}

	set chosen {}
	lappend chosen [list bootargs string $bootargs]

	set dev_tree [concat $toplevel $ip_tree]
	if {$consoleip != ""} {
		set consolepath [get_pathname_for_label $dev_tree $consoleip]
		if {$consolepath != ""} {
			lappend chosen [list "linux,stdout-path" string $consolepath]
		} else {
			debug warning "WARNING: console ip $consoleip was not found.  This may prevent output from appearing on the boot console."
		}
	} else {
		debug warning "WARNING: no console ip was specified.  This may prevent output from appearing on the boot console."
	}

	lappend toplevel [list \#size-cells int 1]
	lappend toplevel [list \#address-cells int 1]

	if { [info exists board_name] } {
		lappend toplevel [list model string [prj_dir]]
	}

	set reset [reset_gpio]
	if { "$reset" != "" } {
		lappend toplevel $reset
	}
	lappend toplevel [list chosen tree $chosen]

	#
	# Add the alias section to toplevel
	#
	lappend toplevel [list aliases tree $alias_node_list]

	set toplevel [gen_memories $toplevel $hwproc_handle]

	set toplevel_file [open $filepath w]
	headerc $toplevel_file $device_tree_generator_version
	puts $toplevel_file "/dts-v1/;"
	puts $toplevel_file "/ {"
	write_tree 0 $toplevel_file $toplevel
	write_tree 0 $toplevel_file $ip_tree
	puts $toplevel_file "} ;"
	close $toplevel_file
}

proc post_generate {lib_handle} {
}

proc prj_dir {} {
	# board_name comes from toplevel BSP context
	global board_name

	if { [info exists board_name] } {

		return $board_name
	}
	return [file tail [file normalize [file join .. .. ..]]]
}

proc headerc {ufile generator_version} {
	puts $ufile "/*"
	puts $ufile " * Device Tree Generator version: $generator_version"
	puts $ufile " *"
	puts $ufile " * (C) Copyright 2007-2013 Xilinx, Inc."
	puts $ufile " * (C) Copyright 2007-2013 Michal Simek"
	puts $ufile " * (C) Copyright 2007-2012 PetaLogix Qld Pty Ltd"
	puts $ufile " *"
	puts $ufile " * Michal SIMEK <monstr@monstr.eu>"
	puts $ufile " *"
	puts $ufile " * CAUTION: This file is automatically generated by HSM."
	puts $ufile " * Version: HSM [xget_swverandbld]"
	puts $ufile " * [clock format [clock seconds] -format {Today is: %A, the %d of %B, %Y; %H:%M:%S}]"
	puts $ufile " *"
	puts $ufile " * project directory: [prj_dir]"
	puts $ufile " */"
	puts $ufile ""
}

# generate structure for reset gpio.
# mss description - first pin of Reset_GPIO ip is used for system reset
# {key-word IP_name gpio_pin size_of_pin}
# for reset-gpio is used only size equals 1
#
# PARAMETER periph_type_overrides = {hard-reset-gpios Reset_GPIO 1 1}
proc reset_gpio {} {
	global overrides
	# ignore size parameter
	set reset {}
	foreach over $overrides {
		# parse hard-reset-gpio keyword
		if {[lindex $over 0] == "hard-reset-gpios"} {
			# search if that gpio name is valid IP core in system
			set desc [valid_gpio [lindex $over 1]]
			if { "$desc" != "" } {
				# check if is pin larger then gpio width
				if {[lindex $desc 1] > [lindex $over 2]} {
					set k [ list [lindex $over 1] [lindex $over 2] 1]
					set reset "hard-reset-gpios labelref-ext {{$k}}"
					return $reset
				} else {
					debug info "RESET-GPIO: Requested pin is greater than number of GPIO pins: $over"
				}
			} else {
				debug info "RESET-GPIO: Not valid IP name: $over"
			}
		}
	}
	return
}

# For generation of gpio led description
# this function is called from bus code because linux needs to have this description in the same node as is IP
# FIXME there could be maybe problem if system contains bridge and gpio is after it - needs test
#
# PARAMETER periph_type_overrides = {led heartbeat LEDs_8Bit 5 5} {led yellow LEDs_8Bit 7 2} {led green LEDs_8Bit 4 1}
proc led_gpio {} {
	global overrides
	set tree {}
	foreach over $overrides {
		# parse hard-reset-gpio keyword
		if {[lindex $over 0] == "led"} {
			# clear trigger
			set trigger ""
			set desc [valid_gpio [lindex $over 2]]
			if { "$desc" != "" } {
				# check if is pin larger then gpio width
				if { [lindex $desc 1] > [lindex $over 3]} {
					# check if the size exceed number of pins
					if { [lindex $desc 1] >= [expr [lindex $over 3] + [lindex $over 4]] } {
						# assemble led node
						set label_desc "{label string [lindex $over 1]}"
						set led_pins "{[lindex $over 2] [lindex $over 3] [lindex $over 4]}"
						if { [string match -nocase "heartbeat" [lindex $over 1]] } {
							set trigger "{linux,default-trigger string heartbeat}"
						}
						set tree "{[lindex $over 1] tree { $label_desc $trigger { gpios labelref-ext $led_pins }}} $tree"
					} else {
						debug info "LED-GPIO: Requested pin size reach out of GPIO pins width: $over"
					}

				} else {
					debug info "LED-GPIO: Requested pin is greater than number of GPIO pins: $over"
				}
			} else {
				debug info "LED-GPIO: Not valid IP name $over"
			}
		}
	}
	# it is a complex node that's why I have to assemble it
	if { "$tree" != "" } {
		set tree "gpio-leds tree { {compatible string gpio-leds} $tree }"
	}
	return $tree
}

# Check if gpio name is valid or not
proc valid_gpio {name} {
	global gpio_names
	foreach gpio_desc $gpio_names {
		if { [string match -nocase [lindex $gpio_desc 0] "$name" ] } {
			return $gpio_desc
		}
	}
	return
}

proc get_intc_signals {intc} {

	# MS the simplest way to detect ARM is through intc type
	if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
		# MS here is small complication because INTC from FPGA
		# are divided to two separate segments. That's why
		# I generate two silly offsets to setup correct location
		# for both segments.
		# FPGA 7-0 - irq 61 - 68
		# FPGA 15-8 - irq 84 - 91

		set interrupt_pin [get_pins -of_objects $intc IRQ_F2P]
		set interrupt_net [get_nets -of_objects $interrupt_pin]
		set int_lines "[split $interrupt_net "&"]"

		set fpga_irq_id 0
		set irq_signals {}

		# append the leading irq bits equal to 0
		for {set x [llength ${irq_signals}]} {$x < [expr "16-[llength $int_lines]"]} {incr x} {
			lappend irq_signals 0
		}

		for {set x 0} {$x < [llength $int_lines]} {incr x} {
				set e [string trim [lindex ${int_lines} $x ]]
				if { [string range $e 0 1] == "0b" } {
					# Sometimes there could be 0 instead of a physical interrupt signal
					set siglength [ expr [string length $e] - 2 ]
					for {set y 0} {$y < ${siglength}} {incr y} {
						lappend irq_signals 0
					}
				} elseif { [string range $e 0 1] == "0x" } {
					# Sometimes there could be 0 instead of a physical interrupt signal
					error "This interrupt signal is a hex digit, cannot detect the length of it"
				} else {
					# actual interrupt signal
					lappend irq_signals $e
				}
		}
		if { [llength $irq_signals] > 16 } {
			error "Too many interrupt lines connected to Zynq GIC"
		}


		# skip the first 32 interrupts because of Linux
		# and generate numbers till the first fpga area
		# top to down 60 - 32
		set linux_irq_offset 32
		for {set x 60} {$x >= $linux_irq_offset} { set x [expr $x - 1] } {
			lappend pl1 $x
		}

		# offset between fpga 7-0 and 15-8 is fixed
		# top to down 83 - 69
		for {set x 83} {$x >= 69} { set x [expr $x - 1] } {
			lappend pl2 $x
		}

		# Compose signal string with this layout from top to down
		set signals "[lrange ${irq_signals} 0 7] $pl2 [lrange ${irq_signals} 8 15] $pl1"

	} else {
		set interrupt_pin [get_pins -of_objects $intc intr]
		set interrupt_net [get_nets -of_objects $interrupt_pin]
		set signals [split $interrupt_net "&"]
	}

	set intc_signals {}
	foreach signal $signals {
		lappend intc_signals [string trim $signal]
	}
	return $intc_signals
}

# Get interrupt number
proc get_intr {ip_handle intc port_name} {
	if {![string match "" $intc] && ![string match -nocase "none" $intc]} {
		set intc_signals [get_intc_signals $intc]
		set port_handle [get_pins -of_objects $ip_handle "$port_name"]
		set interrupt_signal [get_nets -of_objects $port_handle ]
		set index [lsearch $intc_signals $interrupt_signal]
		if {$index == -1} {
			return -1
		} else {
			# interrupt 0 is last in list.
			return [expr [llength $intc_signals] - $index - 1]
		}
	} else {
		return -1
	}
}

proc get_intr_type {intc ip_handle port_name} {
	set ip_name [get_property NAME $ip_handle]
	set port_handle [get_pins -of_objects $ip_handle "$port_name"]
	set sensitivity [get_property SENSITIVITY $port_handle];

	if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
		# Follow the openpic specification
		if { [string compare -nocase $sensitivity "EDGE_FALLING"] == 0 } {
			return 2;
		} elseif { [string compare -nocase $sensitivity "EDGE_RISING"] == 0 } {
			return 1;
		} elseif { [string compare -nocase $sensitivity "LEVEL_HIGH"] == 0 } {
			return 4;
		} elseif { [string compare -nocase $sensitivity "LEVEL_LOW"] == 0 } {
			return 8;
		}
	} else {
		# Follow the openpic specification
		if { [string compare -nocase $sensitivity "EDGE_FALLING"] == 0 } {
			return 3;
		} elseif { [string compare -nocase $sensitivity "EDGE_RISING"] == 0 } {
			return 0;
		} elseif { [string compare -nocase $sensitivity "LEVEL_HIGH"] == 0 } {
			return 2;
		} elseif { [string compare -nocase $sensitivity "LEVEL_LOW"] == 0 } {
			return 1;
		}
	}

	error "Unknown interrupt sensitivity on port $port_name of $ip_name was $sensitivity"
}

# Generate a template for a compound slave, such as the ll_temac
proc compound_slave {slave {baseaddrname "C_BASEADDR"}} {
	set baseaddr [scan_int_parameter_value $slave ${baseaddrname}]
	set ip_name [get_property NAME $slave]
	set ip_type [get_property IP_NAME $slave]
	set tree [list [format_ip_name $ip_type $baseaddr $ip_name] tree {}]
	set tree [tree_append $tree [list \#size-cells int 1]]
	set tree [tree_append $tree [list \#address-cells int 1]]
	set tree [tree_append $tree [list ranges empty empty]]
	set tree [tree_append $tree [list compatible stringtuple [list "xlnx,compound"]]]
	return $tree
}

proc slaveip_intr {slave intc interrupt_port_list devicetype params {baseaddr_prefix ""} {dcr_baseaddr_prefix ""} {other_compatibles {}} {irq_names {}} } {
	set tree [slaveip $slave $intc $devicetype $params $baseaddr_prefix $other_compatibles]
	return [gen_interrupt_property $tree $slave $intc $interrupt_port_list $irq_names]
}

proc get_dcr_parent_name {slave face} {
	set busif_handle [get_intf_pins -of_objects $slave $face]
	if {[llength $busif_handle] == 0} {
		error "Bus handle $face not found!"
	}
	set bus_name [get_intf_nets -of_objects $busif_handle]

	debug ip "IP on DCR bus $bus_name"
	debug handles "  bus_handle: $busif_handle"
	set bus_handle [get_cells $bus_name]

	set master_ifs [get_intf_pins -of_objects $bus_name -filter "TYPE==MASTER"]
	if {[llength $master_ifs] == 1} {
		set ip_handle [get_cells -of_objects [lindex $master_ifs 0 0]]
		set ip_name [get_property NAME $ip_handle]
		return $ip_name
	} else {
		error "DCR bus found which does not have exactly one master.  Masters were $master_ifs"
	}
}

proc slaveip {slave intc devicetype params {baseaddr_prefix ""} {other_compatibles {}} } {
	set baseaddr_handle [get_property CONFIG.[format "C_%sBASEADDR" $baseaddr_prefix] $slave]
	set highaddr_handle [get_property CONFIG.[format "C_%sHIGHADDR" $baseaddr_prefix] $slave]
	if { $baseaddr_handle != "" && $highaddr_handle != "" } {
		set baseaddr [scan_int_parameter_value $slave [format "C_%sBASEADDR" $baseaddr_prefix]]
		set highaddr [scan_int_parameter_value $slave [format "C_%sHIGHADDR" $baseaddr_prefix]]
	} else {
		set baseaddr 0
		set highaddr 0
		set ip_mem_ranges [xget_ip_mem_ranges $slave]
		set memory_ranges {}
		foreach ip_mem_range $ip_mem_ranges {
			# check all
				set base [get_property BASE_NAME $ip_mem_range]
				set high [get_property HIGH_NAME $ip_mem_range]
				set baseaddr [scan_int_parameter_value $slave $base]
				set highaddr [scan_int_parameter_value $slave $high]
				if { "${baseaddr}" < "${highaddr}" } {
					break
				}
		}
	}

	set tree [slaveip_explicit_baseaddr $slave $intc $devicetype $params $baseaddr $highaddr $other_compatibles]
	return $tree
}

proc slaveip_pcie_ipif_slave {slave intc devicetype params {baseaddr_prefix ""} {other_compatibles {}} } {
	set baseaddr [scan_int_parameter_value $slave [format "C_%sMEM0_BASEADDR" $baseaddr_prefix]]
	set highaddr [scan_int_parameter_value $slave [format "C_%sMEM0_HIGHADDR" $baseaddr_prefix]]
	set tree [slaveip_explicit_baseaddr $slave $intc $devicetype $params $baseaddr $highaddr $other_compatibles]
	return $tree
}

proc slaveip_explicit_baseaddr {slave intc devicetype params baseaddr highaddr {other_compatibles {}} } {
	set name [get_property NAME $slave]
	set type [get_property IP_NAME $slave]
	if {$devicetype == ""} {
		set devicetype $type
	}
	set tree [slaveip_basic $slave $intc $params [format_ip_name $devicetype $baseaddr $name] $other_compatibles]
	return [tree_append $tree [gen_reg_property $name $baseaddr $highaddr]]
}

proc slaveip_basic {slave intc params nodename {other_compatibles {}} } {
	set name [get_property NAME $slave]
	set type [get_property IP_NAME $slave]

	set hw_ver [get_ip_version $slave]

	set ip_node {}
	lappend ip_node [gen_compatible_property $name $type $hw_ver $other_compatibles]

	# Generate the parameters
	set ip_node [gen_params $ip_node $slave $params]

	return [list $nodename tree $ip_node]
}

proc gen_intc {slave intc devicetype param {prefix ""} {other_compatibles {}}} {
	set tree [slaveip $slave $intc $devicetype $param $prefix $other_compatibles]
	set intc_name [lindex $tree 0]
	set intc_node [lindex $tree 2]

	# Tack on the interrupt-specific tags.
	lappend intc_node [list \#interrupt-cells hexint 2]
	lappend intc_node [list interrupt-controller empty empty]
	return [list $intc_name tree $intc_node]
}

proc ll_temac_parameters {ip_handle index} {
	set params {}
	foreach param [default_parameters $ip_handle] {
		set pattern [format "C_TEMAC%d*" $index]
		if {[string match $pattern $param]} {
			lappend params $param
		}
	}
	return $params
}

# Generate a slaveip, assuming it is inside a compound that has a
# baseaddress and reasonable ranges.
# index: The index of this slave
# stride: The distance between instances of the slave inside the container
# size: The size of the address space for the slave
proc slaveip_in_compound_intr {slave intc interrupt_port_list devicetype parameter_list index stride size} {
	set name [get_property NAME $slave]
	set type [get_property IP_NAME $slave]
	if {$devicetype == ""} {
		set devicetype $type
	}
	set baseaddr [expr $index * $stride]
	set highaddr [expr $baseaddr + $size - 1]
	set ip_tree [slaveip_basic $slave $intc $parameter_list [format_ip_name $devicetype $baseaddr]]
	set ip_tree [tree_append $ip_tree [gen_reg_property $name $baseaddr $highaddr]]
	set ip_tree [gen_interrupt_property $ip_tree $slave $intc $interrupt_port_list]
	return $ip_tree
}

proc slave_ll_temac_port {slave intc index} {
	set name [get_property NAME $slave]
	set type [get_property IP_NAME $slave]
	set baseaddr [scan_int_parameter_value $slave "C_BASEADDR"]
	set baseaddr [expr $baseaddr + $index * 0x40]
	set highaddr [expr $baseaddr + 0x3f]

	#
	# Add this temac channel to the alias list
	#
	variable ethernet_count
	variable alias_node_list
	set subnode_name [format "%s_%s" $name "ETHERNET"]
	set alias_node [list ethernet$ethernet_count aliasref $subnode_name $ethernet_count]
	lappend alias_node_list $alias_node
	incr ethernet_count

	set ip_tree [slaveip_basic $slave $intc "" [format_ip_name "ethernet" $baseaddr $subnode_name]]
	set ip_tree [tree_append $ip_tree [list "device_type" string "network"]]
	variable mac_count
	set ip_tree [tree_append $ip_tree [list "local-mac-address" bytesequence [list 0x00 0x0a 0x35 0x00 0x00 $mac_count]]]
	incr mac_count

	set ip_tree [tree_append $ip_tree [gen_reg_property $name $baseaddr $highaddr]]
	set ip_tree [gen_interrupt_property $ip_tree $slave $intc [format "TemacIntc%d_Irpt" $index]]
	set ip_name [lindex $ip_tree 0]
	set ip_node [lindex $ip_tree 2]
	# Generate the parameters, stripping off the right prefix.
	set ip_node [gen_params $ip_node $slave [ll_temac_parameters $slave $index] [format "C_TEMAC%i_" $index]]
	# Generate the common parameters.
	set ip_node [gen_params $ip_node $slave [list "C_PHY_TYPE" "C_TEMAC_TYPE" "C_BUS2CORE_CLK_RATIO"]]
	set ip_tree [list $ip_name tree $ip_node]
	# See what the temac is connected to.
	set ll_busif_handle [get_intf_pins -of_objects $slave "LLINK$index"]
	set ll_name [get_intf_nets -of_objects $ll_busif_handle]
	set ll_ip_handle [get_intf_pins -of_objects $ll_name -filter "TYPE==TARGET"]
	set ll_ip_handle_name [get_property NAME $ll_ip_handle]
	set connected_ip_handle [get_cells -of_objects $ll_ip_handle]
	set connected_ip_name [get_property NAME $connected_ip_handle]
	set connected_ip_type [get_property IP_NAME $connected_ip_handle]
	if {$connected_ip_type == "mpmc"} {
		# Assumes only one MPMC.
		if {[string match SDMA_LL? $ll_ip_handle_name]} {
			set port_number [string range $ll_ip_handle_name 7 7]
			set sdma_name "PIM$port_number"
			set ip_tree [tree_append $ip_tree [list "llink-connected" labelref $sdma_name]]
		} else {
			error "found ll_temac connected to mpmc, but can't find the port number!"
		}
	} else {
		# Hope it's something that only has one locallink
		set ip_tree [tree_append $ip_tree [list "llink-connected" labelref "$connected_ip_name"]]
	}
	return $ip_tree
}
proc slave_ll_temac {slave intc} {
	set tree [compound_slave $slave]
	set tree [tree_append $tree [slave_ll_temac_port $slave $intc 0] ]
	set port1_enabled  [scan_int_parameter_value $slave "C_TEMAC1_ENABLED"]
	if {$port1_enabled == "1"} {
		set tree [tree_append $tree [slave_ll_temac_port $slave $intc 1] ]
	}
	return $tree
}
proc slave_mpmc {slave intc} {
	set share_addresses [scan_int_parameter_value $slave "C_ALL_PIMS_SHARE_ADDRESSES"]
	if {[catch {
		# Found control port for ECC and performance monitors
		set tree [slaveip $slave $intc "" "" "MPMC_CTRL_"]
		set ip_name [lindex $tree 0]
		set mpmc_node [lindex $tree 2]
	}]} {
		# No control port
		if {$share_addresses == 0} {
			set baseaddr [scan_int_parameter_value $slave "C_PIM0_BASEADDR"]
		} else {
			set baseaddr [scan_int_parameter_value $slave "C_MPMC_BASEADDR"]
		}
		set tree [slaveip_basic $slave $intc "" [format_ip_name "mpmc" $baseaddr] ]
		set ip_name [lindex $tree 0]
		set mpmc_node [lindex $tree 2]

		# Generate the parameters
		# set mpmc_node [gen_params $mpmc_node $slave [default_parameters $slave] ]

	}
	lappend mpmc_node [list \#size-cells int 1]
	lappend mpmc_node [list \#address-cells int 1]
	lappend mpmc_node [list ranges empty empty]

	set num_ports [scan_int_parameter_value $slave "C_NUM_PORTS"]
	for {set x 0} {$x < $num_ports} {incr x} {
		set pim_type [scan_int_parameter_value $slave [format "C_PIM%d_BASETYPE" $x]]
		if {$pim_type == 3} {
			# Found an SDMA port
			if {$share_addresses == 0} {
				set baseaddr [scan_int_parameter_value $slave [format "C_SDMA_CTRL%d_BASEADDR" $x]]
				set highaddr [scan_int_parameter_value $slave [format "C_SDMA_CTRL%d_HIGHADDR" $x]]
			} else {
				set baseaddr [scan_int_parameter_value $slave "C_SDMA_CTRL_BASEADDR"]
				set baseaddr [expr $baseaddr + $x * 0x80]
				set highaddr [expr $baseaddr + 0x7f]
			}

			set sdma_name [format_ip_name sdma $baseaddr "PIM$x"]
			set sdma_tree [list $sdma_name tree {}]
			set sdma_tree [tree_append $sdma_tree [gen_reg_property $sdma_name $baseaddr $highaddr]]
			set sdma_tree [tree_append $sdma_tree [gen_compatible_property $sdma_name "ll_dma" "1.00.a"]]
			set sdma_tree [gen_interrupt_property $sdma_tree $slave $intc [list [format "SDMA%d_Rx_IntOut" $x] [format "SDMA%d_Tx_IntOut" $x]]]

			lappend mpmc_node $sdma_tree

		}
	}
	return [list $ip_name tree $mpmc_node]
}

#
#get handle to interrupt controller from CPU handle
#
proc get_handle_to_intc {proc_handle port_name} {
	#one CPU handle
    set hwproc_handle [get_cells -filter "NAME==[get_property HW_INSTANCE $proc_handle]"]

	#get handle to interrupt port on Microblaze
	set intr_port [get_pins -of_objects $hwproc_handle $port_name]
	if { [llength $intr_port] == 0 } {
		error "CPU has not connection to Interrupt controller"
	}
	#get source port periphery handle - on interrupt controller
	set source_port [xget_source_pins $intr_port ]
	#get interrupt controller handle
	set intc [get_cells -of_objects $source_port]
	set name [get_property NAME $intc]
	debug handles "Interrupt Controller: $name $intc"
	return $intc
}

#return number of tabulator
proc tt {number} {
	set tab ""
	for {set x 0} {$x < $number} {incr x} {
		set tab "$tab\t"
	}
	return $tab
}

# Change the name of a node.
proc change_nodename {nodetochange oldname newname} {
	if {[llength $nodetochange] == 0} {
		error "Tried to change the name of an empty node: $oldname with $newname"
	}
	# The name of a node is in the first element of the node
	set lineofname [lindex $nodetochange 0]
	set substart [string first $oldname $lineofname]
	set subend [expr {$substart + [string length $oldname] - 1}]
	set lineofname [string replace $lineofname $substart $subend $newname]
	return [lreplace $nodetochange 0 0 "$lineofname"]
}

proc check_console_irq {slave intc} {
	global consoleip
	set name [get_property NAME $slave]

	set irq [get_intr $slave $intc [interrupt_list $slave]]
	if { $irq == "-1" } {
		if {[string match -nocase $name $consoleip]} {
			error "Console($name) interrupt line is not connected to the interrupt controller [get_property NAME $intc]. Please connect it or choose different console IP."
		} else {
			debug warning "Warning!: Serial IP ($name) has no interrupt connected!"
		}
	}
	return $irq
}

proc zynq_irq {ip_tree intc name } {
	array set zynq_irq_list [ list \
		{cpu_timerFIXME} {{1 11 1}} \
		{ps7_globaltimer_0} {{1 11 0x301}} \
		{nFIQFIXME} {{1 12 8}} \
		{ps7_scutimer_0} {{1 13 0x301}} \
		{ps7_scuwdt_0} {{1 14 0x301}} \
		{nIRQFIXME} {{1 15 8}} \
		{ps7_core_parity} {{0 0 1 0 1 1}} \
		{ps7_pl310} {{0 2 4}} \
		{ps7_ram_0} {{0 3 4}} \
		{ps7_reserved} {{0 4 4}} \
		{ps7_pmu} {{0 5 4 0 6 4}} \
		{ps7_xadc} {{0 7 4}} \
		{ps7_dev_cfg_0} {{0 8 4}} \
		{ps7_wdt_0} {{0 9 1}} \
		{ps7_ttc_0} {{0 10 4 0 11 4 0 12 4} {ttc0 ttc1 ttc2}}\
		{ps7_dma_s} {{0 13 4 0 14 4 0 15 4 0 16 4 0 17 4 0 40 4 0 41 4 0 42 4 0 43 4} {abort dma0 dma1 dma2 dma3 dma4 dma5 dma6 dma7}} \
		{ps7_dma_ns} {{0 13 4 0 14 4 0 15 4 0 16 4 0 17 4 0 40 4 0 41 4 0 42 4 0 43 4} {abort dma0 dma1 dma2 dma3 dma4 dma5 dma6 dma7}} \
		{ps7_smcc} {{0 18 4}} \
		{ps7_qspi_0} {{0 19 4}} \
		{ps7_gpio_0} {{0 20 4}} \
		{ps7_usb_0} {{0 21 4}} \
		{ps7_ethernet_0} {{0 22 4}} \
		{ps7_ethernet_wake0FIXME} {{0 23 1}} \
		{ps7_sd_0} {{0 24 4}} \
		{ps7_i2c_0} {{0 25 4}} \
		{ps7_spi_0} {{0 26 4}} \
		{ps7_uart_0} {{0 27 4}} \
		{ps7_can_0} {{0 28 4}} \
		{ps7_ttc_1} {{0 37 4 0 38 4 0 39 4} {ttc0 ttc1 ttc2}} \
		{ps7_usb_1} {{0 44 4}} \
		{ps7_ethernet_1} {{0 45 4}} \
		{ps7_ethernet_wake1FIXME} {{0 46 1}} \
		{ps7_sd_1} {{0 47 4}} \
		{ps7_i2c_1} {{0 48 4}} \
		{ps7_spi_1} {{0 49 4}} \
		{ps7_uart_1} {{0 50 4}} \
		{ps7_can_1} {{0 51 4}} \
		{scu_parityFIXME} {{0 60 1}} \
	]

	if { [info exists zynq_irq_list($name)] } {
		set irq "$zynq_irq_list($name)"

		set ip_tree [tree_append $ip_tree [list "interrupts" irqtuple3 [lindex $irq 0]]]
		if {[llength $irq] == 2 } {
			set ip_tree [tree_append $ip_tree [list "interrupt-names" stringtuple [lindex $irq 1]]]
		}

		set intc_name [get_property NAME $intc]
		set ip_tree [tree_append $ip_tree [list "interrupt-parent" labelref $intc_name]]
	}
	return $ip_tree
}

proc zynq_clk {ip_tree name} {
	array set zynq_clk_list [ list \
		{ps7_scuwdt_0} {{"clkc 4"}} \
		{ps7_scutimer_0} {{"clkc 4"}} \
		{ps7_globaltimer_0} {{"clkc 4"}} \
		{ps7_ttc_0} {{"clkc 6"}} \
		{ps7_ttc_1} {{"clkc 6"}} \
		{ps7_qspi_0} {{"clkc 10" "clkc 43"} {"ref_clk" "aper_clk"}} \
		{ps7_qspi_linear_0} {{"clkc 10" "clkc 43"} { "ref_clk" "aper_clk" }} \
		{ps7_smcc_0} {{"clkc 11" "clkc 44"} {"memclk" "aclk"}} \
		{ps7_xadc} {{"clkc 12"}} \
		{ps7_dev_cfg_0} {{"clkc 12" "clkc 15" "clkc 16" "clkc 17" "clkc 18"} {"ref_clk" "fclk0" "fclk1" "fclk2" "fclk3"}} \
		{ps7_ethernet_0} {{"clkc 13" "clkc 30"} {"ref_clk" "aper_clk"}} \
		{ps7_ethernet_1} {{"clkc 14" "clkc 31"} {"ref_clk" "aper_clk"}} \
		{ps7_can_0} {{"clkc 19" "clkc 36"} {"ref_clk" "aper_clk"}} \
		{ps7_can_1} {{"clkc 20" "clkc 37"} {"ref_clk" "aper_clk"}} \
		{ps7_sd_0} {{"clkc 21" "clkc 32"} {"clk_xin" "clk_ahb"}} \
		{ps7_sd_1} {{"clkc 22" "clkc 33"} {"clk_xin" "clk_ahb"}} \
		{ps7_uart_0} {{"clkc 23" "clkc 40"} {"ref_clk" "aper_clk"}} \
		{ps7_uart_1} {{"clkc 24" "clkc 41"} {"ref_clk" "aper_clk"}} \
		{ps7_spi_0} {{"clkc 25" "clkc 34"} {"ref_clk" "pclk"}} \
		{ps7_spi_1} {{"clkc 26" "clkc 35"} {"ref_clk" "pclk"}} \
		{ps7_dma_s} {{"clkc 27"} {"apb_pclk"}} \
		{ps7_usb_0} {{"clkc 28"}} \
		{ps7_usb_1} {{"clkc 29"}} \
		{ps7_i2c_0} {{"clkc 38"}} \
		{ps7_i2c_1} {{"clkc 39"}} \
		{ps7_gpio_0} {{"clkc 42"}} \
		{ps7_wdt_0} {{"clkc 45"}} \
	]

	if { [info exists zynq_clk_list($name)] } {
		set clk "$zynq_clk_list($name)"
		set ip_tree [tree_append $ip_tree [list "clocks" labelreftuple [lindex $clk 0]]]
		if { [llength $clk] == 2 } {
			set ip_tree [tree_append $ip_tree [list "clock-names" stringtuple [lindex $clk 1]]]
		}
	}
	return $ip_tree
}

proc ps7_reset_handle {ip_tree slave param_name name} {
	set reset_handle [get_ip_param_value $slave $param_name]
	if { [llength $reset_handle ] } {
		set value $reset_handle
		regsub -all "MIO" $value "" value
		# Hardcode ps7_gpio_0 because it is hardcoded name for ps gpio
		if { $value != "-1" &&  [llength $value] != 0 && [string is integer $value] } {
			set ip_tree [tree_append $ip_tree [list "$name" labelref-ext "ps7_gpio_0 $value 0"]]
		}
	}

	return $ip_tree
}

proc gener_slave {node slave_ip intc {force_type ""} {busif_handle ""}} {
	set slave [get_cells $slave_ip]
	debug handles "gener_slave node=$node slave=$slave intc=$intc force_type=$force_type busif_handle=$busif_handle"
	variable phy_count
	variable mac_count

	set proc_handle [get_sw_processor]
	set hwproc_handle [get_cells -filter "NAME==[get_property HW_INSTANCE $proc_handle]"]
	set proctype [get_property IP_NAME $hwproc_handle ]

	if { [llength $force_type] != 0 } {
		set name $force_type
		set type $force_type
	} else {
		set name [get_property NAME $slave]
		set type [get_property IP_NAME $slave]

		# Ignore IP through overides
		# Command: "ip -ignore <IP name> "
		global overrides
		foreach i $overrides {
			# skip others overrides
			if { [lindex "$i" 0] != "ip" } {
				continue;
			}
			# Compatible command have at least 4 elements in the list
			if { [llength $i] != 3 } {
				error "Wrong compatible override command string - $i"
			}
			# Check command and then IP name
			if { [string match [lindex "$i" 1] "-ignore"] } {
				if { [string match [lindex "$i" 2] "$name"] } {
					debug info "Ignoring $node"
					return $node
				}
			}
		}
	}

	debug handles "ip_type=$type"
	switch -exact $type {
		"axi_intc" {
			# Interrupt controllers
			lappend node [gen_intc $slave $intc "interrupt-controller" "C_NUM_INTR_INPUTS C_KIND_OF_INTR"]
		}
		"mdm" {
			# Microblaze debug

			# Check if uart feature is enabled
			set use_uart [get_ip_param_value $slave "C_USE_UART"]
			if { "$use_uart" == "1" } {
				set irq [check_console_irq $slave $intc]

				variable alias_node_list
				global consoleip
				if { $irq != "-1"} {
					set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "serial" [default_parameters $slave] "" "" "xlnx,xps-uartlite-1.00.a" ]
					if {[string match -nocase $name $consoleip]} {
						lappend alias_node_list [list serial0 aliasref $name 0]
						set ip_tree [tree_append $ip_tree [list "port-number" int 0]]
					} else {
						variable serial_count
						incr serial_count
						lappend alias_node_list [list serial$serial_count aliasref $name $serial_count]
						set ip_tree [tree_append $ip_tree [list "port-number" int $serial_count]]
					}
				} else {
					set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "serial" [default_parameters $slave] "" "" "xlnx,xps-uartlite-1.00.a" ]
				}
			} else {
				# Only bus connected IPs are generated
				set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "debug" [default_parameters $slave] "" "" "" ]
			}
			lappend node $ip_tree
		}
		"axi_uartlite" {
			#
			# Add this uartlite device to the alias list
			#
			check_console_irq $slave $intc

			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "serial" [default_parameters $slave] ]
			set ip_tree [tree_append $ip_tree [list "device_type" string "serial"]]

			variable alias_node_list
			global consoleip
			if {[string match -nocase $name $consoleip]} {
				lappend alias_node_list [list serial0 aliasref $name 0]
				set ip_tree [tree_append $ip_tree [list "port-number" int 0]]
			} else {
				variable serial_count
				incr serial_count
				lappend alias_node_list [list serial$serial_count aliasref $name $serial_count]
				set ip_tree [tree_append $ip_tree [list "port-number" int $serial_count]]
			}

			set ip_tree [tree_append $ip_tree [list "current-speed" int [get_ip_param_value $slave "C_BAUDRATE"]]]
			if { $type == "axi_uartlite" } {
				set ip_tree [tree_append $ip_tree [list "clock-frequency" int [get_clock_frequency $slave "S_AXI_ACLK"]]]
			}
			if { "$proctype" == "microblaze" } {
				set ip_tree [tree_append $ip_tree [list "clocks" labelref "clk_bus"]]
			}
			lappend node $ip_tree
			#"BAUDRATE DATA_BITS CLK_FREQ ODD_PARITY USE_PARITY"]
		}
		"axi_uart16550" {
			#
			# Add this uart device to the alias list
			#
			check_console_irq $slave $intc

			variable alias_node_list
			global consoleip
			if {[string match -nocase $name $consoleip]} {
				lappend alias_node_list [list serial0 aliasref $name 0]
			} else {
				variable serial_count
				incr serial_count
				lappend alias_node_list [list serial$serial_count aliasref $name $serial_count]
			}

			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "serial" [default_parameters $slave] "" "" [list "ns16550a"] ]
			set ip_tree [tree_append $ip_tree [list "device_type" string "serial"]]
			set ip_tree [tree_append $ip_tree [list "current-speed" int "115200"]]

			# The 16550 cores usually use the bus clock as the baud
			# reference, but can also take an external reference clock.
			if { $type == "axi_uart16550"} {
				set freq [get_clock_frequency $slave "S_AXI_ACLK"]
			}
			set has_xin [scan_int_parameter_value $slave "C_HAS_EXTERNAL_XIN"]
			if { $has_xin == "1" } {
				set freq [get_clock_frequency $slave "xin"]
			}
			set ip_tree [tree_append $ip_tree [list "clock-frequency" int $freq]]
			if { "$proctype" == "microblaze" } {
				set ip_tree [tree_append $ip_tree [list "clocks" labelref "clk_bus"]]
			}

			set ip_tree [tree_append $ip_tree [list "reg-shift" int "2"]]
			if { $type == "axi_uart16550"} {
				set ip_tree [tree_append $ip_tree [list "reg-offset" hexint [expr 0x1000]]]
			} else {
				set ip_tree [tree_append $ip_tree [list "reg-offset" hexint [expr 0x1003]]]
			}
			lappend node $ip_tree
			#"BAUDRATE DATA_BITS CLK_FREQ ODD_PARITY USE_PARITY"]
		}
		"ps7_uart" {
			set ip_tree [slaveip $slave $intc "serial" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,xuartps"]]

			variable alias_node_list
			global consoleip
			if {[string match -nocase $name $consoleip]} {
				lappend alias_node_list [list serial0 aliasref $name 0]
				set ip_tree [tree_append $ip_tree [list "port-number" int 0]]
			} else {
				variable serial_count
				incr serial_count
				lappend alias_node_list [list serial$serial_count aliasref $name $serial_count]
				set ip_tree [tree_append $ip_tree [list "port-number" int $serial_count]]
			}

			# MS silly use just clock-frequency which is standard
			set ip_tree [tree_append $ip_tree [list "device_type" string "serial"]]
			set ip_tree [tree_append $ip_tree [list "current-speed" int "115200"]]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"axi_timebase_wdt" {
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "" [default_parameters $slave] ]
			if { $type == "axi_timebase_wdt" } {
				set ip_tree [tree_append $ip_tree [list "clock-frequency" int [get_clock_frequency $slave "S_AXI_ACLK"]]]
			}
			if { "$proctype" == "microblaze" } {
				set ip_tree [tree_append $ip_tree [list "clocks" labelref "clk_bus"]]
			}
			lappend node $ip_tree
		}
		"axi_traffic_gen" {
			variable trafgen_count
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "" "" "" "" "" [list "err-out" "irq-out"] ]
			set ip_tree [tree_append $ip_tree [list "xlnx,device-id" int $trafgen_count]]
			incr trafgen_count
			lappend node $ip_tree
		}
		"axi_timer" {
			global timer
			if {[ string match -nocase $name $timer ]} {
				set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "system_timer" [default_parameters $slave] ]
				set one_timer_only [get_ip_param_value $slave "C_ONE_TIMER_ONLY"]
				if { $one_timer_only == "1" } {
					error "Linux requires dual channel timer, but $name is set to single channel. Please configure the $name to dual channel"
				}
				set irq [get_intr $slave $intc "Interrupt"]
				if { $irq == "-1" } {
					error "Linux requires dual channel timer with interrupt connected. Please configure the $name to interrupt"
				}
				variable microblaze_system_timer
				set microblaze_system_timer $timer
			} else {
				set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "timer" [default_parameters $slave] ]
			}

			# axi_timer runs at bus frequency. The timer driver
			# in microblaze kernel uses the 'clock-frequency' property, if there is one available; otherwise it
			# uses cpu frequency. For axi_timer, generate the 'clock-frequency' property with bus frequency as
			# it's value
			if { $type == "axi_timer"} {
				set freq [get_clock_frequency $slave "S_AXI_ACLK"]
				set ip_tree [tree_append $ip_tree [list "clock-frequency" int $freq]]
				if { "$proctype" == "microblaze" } {
					set ip_tree [tree_append $ip_tree [list "clocks" labelref "clk_bus"]]
				}
			}
			lappend node $ip_tree
		}
		"axi_sysace" {
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "sysace" [default_parameters $slave] ]
			#"MEM_WIDTH"]
			set sysace_width [get_ip_param_value $slave "C_MEM_WIDTH"]
			if { $sysace_width == "8" } {
				set ip_tree [tree_append $ip_tree [list "8-bit" empty empty]]
			} elseif { $sysace_width == "16" } {
				set ip_tree [tree_append $ip_tree [list "16-bit" empty empty]]
			} else {
				error "Unsuported Systemace memory width"
			}
			variable sysace_count
			set ip_tree [tree_append $ip_tree [list "port-number" int $sysace_count]]
			incr sysace_count
			lappend node $ip_tree
		}
		"axi_ethernetlite" {
			#
			# Add this temac channel to the alias list
			#
			variable ethernet_count
			variable alias_node_list
			lappend alias_node_list [list ethernet$ethernet_count aliasref $name $ethernet_count]
			incr ethernet_count

			# 'network' type
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "ethernet" [default_parameters $slave]]
			set ip_tree [tree_append $ip_tree [list "device_type" string "network"]]
			set ip_tree [tree_append $ip_tree [list "local-mac-address" bytesequence [list 0x00 0x0a 0x35 0x00 0x00 $mac_count]]]
			incr mac_count

			if {$type == "axi_ethernetlite"} {
				if {[parameter_exists $slave "C_INCLUDE_MDIO"]} {
					set has_mdio [scan_int_parameter_value $slave "C_INCLUDE_MDIO"]
					if {$has_mdio == 1} {
						set phy_name "phy$phy_count"
						set ip_tree [tree_append $ip_tree [list "phy-handle" labelref $phy_name]]
						set ip_tree [tree_append $ip_tree [gen_mdiotree $slave]]
					}
				}
			}

			lappend node $ip_tree
		}
		"axi_ethernet_buffer" -
		"axi_ethernet" {
			set baseaddr [scan_int_parameter_value $slave "C_BASEADDR"]
			set highaddr [expr $baseaddr + 0x3ffff]

			variable ethernet_count
			variable alias_node_list
			set alias_node [list ethernet$ethernet_count aliasref $name $ethernet_count]
			lappend alias_node_list $alias_node
			incr ethernet_count

			set ip_tree [slaveip_basic $slave $intc "" [format_ip_name "axi-ethernet" $baseaddr $name]]
			set ip_tree [tree_append $ip_tree [list "device_type" string "network"]]
			set ip_tree [tree_append $ip_tree [list "local-mac-address" bytesequence [list 0x00 0x0a 0x35 0x00 0x00 $mac_count]]]
			incr mac_count
			set phy_name "phy$phy_count"
			set ip_tree [tree_append $ip_tree [list "phy-handle" labelref $phy_name]]

			set ip_tree [tree_append $ip_tree [gen_reg_property $name $baseaddr $highaddr]]
			set ip_tree [gen_interrupt_property $ip_tree $slave $intc [format "INTERRUPT"]]
			set ip_name [lindex $ip_tree 0]
			set ip_node [lindex $ip_tree 2]
			# Generate the common parameters.
			set ip_node [gen_params $ip_node $slave [list "C_PHY_TYPE" "C_TYPE" "C_PHYADDR" "C_INCLUDE_IO" "HALFDUP"]]
			set ip_node [gen_params $ip_node $slave [list "C_TXMEM" "C_RXMEM" "C_TXCSUM" "C_RXCSUM" "C_MCAST_EXTEND" "C_STATS" "C_AVB"]]
			set ip_node [gen_params $ip_node $slave [list "C_TXVLAN_TRAN" "C_RXVLAN_TRAN" "C_TXVLAN_TAG" "C_RXVLAN_TAG" "C_TXVLAN_STRP" "C_RXVLAN_STRP"]]
			set ip_tree [list $ip_name tree $ip_node]
			# See what the axi ethernet is connected to.
			set axiethernet_busif_handle [get_intf_pins -of_objects $slave "AXI_STR_RXD"]
			set axiethernet_name [get_intf_nets -of_objects $axiethernet_busif_handle]
			if { [llength $axiethernet_name] != 0 } {
				set axiethernet_ip_handle [get_intf_pins -of_objects $axiethernet_name -filter "TYPE==TARGET"]
			} else {
				# Incorrect system.xml where there is no name for STR_RXD but there is name AXI_STR_TXD
				set axiethernet_busif_handle [get_intf_pins -of_objects $slave "AXI_STR_TXD"]
				set axiethernet_name [get_intf_nets -of_objects $axiethernet_busif_handle]
				set axiethernet_ip_handle [get_intf_pins -of_objects $axiethernet_name -filter "TYPE==INITIATOR"]
			}
			set axiethernet_ip_handle_name [get_property NAME $axiethernet_ip_handle]
			set connected_ip_handle [get_cells -of_objects $axiethernet_ip_handle]
			set connected_ip_name [get_property NAME $connected_ip_handle]
			set connected_ip_type [get_property IP_NAME $connected_ip_handle]
			set ip_tree [tree_append $ip_tree [list "axistream-connected" labelref $connected_ip_name]]
			set ip_tree [tree_append $ip_tree [list "axistream-control-connected" labelref $connected_ip_name]]

			set freq [get_clock_frequency $slave "S_AXI_ACLK"]
			set ip_tree [tree_append $ip_tree [list "clock-frequency" int $freq]]

			if { "$proctype" == "microblaze" } {
				set ip_tree [tree_append $ip_tree [list "clocks" labelref "clk_bus"]]
			}
			set ip_tree [tree_append $ip_tree [gen_mdiotree $slave]]

			lappend node $ip_tree
		}
		"axis_loopback_widget" {
			# maybe just IP just with interrupt line
			variable no_reg_id
			set tree [slaveip_basic $slave $intc [default_parameters $slave] [format_ip_name $type "$no_reg_id" $name] ""]
			set tree [gen_interrupt_property $tree $slave $intc [interrupt_list $slave]]
			lappend node $tree
			incr no_reg_id
		}
		"axi_dma" {
			set axiethernetfound 0
			variable dma_device_id
			set xdma "axi-dma"
			set tx_chan [scan_int_parameter_value $slave "C_INCLUDE_MM2S"]
			if {$tx_chan == 1} {
				set axidma_busif_handle [get_intf_pins -of_objects $slave "M_AXIS_MM2S"]
				set axidma_name [get_intf_nets -of_objects $axidma_busif_handle]
				set axidma_ip_handle [get_intf_pins -of_objects $axidma_name -filter "TYPE==TARGET"]
				set axidma_ip_handle_name [get_property NAME $axidma_ip_handle]
				set connected_ip_handle [get_cells -of_objects $axidma_ip_handle]
				set connected_ip_name [get_property NAME $connected_ip_handle]
				set connected_ip_type [get_property IP_NAME $connected_ip_handle]

				# FIXME - this need to be check because axi_ethernet contains axi dma handling in it
				if {[string compare $connected_ip_type "axi_ethernet"] == 0} {
					set axiethernetfound 1
				} elseif {[string compare $connected_ip_type "axi_ethernet_buffer"] == 0} {
					set axiethernetfound 1
				} else {
					# Axi loopback widget can be found just in this way because they are not connected to any bus
					variable periphery_array
					if {[lsearch $periphery_array $connected_ip_handle] == -1 && $connected_ip_name != $name } {
						set node [gener_slave $node $connected_ip_handle $intc]
						lappend periphery_array $connected_ip_handle
					}
				}
			}
			if {$axiethernetfound != 1} {
				set hw_name [get_property NAME $slave]

				set baseaddr [scan_int_parameter_value $slave "C_BASEADDR"]
				set highaddr [scan_int_parameter_value $slave "C_HIGHADDR"]

				set mytree [list [format_ip_name "axidma" $baseaddr $hw_name] tree {}]

				set tx_chan [scan_int_parameter_value $slave "C_INCLUDE_MM2S"]
				if {$tx_chan == 1} {
					set chantree [dma_channel_config $xdma $baseaddr "MM2S" $intc $slave $dma_device_id]
					set chantree [tree_append $chantree [list "axistream-connected" labelref $connected_ip_name]]
					set chantree [tree_append $chantree [list "axistream-control-connected" labelref $connected_ip_name]]
					set mytree [tree_append $mytree $chantree]

				}

				set rx_chan [scan_int_parameter_value $slave "C_INCLUDE_S2MM"]
				if {$rx_chan == 1} {
					# Find out initiator side
					set axidma_busif_handle [get_intf_pins -of_objects $slave "S_AXIS_S2MM"]
					set axidma_name [get_intf_nets -of_objects $axidma_busif_handle]
					set axidma_ip_handle [get_intf_pins -of_objects $axidma_name -filter "TYPE==INITIATOR"]
					set axidma_ip_handle_name [get_property NAME $axidma_ip_handle]
					set connected_ip_handle [get_cells -of_objects $axidma_ip_handle]
					set connected_ip_name [get_property NAME $connected_ip_handle]
					set connected_ip_type [get_property IP_NAME $connected_ip_handle]

					set chantree [dma_channel_config $xdma [expr $baseaddr + 0x30] "S2MM" $intc $slave $dma_device_id]
					set chantree [tree_append $chantree [list "axistream-connected-slave" labelref $connected_ip_name]]
					set chantree [tree_append $chantree [list "axistream-control-connected-slave" labelref $connected_ip_name]]
					set mytree [tree_append $mytree $chantree]
				}

				set mytree [tree_append $mytree [list \#size-cells int 1]]
				set mytree [tree_append $mytree [list \#address-cells int 1]]
				set mytree [tree_append $mytree [list compatible stringtuple [list "xlnx,axi-dma"]]]

				set stsctrl 1
				set sgdmamode1 1
				set sgdmamode [get_ip_param_value $slave "C_INCLUDE_SG"]
				if {$sgdmamode != ""} {
					set sgdmamode1 [scan_int_parameter_value $slave "C_INCLUDE_SG"]
					if {$sgdmamode1 == 0} {
						set stsctrl 0
					} else {
						set stsctrl [get_ip_param_value $slave "C_SG_INCLUDE_STSCNTRL_STRM"]
						if {$stsctrl != ""} {
							set stsctrl [scan_int_parameter_value $slave "C_SG_INCLUDE_STSCNTRL_STRM"]
						} else {
							set stsctrl 0
						}
					}
					set mytree [tree_append $mytree [list "xlnx,include-sg" empty empty]]
				} else {
					set stsctrl [get_ip_param_value $slave "C_SG_INCLUDE_STSCNTRL_STRM"]
					if {$stsctrl != ""} {
						set stsctrl [scan_int_parameter_value $slave "C_SG_INCLUDE_STSCNTRL_STRM"]
					} else {
						set stsctrl 0
					}
				}
				if {$stsctrl != "0"} {
					set mytree [tree_append $mytree [list "xlnx,sg-include-stscntrl-strm" empty empty]]
				}

				set mytree [tree_append $mytree [gen_ranges_property $slave $baseaddr $highaddr $baseaddr]]
				set mytree [tree_append $mytree [gen_reg_property $hw_name $baseaddr $highaddr]]
			}

			if {$axiethernetfound == 1} {
				if {[catch {set mytree [slaveip_intr $slave $intc [interrupt_list $slave] "" [default_parameters $slave] "" ]} {error}]} {
					debug warning $error
				}
				set mytree [tree_append $mytree [list "axistream-connected" labelref $connected_ip_name]]
				set mytree [tree_append $mytree [list "axistream-control-connected" labelref $connected_ip_name]]
			}
			lappend node $mytree
			incr dma_device_id
		}
		"axi_vdma" {
			variable vdma_device_id
			set xdma "axi-vdma"
			set hw_name [get_property NAME $slave]

			set baseaddr [scan_int_parameter_value $slave "C_BASEADDR"]
			set highaddr [scan_int_parameter_value $slave "C_HIGHADDR"]

			set mytree [list [format_ip_name "axivdma" $baseaddr $hw_name] tree {}]
			set tx_chan [scan_int_parameter_value $slave "C_INCLUDE_MM2S"]
			if {$tx_chan == 1} {
				set chantree [dma_channel_config $xdma $baseaddr "MM2S" $intc $slave $vdma_device_id]
				set mytree [tree_append $mytree $chantree]
			}

			set rx_chan [scan_int_parameter_value $slave "C_INCLUDE_S2MM"]
			if {$rx_chan == 1} {
				set chantree [dma_channel_config $xdma [expr $baseaddr + 0x30] "S2MM" $intc $slave $vdma_device_id]
				set mytree [tree_append $mytree $chantree]
			}

			set mytree [tree_append $mytree [list \#size-cells int 1]]
			set mytree [tree_append $mytree [list \#address-cells int 1]]
			set mytree [tree_append $mytree [list compatible stringtuple [list "xlnx,axi-vdma"]]]

			set tmp [get_ip_param_value $slave "C_INCLUDE_SG"]

			if {$tmp != ""} {
				set tmp [scan_int_parameter_value $slave "C_INCLUDE_SG"]
				if {$tmp == 1} {
					set mytree [tree_append $mytree [list "xlnx,include-sg" empty empty]]
				}
			} else {
				# older core always has SG
				set mytree [tree_append $mytree [list "xlnx,include-sg" empty empty]]
			}

			set tmp [scan_int_parameter_value $slave "C_NUM_FSTORES"]
			set mytree [tree_append $mytree [list "xlnx,num-fstores" hexint $tmp]]

			set tmp [scan_int_parameter_value $slave "C_FLUSH_ON_FSYNC"]
			set mytree [tree_append $mytree [list "xlnx,flush-fsync" hexint $tmp]]

			set mytree [tree_append $mytree [gen_ranges_property $slave $baseaddr $highaddr $baseaddr]]
			set mytree [tree_append $mytree [gen_reg_property $hw_name $baseaddr $highaddr]]

			lappend node $mytree
			incr vdma_device_id
		}
		"axi_cdma" {
			variable cdma_device_id
			set hw_name [get_property NAME $slave]

			set baseaddr [scan_int_parameter_value $slave "C_BASEADDR"]
			set highaddr [scan_int_parameter_value $slave "C_HIGHADDR"]

			set mytree [list [format_ip_name "axicdma" $baseaddr $hw_name] tree {}]
			set namestring "dma-channel"
			set channame [format_name [format "%s@%x" $namestring $baseaddr]]

			set chan {}
			lappend chan [list compatible stringtuple [list "xlnx,axi-cdma-channel"]]
			set tmp [scan_int_parameter_value $slave "C_INCLUDE_DRE"]
			if {$tmp == 1} {
				lappend chan [list "xlnx,include-dre" empty empty]
			}

			set tmp [scan_int_parameter_value $slave "C_USE_DATAMOVER_LITE"]
			if {$tmp == 1} {
				lappend chan [list "xlnx,lite-mode" empty empty]
			}

			set tmp [scan_int_parameter_value $slave "C_M_AXI_DATA_WIDTH"]
			lappend chan [list "xlnx,datawidth" hexint $tmp]

			set tmp [scan_int_parameter_value $slave "C_M_AXI_MAX_BURST_LEN"]
			lappend chan [list "xlnx,max-burst-len" hexint $tmp]

			lappend chan [list "xlnx,device-id" hexint $cdma_device_id]

			set chantree [list $channame tree $chan]
			set chantree [gen_interrupt_property $chantree $slave $intc [list "cdma_introut"]]

			set mytree [tree_append $mytree $chantree]

			set mytree [tree_append $mytree [list \#size-cells int 1]]
			set mytree [tree_append $mytree [list \#address-cells int 1]]
			set mytree [tree_append $mytree [list compatible stringtuple [list "xlnx,axi-cdma"]]]

			set tmp [scan_int_parameter_value $slave "C_INCLUDE_SG"]
			if {$tmp == 1} {
				set mytree [tree_append $mytree [list "xlnx,include-sg" empty empty]]
			}

			set mytree [tree_append $mytree [gen_ranges_property $slave $baseaddr $highaddr $baseaddr]]
			set mytree [tree_append $mytree [gen_reg_property $hw_name $baseaddr $highaddr]]

			lappend node $mytree
			incr cdma_device_id
		}
		"axi_tft" {
			# Get the value of the parameter which indicates about the interface
			# on which the core is connected.
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "tft" [default_parameters $slave]]
			set ip_tree [tree_append $ip_tree [list "xlnx,dcr-splb-slave-if" int "1"]]
			lappend node $ip_tree
		}
		"logi3d" -
		"logiwin" -
		"logibmp" {
			lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "" "[default_parameters $slave]" "REGS_"]
		}
		"logibayer" -
		"logicvc" {
			set params "C_VMEM_BASEADDR C_VMEM_HIGHADDR"
			lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "" "[default_parameters $slave] $params" "REGS_"]
		}
		"logibitblt" {
			set params "C_BB_BASEADDR C_BB_HIGHADDR"
			lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "" "[default_parameters $slave] $params" "REGS_"]
		}

		"axi_gpio" {
			# save gpio names and width for gpio reset code
			global gpio_names
			lappend gpio_names [list [get_property NAME $slave] [scan_int_parameter_value $slave "C_GPIO_WIDTH"]]
			# We should handle this specially, to report two ports.
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "gpio" [default_parameters $slave]]
			set ip_tree [tree_append $ip_tree [list "#gpio-cells" int "2"]]
			set ip_tree [tree_append $ip_tree [list "gpio-controller" empty empty]]
			lappend node $ip_tree
		}
		"axi_iic" {
			variable i2c_count
			variable alias_node_list
			set alias_node [list i2c$i2c_count aliasref $name $i2c_count]
			lappend alias_node_list $alias_node
			incr i2c_count

			# We should handle this specially, to report two ports.
			lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "i2c" [default_parameters $slave]]
		}
		"axi_quad_spi" -
		"axi_spi" {
			variable spi_count
			variable alias_node_list
			set alias_node [list spi$spi_count aliasref $name $spi_count]
			lappend alias_node_list $alias_node
			incr spi_count

			# We will handle SPI FLASH here
			global flash_memory flash_memory_bank
			set tree [slaveip_intr $slave $intc [interrupt_list $slave] "spi" [default_parameters $slave] "" ]

			if {[string match -nocase $flash_memory $name]} {
				# Add the address-cells and size-cells to make the DTC compiler stop outputing warning
				set tree [tree_append $tree [list "#address-cells" int "1"]]
				set tree [tree_append $tree [list "#size-cells" int "0"]]
				# If it is a SPI FLASH, we will add a SPI Flash
				# subnode to the SPI controller
				set subnode {}
				# Set the SPI Flash chip select
				lappend subnode [list "reg" hexinttuple [list $flash_memory_bank]]
				# Set the SPI Flash clock freqeuncy
				set sys_clk_handle [get_pins -of_objects $slave "S_AXI4_ACLK"]
				set sys_clk ""
				if {[llength $sys_clk_handle] != 0} {
					set sys_clk [get_clock_frequency $slave "S_AXI4_ACLK"]
				}
				if {[llength $sys_clk] == 0} {
					set sys_clk [get_clock_frequency $slave "S_AXI_ACLK"]
				}
				set sck_ratio [scan_int_parameter_value $slave "C_SCK_RATIO"]
				set sck [expr { $sys_clk / $sck_ratio }]
				lappend subnode [list [format_name "spi-max-frequency"] int $sck]
				set tree [tree_append $tree [list [format_ip_name $type $flash_memory_bank "primary_flash"] tree $subnode]]
			}
			lappend node $tree
		}
		"mailbox" {
			foreach i "S0_AXI S1_AXI" {
				set ip_busif_handle [get_intf_pins -of_objects $slave $i]
				set ip_bus_name [get_intf_nets -of_objects $ip_busif_handle]
				set bus_name [get_intf_nets -of_objects $busif_handle]
				if { $ip_bus_name == $bus_name } {
					debug ip "global bus: $bus_name/$busif_handle"
					debug ip "local bus: $ip_bus_name/$ip_busif_handle"
					lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "mailbox" [default_parameters $slave] "$i\_" ]
				}
			}
		}
		"ps7_dma" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arm,primecell arm,pl330"]]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]
			set ip_tree [tree_append $ip_tree [list "#dma-cells" int "1"]]
			set ip_tree [tree_append $ip_tree [list "#dma-channels" int "8"]]
			set ip_tree [tree_append $ip_tree [list "#dma-requests" int "4"]]

			lappend node $ip_tree
		}
		"ps7_slcr" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-slcr syscon"]]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]

			set ip_tree [tree_append $ip_tree [list "#address-cells" int "1"]]
			set ip_tree [tree_append $ip_tree [list "#size-cells" int "1"]]
			set ip_tree [tree_append $ip_tree [list ranges empty empty]]

			# PS_CLK node creation
			set subclk_tree [list "clkc: clkc@100" tree {}]
			set subclk_tree [tree_append $subclk_tree [list "#clock-cells" int "1"]]
			set subclk_tree [tree_append $subclk_tree [list "compatible" stringtuple "xlnx,ps7-clkc"]]
			set subclk_tree [tree_append $subclk_tree [list "ps-clk-frequency" int "33333333"]]
			set subclk_tree [tree_append $subclk_tree [list "fclk-enable" hexint "0xF"]]
			set subclk_tree [tree_append $subclk_tree [list "reg" hexinttuple "0x100 0x100"]]

			set subclk_tree [tree_append $subclk_tree [list "clock-output-names" stringtuple \
									[ list "armpll" "ddrpll" "iopll" "cpu_6or4x" \
									"cpu_3or2x" "cpu_2x" "cpu_1x" "ddr2x" "ddr3x" \
									"dci" "lqspi" "smc" "pcap" "gem0" "gem1" \
									"fclk0" "fclk1" "fclk2" "fclk3" "can0" "can1" \
									"sdio0" "sdio1" "uart0" "uart1" "spi0" "spi1" \
									"dma" "usb0_aper" "usb1_aper" "gem0_aper" \
									"gem1_aper" "sdio0_aper" "sdio1_aper" \
									"spi0_aper" "spi1_aper" "can0_aper" "can1_aper" \
									"i2c0_aper" "i2c1_aper" "uart0_aper" "uart1_aper" \
									"gpio_aper" "lqspi_aper" "smc_aper" "swdt" \
									"dbg_trc" "dbg_apb" \
									]]]

			set ip_tree [tree_append $ip_tree $subclk_tree]

			lappend node $ip_tree
		}
		"axi_can" -
		"can" {
			set ip_tree [slaveip_intr $slave $intc "" "" [default_parameters $slave] "" "" "xlnx,axi-can-1.00.a"]
			set ip_tree [tree_append $ip_tree [list "clock-names" stringtuple "ref_clk"]]

			if { "$proctype" == "microblaze" } {
				set ip_tree [tree_append $ip_tree [list "clocks" labelreftuple "clk_bus"]]
			} else {
				set ip_tree [tree_append $ip_tree [list "clocks" labelreftuple {"clkc 0"}]]
			}

			set irq "-1"
			if {![string match "" $intc] && ![string match -nocase "none" $intc]} {
				set intc_signals [get_intc_signals $intc]
				set index [lsearch $intc_signals "$name\_ip2bus_intrevent"]
				if {$index != -1} {
					set interrupt_list {}
					# interrupt 0 is last in list.
					set irq [expr [llength $intc_signals] - $index - 1]
					if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
						set irq_type "1"
						lappend interrupt_list 0 $irq $irq_type
					} else {
						set irq_type "0"
						lappend interrupt_list $irq $irq_type
					}

					if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
						set ip_tree [tree_append $ip_tree [list "interrupts" irqtuple3 $interrupt_list]]
					} else {
						set ip_tree [tree_append $ip_tree [list "interrupts" inttuple2 $interrupt_list]]
					}
					set intc_name [get_property NAME $intc]
					set ip_tree [tree_append $ip_tree [list "interrupt-parent" labelref $intc_name]]
				}
			}

			lappend node $ip_tree
		}
		"ps7_can" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-can-1.0"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_iop_bus_config" -
		"ps7_qspi_linear" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_" ""]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_ddrc" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-ddrc-1.0"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_dev_cfg" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-devcfg-1.0"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			# FIXME: set reg size to 0x100 because XADC is generated separately
			set baseaddr [scan_int_parameter_value $slave "C_S_AXI_BASEADDR"]
			set ip_tree [tree_node_update $ip_tree "reg" [list "reg" hexinttuple [list $baseaddr "256" ]]]

			lappend node $ip_tree
		}
		"ps7_gpio" {
			set count 32
			set ip_tree [slaveip $slave $intc "" "" "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-gpio-1.0"]]
			set ip_tree [tree_append $ip_tree [list "emio-gpio-width" int [get_ip_param_value $slave "C_EMIO_GPIO_WIDTH"]]]
			set gpiomask [get_ip_param_value $slave "C_MIO_GPIO_MASK"]
			set mask [expr {$gpiomask & 0xffffffff}]
			set ip_tree [tree_append $ip_tree [list "gpio-mask-low" hexint $mask]]
			set mask [expr {$gpiomask>>$count}]
			set mask [expr {$mask & 0xffffffff}]
			set ip_tree [tree_append $ip_tree [list "gpio-mask-high" hexint $mask]]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "#gpio-cells" int "2"]]
			set ip_tree [tree_append $ip_tree [list "gpio-controller" empty empty]]

			lappend node $ip_tree
		}
		"ps7_i2c" {
			variable i2c_count
			variable alias_node_list
			set alias_node [list i2c$i2c_count aliasref $name $i2c_count]
			lappend alias_node_list $alias_node

			set ip_tree [slaveip $slave $intc "" [default_parameters $slave "C_I2C_RESET"] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "cdns,i2c-r1p10"]]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			#set ip_tree [tree_append $ip_tree [list "i2c-clk" int 400000]]
			set ip_tree [tree_append $ip_tree [list "clock-frequency" int 400000]]
			#set ip_tree [tree_append $ip_tree [list "bus-id" int $i2c_count]]
			set ip_tree [ps7_reset_handle $ip_tree $slave "C_I2C_RESET" "i2c-reset"]

			incr i2c_count

			lappend node $ip_tree
		}
		"ps7_ttc" {
			set ip_tree [slaveip $slave $intc "" "" "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "cdns,ttc"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_scutimer" {
			# use TCL table
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arm,cortex-a9-twd-timer"]]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_qspi" {
			variable spi_count
			variable alias_node_list
			set alias_node [list spi$spi_count aliasref $name $spi_count]
			lappend alias_node_list $alias_node
			incr spi_count

			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_" ]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-qspi-1.0"]]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "num-chip-select" int 1]]
			set qspi_mode [get_ip_param_value $slave "C_QSPI_MODE"]
			if { $qspi_mode == 2} {
				set is_dual 1
			} else {
				set is_dual 0
			}
			set ip_tree [tree_append $ip_tree [list "is-dual" int $is_dual]]

			# We will handle SPI FLASH here
			global flash_memory flash_memory_bank

			if {[string match -nocase $flash_memory $name]} {
				# Add the address-cells and size-cells to make the DTC compiler stop outputing warning
				set ip_tree [tree_append $ip_tree [list "#address-cells" int "1"]]
				set ip_tree [tree_append $ip_tree [list "#size-cells" int "0"]]
				# If it is a SPI FLASH, we will add a SPI Flash
				# subnode to the SPI controller
				set subnode {}
				# Set the SPI Flash chip select
				lappend subnode [list "reg" hexinttuple [list $flash_memory_bank]]
				# Set the SPI Flash clock frequency, assume it will be
				# 1/4 of the QSPI controller frequency.
				# Note this is not the actual maximum SPI flash frequency
				# as we can't know.
				lappend subnode [list [format_name "spi-max-frequency"] int [expr [get_ip_param_value $slave "C_QSPI_CLK_FREQ_HZ"]/4]]
				set ip_tree [tree_append $ip_tree [list [format_ip_name $type $flash_memory_bank "primary_flash"] tree $subnode]]
			}

			lappend node $ip_tree
		}
		"ps7_wdt" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "xlnx,zynq-wdt-r1p2"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "device_type" string "watchdog"]]
			set ip_tree [tree_append $ip_tree [list "reset" int 0]]
			set ip_tree [tree_append $ip_tree [list "timeout-sec" int 10]]

			lappend node $ip_tree
		}
		"ps7_scuwdt" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_" ""]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "device_type" string "watchdog"]]

			lappend node $ip_tree
		}
		"ps7_usb" {
			set ip_tree [slaveip $slave $intc "" "" "S_AXI_" "xlnx,zynq-usb-1.00.a"]
			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "dr_mode" string "host"]]
			set ip_tree [tree_append $ip_tree [list "phy_type" string "ulpi"]]

			set ip_tree [ps7_reset_handle $ip_tree $slave "C_USB_RESET" "usb-reset"]

			lappend node $ip_tree
		}
		"ps7_spi" {
			variable spi_count
			variable alias_node_list
			set alias_node [list spi$spi_count aliasref $name $spi_count]
			lappend alias_node_list $alias_node
			incr spi_count

			set ip_tree [slaveip $slave $intc "" "" "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "cdns,spi-r1p6"]]

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			set ip_tree [tree_append $ip_tree [list "num-chip-select" int 4]]

			# We will handle SPI FLASH here
			global flash_memory flash_memory_bank

			if {[string match -nocase $flash_memory $name]} {
				# Add the address-cells and size-cells to make the DTC compiler stop outputing warning
				set ip_tree [tree_append $ip_tree [list "#address-cells" int "1"]]
				set ip_tree [tree_append $ip_tree [list "#size-cells" int "0"]]
				# If it is a SPI FLASH, we will add a SPI Flash
				# subnode to the SPI controller
				set subnode {}
				# Set the SPI Flash chip select
				lappend subnode [list "reg" hexinttuple [list $flash_memory_bank]]
				# Set the SPI Flash clock freqeuncy
				# hardcode this spi-max-frequency (based on board_zc770_xm010.c)
				lappend subnode [list [format_name "spi-max-frequency"] int 75000000]
				set ip_tree [tree_append $ip_tree [list [format_ip_name $type $flash_memory_bank "primary_flash"] tree $subnode]]
			}

			lappend node $ip_tree
		}
		"ps7_sdio" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arasan,sdhci-8.9a"]]
			# FIXME linux sdhci requires clock-frequency even if we use common clock framework
			set ip_tree [tree_append $ip_tree [list "clock-frequency" int [get_ip_param_value $slave "C_SDIO_CLK_FREQ_HZ"]]]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			# Be compatible with sdhci_get_of_property
			set has_cd [get_ip_param_value $slave "C_HAS_CD"]
			if { "$has_cd" == "0" } {
				    set ip_tree [tree_append $ip_tree [list "broken-cd" empty empty]]
			}
			lappend node $ip_tree
		}
		"ps7_smcc" {
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arm,pl353-smc-r2p1"]]
			# Replace xlnx prefix by arm prefix
			regsub -all "xlnx" $ip_tree "arm" ip_tree

			# use TCL table
			set ip_tree [zynq_irq $ip_tree $intc $type]
			set ip_tree [zynq_clk $ip_tree $name]

			variable ps7_smcc_list
			if {![string match "" $ps7_smcc_list]} {
				set ip_tree [tree_append $ip_tree [list "#address-cells" int "1"]]
				set ip_tree [tree_append $ip_tree [list "#size-cells" int "1"]]
				set ip_tree [tree_append $ip_tree [list ranges empty empty]]

				set ip_tree [tree_append $ip_tree $ps7_smcc_list]
			}

			lappend node $ip_tree
		}
		"ps7_nand" {
			# just C_S_AXI_BASEADDR  C_S_AXI_HIGHADDR C_NAND_CLK_FREQ_HZ C_NAND_MODE C_INTERCONNECT_S_AXI_MASTERS HW_VER INSTANCE
			set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arm,pl353-nand-r2p1"]]
			# Replace xlnx prefix by arm prefix
			regsub -all "xlnx" $ip_tree "arm" ip_tree

			# FIXME: set reg size to 16MB. This is a workaround for 14.4
			# tools provides the wrong high address of NAND
			set baseaddr [scan_int_parameter_value $slave "C_S_AXI_BASEADDR"]
			set ip_tree [tree_node_update $ip_tree "reg" [list "reg" hexinttuple [list $baseaddr "16777216" ]]]

			global flash_memory
			if {[ string match -nocase $name $flash_memory ]} {
				set ip_tree [change_nodename $ip_tree $name "primary_flash"]
			}

			variable ps7_smcc_list

			set ps7_smcc_list "$ps7_smcc_list $ip_tree"
		}
		"ps7_nor" -
		"ps7_sram" {
			# NOTE: For 14.4, the ps7_sram_* is refer to NOR flash not SRAM
			global flash_memory
			if {[ string match -nocase $name $flash_memory ]} {
				set ip_tree [slaveip $slave $intc "flash" [default_parameters $slave] "S_AXI_"]
				set ip_tree [change_nodename $ip_tree $name "primary_flash"]
			} else {
				set ip_tree [slaveip $slave $intc "" [default_parameters $slave] "S_AXI_"]
			}
			set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "cfi-flash"]]


			set ip_tree [tree_append $ip_tree [list "bank-width" int 1]]

			regsub -all "ps7_sram" $ip_tree "ps7_nor" ip_tree
			regsub -all "ps7-sram" $ip_tree "ps7-nor" ip_tree

			variable ps7_smcc_list
			set ps7_smcc_list "$ps7_smcc_list $ip_tree"
		}
		"ps7_scugic" {
			# FIXME this node should be provided by SDK and not to compose it by hand

			# Replace _ with - in type to be compatible
			regsub -all "_" $type "-" type

			# Add interrupt distributor because it is not detected
			# num_cpus, num_interrupts are here just for qemu purpose
			set tree [list "$name: $type@f8f01000" tree \
					[list \
						[list "compatible" stringtuple "arm,cortex-a9-gic arm,gic" ] \
						[list "reg" hexinttuple2 [list "0xF8F01000" "0x1000" "0xF8F00100" "0x100"] ] \
						[list "#interrupt-cells" inttuple "3" ] \
						[list "#address-cells" inttuple "2" ] \
						[list "#size-cells" inttuple "1" ] \
						[list "interrupt-controller" empty empty ] \
						[list "num_cpus" inttuple "2"] \
						[list "num_interrupts" inttuple "96" ] \
					] \
				]
			lappend node $tree

		}
		"ps7_pl310" {
			set ip_tree [list "ps7_pl310_0: ps7-pl310@f8f02000" tree \
					[list \
						[list "compatible" stringtuple "arm,pl310-cache" ] \
						[list "cache-unified" empty empty ] \
						[list "cache-level" inttuple "2" ] \
						[list "reg" hexinttuple2 [list "0xF8F02000" "0x1000"] ] \
						[list "arm,data-latency" inttuple [list "3" "2" "2"] ] \
						[list "arm,tag-latency" inttuple [list "2" "2" "2"] ] \
					] \
				]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]
			lappend node $ip_tree
		}
		"ps7_globaltimer" {
			if { [string match "$name" "$type"] } {
				set ip_tree [list "ps7_globaltimer_0: ps7-globaltimer@f8f00200" tree \
						[list \
							[list "compatible" stringtuple "arm,cortex-a9-global-timer" ] \
							[list "reg" hexinttuple2 [list "0xf8f00200" "0x100"] ] \
						] \
					]
				set name "ps7_globaltimer_0"
			} else {
				set ip_tree [slaveip $slave $intc "" "" "S_AXI_"]
				set ip_tree [tree_node_update $ip_tree "compatible" [list "compatible" stringtuple "arm,cortex-a9-global-timer"]]
			}

			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]

			lappend node $ip_tree
		}
		"ps7_xadc" {
			set ip_tree [list "ps7_xadc: ps7-xadc@f8007100" tree \
					[list \
						[list "compatible" stringtuple "xlnx,zynq-xadc-1.00.a" ] \
						[list "reg" hexinttuple [list "0xF8007100" "0x20"] ] \
					] \
				]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]
			lappend node $ip_tree
		}
		"ps7_intc_dist" -
		"ps7_l2cachec" -
		"ps7_coresight_comp" -
		"ps7_gpv" -
		"ps7_m_axi_gp" -
		"ps7_scuc" -
		"ps7_trace" -
		"ps7_ddr" {
			# Do nothing
		}
		"ps7_ethernet" {
			variable ethernet_count
			variable alias_node_list
			set alias_node [list ethernet$ethernet_count aliasref $name $ethernet_count]
			lappend alias_node_list $alias_node
			incr ethernet_count

			set ip_tree [slaveip $slave $intc "" [default_parameters $slave "C_ENET_RESET"] "S_AXI_" ""]
			set ip_tree [zynq_irq $ip_tree $intc $name]
			set ip_tree [zynq_clk $ip_tree $name]
			set ip_tree [tree_append $ip_tree [list "local-mac-address" bytesequence [list 0x00 0x0a 0x35 0x00 0x00 $mac_count]]]
			incr mac_count

			set ip_tree [tree_append $ip_tree [list "#address-cells" int "1"]]
			set ip_tree [tree_append $ip_tree [list "#size-cells" int "0"]]
			set phy_name "phy$phy_count"
			set ip_tree [tree_append $ip_tree [list "phy-handle" labelref $phy_name]]

			set mdio_tree [list "mdio" tree {}]
			set mdio_tree [tree_append $mdio_tree [list \#size-cells int 0]]
			set mdio_tree [tree_append $mdio_tree [list \#address-cells int 1]]
			set phya 7
			set phy_chip "marvell,88e1116r"
			set mdio_tree [tree_append $mdio_tree [gen_phytree $slave $phya $phy_chip]]

			set phya [is_gmii2rgmii_conv_present $slave]
			if { $phya != "-1" } {
				set phy_name "phy$phy_count"
				set ip_tree [tree_append $ip_tree [list "gmii2rgmii-phy-handle" labelref $phy_name]]
				set phy_chip "xlnx,gmii2rgmii"
				set mdio_tree [tree_append $mdio_tree [gen_phytree $slave $phya $phy_chip]]
			}
			set ip_tree [tree_append $ip_tree $mdio_tree]

			variable ps7_cortexa9_1x_clk
			set ip_tree [tree_append $ip_tree [list "xlnx,ptp-enet-clock" int $ps7_cortexa9_1x_clk]]

			set phymode [scan_int_parameter_value $slave "C_ETH_MODE"]
			if { $phymode == 0 } {
				set ip_tree [tree_append $ip_tree [list "phy-mode" string "gmii"]]
			} else {
				set ip_tree [tree_append $ip_tree [list "phy-mode" string "rgmii-id"]]
			}

			set ip_tree [ps7_reset_handle $ip_tree $slave "C_ENET_RESET" "enet-reset"]
			lappend node $ip_tree
		}
		"axi_fifo_mm_s" {
			set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "" [default_parameters $slave]]
			lappend node $ip_tree
		}
		"ps7_ocmc" -
		"ps7_ram" {
			if {"$name" == "ps7_ram_0"} {
				set ip_tree [list "ps7_ocmc_0: ps7-ocmc@f800c000" tree \
					[list \
						[list "compatible" stringtuple "xlnx,zynq-ocmc-1.0" ] \
						[list "reg" hexinttuple [list "0xf800c000" "0x1000"] ] \
					] \
				]
				# use TCL table
				set ip_tree [zynq_irq $ip_tree $intc $name]
				set ip_tree [zynq_clk $ip_tree $name]

				lappend node $ip_tree
			}
		}
		"axi_bram_ctrl" {
			lappend node [slaveip_intr $slave $intc [interrupt_list $slave] "" [default_parameters $slave] "S_AXI_" ""]
		}
		"axi_s6_ddrx" -
		"axi_v6_ddrx" -
		"axi_7series_ddrx" -
		"mig_7series" {
			# Do nothing..  this is handled by the 'memory' special case.
		}
		"axi_emc" {
			# Handle flash memories with 'banks'. Generate one flash node
			# for each bank, if necessary.  If not connected to flash,
			# then do nothing.
			set count [scan_int_parameter_value $slave "C_NUM_BANKS_MEM"]
			if { [llength $count] == 0 } {
				set count 1
			}
			for {set x 0} {$x < $count} {incr x} {

				set synch_mem [scan_int_parameter_value $slave [format "C_MEM%d_TYPE" $x]]
				# C_MEM$x_TYPE = 2 or 3 indicates the bank handles
				# a flash device and it should be listed as a
				# slave in fdt.
				# C_MEM$x_TYPE = 0, 1 or 4 indicates the bank handles
				# SRAM and it should be listed as a memory in
				# fdt.

				global main_memory main_memory_bank
				# Make sure we didn't already register this guy as the main memory.
				# see main handling in gen_memories
				if {[ string match -nocase $name $main_memory ] && $x == $main_memory_bank } {
					if { $synch_mem == 0 || $synch_mem == 1 || $synch_mem == 4 } {
						continue;
					}
				}

				set baseaddr_prefix [format "S_AXI_MEM%d_" $x]
				if { $synch_mem == 2 || $synch_mem == 3 || $synch_mem == 5} {
					set tree [slaveip_intr $slave $intc [interrupt_list $slave] "flash" [default_parameters $slave] $baseaddr_prefix "" "cfi-flash"]
				} else {
					set tree [slaveip_intr $slave $intc [interrupt_list $slave] "memory" [default_parameters $slave] $baseaddr_prefix "" ""]
				}

				# Flash needs a bank-width attribute.
				set datawidth [scan_int_parameter_value $slave [format "C_MEM%d_WIDTH" $x]]
				set tree [tree_append $tree [list "bank-width" int "[expr ($datawidth/8)]"]]

				# If it is a set as the system Flash memory, change the name of this node to PetaLinux standard system Flash emmory name
				global flash_memory flash_memory_bank
				if {[ string match -nocase $name $flash_memory ] && $x == $flash_memory_bank} {
					set tree [change_nodename $tree $name "primary_flash"]
				}
				lappend node $tree
			}
		}
		"mpmc" {
			# We should handle this specially, to report the DMA
			# ports.  This is a hack that happens to work for the
			# design I have.  Note that we don't use the default
			# parameters here because of the slew of parameters the
			# mpmc has.
			lappend node [slave_mpmc $slave $intc]
		}
		"axi_pcie" {
			# IPI ip stopped to use C_ prefix for baseaddr - that's why this detection
			set param_handle [get_ip_param_value $slave "C_BASEADDR"]
			if {$param_handle == ""} {
				set baseaddr [scan_int_parameter_value $slave "BASEADDR"]
				set highaddr [scan_int_parameter_value $slave "HIGHADDR"]
				set ip_tree [slaveip_explicit_baseaddr $slave $intc "" [default_parameters $slave] $baseaddr $highaddr ""]
			} else {
				set ip_tree [slaveip_intr $slave $intc [interrupt_list $slave] "" [default_parameters $slave] ]
			}
			set ip_tree [tree_append $ip_tree [list \#address-cells int 3]]
			set ip_tree [tree_append $ip_tree [list \#size-cells int 2]]
			# 64-bit high address.
			set high_64bit 0x00000000
			set ranges {}
			set ranges_list [axipcie_ranges $slave "C_AXIBAR_NUM" "C_AXIBAR_%d" "C_AXIBAR2PCIEBAR_%d" "C_AXIBAR_HIGHADDR_%d"]
			foreach range $ranges_list {
				set range_type [lindex $range 0]
				set axi_baseaddr [lindex $range 1]
				set child_baseaddr [lindex $range 1]
				set pcie_baseaddr [lindex $range 2]
				set axi_highaddr [lindex $range 3]
				set size [validate_ranges_property $slave $axi_baseaddr $axi_highaddr $child_baseaddr]
				lappend ranges $range_type $high_64bit $pcie_baseaddr $axi_baseaddr $high_64bit $size
			}
			set ip_tree [tree_append $ip_tree [list "ranges" hexinttuple $ranges]]
			lappend node $ip_tree
		}
		"pcie_ipif_slave" {
			# We can automatically generate the ranges property, but that's about it
			# the interrupt-map encodes board-level info that cannot be
			# derived from the MHS.
			# Default handling for all params first
			set ip_tree [slaveip_pcie_ipif_slave $slave $intc "pcie_ipif_slave" [default_parameters $slave]]

			# Standard stuff required fror the pci OF bindings
			set ip_tree [tree_append $ip_tree [list "#size-cells" int "2"]]
			set ip_tree [tree_append $ip_tree [list "#address-cells" int "3"]]
			set ip_tree [tree_append $ip_tree [list "#interrupt-cells" int "1"]]
			set ip_tree [tree_append $ip_tree [list "device_type" string "pci"]]
			# Generate ranges property.  Lots of assumptions here - 32 bit address space being the main one
			set ranges ""

			set ipifbar [ scan_int_parameter_value $slave "C_MEM1_BASEADDR" ]
			set ipif_highaddr [ scan_int_parameter_value $slave "C_MEM1_HIGHADDR" ]
			set space_code "0x02000000"

			set ranges [lappend ranges $space_code 0 $ipifbar $ipifbar 0 [ expr $ipif_highaddr - $ipifbar + 1 ]]

			set ip_tree [tree_append $ip_tree [ list "ranges" hexinttuple $ranges ]]

			# Now the interrupt-map-mask etc
			set ip_tree [tree_append $ip_tree [ list "interrupt-map-mask" hexinttuple "0xff00 0x0 0x0 0x7" ]]

			# Make sure the user knows they've still got more work to do
			# If we were prepared to add a custom PARAMETER to the MLD then we could do moer here, but for now this is
			# the best we can do
			debug warning "WARNING: Cannot automatically populate PCI interrupt-map property - this must be completed manually"
			lappend node $ip_tree
		}
		"axi2axi_connector" {
			# FIXME: multiple ranges!
			set baseaddr [scan_int_parameter_value $slave "C_S_AXI_RNG00_BASEADDR"]
			set tree [bus_bridge $slave $intc $baseaddr "M_AXI"]

			if {[llength $tree] != 0} {
				set ranges_list [default_ranges $slave "C_S_AXI_NUM_ADDR_RANGES" "C_S_AXI_RNG%02d_BASEADDR" "C_S_AXI_RNG%02d_HIGHADDR"]
				set tree [tree_append $tree [gen_ranges_property_list $slave $ranges_list]]
				lappend node $tree
			}
		}
		"microblaze" {
			debug ip "Other Microblaze CPU $name=$type"
			lappend node [gen_microblaze $slave [default_parameters $slave] $intc]
		}
		"axi_epc" {
			set tree [compound_slave $slave "C_PRH0_BASEADDR"]

			set epc_peripheral_num [get_ip_param_value $slave "C_NUM_PERIPHERALS"]
			for {set x 0} {$x < ${epc_peripheral_num}} {incr x} {
				set subnode [slaveip_intr $slave $intc [interrupt_list $slave] "" "" "PRH${x}_" ]
				set subnode [change_nodename $subnode $name "${name}_p${x}"]
				set tree [tree_append $tree $subnode]
			}
			lappend node $tree
		}
		default {
			# *Most* IP should be handled by this default case.
			# check if is any memory range
            set mem_ranges [xget_ip_mem_ranges $slave]
            lappend memory_ranges
            foreach mem_range $mem_ranges {
                set base_par_name [get_property BASE_NAME $mem_range]
                set high_par_name [get_property HIGH_NAME $mem_range]
                set baseaddr [get_property BASE_VALUE $mem_range]
                set highaddr [get_property HIGH_VALUE $mem_range]
                if { "${baseaddr}" < "${highaddr}" } {
                    lappend memory_ranges $mem_range
                    lappend range_list [list $baseaddr $highaddr $baseaddr]
                }
            }
			switch [llength $memory_ranges] {
				"0" {
					# maybe just IP just with interrupt line
					set tree [slaveip_basic $slave $intc [default_parameters $slave] [format_ip_name $type "0" $name] ""]
					set tree [gen_interrupt_property $tree $slave $intc [interrupt_list $slave]]
					lappend node $tree
				}
				"1" {
					set mem_range $memory_ranges
					set base [get_property BASE_NAME $mem_range]
					set high [get_property HIGH_NAME $mem_range]
                    set baseaddr [get_property BASE_VALUE $mem_range]
                    set highaddr [get_property HIGH_VALUE $mem_range]
					set tree [slaveip_explicit_baseaddr $slave $intc "" [default_parameters $slave] $baseaddr $highaddr ""]
					set tree [gen_interrupt_property $tree $slave $intc [interrupt_list $slave]]
					lappend node $tree
				}
				default {
					# Use the first BASEADDR parameter to be in node name - order is directed by mpd
					set tree [slaveip_basic $slave $intc [default_parameters $slave] [format_ip_name $type [lindex $ranges_list 0 0] $name] ""]
					set tree [tree_append $tree [list \#size-cells int 1]]
					set tree [tree_append $tree [list \#address-cells int 1]]
					set tree [tree_append $tree [gen_ranges_property_list $slave $ranges_list]]
					set tree [gen_interrupt_property $tree $slave $intc [interrupt_list $slave]]
					lappend node $tree
				}
			}
		}
	}
	return [dts_override $node]
}

proc memory {slave baseaddr_prefix params} {
	set name [get_property NAME $slave]
	set type [get_property IP_NAME $slave]
	set par [list_property $slave]
	set hw_ver [get_ip_version $slave]

	set ip_node {}

	set baseaddr [scan_int_parameter_value $slave [format "C_%sBASEADDR" $baseaddr_prefix]]
	set highaddr [scan_int_parameter_value $slave [format "C_%sHIGHADDR" $baseaddr_prefix]]

	lappend ip_node [gen_reg_property $name $baseaddr $highaddr]
	lappend ip_node [list "device_type" string "memory"]
	set ip_node [gen_params $ip_node $slave $params]
	return [list [format_ip_name memory $baseaddr $name] tree $ip_node]
}

proc gen_cortexa9 {tree hwproc_handle intc params buses} {
	set out ""
	variable cpunumber
	set cpus_node {}

	set lprocs [xget_cortexa9_handles]

	# add both the cortex a9 processors to the cpus node
	foreach hw_proc $lprocs {
		set cpu_name [get_property NAME $hw_proc]
		set cpu_type [get_property IP_NAME $hw_proc]
		set hw_ver [get_ip_version $hw_proc]

		set proc_node {}
		lappend proc_node [list "device_type" string "cpu"]
		lappend proc_node [list "compatible" string "arm,cortex-a9"]

		lappend proc_node [list "reg" hexint $cpunumber]
		lappend proc_node [list "bus-handle" labelreftuple $buses]
		lappend proc_node [list "interrupt-handle" labelref [get_property NAME $intc]]

		lappend proc_node [list "clocks" labelref "clkc 3"]
		if { "$cpunumber" == "0" } {
			lappend proc_node [list "operating-points" inttuple "666667 1000000 333334 1000000 222223 1000000"]
			lappend proc_node [list "clock-latency" inttuple "1000"];
		}
		set proc_node [gen_params $proc_node $hw_proc $params]
		lappend cpus_node [list [format_ip_name "cpu" $cpunumber $cpu_name] "tree" "$proc_node"]

		incr cpunumber
	}
	lappend cpus_node [list \#size-cells int 0]
	lappend cpus_node [list \#address-cells int 1]
	lappend tree [list cpus tree "$cpus_node"]

	# Add PMU node
	set ip_tree [list "pmu" tree ""]
	set ip_tree [zynq_irq $ip_tree $intc "ps7_pmu"]
	set ip_tree [tree_append $ip_tree [list "reg" hexinttuple2 [list "0xF8891000" "0x1000" "0xF8893000" "0x1000"] ] ]
	set ip_tree [tree_append $ip_tree [list "reg-names" stringtuple [list "cpu0" "cpu1"] ] ]
	set ip_tree [tree_append $ip_tree [list "compatible" stringtuple "arm,cortex-a9-pmu"]]
	lappend tree "$ip_tree"

	return $tree
}

proc xget_cortexa9_handles { } {
	set lprocs [get_cells -filter "IP_NAME==ps7_cortexa9"]
	return $lprocs
}

proc gen_microblaze {tree hwproc_handle params intc {buses ""}} {
	set out ""
	variable cpunumber

	set cpu_name [get_property NAME $hwproc_handle]
	set cpu_type [get_property IP_NAME $hwproc_handle]

	set icache_size [scan_int_parameter_value $hwproc_handle "C_CACHE_BYTE_SIZE"]
	set icache_base [scan_int_parameter_value $hwproc_handle "C_ICACHE_BASEADDR"]
	set icache_high [scan_int_parameter_value $hwproc_handle "C_ICACHE_HIGHADDR"]
	set dcache_size [scan_int_parameter_value $hwproc_handle "C_DCACHE_BYTE_SIZE"]
	set dcache_base [scan_int_parameter_value $hwproc_handle "C_DCACHE_BASEADDR"]
	set dcache_high [scan_int_parameter_value $hwproc_handle "C_DCACHE_HIGHADDR"]
	# The Microblaze parameters are in *words*, while the device tree
	# is in bytes.
	set icache_line_size [expr 4*[scan_int_parameter_value $hwproc_handle "C_ICACHE_LINE_LEN"]]
	set dcache_line_size [expr 4*[scan_int_parameter_value $hwproc_handle "C_DCACHE_LINE_LEN"]]
	set hw_ver [get_ip_version $hwproc_handle]

	set cpus_node {}
	set proc_node {}
	lappend proc_node [list "device_type" string "cpu"]
	lappend proc_node [list model string "$cpu_type,$hw_ver"]
	lappend proc_node [gen_compatible_property $cpu_type $cpu_type $hw_ver]

	# Get the clock frequency from the processor
	set clk [get_clock_frequency $hwproc_handle "CLK"]
	debug clock "Clock Frequency: $clk"
	lappend proc_node [list clock-frequency int $clk]
	lappend proc_node [list "clocks" labelref "clk_cpu"]
	lappend proc_node [list timebase-frequency int $clk]
	lappend proc_node [list reg int 0]
	if { [llength $icache_size] != 0 } {
		lappend proc_node [list i-cache-baseaddr hexint $icache_base]
		lappend proc_node [list i-cache-highaddr hexint $icache_high]
		lappend proc_node [list i-cache-size hexint $icache_size]
		lappend proc_node [list i-cache-line-size hexint $icache_line_size]
	}
	if { [llength $dcache_size] != 0 } {
		lappend proc_node [list d-cache-baseaddr hexint $dcache_base]
		lappend proc_node [list d-cache-highaddr hexint $dcache_high]
		lappend proc_node [list d-cache-size hexint $dcache_size]
		lappend proc_node [list d-cache-line-size hexint $dcache_line_size]
	}
	if {[llength $buses] != 0} {
		lappend proc_node [list "bus-handle" labelreftuple $buses]
	}
	lappend proc_node [list "interrupt-handle" labelref [get_property NAME $intc]]

	#-----------------------------
	# generating additional parameters
	# the list of Microblaze parameters
	set proc_node [gen_params $proc_node $hwproc_handle $params]

	#-----------------------------
	lappend cpus_node [list [format_ip_name "cpu" $cpunumber  $cpu_name] "tree" "$proc_node"]
	lappend cpus_node [list \#size-cells int 0]
	lappend cpus_node [list \#address-cells int 1]
	incr cpunumber
	lappend cpus_node [list \#cpus hexint "$cpunumber" ]
	lappend tree [list cpus tree "$cpus_node"]
	return $tree
}

proc get_first_mem_controller { memory_nodes } {
	foreach order "ps7_ddr axi_v6_ddrx axi_7series_ddrx axi_s6_ddrx mpmc" {
		foreach node $memory_nodes {
			if { "[lindex $node 0]" == "$order" } {
				return $node
			}
		}
	}
}

proc gen_memories {tree hwproc_handle} {
	global main_memory main_memory_bank
	global main_memory_start main_memory_size
	set ip_handles [get_cells]
	set memory_count 0
	set baseaddr [expr ${main_memory_start}]
	set memsize [expr ${main_memory_size}]
	if {$baseaddr >= 0 && $memsize > 0} {
		# Manual memory setup
		set subnode {}
		set devtype "memory"
		lappend subnode [list "device_type" string "${devtype}"]
		lappend subnode [list "reg" hexinttuple [list $baseaddr $memsize]]
		lappend tree [list [format_ip_name "${devtype}" $baseaddr "system_memory"] tree $subnode]
		incr memory_count
		return $tree
	}
	set ip_handles [get_cells]
	set memory_count 0
	set memory_nodes {}
	foreach slave $ip_handles {
		set name [get_property NAME $slave]
		set type [get_property IP_NAME $slave]

		if {![string match "" $main_memory] && ![string match -nocase "none" $main_memory]} {
			if {![string match $name $main_memory]} {
				continue;
			}
		}
		set node $type
		switch $type {
			"lmb_bram_if_cntlr" {
				if { "$name" == "microblaze_0_i_bram_ctrl" } {
					lappend node [memory $slave "" ""]
					lappend memory_nodes $node
					incr memory_count
				}
			}
			"axi_bram_ctrl" {
				# Ignore these, since they aren't big enough to be main
				# memory, and we can't currently handle non-contiguous memory
				# regions.
			}
			"mig_7series" {
				# Handle bankless memories.
				lappend node [memory $slave "" ""]
				lappend memory_nodes $node
				incr memory_count
			}
			"axi_s6_ddrx" {
				for {set x 0} {$x < 6} {incr x} {
					set baseaddr [scan_int_parameter_value $slave [format "C_S%d_AXI_BASEADDR" $x]]
					set highaddr [scan_int_parameter_value $slave [format "C_S%d_AXI_HIGHADDR" $x]]
					if {$highaddr < $baseaddr} {
						continue;
					}
					lappend node [memory $slave [format "S%d_AXI_" $x] ""]
					lappend memory_nodes $node
					break;
				}
				incr memory_count
			}
			"ps7_ddr" {
				# FIXME: this is workaround for Xilinx tools to
				# generate correct base memory address for ps7_ddr
				set subnode {}
				set baseaddr 0
				set highaddr [scan_int_parameter_value $slave "C_S_AXI_HIGHADDR"]
				set highaddr [expr $highaddr + 1]
				lappend subnode [list "device_type" string "memory"]
				lappend subnode [list "reg" hexinttuple [list $baseaddr $highaddr]]
				lappend node [list [format_ip_name "memory" $baseaddr $name] tree $subnode]
				lappend memory_nodes $node
				incr memory_count
			}
			"axi_v6_ddrx" -
			"axi_7series_ddrx" {
				lappend node [memory $slave "S_AXI_" ""]
				lappend memory_nodes $node
				incr memory_count
			}
			"axi_emc" {
				# Handle memories with 'banks'. Generate one memory
				# node for each bank.
				set count [scan_int_parameter_value $slave "C_NUM_BANKS_MEM"]
				if { [llength $count] == 0 } {
					set count 1
				}
				for {set x 0} {$x < $count} {incr x} {
					set synch_mem [scan_int_parameter_value $slave [format "C_MEM%d_TYPE" $x]]
					# C_MEM$x_TYPE = 2 or 3 indicates the bank handles
					# a flash device and it should be listed as a
					# slave in fdt.
					# C_MEM$x_TYPE = 0, 1 or 4 indicates the bank handles
					# SRAM and it should be listed as a memory in
					# fdt.
					if { $synch_mem == 2 || $synch_mem == 3 } {
						continue;
					}
					lappend node [memory $slave [format "S_AXI_MEM%d_" $x] ""]
					lappend memory_nodes $node
					incr memory_count
				}
			}
			"mpmc" {
				set share_addresses [scan_int_parameter_value $slave "C_ALL_PIMS_SHARE_ADDRESSES"]
				if {$share_addresses != 0} {
					lappend node [memory $slave "MPMC_" ""]
					lappend memory_nodes $node
				} else {
					set old_baseaddr [scan_int_parameter_value $slave [format "C_PIM0_BASEADDR" $x]]
					set old_offset [scan_int_parameter_value $slave [format "C_PIM0_OFFSET" $x]]
					set safe_addresses 1
					set num_ports [scan_int_parameter_value $slave "C_NUM_PORTS"]
					for {set x 1} {$x < $num_ports} {incr x} {
						set baseaddr [scan_int_parameter_value $slave [format "C_PIM%d_BASEADDR" $x]]
						set baseaddr [scan_int_parameter_value $slave [format "C_PIM%d_OFFSET" $x]]
						if {$baseaddr != $old_baseaddr} {
							debug warning "Warning!: mpmc is configured with different baseaddresses on different ports!  Since this is a potentially hazardous configuration, a device tree node describing the memory will not be generated."
							set safe_addresses 0
						}
						if {$offset != $old_offset} {
							debug warning "Warning!: mpmc is configured with different offsets on different ports!  Since this is a potentially hazardous configuration, a device tree node describing the memory will not be generated."
						}
					}
					if {$safe_addresses == 1} {
						lappend node [memory $slave "PIM0_" ""]
						lappend memory_nodes $node
					}
				}

				incr memory_count
			}
		}
	}
	if {$memory_count == 0} {
		error "No main memory found in design!"
	}
	if {$memory_count > 1} {
		debug warning "Warning!: More than one memory found.  Note that most platforms don't support non-contiguous memory maps!"
		debug warning "Warning!: Try to find out the main memory controller!"
		set memory_node [get_first_mem_controller $memory_nodes]
	} else {
		set memory_node [lindex $memory_nodes 0]
	}

	# Skip type because only one memory node is selected
	lappend tree [lindex $memory_node 1]

	return $tree
}

# Return 1 if the given interface of the given slave is connected to a bus.
proc bus_is_connected {slave face} {
	set busif_handle [get_intf_pins -of_objects $slave $face]
	if {[llength $busif_handle] == 0} {
		error "Bus handle $face not found!"
	}
	set bus_name [get_intf_nets -of_objects $busif_handle]

	set bus_handle [get_cells -of_objects $bus_name]

	return [llength $bus_handle]
}

# Populates a bus node with components connected to the given slave
# and adds it to the given tree
#
# tree         : Tree to populate
# slave_handle : The slave to use as a starting point, this is
# typically the root processor or a previously traversed bus bridge.
# intc_handle	: The interrupt controller associated with the
# processor. Slave will have an interrupts node relative to this
# controller.
# baseaddr     : The base address of the address range of this bus.
# face : The name of the port of the slave that is connected to the
# bus.
proc bus_bridge {slave_ip intc_handle baseaddr face {handle ""} {ps_ips ""} {force_ips ""}} {
	debug handles "+++++++++++ $slave_ip ++++++++"
    set slave [get_cells $slave_ip]
	debug handles "bus_bridge slave=$slave intc=$intc_handle baseaddr=$baseaddr face=$face \
    handle=$handle ips=\{$ps_ips\} force_ips=$force_ips"
	set busif_handle [get_intf_pins -of_objects $slave $face]
	if {[llength $handle] != 0} {
		set busif_handle $handle
	}
 	if {[llength $busif_handle] == 0} {
		debug handles "Bus handle $face not found!"
        return {}
	}
	set bus_name [get_intf_nets -of_objects $busif_handle]
	global buses
	if {[lsearch $buses $bus_name] >= 0} {
		return {}
	}
	lappend buses $bus_name
	debug ip "IP connected to bus: $bus_name"
	debug handles "bus_handle: $busif_handle"

	set bus_handle [get_cells $bus_name]

#FIXME remove compatible_list property and add simple-bus in  gen_compatible_property function
	set compatible_list {}
	if {[llength $bus_handle] == 0} {
		debug handles "Bus handle $face connected directly..."
		set slave_ifs [get_intf_pins -of_objects $bus_name -filter "TYPE==TARGET"]
		set bus_type "xlnx,compound"
		set hw_ver ""
		set devicetype $bus_type
	} else {
		debug handles "Bus handle $face connected through a bus..."
		set bus_type [get_property IP_NAME $bus_handle]
		switch $bus_type {
			"axi_crossbar" -
			"axi_interconnect" {
				set devicetype "axi"
				set compatible_list [list "simple-bus"]
			}
			"ps7_axi_interconnect" {
				set devicetype "amba"
				set compatible_list [list "simple-bus"]
			}
			default {
				set devicetype $bus_type
			}
		}
        set hw_ver [get_ip_version $bus_handle]

		set master_ifs [get_intf_pins -of_objects $bus_name -filter "TYPE==MASTER"]
		foreach if $master_ifs {
			set ip_handle [get_cells -of_objects $if]
			debug ip "-master [get_property NAME $if] [get_intf_nets -of_objects $if] [get_property NAME $ip_handle]"
			debug handles "  handle: $ip_handle"

			# Note that bus masters do not need to be traversed, so we don't
			# add them to the list of ip.
		}
		set slave_ifs [get_intf_pins -of_objects $bus_name  -filter "TYPE==SLAVE"]
	}

	set bus_ip_handles {}
	# Compose peripherals & cleaning

	foreach if $slave_ifs {
		set ip_handle [get_cells -of_objects $if]
		debug ip "-slave [get_property NAME $if] [get_intf_nets -of_objects $if] [get_property NAME $ip_handle]"
		debug handles "  handle: $ip_handle"

		# Do not generate ps7_dma type with name ps7_dma_ns
		if { "[get_property IP_NAME $ip_handle]" == "ps7_dma" &&  "[get_property NAME $ip_handle]" == "ps7_dma_ns" } {
			continue
		}

		# If its not already in the list, and its not the bridge, then
		# append it.
		if {$ip_handle != $slave} {
			if {[lsearch $bus_ip_handles $ip_handle] == -1} {
				lappend bus_ip_handles $ip_handle
			}
		}
	}

	# MS This is specific function for AXI zynq IPs - I hope it will be removed
	# soon by providing M_AXI_GP0 interface
	foreach ps_ip $ps_ips {
		debug ip "-slave [get_property NAME $ps_ip]"
		debug handles "  handle: $ps_ip"

		# Do not generate ps7_dma type with name ps7_dma_ns
		if { "[get_property IP_NAME $ps_ip]" == "ps7_dma" &&  "[get_property NAME $ps_ip]" == "ps7_dma_ns" } {
			continue
		}

		# If its not already in the list, and its not the bridge, then
		# append it.
		if {$ps_ip != $slave} {
			if {[lsearch $bus_ip_handles $ps_ip] == -1} {
				lappend bus_ip_handles $ps_ip
			} else {
				debug ip "IP $ps_ip [get_property NAME $ps_ip] is already appended - skip it"
			}
		}
	}

	# A list of all the IP that have been generated already.
	variable periphery_array

	set mdm {}
	set uartlite {}
	set fulluart {}
	set ps_smcc {}
	set sorted_ip {}
	set console_type ""

	global consoleip
	# Sort all serial IP to be nice in the alias list
	foreach ip $bus_ip_handles {
		set name [get_property NAME $ip]
		set type [get_property IP_NAME $ip]

		# Save console type for alias sorting
		if { [string match "$name" "$consoleip"] } {
			set console_type "$type"
		}

		# Add all uarts to own class
		if { [string first "uartlite" "$type"] != -1 } {
			lappend uartlite $ip
		} elseif { [string first "uart16550" "$type"] != -1 } {
			lappend fulluart $ip
		} elseif { [string first "mdm" "$type"] != -1 } {
			lappend mdm $ip
		} elseif { [string first "smcc" "$type"] != -1 } {
			lappend ps_smcc $ip
		} else {
			lappend sorted_ip $ip
		}
	}

	# This order will be in alias list
	if { [string first "uart16550" "$console_type"] != -1 } {
		set sorted_ip "$sorted_ip $fulluart $uartlite $mdm $ps_smcc"
	} else {
		set sorted_ip "$sorted_ip $uartlite $fulluart $mdm $ps_smcc"
	}

	# Start generating the node for the bus.
	set bus_node {}

	# Populate with all the slaves.
	foreach ip $sorted_ip {
        # make sure the sorted_ip list does not content force ip list
		# otherwise, same duplication of dts node will appeared.
		set found_force_ip 0
		set ip [get_cells $ip]
		foreach force_typ_ip $force_ips {
			if { [get_property IP_NAME $ip] == $force_typ_ip } {
				set found_force_ip 1
				break
			}
		}
		if { $found_force_ip == 1 } {
			continue
		}
		# If we haven't already generated this ip
		if {[lsearch $periphery_array $ip] == -1} {
			set bus_node [gener_slave $bus_node $ip $intc_handle "" $busif_handle]
			lappend periphery_array $ip
		}
	}

	# Force nodes to bus $force_ips is list of IP types
	foreach ip $force_ips {
		set bus_node [gener_slave $bus_node "" $intc_handle $ip]
	}

	set led [led_gpio]
	if { "$led" != "" } {
		lappend bus_node $led
	}

	if {[llength $bus_node] != 0} {
		lappend bus_node [list \#size-cells int 1]
		lappend bus_node [list \#address-cells int 1]
		lappend bus_node [gen_compatible_property $bus_name $bus_type $hw_ver $compatible_list]
		variable bus_count
		set baseaddr $bus_count
		incr bus_count
		return [list [format_ip_name $devicetype $baseaddr $bus_name] tree $bus_node]
	}
}

# Return the clock frequency attribute of the port of the given ip core.
proc get_clock_frequency {ip_handle portname} {
	set clk ""
	set clkhandle [get_pins -of_objects $ip_handle $portname]
	if {[string compare -nocase $clkhandle ""] != 0} {
		set clk [get_property CLK_FREQ $clkhandle ]
	}
	return $clk
}

# Return a sorted list of all the port names that we think are
proc interrupt_list {ip_handle} {
	set interrupt_ports [get_pins -of_objects $ip_handle -filter "TYPE==INTERRUPT"]
	return [lsort $interrupt_ports]
}

# Return a list of translation ranges for bridges which support
# multiple ranges with identity translation.
# ip_handle: handle to the bridge
# num_ranges_name: name of the bridge parameter which gives the number
# of active ranges.
# range_base_name_template: parameter name for the base address of
# each range, with a %d in place of the range number.
# range_high_name_template: parameter name for the high address of
# each range, with a %d in place of the range number.
proc default_ranges {ip_handle num_ranges_name range_base_name_template range_high_name_template {range_start "0"}} {
	set count [scan_int_parameter_value $ip_handle $num_ranges_name]
	if { [llength $count] == 0 } {
		set count 1
	}
	set ranges_list {}
	for {set x ${range_start}} {$x < [expr $count + ${range_start}]} {incr x} {
		set baseaddr [scan_int_parameter_value $ip_handle [format $range_base_name_template $x]]
		set highaddr [scan_int_parameter_value $ip_handle [format $range_high_name_template $x]]
		lappend ranges_list [list $baseaddr $highaddr $baseaddr]
	}
	return $ranges_list
}

proc axipcie_ranges {ip_handle num_ranges_name axi_base_name_template pcie_base_name_template axi_high_name_template} {
	set count [scan_int_parameter_value $ip_handle $num_ranges_name]
	if { [llength $count] == 0 } {
		set count 1
	}
	set ranges_list {}
	for {set x 0} {$x < $count} {incr x} {
		set range_type 0x02000000
		set axi_baseaddr [scan_int_parameter_value $ip_handle [format $axi_base_name_template $x]]
		set pcie_baseaddr [scan_int_parameter_value $ip_handle [format $pcie_base_name_template $x]]
		set axi_highaddr [scan_int_parameter_value $ip_handle [format $axi_high_name_template $x]]
		lappend ranges_list [list $range_type $axi_baseaddr $pcie_baseaddr $axi_highaddr]
	}
	return $ranges_list
}

# Return a list of all the parameter names for the given ip that
# should be reported in the device tree for generic IP. This list
# includes all the parameter names, except those that are handled
# specially, such as the instance name, baseaddr, etc.
proc default_parameters {ip_handle {dont_generate ""}} {
	set par_handles [list_property $ip_handle]
	set params {}
	foreach par $par_handles {
        set par_name [string map -nocase {CONFIG. "" } $par]
		# Ignore some parameters that are always handled specially
		switch -glob $par_name \
			$dont_generate - \
			"INSTANCE" - \
			"*BASEADDR" - \
			"*HIGHADDR" - \
			"C_SPLB*" - \
			"C_DPLB*" - \
			"C_IPLB*" - \
			"C_PLB*" - \
			"M_AXI*" - \
			"C_M_AXI*" - \
			"S_AXI_ADDR_WIDTH" - \
			"C_S_AXI_ADDR_WIDTH" - \
			"S_AXI_DATA_WIDTH" - \
			"C_S_AXI_DATA_WIDTH" - \
			"S_AXI_ACLK_FREQ_HZ" - \
			"C_S_AXI_ACLK_FREQ_HZ" - \
			"S_AXI_LITE*" - \
			"C_S_AXI_LITE*" - \
			"S_AXI_PROTOCOL" - \
			"C_S_AXI_PROTOCOL" - \
			"*INTERCONNECT_?_AXI*" - \
			"*S_AXI_ACLK_PERIOD_PS" - \
			"M*_AXIS*" - \
			"C_M*_AXIS*" - \
			"S*_AXIS*" - \
			"C_S*_AXIS*" - \
			"PRH*" - \
			"C_FAMILY" - \
			"FAMILY" - \
			"*CLK_FREQ_HZ" - \
			"*ENET_SLCR_*Mbps_DIV?" - \
			"HW_VER" { } \
			default {
				if { [ regexp {^C_.+} $par_name ] } {
					lappend params $par_name
				}
			}
	}

	return $params
}

proc parameter_exists {ip_handle name} {
	set param_handle [get_ip_param_value $ip_handle $name]
	if {$param_handle == ""} {
		return 0
	}
	return 1
}

proc scan_int_parameter_value {ip_handle name} {
    set param_handle [get_ip_param_value $ip_handle $name]

	set value $param_handle
	# tcl 8.4 doesn't handle binary literals..
	if {[string match 0b* $value]} {
		# Chop off the 0b
		set tail [string range $value 2 [expr [string length $value]-1]]
		# Pad to 32 bits, because binary scan ignores incomplete words
		set list [split $tail ""]
		for {} {[llength $list] < 32} {} {
			set list [linsert $list 0 0]
		}
		set tail [join $list ""]
		# Convert the remainder back to decimal
		binary scan [binary format "B*" $tail] "I*" value
	}
	return [expr $value]
}

# generate structure for phy.
# PARAMETER periph_type_overrides = {phy <IP_name> <phy_addr> <compatible>}
proc gen_phytree {ip phya phy_chip} {
	variable phy_count

	global overrides

	set name [get_property NAME $ip]
	set type [get_property IP_NAME $ip]

	foreach over $overrides {
		if {[lindex $over 0] == "phy"} {
			if { [get_property NAME $ip] == [lindex $over 1] } {
				set phya [lindex $over 2]
				set phy_chip [lindex $over 3]
			} else {
				debug info "PHY: Not valid PHY addr for this ip: $name/$type"
			}
		}
	}

	set phy_name [format_ip_name phy $phya "phy$phy_count"]
	set phy_tree [list $phy_name tree {}]
	set phy_tree [tree_append $phy_tree [list "reg" int $phya]]
	set phy_tree [tree_append $phy_tree [list "device_type" string "ethernet-phy"]]
	set phy_tree [tree_append $phy_tree [list "compatible" string "$phy_chip"]]

	incr phy_count
	return $phy_tree
}

proc gen_mdiotree {ip} {
	# set default to 7
	set phya 7
	set phy_chip "marvell,88e1111"
	set mdio_tree [list "mdio" tree {}]
	set mdio_tree [tree_append $mdio_tree [list \#size-cells int 0]]
	set mdio_tree [tree_append $mdio_tree [list \#address-cells int 1]]
	return [tree_append $mdio_tree [gen_phytree $ip $phya $phy_chip]]
}

proc format_name {par_name} {
	set par_name [string tolower $par_name]
	set par_name [string map -nocase {"_" "-"} $par_name]
	return $par_name
}

proc format_xilinx_name {name} {
	return "xlnx,[format_name $name]"
}

proc format_param_name {name trimprefix} {
	if {[string match [string range $name 0 [expr [string length $trimprefix] - 1]] $trimprefix]} {
		set name [string range $name [string length $trimprefix] [string length $name]]
	}

	#Added specific to HSM. HSM parameters start with CONFIG.
	set trimprefix "CONFIG."
	if {[string match [string range $name 0 [expr [string length $trimprefix] - 1]] $trimprefix]} {
		set name [string range $name [string length $trimprefix] [string length $name]]
	}

	return [format_xilinx_name $name]
}

proc format_ip_name {devicetype baseaddr {label ""}} {
	set node_name [format_name [format "%s@%x" $devicetype $baseaddr]]
	if {[string match $label ""]} {
		return $node_name
	} else {
		return [format "%s: %s" $label $node_name]
	}
}

set num_intr_inputs -1

proc gen_params {node_list handle params {trimprefix "C_"} } {
	foreach par_name $params {
		if {[catch {
			set par_value [scan_int_parameter_value $handle $par_name]
			if {[string match C_NUM_INTR_INPUTS $par_name]} {
				set num_intr_inputs $par_value
			} elseif {[string match C_KIND_OF_INTR $par_name]} {
				# Pad to 32 bits - num_intr_inputs
				if {$num_intr_inputs != -1} {
					set count 0
					set mask 0
					set par_mask 0
					while {$count < $num_intr_inputs} {
						set mask [expr {1<<$count}]
						set new_mask [expr {$mask | $par_mask}]
						set par_mask $new_mask
						incr count
					}
					set par_value_32 $par_value
					set par_value [expr {$par_value_32 & $par_mask}]
				} else {
					debug warning "Warning: num-intr-inputs not set yet, kind-of-intr will be set to zero"
					set par_value 0
				}
			}
			if { [llength $par_value] != 0 } {
				lappend node_list [list [format_param_name $par_name $trimprefix] hexint "$par_value"]
			}
		} {err}]} {
			set par_value [get_ip_param_value $handle $par_name]
			if { [llength $par_value] != 0 } {
				lappend node_list [list [format_param_name $par_name $trimprefix] string "$par_value"]
			}
		}
	}
	return $node_list
}

proc gen_compatible_property {nodename type hw_ver {other_compatibles {}} } {
	array set compatible_list [ list \
		{axi_timer} {xps_timer_1.00.a} \
		{mpmc} {mpmc_3.00.a} \
		{axi_bram_ctrl} {xps_bram_if_cntlr_1.00.a} \
		{axi_ethernetlite} {xps_ethernetlite_1.00.a} \
		{axi_gpio} {xps_gpio_1.00.a} \
		{axi_tft} {xps_tft_1.00.a} \
		{axi_iic} {xps_iic_2.00.a} \
		{axi_traffic_gen} {axi_traffic_gen} \
		{axi_intc} {xps_intc_1.00.a} \
		{axi_ethernet} {axi_ethernet_1.00.a} \
		{axi_ethernet_buffer} {axi_ethernet_1.00.a} \
		{axi_dma} {axi_dma_1.00.a} \
		{axi_spi} {xps_spi_2.00.a} \
		{axi_quad_spi} {xps_spi_2.00.a} \
		{axi_uart16550} {xps_uart16550_2.00.a} \
		{axi_uartlite} {xps_uartlite_1.00.a} \
		{axi_timebase_wdt} {xps_timebase_wdt_1.00.a} \
		{axi_can} {xps_can_1.00.a} \
		{axi_sysace} {xps_sysace_1.00.a} \
		{axi_usb2_device} {xps_usb2_device_4.00.a} \
		{axi_pcie} {axi_pcie_1.05.a} \
		{ps7_ddrc} {ps7_ddrc} \
		{ps7_can} {ps7_can} \
		{axi_perf_mon} {axi_perf_monitor} \
	]

	if {$hw_ver != ""} {
		set namewithver [format "%s_%s" $type $hw_ver]
		set clist [list [format_xilinx_name "$namewithver"]]
		regexp {([^\.]*)} $hw_ver hw_ver_wildcard
		set namewithwildcard [format "%s_%s" $type $hw_ver_wildcard]
		if { [info exists compatible_list($namewithver)] } {              # Check exact match
			set add_clist [list [format_xilinx_name "$compatible_list($namewithver)"]]
			set clist [concat $clist $add_clist]
		} elseif { [info exists compatible_list($namewithwildcard)] } {   # Check major wildcard match
			set add_clist [list [format_xilinx_name "$compatible_list($namewithwildcard)"]]
			set clist [concat $clist $add_clist]
		} elseif { [info exists compatible_list($type)] } {               # Check type wildcard match
			# Extended compatible property - for example ll_temac
			foreach single "$compatible_list($type)" {
				set add_clist [list [format_xilinx_name "$single"]]
				if { ![string match $clist $add_clist] } {
					set clist [concat $clist $add_clist]
				}
			}
		}
	} else {
		set clist [list [format_xilinx_name "$type"]]
	}
	set clist [concat $clist $other_compatibles]

	# Command: "compatible -replace/-append <IP name> <compatible list>"
	# or: "compatible <IP name> <compatible list>" where replace is used
	global overrides
	foreach i $overrides {
		# skip others overrides
		if { [lindex "$i" 0] != "compatible" } {
			continue;
		}
		# Compatible command have at least 4 elements in the list
		if { [llength $i] < 3 } {
			error "Wrong compatible override command string - $i"
		}
		# Check command and then IP name
		if { [string match [lindex "$i" 1] "-append"] } {
	                if { [string match [lindex "$i" 2] "$nodename"] } {
				# Append it to the list
				set compact [lrange "$i" 3 end]
				set clist [concat $clist $compact]
				break;
			}
		} elseif { [string match [lindex "$i" 1] "-replace"] } {
	                if { [string match [lindex "$i" 2] "$nodename"] } {
				# Replace the whole compatible property list
				set clist [lrange "$i" 3 end]
				break;
			}
		} else {
	                if { [string match [lindex "$i" 1] "$nodename"] } {
				# Replace behavior
				set clist [lrange "$i" 2 end]
				break;
			}
		}
	}

	return [list "compatible" stringtuple $clist]
}

proc validate_ranges_property {slave parent_baseaddr parent_highaddr child_baseaddr} {
	set nodename [get_property NAME $slave]
	if { ![llength $parent_baseaddr] || ![llength $parent_highaddr] } {
		error "Bad address range $nodename"
	}
	if {[string match $parent_highaddr "0x00000000"]} {
		error "Bad highaddr for $nodename"
	}
	set size [expr $parent_highaddr - $parent_baseaddr + 1]
	if { $size < 0 } {
		error "Bad highaddr for $nodename"
	}
	return $size
}

proc gen_ranges_property {slave parent_baseaddr parent_highaddr child_baseaddr} {
	set size [validate_ranges_property $slave $parent_baseaddr $parent_highaddr $child_baseaddr]
	return [list "ranges" hexinttuple [list $child_baseaddr $parent_baseaddr $size]]
}

proc gen_ranges_property_list {slave rangelist} {
	set ranges {}
	foreach range $rangelist {
		set parent_baseaddr [lindex $range 0]
		set parent_highaddr [lindex $range 1]
		set child_baseaddr [lindex $range 2]
		set size [validate_ranges_property $slave $parent_baseaddr $parent_highaddr $child_baseaddr]
		lappend ranges $child_baseaddr $parent_baseaddr $size
	}
	return [list "ranges" hexinttuple $ranges]
}

proc gen_interrupt_property {tree slave intc interrupt_port_list {irq_names {}}} {
	set intc_name [get_property NAME $intc]
	set interrupt_list {}
	foreach in $interrupt_port_list {
		set irq [get_intr $slave $intc $in]

		if {![string match $irq "-1"]} {
			set irq_type [get_intr_type $intc $slave $in]
			if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
				lappend interrupt_list 0 $irq $irq_type
			} else {
				lappend interrupt_list $irq $irq_type
			}
		}
	}
	if {[llength $interrupt_list] != 0} {
		if { "[get_property IP_NAME $intc]" == "ps7_scugic" } {
			set tree [tree_append $tree [list "interrupts" irqtuple3 $interrupt_list]]
		} else {
			set tree [tree_append $tree [list "interrupts" inttuple2 $interrupt_list]]
		}
		set tree [tree_append $tree [list "interrupt-parent" labelref $intc_name]]
		if {[llength $irq_names] != 0} {
			set tree [tree_append $tree [list "interrupt-names" stringtuple $irq_names]]
		}
	}
	return $tree
}

proc gen_reg_property {nodename baseaddr highaddr {name "reg"}} {
	if { ![llength $baseaddr] || ![llength $highaddr] } {
		error "Bad address range $nodename"
	}
	if {[string match $highaddr "0x00000000"]} {
		error "No high address for $nodename"
	}
	# Detect undefined baseaddr for MPMC CTRL
	if {[string match "0x[format %x $baseaddr]" "0xffffffff"]} {
		error "No base address for $nodename"
	}
	set size [expr $highaddr - $baseaddr + 1]
	if { [format %x $size] < 0 } {
		error "Bad highaddr for $nodename"
	}
	return [list $name hexinttuple [list $baseaddr $size]]
}

proc dts_override {root} {
	#PARAMETER periph_type_overrides = {dts <IP_name> <parameter> <value_type> <value>}
	global overrides

	foreach iptree $root {
		if {[lindex $iptree 1] != "tree"} {
			error {"tree_append called on $iptree, which is not a tree."}
		}

		set name [lindex $iptree 0]
		set name_list [split $name ":"]
		set hw_name [lindex $name_list 0]
		set node [lindex $iptree 2]

		foreach over $overrides {
			if {[lindex $over 0] == "dts"} {
				if { [llength $over] != 5 } {
					error "Wrong compatible override command string - $over"
				}

				if { $hw_name == [lindex $over 1] } {
					set over_parameter [lindex $over 2]
					set over_type [lindex $over 3]
					set over_value [lindex $over 4]
					set idx 0
					set node_found 0
					set new_node ""
					foreach list $node {
						set node_parameter [lindex $list 0]
						if { $over_parameter == $node_parameter } {
							set new_node "$over_parameter $over_type $over_value"
							set node [lreplace $node $idx $idx $new_node ]
							set node_found 1
						}
						incr idx
					}

					if { $node_found == 0 } {
						set new_node "$over_parameter $over_type $over_value"
						set node [linsert $node $idx $new_node ]
					}
				}
			}
		}
		set new_tree [list $name tree $node]
		if { [info exists new_root] } {
			lappend new_root $new_tree
		} else {
			set new_root [list $new_tree]
		}
	}

	if { [info exists new_root] } {
		return $new_root
	} else {
		return $root
	}
}

proc string_to_bool { str } {
	if {$str == "true" } {
		return 1
	} elseif { $str == "false" } {
		return 0
	} else {
		return $str
	}
}

proc write_value {file indent type value} {
	if {[catch {
		if {$type == "int"} {
			set value [string_to_bool $value]
			puts -nonewline $file "= <[format %d $value]>"
		} elseif {$type == "hexint"} {
			# Mask down to 32-bits
			set value [string_to_bool $value]
			puts -nonewline $file "= <0x[format %x [expr $value & 0xffffffff]]>"
		} elseif {$type == "empty"} {
		} elseif { [string match "irqtuple*" $type] } {
			# decode how manu ints should be inside <>
			regsub -all "irqtuple" $type "" number
			if {[llength $number] == 0} {
				set number 0
			}
			set first true
			set count 0
			puts -nonewline $file "= <"
			foreach element $value {
				if {$first != true} { puts -nonewline $file " " }
				set first false
				incr count
				if { [string match [expr $count % $number] "0"] && [expr [format %d $element] > 15] } {
					puts -nonewline $file "0x[format %x $element]"
				} else {
					puts -nonewline $file "[format %d $element]"
				}
				if { $number && [string match [expr $count % $number] "0"] && [expr [llength $value] != $count] } {
					puts -nonewline $file ">, <"
					set first true
				}
			}
			puts -nonewline $file ">"
		} elseif { [string match "inttuple*" $type] } {
			# decode how manu ints should be inside <>
			regsub -all "inttuple" $type "" number
			if {[llength $number] == 0} {
				set number 0
			}

			set first true
			set count 0
			puts -nonewline $file "= <"
			foreach element $value {
				if {$first != true} { puts -nonewline $file " " }
				set first false
				incr count
				puts -nonewline $file "[format %d $element]"
				if { $number && [string match [expr $count % $number] "0"] && [expr [llength $value] != $count] } {
					puts -nonewline $file ">, <"
					set first true
				}
			}
			puts -nonewline $file ">"
		} elseif { [string match "hexinttuple*" $type] } {
			# decode how manu ints should be inside <>
			regsub -all "hexinttuple" $type "" number
			if {[llength $number] == 0} {
				set number 0
			}

			set first true
			set count 0
			puts -nonewline $file "= <"
			foreach element $value {
				if {$first != true} { puts -nonewline $file " " }
				set first false
				incr count
				puts -nonewline $file "0x[format %x [expr $element & 0xffffffff]]"
				if { $number && [string match [expr $count % $number] "0"] && [expr [llength $value] != $count] } {
					puts -nonewline $file ">, <"
					set first true
				}
			}
			puts -nonewline $file ">"
		} elseif {$type == "bytesequence"} {
			set first true
			puts -nonewline $file "= \["
			foreach element $value {
				if {[expr $element > 255]} {
					error {"Value $element is not a byte!"}
				}
				if {$first != true} { puts -nonewline $file " " }
				puts -nonewline $file "[format %02x $element]"
				set first false
			}
			puts -nonewline $file "\]"
		} elseif {$type == "labelref"} {
			puts -nonewline $file "= <&$value>"
		} elseif {$type == "labelref-ext"} {
			set first true
			puts -nonewline $file "= <&"
			foreach element $value {
				if {$first != true} { puts -nonewline $file " " }
				puts -nonewline $file "$element"
				set first false
			}
			puts -nonewline $file ">"
		} elseif {$type == "labelreftuple"} {
			set first true
			puts -nonewline $file "= "
			foreach element $value {
				if {$first != true} { puts -nonewline $file ", " }
				puts -nonewline $file "<&$element>"
				set first false
			}
		} elseif {$type == "aliasref"} {
			puts -nonewline $file "= &$value"
		} elseif {$type == "string"} {
			puts -nonewline $file "= \"$value\""
		} elseif {$type == "stringtuple"} {
			puts -nonewline $file "= "
			set first true
			set count 0
			foreach element $value {
				if {$first != true} { puts -nonewline $file ", " }
				set first false
				incr count
				puts -nonewline $file "\"$element\""
				if { [string match [expr $count % 5] "0"] && [expr [llength $value] != $count] } {
					puts $file ","
					puts -nonewline $file "[tt [expr $indent + 1]]"
					set first true
				}
			}
		} elseif {$type == "tree"} {
			puts $file "{"
			write_tree $indent $file $value
			puts -nonewline $file "} "
		} else {
			debug info "unknown type $type"
		}
	} {error}]} {
		debug info $error
		puts -nonewline $file "= \"$value\""
	}
	puts $file ";"
}

# tree: a tree triple
# child_node: a tree triple
# returns: tree with child_node appended to the list of child nodes
proc tree_append {tree child_node} {
	if {[lindex $tree 1] != "tree"} {
		error {"tree_append called on $tree, which is not a tree."}
	}
	set name [lindex $tree 0]
	set node [lindex $tree 2]
	lappend node $child_node
	return [list $name tree $node]
}

# tree: a tree triple
# child_node_name: name of the childe node that will be updated
# new_child_node: the new child_node node
proc tree_node_update {tree child_node_name new_child_node} {
	if {[lindex $tree 1] != "tree"} {
		error {"tree_append called on $tree, which is not a tree."}
	}
	set name [lindex $tree 0]
	set node [lindex $tree 2]
	set new_node []

	foreach p [lindex $tree 2] {
		set node_name [lindex $p 0]
		if { "[string compare $node_name $child_node_name ]" == "0" } {
			lappend new_node $new_child_node
		} else {
			lappend new_node $p
		}
	}
	return [list $name tree $new_node]
}

proc write_nodes {indent file tree} {
	set tree [lsort -index 0 $tree]
	foreach node $tree {
		if { [string match [expr [llength $node] % 3]  "0"] && [expr [llength $node] > 0]} {
			set loop_count [expr [llength $node] / 3 ]
			for { set i 0} { $i < $loop_count } { incr i } {
				set name [lindex $node [expr $i * 3 ]]
				set type [lindex $node [expr $i * 3 + 1]]
				set value [lindex $node [expr $i * 3 + 2]]
				puts -nonewline $file "[tt [expr $indent + 1]]$name "
				write_value $file [expr $indent + 1] $type $value
			}
		} elseif { [string match [llength $node] "4"] && [string match [lindex $node 1] "aliasref"] } {
			set name [lindex $node 0]
			set type [lindex $node 1]
			set value [lindex $node 2]
			puts -nonewline $file "[tt [expr $indent + 1]]$name "
			write_value $file [expr $indent + 1] $type $value
		} else {
			debug info "Error_bad_tree_node length = [llength $node], $node"
		}
	}
}

proc write_tree {indent file tree} {
	set trees {}
	set nontrees {}
	foreach node $tree {
		if { [string match [lindex $node 1] "tree"]} {
			lappend trees $node
		} else {
			lappend nontrees $node
		}
	}
	write_nodes $indent $file $nontrees
	write_nodes $indent $file $trees

	puts -nonewline $file "[tt $indent]"
}

proc get_pathname_for_label {tree label {path /}} {
	foreach node $tree {
		set fullname [lindex $node 0]
		set type [lindex $node 1]
		set value [lindex $node 2]
		set nodelabel [string trim [lindex [split $fullname ":"] 0]]
		set nodename [string trim [lindex [split $fullname ":"] 1]]
		if {[string equal $label $nodelabel]} {
			return $path$nodename
		}
		if {$type == "tree"} {
			set p [get_pathname_for_label $value $label "$path$nodename/"]
			if {$p != ""} {return $p}
		}
	}
	return ""
}

# help function for debug purpose
proc debug {level string} {
	variable debug_level
	if {[lsearch $debug_level $level] != -1} {
		puts $string
	}
}

proc dma_channel_config {xdma addr mode intc slave devid} {
	set modelow [string tolower $mode]
	set namestring "dma-channel"
	set channame [format_name [format "%s@%x" $namestring $addr]]

	set chan {}
	lappend chan [list compatible stringtuple [list [format "xlnx,%s-%s-channel" $xdma $modelow]]]
	set tmp [scan_int_parameter_value $slave [format "C_INCLUDE_%s_DRE" $mode]]
	if {$tmp == 1} {
		lappend chan [list "xlnx,include-dre" empty empty]
	}

	lappend chan [list "xlnx,device-id" hexint $devid]
	set tmp [get_ip_param_value $slave [format "C_%s_AXIS_%s_TDATA_WIDTH" [string index $mode 0] $mode]]
	if {$tmp != ""} {
		set tmp [scan_int_parameter_value $slave [format "C_%s_AXIS_%s_TDATA_WIDTH" [string index $mode 0] $mode]]
		lappend chan [list "xlnx,datawidth" hexint $tmp]
	}

	set tmp [get_ip_param_value $slave [format "C_%s_AXIS_%s_DATA_WIDTH" [string index $mode 0] $mode]]
	if {$tmp != ""} {
		set tmp [scan_int_parameter_value $slave [format "C_%s_AXIS_%s_DATA_WIDTH" [string index $mode 0] $mode]]
		lappend chan [list "xlnx,datawidth" hexint $mode]
	}

	if { [string compare -nocase $xdma "axi-dma"] != 0} {
		set tmp [scan_int_parameter_value $slave [format "C_%s_GENLOCK_MODE" $mode]]
		lappend chan [list "xlnx,genlock-mode" hexint $tmp]
	}

	set chantree [list $channame tree $chan]
	set chantree [gen_interrupt_property $chantree $slave $intc [list [format "%s_introut" $modelow]]]

	return $chantree
}

proc is_gmii2rgmii_conv_present {slave} {
	set port_value 0
	set phy_addr -1
	set ipconv 0

	# No any other way how to detect this convertor
	set ips [get_cells]
	set ip_name [get_property NAME $slave]

	foreach ip $ips {
		set periph [get_property IP_NAME $ip]
		if { [string compare -nocase $periph "gmii_to_rgmii"] == 0} {
			set ipconv $ip
			break
		}
	}
	if { $ipconv != 0 }  {
		set port_value [get_pins -of_objects $ipconv "gmii_txd"]
		if { $port_value != 0 } {
			set tmp [string first "ENET0" $port_value]
			if { $tmp >= 0 } {
				if { [string compare -nocase $ip_name "ps7_ethernet_0"] == 0} {
					set phy_addr [scan_int_parameter_value $ipconv "C_PHYADDR"]
				}
			} else {
				set tmp0 [string first "ENET1" $port_value]
				if { $tmp0 >= 0 } {
					if { [string compare -nocase $ip_name "ps7_ethernet_1"] == 0} {
						set phy_addr [scan_int_parameter_value $ipconv "C_PHYADDR"]
					}
				}
			}
		}
	}
	return $phy_addr
}
