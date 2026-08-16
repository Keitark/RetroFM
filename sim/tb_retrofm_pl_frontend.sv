// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_pl_frontend;
    localparam logic [7:0] REG_ID              = 8'h00;
    localparam logic [7:0] REG_VERSION         = 8'h04;
    localparam logic [7:0] REG_CONTROL         = 8'h08;
    localparam logic [7:0] REG_COMMAND         = 8'h0c;
    localparam logic [7:0] REG_EVENT_LO        = 8'h10;
    localparam logic [7:0] REG_EVENT_HI        = 8'h14;
    localparam logic [7:0] REG_EVENT_STATUS    = 8'h18;
    localparam logic [7:0] REG_EVENT_WATERMARK = 8'h1c;
    localparam logic [7:0] REG_PCM_FRAME       = 8'h20;
    localparam logic [7:0] REG_PCM_STATUS      = 8'h24;
    localparam logic [7:0] REG_VOLUME          = 8'h28;
    localparam logic [7:0] REG_KEY_MASKS       = 8'h30;
    localparam logic [7:0] REG_LATE_COUNT      = 8'h38;
    localparam logic [7:0] REG_IRQ_STATUS      = 8'h4c;
    localparam logic [7:0] REG_SPECTRUM_0      = 8'h50;
    localparam logic [7:0] REG_SPECTRUM_7      = 8'h6c;
    localparam logic [7:0] REG_JT03_METER_LO   = 8'h70;
    localparam logic [7:0] REG_JT03_METER_HI   = 8'h74;
    localparam logic [7:0] REG_OPNA_SAMPLE_ADDR = 8'h78;
    localparam logic [7:0] REG_OPNA_SAMPLE_DATA = 8'h7c;
    localparam logic [7:0] REG_OPNA_METER_0      = 8'h80;
    localparam logic [7:0] REG_OPNA_METER_1      = 8'h84;
    localparam logic [7:0] REG_OPNA_METER_2      = 8'h88;
    localparam logic [7:0] REG_OPNA_METER_FLAGS  = 8'h8c;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    always #5 clk = ~clk;

    integer failures = 0;
    integer test_stage = 0;

    initial begin
        #200000;
        $fatal(1, "RETROFM FRONTEND SELF-TEST TIMEOUT at stage %0d", test_stage);
    end

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    logic [7:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [7:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    logic [13:0] key_masks;
    logic [47:0] jt03_meter_volume;
    logic [5:0] jt03_meter_trigger;
    logic jt03_meter_trigger_clear;
    logic [87:0] opna_meter_volume;
    logic [10:0] opna_meter_trigger;
    logic opna_meter_trigger_clear;
    logic [15:0] peak_left;
    logic [15:0] peak_right;
    logic [4:0]  buttons;
    logic command_cdc_fault;
    logic command_backpressure_seen;
    logic [255:0] spectrum_bins;
    logic jt51_ready;
    logic jt03_ready;
    logic pcm_pop;
    logic pcm_valid;
    logic [31:0] pcm_frame;
    logic jt51_wr;
    logic [7:0] jt51_reg;
    logic [7:0] jt51_data;
    logic jt03_wr;
    logic jt03_port;
    logic [7:0] jt03_reg;
    logic [7:0] jt03_data;
    logic end_pulse;
    logic diagnostic_pulse;
    logic mute_pulse;
    logic unmute_pulse;
    logic core_reset_pulse;
    logic event_flush_pulse;
    logic pcm_flush_pulse;
    logic clear_faults_pulse;
    logic command_cdc_fault_clear_pulse;
    logic [15:0] volume_q15;
    logic [31:0] ym2203_clock_hz;
    logic opna_sample_write;
    logic [16:0] opna_sample_write_addr;
    logic [31:0] opna_sample_write_data;
    logic [3:0] opna_sample_write_strb;
    logic [1:0] active_chip;
    logic pcm_enable;
    logic fm_mute_enable;
    logic [31:0] lcd_aux;
    logic irq;
    logic [12:0] event_level;
    logic [12:0] pcm_level;
    logic event_prefetch_valid;
    logic scheduler_pending;
    logic scheduler_halted;
    logic scheduler_underrun_active;
    logic [31:0] late_count;
    logic [31:0] underrun_count;
    logic [63:0] playback_cycles;

    integer jt51_write_count;
    integer jt03_write_count;
    integer jt51_issue_time;
    integer jt03_issue_time;
    integer mute_count;
    integer unmute_count;
    integer reset_count;
    integer cdc_clear_count;
    integer meter_clear_count;
    integer opna_meter_clear_count;
    integer diagnostic_count;
    integer end_count;
    integer opna_write_count;
    logic [16:0] opna_write_addr_seen;
    logic [31:0] opna_write_data_seen;
    logic [3:0] opna_write_strb_seen;
    logic [7:0] jt51_regs_seen [0:15];

    retrofm_pl_frontend #(
        .AXI_ADDR_WIDTH(8),
        .EVENT_FIFO_DEPTH(4),
        .PCM_FIFO_DEPTH(4)
    ) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .key_masks(key_masks),
        .jt03_meter_volume(jt03_meter_volume),
        .jt03_meter_trigger(jt03_meter_trigger),
        .jt03_meter_trigger_clear(jt03_meter_trigger_clear),
        .opna_meter_volume(opna_meter_volume),
        .opna_meter_trigger(opna_meter_trigger),
        .opna_meter_trigger_clear(opna_meter_trigger_clear),
        .peak_left(peak_left),
        .peak_right(peak_right), .buttons(buttons),
        .command_cdc_fault(command_cdc_fault),
        .command_backpressure_seen(command_backpressure_seen),
        .spectrum_bins(spectrum_bins),
        .jt51_ready(jt51_ready), .jt03_ready(jt03_ready),
        .pcm_pop(pcm_pop), .pcm_valid(pcm_valid), .pcm_frame(pcm_frame),
        .jt51_wr(jt51_wr), .jt51_reg(jt51_reg), .jt51_data(jt51_data),
        .jt03_wr(jt03_wr), .jt03_port(jt03_port),
        .jt03_reg(jt03_reg), .jt03_data(jt03_data),
        .end_pulse(end_pulse), .diagnostic_pulse(diagnostic_pulse),
        .mute_pulse(mute_pulse), .unmute_pulse(unmute_pulse),
        .core_reset_pulse(core_reset_pulse),
        .event_flush_pulse(event_flush_pulse),
        .pcm_flush_pulse(pcm_flush_pulse),
        .clear_faults_pulse(clear_faults_pulse),
        .command_cdc_fault_clear_pulse(command_cdc_fault_clear_pulse),
        .volume_q15(volume_q15), .ym2203_clock_hz(ym2203_clock_hz),
        .opna_sample_write(opna_sample_write),
        .opna_sample_write_addr(opna_sample_write_addr),
        .opna_sample_write_data(opna_sample_write_data),
        .opna_sample_write_strb(opna_sample_write_strb),
        .active_chip(active_chip), .pcm_enable(pcm_enable),
        .fm_mute_enable(fm_mute_enable),
        .lcd_aux(lcd_aux), .irq(irq),
        .event_level(event_level), .pcm_level(pcm_level),
        .event_prefetch_valid(event_prefetch_valid),
        .scheduler_pending(scheduler_pending),
        .scheduler_halted(scheduler_halted),
        .scheduler_underrun_active(scheduler_underrun_active),
        .late_count(late_count), .underrun_count(underrun_count),
        .playback_cycles(playback_cycles)
    );

    function automatic logic [31:0] event_hi(
        input logic [3:0] opcode,
        input logic [7:0] reg_address,
        input logic [7:0] write_value
    );
        begin
            event_hi = 32'h00000000;
            event_hi[7:0]   = reg_address;
            event_hi[15:8]  = write_value;
            event_hi[19:16] = opcode;
        end
    endfunction

    task automatic axi_write(
        input logic [7:0] address,
        input logic [31:0] value,
        input logic [3:0] strobes,
        output logic [1:0] response
    );
        logic aw_done;
        logic w_done;
        integer guard;
        begin
            aw_done = 1'b0;
            w_done = 1'b0;
            guard = 0;
            @(negedge clk);
            awaddr = address;
            awvalid = 1'b1;
            wdata = value;
            wstrb = strobes;
            wvalid = 1'b1;

            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (awvalid && awready)
                    aw_done = 1'b1;
                if (wvalid && wready)
                    w_done = 1'b1;
                guard = guard + 1;
                if (guard > 40)
                    $fatal(1, "AXI write address/data handshake timeout");
                @(negedge clk);
                if (aw_done)
                    awvalid = 1'b0;
                if (w_done)
                    wvalid = 1'b0;
            end

            guard = 0;
            while (!bvalid) begin
                @(posedge clk); #1;
                guard = guard + 1;
                if (guard > 40)
                    $fatal(1, "AXI write response timeout");
            end
            response = bresp;
            @(negedge clk);
            bready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [7:0] address,
        output logic [31:0] value,
        output logic [1:0] response
    );
        integer guard;
        begin
            guard = 0;
            @(negedge clk);
            araddr = address;
            arvalid = 1'b1;
            while (!(arvalid && arready)) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 40)
                    $fatal(1, "AXI read address handshake timeout");
            end
            @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;

            guard = 0;
            while (!rvalid) begin
                @(posedge clk); #1;
                guard = guard + 1;
                if (guard > 40)
                    $fatal(1, "AXI read response timeout");
            end
            value = rdata;
            response = rresp;
            @(negedge clk);
            rready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task automatic enqueue_event(
        input logic [31:0] delta,
        input logic [3:0] opcode,
        input logic [7:0] reg_address,
        input logic [7:0] write_value
    );
        logic [1:0] response;
        begin
            axi_write(REG_EVENT_LO, delta, 4'hf, response);
            check(response == 2'b00, "EVENT_LO write returns OKAY");
            axi_write(REG_EVENT_HI,
                      event_hi(opcode, reg_address, write_value),
                      4'hf, response);
            check(response == 2'b00, "EVENT_HI atomic commit returns OKAY");
        end
    endtask

    task automatic pop_pcm_check(input logic [31:0] expected);
        begin
            @(negedge clk);
            pcm_pop = 1'b1;
            @(posedge clk); #1;
            check(pcm_valid, "PCM FIFO pop produces rd_valid");
            check(pcm_frame == expected, "PCM FIFO preserves wrapped ordering");
            @(negedge clk);
            pcm_pop = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (jt51_wr) begin
            jt51_regs_seen[jt51_write_count] = jt51_reg;
            jt51_write_count = jt51_write_count + 1;
            jt51_issue_time = playback_cycles;
        end
        if (jt03_wr) begin
            jt03_write_count = jt03_write_count + 1;
            jt03_issue_time = playback_cycles;
        end
        if (mute_pulse)
            mute_count = mute_count + 1;
        if (unmute_pulse)
            unmute_count = unmute_count + 1;
        if (core_reset_pulse)
            reset_count = reset_count + 1;
        if (command_cdc_fault_clear_pulse)
            cdc_clear_count = cdc_clear_count + 1;
        if (jt03_meter_trigger_clear)
            meter_clear_count = meter_clear_count + 1;
        if (opna_meter_trigger_clear)
            opna_meter_clear_count = opna_meter_clear_count + 1;
        if (diagnostic_pulse)
            diagnostic_count = diagnostic_count + 1;
        if (end_pulse)
            end_count = end_count + 1;
        if (opna_sample_write) begin
            opna_write_count = opna_write_count + 1;
            opna_write_addr_seen = opna_sample_write_addr;
            opna_write_data_seen = opna_sample_write_data;
            opna_write_strb_seen = opna_sample_write_strb;
        end
    end

    logic [31:0] read_value;
    logic [1:0] response;
    integer timeout_guard;
    integer jt51_baseline;
    integer diagnostic_baseline;
    logic [63:0] stalled_time;

    initial begin
        awaddr = '0;
        awprot = '0;
        awvalid = 1'b0;
        wdata = '0;
        wstrb = '0;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = '0;
        arprot = '0;
        arvalid = 1'b0;
        rready = 1'b0;
        key_masks = 14'h3321;
        jt03_meter_volume = 48'h665544332211;
        jt03_meter_trigger = 6'b101101;
        opna_meter_volume = 88'h0b0a090807060504030201;
        opna_meter_trigger = 11'b10101010101;
        peak_left = 16'h0123;
        peak_right = 16'h4567;
        buttons = 5'b10101;
        command_cdc_fault = 1'b0;
        command_backpressure_seen = 1'b0;
        spectrum_bins = 256'hffeeddccbbaa998877665544332211008877665544332211ffeeddccbbaa9988;
        jt51_ready = 1'b1;
        jt03_ready = 1'b1;
        pcm_pop = 1'b0;
        jt51_write_count = 0;
        jt03_write_count = 0;
        jt51_issue_time = 0;
        jt03_issue_time = 0;
        mute_count = 0;
        unmute_count = 0;
        reset_count = 0;
        cdc_clear_count = 0;
        meter_clear_count = 0;
        opna_meter_clear_count = 0;
        diagnostic_count = 0;
        end_count = 0;
        opna_write_count = 0;
        opna_write_addr_seen = '0;
        opna_write_data_seen = '0;
        opna_write_strb_seen = '0;

        repeat (6) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        test_stage = 1;
        axi_read(REG_ID, read_value, response);
        check(response == 2'b00 && read_value == 32'h52464d31,
              "AXI reads the RFM1 peripheral ID");
        axi_read(REG_VERSION, read_value, response);
        check(response == 2'b00 && read_value == 32'h00010002,
              "AXI reads ABI version 1.2");
        axi_read(REG_KEY_MASKS, read_value, response);
        check(response == 2'b00 && read_value == 32'h00003321,
              "KEY_MASKS exposes JT51 plus all six JT03 channels");
        axi_read(REG_JT03_METER_LO, read_value, response);
        check(response == 2'b00 && read_value == 32'h44332211,
              "JT03 meter low word exposes FM1-FM3 and SSG1 volume");
        axi_read(REG_JT03_METER_HI, read_value, response);
        check(response == 2'b00 && read_value == 32'h002d6655,
              "JT03 meter high word exposes SSG2-SSG3 and trigger mask");
        check(meter_clear_count == 1,
              "JT03 high-word read emits one trigger-clear pulse");
        axi_read(REG_OPNA_METER_0, read_value, response);
        check(response == 2'b00 && read_value == 32'h04030201,
              "OPNA meter word 0 exposes FM1-FM4 levels");
        axi_read(REG_OPNA_METER_1, read_value, response);
        check(response == 2'b00 && read_value == 32'h08070605,
              "OPNA meter word 1 exposes FM5-FM6 and SSG1-SSG2 levels");
        axi_read(REG_OPNA_METER_2, read_value, response);
        check(response == 2'b00 && read_value == 32'h000b0a09,
              "OPNA meter word 2 exposes SSG3, rhythm, and ADPCM-B levels");
        axi_read(REG_OPNA_METER_FLAGS, read_value, response);
        check(response == 2'b00 && read_value == 32'h00000555,
              "OPNA meter flags retain eleven lane triggers");
        check(opna_meter_clear_count == 1,
              "OPNA meter-flags read emits one trigger-clear pulse");
        axi_read(8'h90, read_value, response);
        check(response == 2'b10, "unmapped AXI read returns SLVERR");

        axi_write(REG_VOLUME, 32'h12345678, 4'b0011, response);
        check(response == 2'b00, "partial volume write returns OKAY");
        axi_read(REG_VOLUME, read_value, response);
        check(read_value == 32'h00005678 && volume_q15 == 16'h5678,
              "WSTRB updates only selected register bytes");

        axi_write(REG_OPNA_SAMPLE_ADDR, 32'h00001234, 4'hf, response);
        check(response == 2'b00, "OPNA sample-address write returns OKAY");
        axi_read(REG_OPNA_SAMPLE_ADDR, read_value, response);
        check(read_value == 32'h00001234,
              "OPNA sample-address register reads its byte address");
        axi_write(REG_OPNA_SAMPLE_DATA, 32'h44332211, 4'b1011, response);
        repeat (2) @(posedge clk);
        check(opna_write_count == 1 && opna_write_addr_seen == 17'h01234 &&
              opna_write_data_seen == 32'h44332211 &&
              opna_write_strb_seen == 4'b1011,
              "OPNA sample-data write emits one word-store transaction");
        axi_read(REG_OPNA_SAMPLE_ADDR, read_value, response);
        check(read_value == 32'h00001238,
              "OPNA sample-data write advances by one aligned word");

        // Normal bridge ready/valid backpressure is useful diagnostic history
        // but does not mean that a command was dropped and must not raise the
        // fatal command/CDC IRQ.
        command_backpressure_seen = 1'b1;
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[23] && !read_value[21],
              "EVENT_STATUS[23] exposes nonfatal command backpressure");
        axi_read(REG_IRQ_STATUS, read_value, response);
        check(!read_value[6],
              "normal command backpressure does not set fault IRQ status");
        axi_write(REG_CONTROL, 32'h00000200, 4'hf, response);
        #1;
        check(!irq, "normal command backpressure is nonfatal");
        command_backpressure_seen = 1'b0;

        // An actual outer command-queue overflow/drop occupies reserved fatal
        // status bits.  It remains level-visible until the top consumes the
        // dedicated W1C pulse and clears its sticky latch.
        command_cdc_fault = 1'b1;
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[21],
              "EVENT_STATUS[21] exposes the command/CDC fault sticky");
        axi_read(REG_IRQ_STATUS, read_value, response);
        check(read_value[6],
              "IRQ_STATUS[6] exposes the command/CDC fault sticky");
        #1;
        check(irq, "fault IRQ enable includes command/CDC fault bit 6");
        axi_write(REG_IRQ_STATUS, 32'h00000040, 4'hf, response);
        check(cdc_clear_count == 1,
              "IRQ_STATUS[6] W1C emits one dedicated top-level clear pulse");
        command_cdc_fault = 1'b0;
        repeat (2) @(posedge clk);
        axi_read(REG_IRQ_STATUS, read_value, response);
        check(!read_value[6] && !irq,
              "cleared top-owned CDC fault removes status and fault IRQ");
        axi_write(REG_CONTROL, 32'h00000000, 4'hf, response);
        axi_read(REG_SPECTRUM_0, read_value, response);
        check(response == 2'b00 && read_value == 32'hbbaa9988,
              "SPECTRUM_0 exposes packed bins 0 through 3");
        axi_read(REG_SPECTRUM_7, read_value, response);
        check(response == 2'b00 && read_value == 32'hffeeddcc,
              "SPECTRUM_7 exposes packed bins 28 through 31");

        test_stage = 2;
        // EVENT_LO alone must not create an entry.  EVENT_HI atomically
        // commits the staged 64-bit value.
        axi_write(REG_EVENT_LO, 32'd0, 4'hf, response);
        repeat (4) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 0 && read_value[16],
              "EVENT_LO does not enqueue before EVENT_HI");
        axi_write(REG_EVENT_HI, event_hi(4'h0, 8'hee, 8'hee), 4'h0, response);
        repeat (3) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 0,
              "zero-WSTRB EVENT_HI transaction does not commit an event");
        axi_write(REG_EVENT_HI, event_hi(4'h0, 8'h11, 8'ha1), 4'hf, response);
        repeat (5) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 1 && !read_value[16],
              "EVENT_HI commits exactly one logical event");
        check(event_prefetch_valid && jt51_write_count == 0,
              "prefetch holds the committed event while run is clear");

        // Fill the four-entry logical queue.  The skid word remains included
        // in the reported level, so it does not silently increase capacity.
        enqueue_event(32'd0, 4'h0, 8'h12, 8'ha2);
        enqueue_event(32'd0, 4'h0, 8'h13, 8'ha3);
        enqueue_event(32'd0, 4'h0, 8'h14, 8'ha4);
        repeat (4) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 4 && read_value[17],
              "event queue reports full at configured logical depth");
        enqueue_event(32'd0, 4'h0, 8'h15, 8'ha5);
        repeat (3) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 4 && read_value[18],
              "full event commit is rejected and sets overflow sticky");

        // Drain two entries with explicit core backpressure, enqueue into the
        // freed slots after the write pointer has wrapped, then verify all six
        // payloads emerge in order.
        jt51_ready = 1'b0;
        axi_write(REG_CONTROL, 32'h00000001, 4'hf, response);
        timeout_guard = 0;
        while (!scheduler_pending) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "event wrap test did not retain first command");
        end
        @(negedge clk);
        jt51_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        jt51_ready = 1'b0;
        check(jt51_write_count == 1 && jt51_regs_seen[0] == 8'h11,
              "event wrap test dispatches first command");
        repeat (3) @(posedge clk);
        @(negedge clk);
        jt51_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        jt51_ready = 1'b0;
        check(jt51_write_count == 2 && jt51_regs_seen[1] == 8'h12,
              "event wrap test dispatches second command");

        enqueue_event(32'd0, 4'h0, 8'h15, 8'ha5);
        enqueue_event(32'd0, 4'h0, 8'h16, 8'ha6);
        jt51_ready = 1'b1;
        timeout_guard = 0;
        while (jt51_write_count < 6) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 80)
                $fatal(1, "wrapped event FIFO did not drain");
        end
        check(jt51_regs_seen[2] == 8'h13 &&
              jt51_regs_seen[3] == 8'h14 &&
              jt51_regs_seen[4] == 8'h15 &&
              jt51_regs_seen[5] == 8'h16,
              "event FIFO preserves order through read/write pointer wrap");
        axi_write(REG_CONTROL, 32'h00000000, 4'hf, response);

        axi_write(REG_COMMAND, 32'h00000028, 4'hf, response);
        repeat (4) @(posedge clk);
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[12:0] == 0 && read_value[16] && !read_value[18],
              "event flush and clear-fault commands empty and clear queue");

        test_stage = 3;
        // The 48 kHz consumer may continue pulsing pcm_pop during an FM-only
        // track.  CONTROL[1]=0 must suppress both reads and false underruns.
        @(negedge clk);
        pcm_pop = 1'b1;
        @(posedge clk); #1;
        check(!pcm_valid, "disabled PCM consumer cannot pop the FIFO");
        @(negedge clk);
        pcm_pop = 1'b0;
        repeat (2) @(posedge clk);
        axi_read(REG_PCM_STATUS, read_value, response);
        check(!read_value[19],
              "disabled PCM consumer does not set underrun sticky");
        axi_write(REG_CONTROL, 32'h00000002, 4'hf, response);
        check(pcm_enable, "CONTROL[1] explicitly enables PCM playback");
        axi_write(REG_CONTROL, 32'h00000006, 4'hf, response);
        check(fm_mute_enable && pcm_enable,
              "CONTROL[2] independently requests FM-only mute");
        axi_write(REG_CONTROL, 32'h00000002, 4'hf, response);

        // PCM FIFO full/overflow followed by read/write pointer wrap.
        axi_write(REG_PCM_FRAME, 32'h00000001, 4'hf, response);
        axi_write(REG_PCM_FRAME, 32'h00000002, 4'hf, response);
        axi_write(REG_PCM_FRAME, 32'h00000003, 4'hf, response);
        axi_write(REG_PCM_FRAME, 32'h00000004, 4'hf, response);
        axi_read(REG_PCM_STATUS, read_value, response);
        check(read_value[12:0] == 4 && read_value[17],
              "PCM FIFO reports full at configured depth");
        axi_write(REG_PCM_FRAME, 32'hdeadbeef, 4'hf, response);
        repeat (2) @(posedge clk);
        axi_read(REG_PCM_STATUS, read_value, response);
        check(read_value[12:0] == 4 && read_value[18],
              "PCM FIFO rejects overflow and sets sticky status");

        pop_pcm_check(32'h00000001);
        pop_pcm_check(32'h00000002);
        axi_write(REG_PCM_FRAME, 32'h00000005, 4'hf, response);
        axi_write(REG_PCM_FRAME, 32'h00000006, 4'hf, response);
        pop_pcm_check(32'h00000003);
        pop_pcm_check(32'h00000004);
        pop_pcm_check(32'h00000005);
        pop_pcm_check(32'h00000006);
        check(pcm_level == 0, "PCM FIFO wrap test drains to empty");

        @(negedge clk);
        pcm_pop = 1'b1;
        @(posedge clk); #1;
        check(!pcm_valid, "empty PCM pop is not marked valid");
        @(negedge clk);
        pcm_pop = 1'b0;
        repeat (2) @(posedge clk);
        axi_read(REG_PCM_STATUS, read_value, response);
        check(read_value[19], "empty PCM pop sets underrun sticky");

        axi_write(REG_COMMAND, 32'h00000020, 4'hf, response);
        repeat (3) @(posedge clk);
        axi_read(REG_PCM_STATUS, read_value, response);
        check(!read_value[18] && !read_value[19],
              "clear-fault command clears PCM sticky flags");

        test_stage = 4;
        axi_write(REG_COMMAND, 32'h00000007, 4'hf, response);
        repeat (3) @(posedge clk);
        check(mute_count == 1 && unmute_count == 1 && reset_count == 1,
              "COMMAND emits one-cycle mute, unmute, and reset pulses");

        test_stage = 5;
        // Future-deadline backpressure: first event waits for cycle 20 while
        // the second is retained in the prefetch skid slot.
        axi_write(REG_COMMAND, 32'h00000028, 4'hf, response);
        axi_write(REG_CONTROL, 32'h00000000, 4'hf, response);
        enqueue_event(32'd20, 4'h0, 8'h20, 8'h7f);
        enqueue_event(32'd0, 4'h1, 8'h2a, 8'h55);
        jt51_baseline = jt51_write_count;
        timeout_guard = 0;
        while (!event_prefetch_valid) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "event prefetch did not fill before run");
        end
        check(event_level == 2, "logical event level includes prefetched word");

        axi_write(REG_EVENT_WATERMARK, 32'd1, 4'hf, response);
        axi_write(REG_CONTROL, 32'h00000001, 4'hf, response);
        timeout_guard = 0;
        while (!scheduler_pending) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "scheduler did not retain future event");
        end
        repeat (5) @(posedge clk);
        #1;
        check(event_prefetch_valid && jt51_write_count == jt51_baseline,
              "second event remains stable during future-deadline backpressure");
        check(event_level == 1,
              "reported event level retains the backpressured skid word");

        timeout_guard = 0;
        while (jt51_write_count == jt51_baseline) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "future JT51 deadline did not fire");
        end
        check(jt51_reg == 8'h20 && jt51_data == 8'h7f,
              "front end preserves JT51 event payload");
        timeout_guard = 0;
        while (jt03_write_count == 0) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 10)
                $fatal(1, "backpressured JT03 event did not fire");
        end
        check(jt03_reg == 8'h2a && jt03_data == 8'h55,
              "front end preserves JT03 event payload");
        check((jt03_issue_time - jt51_issue_time) == 1,
              "zero-delta event follows at one-write-per-clock throughput");
        check(jt51_issue_time == 20,
              "future event fires at the exact cumulative cycle deadline");
        axi_read(REG_LATE_COUNT, read_value, response);
        check(read_value == 0 && late_count == 0,
              "resident zero-delta burst does not create a late fault");

        // Once that resident stream drains, the scheduler starves.  A later
        // zero-delta event inherits the old cumulative deadline and is late.
        repeat (5) @(posedge clk);
        check(scheduler_underrun_active,
              "empty running event stream exposes active underrun for mute");
        jt51_baseline = diagnostic_count;
        enqueue_event(32'd0, 4'hf, 8'h00, 8'h00);
        timeout_guard = 0;
        while (diagnostic_count == jt51_baseline) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "starvation diagnostic did not dispatch");
        end
        axi_read(REG_LATE_COUNT, read_value, response);
        check(read_value == 1 && late_count == 1,
              "post-starvation past-deadline event increments late count");
        // The recovery event clears starvation for its dispatch cycle.  With
        // no following resident entry, the still-running stream immediately
        // enters a new underrun on the next cycle.
        check(scheduler_underrun_active,
              "a still-empty running stream re-enters underrun after recovery");

        test_stage = 6;
        // After a future event releases the timestamp-zero startup barrier, a
        // busy core must retain a zero-delta burst without stretching musical
        // time.  This models the X68000 OPM timer continuing during BUSY waits.
        axi_write(REG_CONTROL, 32'h00000000, 4'hf, response);
        axi_write(REG_COMMAND, 32'h00000028, 4'hf, response);
        repeat (5) @(posedge clk);
        jt51_baseline = jt51_write_count;
        diagnostic_baseline = diagnostic_count;
        enqueue_event(32'd1, 4'hf, 8'h00, 8'h00);
        enqueue_event(32'd0, 4'h0, 8'h30, 8'hc1);
        enqueue_event(32'd0, 4'h0, 8'h31, 8'hc2);
        timeout_guard = 0;
        while (!event_prefetch_valid) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "blocked-core test did not prefetch first event");
        end
        jt51_ready = 1'b0;
        axi_write(REG_CONTROL, 32'h00000001, 4'hf, response);
        timeout_guard = 0;
        while (diagnostic_count == diagnostic_baseline) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "startup-release diagnostic did not fire");
        end
        timeout_guard = 0;
        while (!scheduler_pending) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "blocked core event was not retained");
        end
        stalled_time = playback_cycles;
        repeat (8) begin
            @(posedge clk); #1;
            check(jt51_write_count == jt51_baseline,
                  "core-ready low suppresses, rather than drops, write strobe");
        end
        check(playback_cycles == stalled_time + 8,
              "runtime core backpressure does not stretch musical time");

        @(negedge clk);
        jt51_ready = 1'b1;
        @(posedge clk); #1;
        check(jt51_write_count == jt51_baseline + 1 &&
              jt51_reg == 8'h30 && jt51_data == 8'hc1,
              "first blocked JT51 command fires when ready returns");
        @(negedge clk);
        jt51_ready = 1'b0;
        stalled_time = playback_cycles;
        repeat (5) begin
            @(posedge clk); #1;
            check(jt51_write_count == jt51_baseline + 1,
                  "second blocked command remains queued without duplicate strobe");
        end
        check(playback_cycles == stalled_time + 5,
              "second blocked command also leaves musical time running");
        @(negedge clk);
        jt51_ready = 1'b1;
        @(posedge clk); #1;
        check(jt51_write_count == jt51_baseline + 2 &&
              jt51_reg == 8'h31 && jt51_data == 8'hc2,
              "second blocked JT51 command is delivered in order");

        test_stage = 7;
        enqueue_event(32'd0, 4'h3, 8'h00, 8'h00);
        timeout_guard = 0;
        while (end_count == 0) begin
            @(posedge clk); #1;
            timeout_guard = timeout_guard + 1;
            if (timeout_guard > 40)
                $fatal(1, "end event did not dispatch");
        end
        axi_read(REG_EVENT_STATUS, read_value, response);
        check(read_value[22] && scheduler_halted,
              "EVENT_STATUS[22] exposes scheduler halt for auto-advance");

        if (failures == 0) begin
            $display("RETROFM FRONTEND SELF-TEST PASS");
            $finish;
        end else begin
            $fatal(1, "RETROFM FRONTEND SELF-TEST FAILED: %0d checks", failures);
        end
    end
endmodule
