// tb_address_decoder.v
// Directed table-driven test for address_decoder. Five rows come straight
// from the design spec's table; the rest cover the address-aliasing cases
// that only show up once real baremetal software is running.
// Assumes the default 2x2 mesh knobs in noc_defs.vh.

`timescale 1ns/1ps
`include "noc_defs.vh"

module tb_address_decoder;

    integer errors = 0;
    integer checks = 0;

    reg [31:0] addr;

    // One decoder instance per tile ID, all fed the same address, so a single
    // stimulus line can be checked "from" any tile.
    wire        loc  [0:3];
    wire        rem  [0:3];
    wire        ill  [0:3];
    wire [`NOC_X_W-1:0] tx [0:3];
    wire [`NOC_Y_W-1:0] ty [0:3];
    wire [11:0] off [0:3];

    genvar t;
    generate
        for (t = 0; t < 4; t = t + 1) begin : tiles
            address_decoder #(.MY_TILE_ID(t)) dut (
                .addr(addr),
                .is_local(loc[t]), .is_remote(rem[t]), .is_illegal(ill[t]),
                .target_tile(), .target_x(tx[t]), .target_y(ty[t]),
                .local_offset(off[t])
            );
        end
    endgenerate

    task check_remote;
        input [31:0]      a;
        input integer     from;
        input integer     exp_x;
        input integer     exp_y;
        begin
            addr = a; #1; checks = checks + 1;
            if (loc[from] !== 1'b0 || ill[from] !== 1'b0 ||
                tx[from] !== exp_x || ty[from] !== exp_y) begin
                $display("FAIL addr=%h from=Tile%0d : is_local=%b is_illegal=%b x=%0d y=%0d (expected remote x=%0d y=%0d)",
                         a, from, loc[from], ill[from], tx[from], ty[from], exp_x, exp_y);
                errors = errors + 1;
            end else
                $display("  ok  addr=%h from=Tile%0d -> remote, target (x=%0d,y=%0d), offset=%h",
                         a, from, tx[from], ty[from], off[from]);
        end
    endtask

    task check_local;
        input [31:0]  a;
        input integer from;
        begin
            addr = a; #1; checks = checks + 1;
            if (loc[from] !== 1'b1 || ill[from] !== 1'b0) begin
                $display("FAIL addr=%h from=Tile%0d : is_local=%b is_illegal=%b (expected local)",
                         a, from, loc[from], ill[from]);
                errors = errors + 1;
            end else
                $display("  ok  addr=%h from=Tile%0d -> local, offset=%h", a, from, off[from]);
        end
    endtask

    task check_illegal;
        input [31:0]  a;
        input integer from;
        begin
            addr = a; #1; checks = checks + 1;
            if (ill[from] !== 1'b1 || loc[from] !== 1'b0 || rem[from] !== 1'b0) begin
                $display("FAIL addr=%h from=Tile%0d : is_illegal=%b is_local=%b is_remote=%b (expected illegal)",
                         a, from, ill[from], loc[from], rem[from]);
                errors = errors + 1;
            end else
                $display("  ok  addr=%h from=Tile%0d -> illegal (not a tile address)", a, from);
        end
    endtask

    initial begin
        $display("=== spec table ===");
        check_local (32'h0000_0050, 0);
        // expected values are the TARGET's absolute coordinates
        check_remote(32'h0000_1050, 0, 1, 0);
        check_remote(32'h0000_2050, 0, 0, 1);
        check_remote(32'h0000_3100, 0, 1, 1);
        check_remote(32'h0000_0050, 3, 0, 0);

        $display("=== full cross-product: every tile to every tile ===");
        check_remote(32'h0000_0000, 1, 0, 0);
        check_remote(32'h0000_0000, 2, 0, 0);
        check_remote(32'h0000_1000, 2, 1, 0);
        check_remote(32'h0000_2000, 1, 0, 1);
        check_local (32'h0000_1FFF, 1);
        check_local (32'h0000_2000, 2);
        check_local (32'h0000_3000, 3);

        $display("=== offset passthrough is untouched by the tile field ===");
        addr = 32'h0000_3ABC; #1; checks = checks + 1;
        if (off[0] !== 12'hABC) begin
            $display("FAIL offset passthrough: got %h expected ABC", off[0]);
            errors = errors + 1;
        end else $display("  ok  offset passthrough = %h", off[0]);

        $display("=== aliasing / out-of-window (the baremetal hazards) ===");
        check_illegal(32'hFFFF_FFFF, 0);  // picorv32 default STACKADDR
        check_illegal(32'h0000_4050, 0);  // one bit above the window
        check_illegal(32'h8000_0050, 0);  // high memory
        check_illegal(32'h0001_0000, 0);

        $display("");
        if (errors == 0) $display("PASS: %0d/%0d checks", checks, checks);
        else             $display("FAIL: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
