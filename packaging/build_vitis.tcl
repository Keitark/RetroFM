# SPDX-License-Identifier: GPL-3.0-or-later

# Reproducible Vitis Classic/XSCT 2024.2 build for the Zynq-7000 target.
# The PowerShell entry point stages the exact firmware/miniz sources and invokes
# this script with a fresh workspace.

proc retrofm_fail {message} {
    error "RetroFM Vitis build: $message"
}

proc retrofm_find_named_files {directory filename} {
    set result {}
    foreach path [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $path]} {
            set result [concat $result [retrofm_find_named_files $path $filename]]
        } elseif {[file tail $path] eq $filename} {
            lappend result [file normalize $path]
        }
    }
    return $result
}

proc retrofm_read_defines {path} {
    set handle [open $path r]
    set contents [read $handle]
    close $handle

    set definitions [dict create]
    foreach line [split $contents "\n"] {
        if {[regexp {^[ \t]*#define[ \t]+([A-Za-z0-9_]+)[ \t]+([^ \t/]+)} \
                    $line unused name value]} {
            dict set definitions $name $value
        }
    }
    return $definitions
}

proc retrofm_normalize_value {value} {
    return [string trimright [string trim $value] "uUlL"]
}

proc retrofm_choose_macro {definitions requested pattern description} {
    if {$requested ne "AUTO"} {
        if {![dict exists $definitions $requested]} {
            retrofm_fail "requested $description macro '$requested' is absent from xparameters.h"
        }
        return $requested
    }

    set candidates {}
    dict for {name value} $definitions {
        if {[regexp $pattern $name]} {
            lappend candidates $name
        }
    }
    set candidates [lsort -unique $candidates]
    if {[llength $candidates] == 0} {
        retrofm_fail "could not find a generated RetroFM $description macro in xparameters.h"
    }

    set first_value [retrofm_normalize_value \
        [dict get $definitions [lindex $candidates 0]]]
    foreach name [lrange $candidates 1 end] {
        set value [retrofm_normalize_value [dict get $definitions $name]]
        if {$value ne $first_value} {
            retrofm_fail "ambiguous RetroFM $description macros: [join $candidates {, }]"
        }
    }

    # Multiple aliases with the same numeric value are harmless. Prefer the
    # shortest generated spelling, then lexical order, for stable output.
    set selected [lindex $candidates 0]
    foreach name [lrange $candidates 1 end] {
        if {[string length $name] < [string length $selected] ||
            ([string length $name] == [string length $selected] &&
             [string compare $name $selected] < 0)} {
            set selected $name
        }
    }
    return $selected
}

proc retrofm_select_xparameters {workspace domain_name} {
    set candidates [retrofm_find_named_files $workspace "xparameters.h"]
    set domain_candidates {}
    foreach path $candidates {
        if {[string first $domain_name $path] >= 0} {
            lappend domain_candidates $path
        }
    }
    if {[llength $domain_candidates] == 1} {
        return [lindex $domain_candidates 0]
    }
    if {[llength $domain_candidates] == 0} {
        retrofm_fail "no xparameters.h was generated for domain '$domain_name'"
    }

    set bsp_candidates {}
    foreach path $domain_candidates {
        if {[string first "bspinclude" $path] >= 0} {
            lappend bsp_candidates $path
        }
    }
    if {[llength $bsp_candidates] == 1} {
        return [lindex $bsp_candidates 0]
    }
    retrofm_fail "multiple xparameters.h files were generated for domain '$domain_name': [join $domain_candidates {, }]"
}

proc retrofm_select_fsbl {workspace} {
    set candidates [retrofm_find_named_files $workspace "fsbl.elf"]
    set boot_candidates {}
    foreach path $candidates {
        if {[string first "/boot/" [string map {\\ /} $path]] >= 0} {
            lappend boot_candidates $path
        }
    }
    if {[llength $boot_candidates] == 1} {
        return [lindex $boot_candidates 0]
    }
    if {[llength $candidates] == 1} {
        return [lindex $candidates 0]
    }
    retrofm_fail "platform generated [llength $candidates] FSBL ELF candidates"
}

proc retrofm_write_build_config {source_dir base_macro irq_macro} {
    set path [file join $source_dir "retrofm_build_config.h"]
    set handle [open $path w]
    puts $handle "#ifndef RETROFM_BUILD_CONFIG_H"
    puts $handle "#define RETROFM_BUILD_CONFIG_H"
    puts $handle "#include \"xparameters.h\""
    puts $handle "#define RETROFM_HW_BASEADDR $base_macro"
    puts $handle "#define RETROFM_IRQ_ID $irq_macro"
    puts $handle "#define RETROFM_HAS_VGZ 1"
    puts $handle "#define MINIZ_NO_ARCHIVE_APIS 1"
    puts $handle "#define MINIZ_NO_DEFLATE_APIS 1"
    puts $handle "#define MINIZ_NO_MALLOC 1"
    puts $handle "#define MINIZ_NO_STDIO 1"
    puts $handle "#define MINIZ_NO_TIME 1"
    puts $handle "#define MINIZ_NO_ZLIB_APIS 1"
    puts $handle "#endif"
    close $handle
}

proc retrofm_write_linker_script {definitions artifact_dir} {
    foreach macro {
        XPAR_PS7_DDR_0_S_AXI_BASEADDR
        XPAR_PS7_DDR_0_S_AXI_HIGHADDR
    } {
        if {![dict exists $definitions $macro]} {
            retrofm_fail "generated xparameters.h lacks $macro"
        }
    }
    set origin [retrofm_normalize_value \
        [dict get $definitions XPAR_PS7_DDR_0_S_AXI_BASEADDR]]
    set high [retrofm_normalize_value \
        [dict get $definitions XPAR_PS7_DDR_0_S_AXI_HIGHADDR]]
    set length [format "0x%X" [expr {$high - $origin + 1}]]

    set template_path [file join [file dirname [info script]] "app.ld.in"]
    set input [open $template_path r]
    set contents [read $input]
    close $input
    set contents [string map \
        [list "@DDR_ORIGIN@" $origin "@DDR_LENGTH@" $length] $contents]
    set output [open [file join $artifact_dir "retrofm_app.ld"] w]
    puts -nonewline $output $contents
    close $output
    return [list $origin $high $length]
}

if {[llength $argv] != 6} {
    retrofm_fail "usage: build_vitis.tcl XSA WORKSPACE SOURCE_DIR ARTIFACT_DIR BASE_MACRO|AUTO IRQ_MACRO|AUTO"
}

set xsa [file normalize [lindex $argv 0]]
set workspace [file normalize [lindex $argv 1]]
set source_dir [file normalize [lindex $argv 2]]
set artifact_dir [file normalize [lindex $argv 3]]
set requested_base_macro [lindex $argv 4]
set requested_irq_macro [lindex $argv 5]

if {![file isfile $xsa]} {
    retrofm_fail "XSA does not exist: $xsa"
}
if {![file isdirectory $source_dir]} {
    retrofm_fail "staged source directory does not exist: $source_dir"
}
file mkdir $workspace
file mkdir $artifact_dir

set platform_name retrofm_platform
set app_domain retrofm_app_domain
set processor ps7_cortexa9_0

setws $workspace
platform create -name $platform_name -hw $xsa
platform active $platform_name

domain create -name $app_domain -os standalone -proc $processor
domain active $app_domain
bsp setlib -name xilffs
bsp config use_lfn 1
bsp config stdin ps7_uart_1
bsp config stdout ps7_uart_1
bsp write

platform generate

set xparameters [retrofm_select_xparameters $workspace $app_domain]
set definitions [retrofm_read_defines $xparameters]
if {![dict exists $definitions FILE_SYSTEM_USE_LFN] ||
    [retrofm_normalize_value [dict get $definitions FILE_SYSTEM_USE_LFN]] ne "1"} {
    retrofm_fail "generated xilffs configuration does not define FILE_SYSTEM_USE_LFN as 1"
}
set base_macro [retrofm_choose_macro $definitions $requested_base_macro \
    {^XPAR_.*RETROFM.*_BASEADDR$} "AXI base-address"]
set irq_macro [retrofm_choose_macro $definitions $requested_irq_macro \
    {^XPAR_FABRIC_.*RETROFM.*_(INTR|VEC_ID)$} "PL interrupt"]

puts "RetroFM xparameters: $xparameters"
puts "RetroFM AXI base macro: $base_macro = [dict get $definitions $base_macro]"
puts "RetroFM IRQ macro: $irq_macro = [dict get $definitions $irq_macro]"
retrofm_write_build_config $source_dir $base_macro $irq_macro
set ddr_info [retrofm_write_linker_script $definitions $artifact_dir]

set fsbl_elf [retrofm_select_fsbl $workspace]
file copy -force $fsbl_elf [file join $artifact_dir "retrofm_fsbl.elf"]

set receipt [open [file join $artifact_dir "xparameters-selection.txt"] w]
puts $receipt "xparameters=$xparameters"
puts $receipt "base_macro=$base_macro"
puts $receipt "base_value=[dict get $definitions $base_macro]"
puts $receipt "irq_macro=$irq_macro"
puts $receipt "irq_value=[dict get $definitions $irq_macro]"
puts $receipt "file_system_use_lfn=[dict get $definitions FILE_SYSTEM_USE_LFN]"
puts $receipt "ddr_origin=[lindex $ddr_info 0]"
puts $receipt "ddr_high=[lindex $ddr_info 1]"
puts $receipt "ddr_length=[lindex $ddr_info 2]"
close $receipt

puts "RetroFM FSBL ELF: [file join $artifact_dir retrofm_fsbl.elf]"
