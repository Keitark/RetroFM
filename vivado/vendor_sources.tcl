# SPDX-License-Identifier: GPL-3.0-or-later
# Exact, audited source manifest for the RetroFM Yamaha vendor cores.

namespace eval retrofm_vendor {
    variable revisions [dict create \
        jt51 985a573dcfc1ff135553a39f7eae21d18ba57cbe \
        jt12 45f4854f9ab43368f5a514857299ab7dfae4e6ab \
        jt49 7f6abfd08a2af9a92dbd5b32c71ea773248a77e2]

    # JT51 cfg/files.yaml at the pinned revision, in dependency-first order.
    variable jt51_files [list \
        jt51_acc.v \
        jt51_eg.v \
        jt51_exp2lin.v \
        jt51_exprom.v \
        jt51_kon.v \
        jt51_lfo.v \
        jt51_lin2exp.v \
        jt51_mmr.v \
        jt51_mod.v \
        jt51_noise_lfsr.v \
        jt51_noise.v \
        jt51_op.v \
        jt51_pg.v \
        jt51_phinc_rom.v \
        jt51_phrom.v \
        jt51_pm.v \
        jt51_reg.v \
        jt51_sh.v \
        jt51_timers.v \
        jt51_reg_ch.v \
        jt51_csr_op.v \
        jt51.v]

    # JT49 cfg/jt49.yaml at the JT12-pinned submodule revision.  jt49_bus.v
    # is retained even though JT03 directly instantiates jt49.v.
    variable jt49_files [list \
        jt49_cen.v \
        jt49_div.v \
        jt49_eg.v \
        jt49_exp.v \
        jt49_noise.v \
        jt49.v \
        jt49_bus.v]

    # JT12 cfg/jt03.yaml plus the audited JT10 ADPCM primitives used by the
    # OPNA wrapper, excluding JT49 (listed separately above).
    variable jt03_files [list \
        jt12_acc.v \
        jt12_single_acc.v \
        jt12_eg.v \
        jt12_eg_cnt.v \
        jt12_eg_comb.v \
        jt12_eg_step.v \
        jt12_eg_pure.v \
        jt12_eg_final.v \
        jt12_eg_ctrl.v \
        jt12_exprom.v \
        jt12_kon.v \
        jt12_lfo.v \
        jt12_mmr.v \
        jt12_div.v \
        jt12_mod.v \
        jt12_op.v \
        jt12_csr.v \
        jt12_pg.v \
        jt12_pg_inc.v \
        jt12_pg_dt.v \
        jt12_pg_sum.v \
        jt12_pg_comb.v \
        jt12_pm.v \
        jt12_logsin.v \
        jt12_pcm_interpol.v \
        jt12_reg.v \
        jt12_reg_ch.v \
        jt12_sh.v \
        jt12_rst.v \
        jt12_sh_rst.v \
        jt12_sh24.v \
        jt12_sumch.v \
        jt12_timers.v \
        jt12_dout.v \
        jt10_acc.v \
        adpcm/jt10_adpcm.v \
        adpcm/jt10_adpcma_lut.v \
        adpcm/jt10_adpcm_acc.v \
        adpcm/jt10_adpcm_cnt.v \
        adpcm/jt10_adpcm_drvA.v \
        adpcm/jt10_adpcm_drvB.v \
        adpcm/jt10_adpcm_gain.v \
        adpcm/jt10_adpcm_comb.v \
        adpcm/jt10_adpcm_dbrom.v \
        adpcm/jt10_adpcm_div.v \
        adpcm/jt10_adpcm_dt.v \
        adpcm/jt10_adpcmb.v \
        adpcm/jt10_adpcmb_cnt.v \
        adpcm/jt10_adpcmb_gain.v \
        adpcm/jt10_adpcmb_interpol.v \
        adpcm/jt10_cen_burst.v \
        jt03_acc.v \
        jt12_top.v \
        jt03.v]
}

proc retrofm_vendor::read_detached_head {dependency_dir} {
    set head_path [file join $dependency_dir ".git" "HEAD"]
    if {![file exists $head_path]} {
        error "Missing detached Git HEAD: $head_path"
    }
    set handle [open $head_path r]
    set head [string trim [read $handle]]
    close $handle
    if {[string match "ref:*" $head]} {
        error "Dependency must be checked out detached at its lock revision: $dependency_dir"
    }
    return $head
}

proc retrofm_vendor::assert_dependencies {sample_dir} {
    variable revisions
    set deps_dir [file normalize [file join $sample_dir "build" "deps"]]

    foreach name [dict keys $revisions] {
        set dependency_dir [file join $deps_dir $name]
        set actual [retrofm_vendor::read_detached_head $dependency_dir]
        set expected [dict get $revisions $name]
        if {$actual ne $expected} {
            error "$name revision is $actual, expected $expected"
        }
    }

    foreach source [retrofm_vendor::source_files $sample_dir] {
        if {![file exists $source]} {
            error "Missing audited vendor source: $source"
        }
    }
}

proc retrofm_vendor::source_files {sample_dir} {
    variable jt51_files
    variable jt49_files
    variable jt03_files

    set deps_dir [file normalize [file join $sample_dir "build" "deps"]]
    set result [list]

    foreach relative $jt51_files {
        lappend result [file join $deps_dir "jt51" "hdl" $relative]
    }
    foreach relative $jt49_files {
        lappend result [file join $deps_dir "jt49" "hdl" $relative]
    }
    foreach relative $jt03_files {
        lappend result [file join $deps_dir "jt12" "hdl" $relative]
    }

    # Selected second-order signed-input sigma-delta DAC.  It is outside the
    # JT03 YAML manifest and is therefore named explicitly here.
    lappend result [file join $deps_dir "jt12" "hdl" "dac" "jt12_dac2.v"]
    return $result
}

proc retrofm_vendor::wrapper_files {sample_dir} {
    set wrapper_dir [file normalize [file join $sample_dir "rtl" "vendor"]]
    return [list \
        [file join $wrapper_dir "retrofm_jt03_output_mix.v"] \
        [file join $wrapper_dir "retrofm_async_command_fifo.v"] \
        [file join $wrapper_dir "retrofm_yamaha_command_bridge.v"] \
        [file join $wrapper_dir "retrofm_jt51_wrapper.v"] \
        [file join $wrapper_dir "retrofm_jt03_wrapper.v"] \
        [file join $wrapper_dir "retrofm_jt2608_wrapper.v"] \
        [file join $wrapper_dir "retrofm_vendor_compile_top.v"]]
}

proc retrofm_vendor::read_all {sample_dir} {
    retrofm_vendor::assert_dependencies $sample_dir
    foreach source [retrofm_vendor::source_files $sample_dir] {
        read_verilog $source
    }
    foreach source [retrofm_vendor::wrapper_files $sample_dir] {
        if {![file exists $source]} {
            error "Missing RetroFM vendor wrapper: $source"
        }
        read_verilog $source
    }
}
