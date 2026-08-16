// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Relative-deadline event scheduler for the PS-to-PL 64-bit event stream.
//
//   bits 31:0  delta in 100 MHz cycles
//   bits 39:32 register
//   bits 47:40 data
//   bits 51:48 opcode (0=JT51, 1=JT03, 2=delay, 3=end, 4=YM2608, 15=diagnostic)
//   bits 63:52 flags/reserved
//
// The input is a conventional ready/valid stream.  Events are scheduled on an
// absolute cumulative timeline, so a delayed producer cannot silently shift
// all later events; it instead increments late_count.  Timestamp-zero setup
// writes form a startup barrier, but routine Yamaha bus backpressure does not
// stop the musical clock: this matches MXDRV on an X68000, where the OPM timer
// continues counting while the 68000 busy-waits between register writes.
module retrofm_event_scheduler (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        clear_stats,
    input  logic        run,

    input  logic        event_valid,
    input  logic [63:0] event_data,
    output logic        event_ready,
    input  logic        source_has_event,

    input  logic        jt51_ready,
    input  logic        jt03_ready,

    output logic        jt51_wr,
    output logic [7:0]  jt51_reg,
    output logic [7:0]  jt51_data,
    output logic        jt03_wr,
    output logic        jt03_port,
    output logic [7:0]  jt03_reg,
    output logic [7:0]  jt03_data,
    output logic        end_pulse,
    output logic        diagnostic_pulse,

    output logic        pending,
    output logic        halted,
    output logic        core_stalled,
    output logic        playback_advancing,
    output logic        underrun_active,
    output logic        late_pulse,
    output logic        underrun_pulse,
    output logic [31:0] late_count,
    output logic [31:0] underrun_count,
    output logic [63:0] playback_cycles,
    output logic [63:0] scheduled_cycles
);
    localparam logic [3:0] OP_JT51       = 4'h0;
    localparam logic [3:0] OP_JT03       = 4'h1;
    localparam logic [3:0] OP_DELAY      = 4'h2;
    localparam logic [3:0] OP_END        = 4'h3;
    localparam logic [3:0] OP_YM2608     = 4'h4;
    localparam logic [3:0] OP_DIAGNOSTIC = 4'hf;

    logic [63:0] pending_data;
    logic [63:0] pending_deadline;
    logic [63:0] incoming_deadline;
    logic        pending_due;
    logic        pending_is_end;
    logic        pending_dispatchable;
    logic        incoming_dispatchable;
    logic        incoming_due;
    logic        accept_event;
    logic        dispatch_now;
    logic [63:0] dispatch_data;
    logic        accept_is_late;
    logic        initializing;
    logic [63:0] next_playback_cycle;
    // Keep the high- and low-word deadline comparisons structurally separate.
    // A monolithic 64-bit unsigned compare mapped to a 16-CARRY4 chain on the
    // 100 MHz event-dispatch path.  The split is exactly equivalent for an
    // unsigned timestamp, but caps each arithmetic comparator at 32 bits.
    (* keep = "true" *) logic pending_cycle_hi_gt;
    (* keep = "true" *) logic pending_cycle_hi_eq;
    (* keep = "true" *) logic pending_cycle_lo_ge;
    logic pending_due_now;
    (* keep = "true" *) logic incoming_cycle_hi_gt;
    (* keep = "true" *) logic incoming_cycle_hi_eq;
    (* keep = "true" *) logic incoming_cycle_lo_ge;
    logic incoming_due_now;

    function automatic logic [31:0] saturating_increment(
        input logic [31:0] value
    );
        begin
            if (&value)
                saturating_increment = value;
            else
                saturating_increment = value + 1'b1;
        end
    endfunction

    always_comb begin
        // A clock edge both advances musical time and dispatches work due on
        // that edge.  Compare against the post-edge cycle so a deadline N is
        // not serviced at N+1 merely because both registers update together.
        playback_advancing = run && !halted && !initializing;
        // Keep the 64-bit increment independent of run/halt/initialization
        // control. Gating the adder input with those flags creates a long
        // control -> carry chain -> deadline compare path. The explicit
        // current/next comparisons below are cycle-equivalent and leave the
        // control flags after the arithmetic cone.
        next_playback_cycle = playback_cycles + 1'b1;
        pending_cycle_hi_gt = playback_cycles[63:32] > pending_deadline[63:32];
        pending_cycle_hi_eq = playback_cycles[63:32] == pending_deadline[63:32];
        pending_cycle_lo_ge = playback_cycles[31:0] >= pending_deadline[31:0];
        pending_due_now = pending_cycle_hi_gt ||
                          (pending_cycle_hi_eq && pending_cycle_lo_ge);
        // If the current cycle is not due, advancing by exactly one only makes
        // it due when the incremented timestamp equals the deadline.  Equality
        // here replaces a second 64-bit greater-or-equal comparator.
        pending_due = pending &&
                      (pending_due_now || (playback_advancing &&
                                           next_playback_cycle == pending_deadline));
        pending_is_end   = (pending_data[51:48] == OP_END);
        case (pending_data[51:48])
            OP_JT51: pending_dispatchable = jt51_ready;
            OP_JT03, OP_YM2608: pending_dispatchable = jt03_ready;
            default: pending_dispatchable = 1'b1;
        endcase
        case (event_data[51:48])
            OP_JT51: incoming_dispatchable = jt51_ready;
            OP_JT03, OP_YM2608: incoming_dispatchable = jt03_ready;
            default: incoming_dispatchable = 1'b1;
        endcase
        event_ready      = run && !halted &&
                           (!pending || (pending_due && pending_dispatchable &&
                                         !pending_is_end));
        accept_event     = event_valid && event_ready;
        incoming_deadline = scheduled_cycles +
                            {32'h00000000, event_data[31:0]};
        incoming_cycle_hi_gt = playback_cycles[63:32] > incoming_deadline[63:32];
        incoming_cycle_hi_eq = playback_cycles[63:32] == incoming_deadline[63:32];
        incoming_cycle_lo_ge = playback_cycles[31:0] >= incoming_deadline[31:0];
        incoming_due_now = incoming_cycle_hi_gt ||
                           (incoming_cycle_hi_eq && incoming_cycle_lo_ge);
        incoming_due = incoming_due_now ||
                       (playback_advancing &&
                        next_playback_cycle == incoming_deadline);

        core_stalled = run && !halted &&
                       ((pending && pending_due && !pending_dispatchable) ||
                        (!pending && accept_event &&
                         incoming_due &&
                         !incoming_dispatchable));

        dispatch_now  = 1'b0;
        dispatch_data = 64'h0000000000000000;
        if (run && !halted) begin
            if (pending && pending_due && pending_dispatchable) begin
                dispatch_now  = 1'b1;
                dispatch_data = pending_data;
            end else if (!pending && accept_event &&
                         incoming_due &&
                         incoming_dispatchable) begin
                dispatch_now  = 1'b1;
                dispatch_data = event_data;
            end
        end

        // Ordered zero-delta bursts are legal and may take several fabric
        // clocks to dispatch.  "Late" is reserved for a producer starvation
        // episode followed by an event whose cumulative deadline is already
        // in the past; ordinary resident back-to-back traffic is not a fault.
        accept_is_late = underrun_active && accept_event &&
                         (incoming_deadline < playback_cycles);
    end

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            pending          <= 1'b0;
            pending_data     <= '0;
            pending_deadline <= '0;
            halted           <= 1'b0;
            underrun_active  <= 1'b0;
            late_count       <= '0;
            underrun_count   <= '0;
            playback_cycles  <= '0;
            scheduled_cycles <= '0;
            initializing      <= 1'b1;
            jt51_wr          <= 1'b0;
            jt51_reg         <= '0;
            jt51_data        <= '0;
            jt03_wr          <= 1'b0;
            jt03_port        <= 1'b0;
            jt03_reg         <= '0;
            jt03_data        <= '0;
            end_pulse        <= 1'b0;
            diagnostic_pulse <= 1'b0;
            late_pulse       <= 1'b0;
            underrun_pulse   <= 1'b0;
        end else begin
            jt51_wr          <= 1'b0;
            jt03_wr          <= 1'b0;
            jt03_port        <= 1'b0;
            end_pulse        <= 1'b0;
            diagnostic_pulse <= 1'b0;
            late_pulse       <= 1'b0;
            underrun_pulse   <= 1'b0;

            if (clear_stats) begin
                late_count      <= '0;
                underrun_count  <= '0;
                underrun_active <= 1'b0;
            end

            if (!run) begin
                underrun_active <= 1'b0;
            end else if (!halted) begin
                // Keep playback at timestamp zero until the first future
                // event has been accepted.  This lets reset/voice setup reach
                // JT51 before PCM and audible time begin.  Once initialized,
                // never stretch song time merely because the Yamaha command
                // path is busy; queued writes catch up during the remainder
                // of the current MXDRV timer interval.
                if (playback_advancing)
                    playback_cycles <= playback_cycles + 1'b1;

                if (accept_event && incoming_deadline != 64'd0)
                    initializing <= 1'b0;

                if (pending) begin
                    if (pending_due && pending_dispatchable) begin
                        if (accept_event) begin
                            pending          <= 1'b1;
                            pending_data     <= event_data;
                            pending_deadline <= incoming_deadline;
                            scheduled_cycles <= incoming_deadline;
                            underrun_active  <= 1'b0;
                        end else begin
                            pending <= 1'b0;
                        end
                    end
                end else if (accept_event) begin
                    scheduled_cycles <= incoming_deadline;
                    underrun_active  <= 1'b0;
                    if (!incoming_due ||
                        !incoming_dispatchable) begin
                        pending          <= 1'b1;
                        pending_data     <= event_data;
                        pending_deadline <= incoming_deadline;
                    end
                end else if (!source_has_event && !underrun_active) begin
                    underrun_active <= 1'b1;
                    underrun_count  <= saturating_increment(underrun_count);
                    underrun_pulse  <= 1'b1;
                end

                if (accept_is_late) begin
                    late_count <= saturating_increment(late_count);
                    late_pulse <= 1'b1;
                end

                if (dispatch_now) begin
                    case (dispatch_data[51:48])
                        OP_JT51: begin
                            jt51_wr   <= 1'b1;
                            jt51_reg  <= dispatch_data[39:32];
                            jt51_data <= dispatch_data[47:40];
                        end
                        OP_JT03, OP_YM2608: begin
                            jt03_wr   <= 1'b1;
                            jt03_port <= dispatch_data[51:48] == OP_YM2608 ?
                                         dispatch_data[52] : 1'b0;
                            jt03_reg  <= dispatch_data[39:32];
                            jt03_data <= dispatch_data[47:40];
                        end
                        OP_END: begin
                            end_pulse <= 1'b1;
                            halted    <= 1'b1;
                            pending   <= 1'b0;
                        end
                        OP_DIAGNOSTIC: begin
                            diagnostic_pulse <= 1'b1;
                        end
                        OP_DELAY: begin
                            // Deadline-only event: deliberately no write.
                        end
                        default: begin
                            // Reserved opcode: consume without touching a core.
                        end
                    endcase
                end
            end
        end
    end
endmodule
