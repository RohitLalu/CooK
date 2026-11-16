// tb_soak.v
// Randomised soak test of the interconnect with a scoreboard. Every tile has
// a driver behind a real ni.v that issues OPS random accesses to random other
// tiles, with random pauses, all tiles at once. Compile with -DSOAK_BUS for
// the shared bus (sb_bus), without it for the mesh (noc_mesh, any size: the
// knobs NOC_MESH_X / NOC_MESH_Y).
//
// WHAT A DRIVER DOES, at random
//   * read another tile's ID register                 -> must be that tile's number
//   * post a random word into one of ITS OWN slots in another tile's mailbox
//   * read one of its own slots back                  -> must be the last word it posted there
// Each tile owns SLOTS slots in every other tile's mailbox, so every slot has
// exactly one writer and the scoreboard knows what each must hold.
//
// WHAT MUST HOLD
//   * every read returns the right value (a lost, duplicated, reordered or
//     misdelivered packet shows up here)
//   * no access hangs (a deadlock shows up here: each driver has a watchdog)
//   * afterwards every slot of every mailbox equals the scoreboard
//   * no NI error flag, and on the mesh no router drop and no dead output
// Parameters: SEED, OPS, FAULT_MASK (mesh only: links dead from reset, which
// the start-up BIST finds and the routers go around; 2x2 only).

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_soak;

    parameter integer SEED  = 1;
    parameter integer OPS   = 1000;      // accesses per tile (about 25 s of simulation on 2x2)
    parameter [4*`NOC_NUM_TILES-1:0] FAULT_MASK = 0;

    localparam integer NT    = `NOC_NUM_TILES;
    localparam integer FW    = `NOC_FLIT_W;
    localparam integer OB    = `NOC_OFFSET_BITS;
    localparam integer SLOTS = 8;                 // per writer, in every other tile's mailbox
    localparam [31:0]  MBX   = 32'h800;

    generate
        if (NT * SLOTS > 448) begin : tb_check_slots
            TB_ERROR_too_many_tiles_for_the_mailbox u_err ();
        end
    endgenerate

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [NT-1:0]    ni2r_valid, ni2r_ready, r2ni_valid, r2ni_ready, r2ni_room;
    wire [NT*FW-1:0] ni2r_flit, r2ni_flit;
    wire [NT*10-1:0] bist_status;
    wire             fabric_ready, fabric_err;

`ifdef SOAK_BUS
    wire [NT-1:0] err_drop;
    sb_bus #(.N(NT)) u_fabric (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .fault_grant(1'b0), .fault_flip(1'b0), .err_drop(err_drop), .bus_active()
    );
    assign bist_status  = {NT*10{1'b0}};
    assign fabric_ready = 1'b1;
    assign fabric_err   = |err_drop;
`else
    wire [NT*8-1:0] rt_drop_cnt;
    wire [NT*5-1:0] rt_out_dead, rt_out_wd;
    noc_mesh #(.LINK_FAULT_MASK(FAULT_MASK)) u_fabric (
        .clk(clk), .rst_n(rst_n),
        .loc_in_valid(ni2r_valid), .loc_in_ready(ni2r_ready), .loc_in_flit(ni2r_flit),
        .loc_out_valid(r2ni_valid), .loc_out_ready(r2ni_ready),
        .loc_out_room(r2ni_room), .loc_out_flit(r2ni_flit),
        .port_disable({NT*5{1'b0}}), .err_clear(1'b0),
        .rt_in_err(), .rt_out_dead(rt_out_dead), .rt_out_wd(rt_out_wd), .rt_drop_cnt(rt_drop_cnt),
        .fault_rt_mask({4*NT{1'b0}}), .fault_rt_flip(1'b0),
        .bist_status(bist_status), .bist_done(fabric_ready)
    );
    assign fabric_err = (|rt_drop_cnt) || (|rt_out_dead) || (|rt_out_wd);
`endif

    // scoreboard: what slot s of writer w in tile t's mailbox must hold
    reg [31:0] model [0:NT*NT*SLOTS-1];
    integer mi;
    initial for (mi = 0; mi < NT*NT*SLOTS; mi = mi + 1) model[mi] = 32'b0;

    reg  [NT-1:0] done = 0;
    integer errors = 0, reads = 0, writes = 0;
    reg     go = 0, check_now = 0;
    wire [NT*5-1:0] err_flags;

    genvar g;
    generate
        for (g = 0; g < NT; g = g + 1) begin : g_tile
            reg         c_valid = 0;
            reg  [31:0] c_addr = 0, c_wdata = 0;
            reg  [3:0]  c_wstrb = 0;
            wire        c_ready;
            wire [31:0] c_rdata;

            ni #(.MY_ID(g)) u_ni (
                .clk(clk), .rst_n(rst_n),
                .mem_valid(c_valid), .mem_instr(1'b0), .mem_ready(c_ready),
                .mem_addr(c_addr), .mem_wdata(c_wdata), .mem_wstrb(c_wstrb), .mem_rdata(c_rdata),
                .in_valid(r2ni_valid[g]), .in_ready(r2ni_ready[g]), .in_room(r2ni_room[g]),
                .in_flit(r2ni_flit[g*FW +: FW]),
                .out_valid(ni2r_valid[g]), .out_ready(ni2r_ready[g]), .out_flit(ni2r_flit[g*FW +: FW]),
                .err_flags(err_flags[g*5 +: 5]), .sw_status(), .bist_status(bist_status[g*10 +: 10])
            );

            integer seed, n, k, tgt, slot, kind, idx, w;
            reg [31:0] val, got, addr;

            // one access; a watchdog turns a hang into a failure instead of a stuck simulation
            task xfer;
                input  [31:0] a;
                input  [31:0] d;
                input  [3:0]  s;
                output [31:0] r;
                begin
                    c_addr = a;  c_wdata = d;  c_wstrb = s;  c_valid = 1'b1;
                    w = 0;
                    @(posedge clk); #1;
                    while (!c_ready && w < 50000) begin @(posedge clk); #1; w = w + 1; end
                    if (w >= 50000) begin
                        $display("FAIL: tile %0d hung on address %h (deadlock?)", g, a);
                        $finish;
                    end
                    r = c_rdata;
                    c_valid = 1'b0;
                end
            endtask

            initial begin
                // simulation memory starts unknown; the board's block RAM starts at 0
                for (k = 0; k < NT * SLOTS; k = k + 1) u_ni.mem[(MBX >> 2) + k] = 32'b0;
                seed = SEED * 1000 + g;
                wait (go);
                for (n = 0; n < OPS; n = n + 1) begin
                    tgt = $random(seed);
                    tgt = ((tgt % (NT - 1)) + (NT - 1)) % (NT - 1);
                    if (tgt >= g) tgt = tgt + 1;                    // any tile but this one
                    slot = $random(seed);  slot = ((slot % SLOTS) + SLOTS) % SLOTS;
                    kind = $random(seed);  kind = ((kind % 8) + 8) % 8;
                    idx  = (tgt * NT + g) * SLOTS + slot;
                    addr = (tgt << OB) + MBX + 4 * (g * SLOTS + slot);
                    if (kind == 0) begin
                        xfer(tgt << OB, 0, 4'h0, got);              // ID register
                        reads = reads + 1;
                        if (got !== tgt) begin
                            errors = errors + 1;
                            $display("FAIL: tile %0d read ID of tile %0d, got %h", g, tgt, got);
                        end
                    end else if (kind < 5) begin
                        val = $random(seed);
                        model[idx] = val;
                        xfer(addr, val, 4'hF, got);                 // posted write
                        writes = writes + 1;
                    end else begin
                        xfer(addr, 0, 4'h0, got);                   // read my slot back
                        reads = reads + 1;
                        if (got !== model[idx]) begin
                            errors = errors + 1;
                            $display("FAIL: tile %0d slot %0d in tile %0d: read %h, last wrote %h",
                                     g, slot, tgt, got, model[idx]);
                        end
                    end
                    k = $random(seed);  k = ((k % 4) + 4) % 4;      // 0..3 idle cycles
                    repeat (k) @(posedge clk);
                    #1;
                end
                done[g] = 1'b1;
            end

            // afterwards: every slot in this tile's mailbox equals the scoreboard
            integer cw, cs;
            always @(posedge check_now) begin
                for (cw = 0; cw < NT; cw = cw + 1)
                    for (cs = 0; cs < SLOTS; cs = cs + 1)
                        if (cw != g && u_ni.mem[(MBX >> 2) + cw * SLOTS + cs] !== model[(g * NT + cw) * SLOTS + cs]) begin
                            errors = errors + 1;
                            $display("FAIL: tile %0d mailbox, writer %0d slot %0d holds %h, scoreboard %h", g, cw, cs,
                                     u_ni.mem[(MBX >> 2) + cw * SLOTS + cs], model[(g * NT + cw) * SLOTS + cs]);
                        end
            end
        end
    endgenerate

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    initial begin
        repeat (6) @(posedge clk);
        #1 rst_n = 1;
        while (!fabric_ready) @(posedge clk);
        #1 go = 1;
        cyc = 0;
        wait (&done);
        repeat (300) @(posedge clk);          // let the last posted writes land
        check_now = 1;
        #1;
        if (err_flags !== {NT*5{1'b0}}) begin
            errors = errors + 1;
            $display("FAIL: NI error flags %h", err_flags);
        end
        if (fabric_err) begin
            errors = errors + 1;
            $display("FAIL: the fabric dropped a packet, or a watchdog fired");
        end
        $display("soak %0dx%0d %0s seed %0d fault %h: %0d tiles x %0d accesses in %0d cycles, %0d reads checked, %0d writes",
                 `NOC_MESH_X, `NOC_MESH_Y,
`ifdef SOAK_BUS
                 "bus",
`else
                 "mesh",
`endif
                 SEED, FAULT_MASK, NT, OPS, cyc, reads, writes);
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", reads + NT * (NT - 1) * SLOTS + 2);
        else             $display("TOTAL: %0d checks failed", errors);
        $finish;
    end
endmodule
