// noc_funcs.vh
// Shared helper functions and elaboration-time checks.
//
// Include this INSIDE a module body, after the port list:
//     module foo (...);
//     `include "noc_funcs.vh"
// It deliberately has no include guard: every module that includes it needs
// its own copy of the functions, because Verilog-2001 functions are scoped to
// the module that declares them. Requires noc_defs.vh at file scope first.

// ---- check bits -----------------------------------------------------------

// Check bits for a flit body (everything below the CHK field).
function [`NOC_CHK_W-1:0] noc_chk_gen;
    input [`NOC_BODY_W-1:0] body;
    integer b;
    begin
        noc_chk_gen = {`NOC_CHK_W{1'b0}};
        if (`NOC_CHK_MODE == 1) begin
            // even parity per byte: chk[k] = XOR of body[8k +: 8]
            for (b = 0; b < `NOC_BODY_W; b = b + 1)
                noc_chk_gen[b / 8] = noc_chk_gen[b / 8] ^ body[b];
        end
    end
endfunction

// 1 when a received flit's check bits match its body.
function noc_chk_ok;
    input [`NOC_FLIT_W-1:0] f;
    begin
        noc_chk_ok = (`NOC_CHK_MODE == 0) ? 1'b1 :
                     (f[`NOC_F_CHK_LSB +: `NOC_CHK_W] == noc_chk_gen(f[`NOC_BODY_W-1:0]));
    end
endfunction

// Build a complete flit and seal it with fresh check bits.
function [`NOC_FLIT_W-1:0] noc_make_flit;
    input [1:0]             ftype;
    input                   poison;
    input [`NOC_ID_W-1:0]   src;
    input [`NOC_X_W-1:0]    dst_x;
    input [`NOC_Y_W-1:0]    dst_y;
    input [`NOC_DATA_W-1:0] data;
    reg   [`NOC_BODY_W-1:0] body;
    begin
        body = {`NOC_BODY_W{1'b0}};
        body[`NOC_F_DATA_LSB +: `NOC_DATA_W] = data;
        body[`NOC_F_DSTX_LSB +: `NOC_X_W]    = dst_x;
        body[`NOC_F_DSTY_LSB +: `NOC_Y_W]    = dst_y;
        body[`NOC_F_SRC_LSB  +: `NOC_ID_W]   = src;
        body[`NOC_F_TYPE_LSB +: 2]           = ftype;
        body[`NOC_F_POISON]                  = poison;
        noc_make_flit = {noc_chk_gen(body), body};
    end
endfunction

// ---- tile ID <-> coordinates (row-major) ----------------------------------

function [`NOC_X_W-1:0] noc_id_x;
    input [`NOC_ID_W-1:0] id;
    begin
        noc_id_x = id % `NOC_MESH_X;
    end
endfunction

function [`NOC_Y_W-1:0] noc_id_y;
    input [`NOC_ID_W-1:0] id;
    begin
        noc_id_y = id / `NOC_MESH_X;
    end
endfunction

// ---- elaboration-time checks ----------------------------------------------
// Verilog-2001 has no $error at elaboration. An instance of a module that
// does not exist stops every tool (Icarus, XSIM, Vivado synth, Yosys) with
// the instance's name in the message, so the name says what is wrong.
generate
    if (`NOC_H_USED > `NOC_DATA_W) begin : noc_cfg_check
        NOC_CONFIG_ERROR_head_fields_do_not_fit_in_data_width u_err ();
    end
    if ((1 << `NOC_LEN_W) < `NOC_MAX_PKT_FLITS) begin : noc_cfg_check_len
        NOC_CONFIG_ERROR_length_field_too_narrow u_err ();
    end
    if (`NOC_OFFSET_BITS + `NOC_ID_W > 32) begin : noc_cfg_check_addr
        NOC_CONFIG_ERROR_tile_window_exceeds_32bit_address u_err ();
    end
    if ((`NOC_CHK_MODE != 0) && (`NOC_CHK_MODE != 1)) begin : noc_cfg_check_chk
        NOC_CONFIG_ERROR_unsupported_chk_mode u_err ();
    end
endgenerate
