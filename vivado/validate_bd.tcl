set script_dir [file normalize [file dirname [info script]]]
set sample_dir [file normalize [file join $script_dir ".."]]
set repo_dir [file normalize [file join $sample_dir ".." ".."]]
set project_dir [file normalize [file join $repo_dir "build" "vivado" \
    "retrofm_bd_validation"]]

file mkdir $project_dir
create_project retrofm_bd_validation $project_dir \
    -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]

source [file join $script_dir "create_bd.tcl"]
generate_target all [get_files retrofm_system.bd]
write_bd_tcl -force [file join $project_dir "retrofm_system.generated.tcl"]
puts "RETROFM_BD_VALIDATION_OK"

