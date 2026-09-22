
// noc_router.v
// 5-port NoC router: N, S, E, W, L (local / CR-facing).
// Deterministic X-Y routing, wormhole-style route holding (Head
// establishes the route, Body/Tail follow it, Tail releases it),
// round-robin arbitration per output.
// Step 1 of the build roadmap: bare router only -- no BIST, no AXI.

module noc_router #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32,
    parameter ROUTER_CODE = 1,
    parameter TOTAL_ROUTERS = 4,
  // DIFFERENT ROUTER CODE FOR EACH ROUTER (ONE CODE FOR ONE ROUTER - CORE) // ALSO ROUTER CODE IS CHECKED BY NETWORK INTERFACE
  )(
    input  wire                  clk,
    input  wire                  rst_n,

    // Port order for every bus below: index 0=N, 1=S, 2=E, 3=W, 4=L (local)
    input wire [5*$clog2(TOTAL_ROUTERS)-1:0] in_router_code_flit,
    input  wire [4:0]            in_valid,
    output wire [4:0]            in_ready,
    input  wire [9:0]            in_type,   // 2 bits per port
    input  wire [5*DX_W-1:0]     in_dx,
    input  wire [5*DY_W-1:0]     in_dy,
    input  wire [5*DATA_W-1:0]   in_data,

    output wire [5*$clog2(TOTAL_ROUTERS)-1:0] out_router_code_flit,
    output wire [4:0]            out_valid,
    input  wire [4:0]            out_ready,
    output wire [9:0]            out_type,
    output wire [5*DX_W-1:0]     out_dx,
    output wire [5*DY_W-1:0]     out_dy,
    output wire [5*DATA_W-1:0]   out_data,

    input wire correct_flit_check, // network interface sends signal to access router code
    output wire [$clog2(TOTAL_ROUTERS):0] router_code
  );


  //
  """
  FIXING CONVENTION HERE:
    Port order for every bus below: index 0=N, 1=S, 2=E, 3=W, 4=L
    {same for out}
    in_valid[0] -> N
    in_valid[1] -> S
    in_valid[2] -> E
    in_valid[3] -> W
    in_valid[4] -> L (to NI to PE)

    in_ready[0] -> N
    in_ready[1] -> S
    in_ready[2] -> E
    in_ready[3] -> W
    in_ready[4] -> L (to NI to PE)

    in_type[1:0] -> N
    in_type[3:2] -> S
    in_type[5:4] -> E
    in_type[7:6] -> W
    in_type[9:8] -> L (to NI to PE)

  """
  localparam N = 0, S = 1, E = 2, W = 3, L = 4;
  localparam [1:0] BODY = 2'b00, HEAD = 2'b01, HEADTAIL = 2'b10, TAIL = 2'b11;

  integer i, j, s;

  always@(*)begin
    if (correct_flit_check) & (in_ready[4]) begin
      //send router code of currently held flit. NI performs check
      router_code = 0 ; //fill stuff here after flit is modified
    end
    else router_code = $clog2(TOTAL_ROUTERS); 
  end


  // ---------------------------------------------------------------
  // Unpack the flattened input buses into per-port arrays
  // ---------------------------------------------------------------
  wire [1:0]             p_in_type [0:4];
  wire signed [DX_W-1:0] p_in_dx   [0:4];
  wire signed [DY_W-1:0] p_in_dy   [0:4];
  wire [DATA_W-1:0]      p_in_data [0:4];

  genvar g;
  generate
    for (g = 0; g < 5; g = g + 1)
    begin : unpack
      assign p_in_type[g] = in_type[2*g +: 2];
      assign p_in_dx[g]   = in_dx[DX_W*g +: DX_W];
      assign p_in_dy[g]   = in_dy[DY_W*g +: DY_W];
      assign p_in_data[g] = in_data[DATA_W*g +: DATA_W];
    end
  endgenerate

  // ---------------------------------------------------------------
  // Routing function: which output does (dx,dy) want? X first, then Y.
  // ---------------------------------------------------------------
  function [2:0] route_of;
    input signed [DX_W-1:0] dx;
    input signed [DY_W-1:0] dy;
    begin
      if (dx < 0)
        route_of = W;
      else if (dx > 0)
        route_of = E;
      else if (dy < 0)
        route_of = N;
      else if (dy > 0)
        route_of = S;
      else
        route_of = L;
    end
  endfunction

  function signed [DX_W-1:0] next_dx;
    input signed [DX_W-1:0] dx;
    begin
      if (dx < 0)
        next_dx = dx + 1'b1;
      else if (dx > 0)
        next_dx = dx - 1'b1;
      else
        next_dx = dx;
    end
  endfunction

  function signed [DY_W-1:0] next_dy;
    input signed [DX_W-1:0] dx;
    input signed [DY_W-1:0] dy;
    begin
      if (dx != 0)
        next_dy = dy;
      else if (dy < 0)
        next_dy = dy + 1'b1;
      else if (dy > 0)
        next_dy = dy - 1'b1;
      else
        next_dy = dy;
    end
  endfunction

  // Candidate input for output `outp`, at rotation slot 0..3
  // (the four ports other than outp itself -- no same-direction bounce-back)
  function [2:0] cand_input;
    input [2:0] outp;
    input [1:0] slot;
    begin
      case (outp)
        N:
        case (slot)
          2'd0:
            cand_input=S;
          2'd1:
            cand_input=E;
          2'd2:
            cand_input=W;
          default:
            cand_input=L;
        endcase
        S:
        case (slot)
          2'd0:
            cand_input=N;
          2'd1:
            cand_input=E;
          2'd2:
            cand_input=W;
          default:
            cand_input=L;
        endcase
        E:
        case (slot)
          2'd0:
            cand_input=N;
          2'd1:
            cand_input=S;
          2'd2:
            cand_input=W;
          default:
            cand_input=L;
        endcase
        W:
        case (slot)
          2'd0:
            cand_input=N;
          2'd1:
            cand_input=S;
          2'd2:
            cand_input=E;
          default:
            cand_input=L;
        endcase
        default:
        case (slot)
          2'd0:
            cand_input=N;
          2'd1:
            cand_input=S;
          2'd2:
            cand_input=E;
          default:
            cand_input=W;
        endcase
      endcase
    end
  endfunction

  // ---------------------------------------------------------------
  // Per-input route-hold state (wormhole-style)
  // ---------------------------------------------------------------
  reg       route_active [0:4];
  reg [2:0] route_dest   [0:4];

  reg [2:0] want_out   [0:4];
  reg       want_valid [0:4];

  always @(*)
  begin
    for (i = 0; i < 5; i = i + 1)
    begin
      if (route_active[i])
      begin
        if (p_in_type[i] == BODY || p_in_type[i] == TAIL)
        begin
          want_valid[i] = in_valid[i];
          want_out[i]   = route_dest[i];
        end
        else
        begin
          // Illegal: a HEAD/HEADTAIL arrived while this input
          // already has a route held (the sender should be
          // sending BODY/TAIL to continue it, or nothing at
          // all). Do NOT treat it as a continuation of the old
          // route -- that would silently misroute it. Refuse
          // to grant it instead; see the protocol-check block
          // below for the corresponding visibility check.
          want_valid[i] = 1'b0;
          want_out[i]   = 3'd0;
        end
      end
      else if (in_valid[i] && (p_in_type[i] == HEAD || p_in_type[i] == HEADTAIL))
      begin
        want_valid[i] = 1'b1;
        want_out[i]   = route_of(p_in_dx[i], p_in_dy[i]);
      end
      else
      begin
        want_valid[i] = 1'b0;
        want_out[i]   = 3'd0;
      end
    end
  end

  // ---------------------------------------------------------------
  // Per-output round-robin arbitration among the 4 legal candidates
  // ---------------------------------------------------------------
  reg [1:0] rr_ptr [0:4];

  reg [2:0] grant_input [0:4];
  reg       grant_valid [0:4];
  reg [1:0] grant_slot  [0:4]; // which candidate slot actually won, per output

  integer idx_int;
  reg [1:0] idx2, chosen_slot;
  reg found;

  always @(*)
  begin
    for (j = 0; j < 5; j = j + 1)
    begin
      found = 1'b0;
      chosen_slot = 2'd0;
      for (s = 0; s < 4; s = s + 1)
      begin
        idx_int = rr_ptr[j] + s;
        idx2    = idx_int[1:0];
        if (!found && want_valid[cand_input(j[2:0], idx2)] &&
            want_out[cand_input(j[2:0], idx2)] == j[2:0])
        begin
          found       = 1'b1;
          chosen_slot = idx2;
        end
      end
      grant_valid[j] = found;
      grant_input[j] = found ? cand_input(j[2:0], chosen_slot) : 3'd0;
      grant_slot[j]  = chosen_slot;
    end
  end

  // ---------------------------------------------------------------
  // Crossbar: drive each output from its granted input
  // ---------------------------------------------------------------
  reg [1:0]              p_out_type [0:4];
  reg signed [DX_W-1:0]  p_out_dx   [0:4];
  reg signed [DY_W-1:0]  p_out_dy   [0:4];
  reg [DATA_W-1:0]       p_out_data [0:4];

  always @(*)
  begin
    for (j = 0; j < 5; j = j + 1)
    begin
      if (grant_valid[j])
      begin
        p_out_type[j] = p_in_type[grant_input[j]];
        p_out_data[j] = p_in_data[grant_input[j]];
        if (p_in_type[grant_input[j]] == HEAD || p_in_type[grant_input[j]] == HEADTAIL)
        begin
          p_out_dx[j] = next_dx(p_in_dx[grant_input[j]]);
          p_out_dy[j] = next_dy(p_in_dx[grant_input[j]], p_in_dy[grant_input[j]]);
        end
        else
        begin
          p_out_dx[j] = {DX_W{1'b0}};
          p_out_dy[j] = {DY_W{1'b0}};
        end
      end
      else
      begin
        p_out_type[j] = 2'b00;
        p_out_dx[j]   = {DX_W{1'b0}};
        p_out_dy[j]   = {DY_W{1'b0}};
        p_out_data[j] = {DATA_W{1'b0}};
      end
    end
  end

  assign out_valid = {grant_valid[L], grant_valid[W], grant_valid[E], grant_valid[S], grant_valid[N]};

  generate
    for (g = 0; g < 5; g = g + 1)
    begin : pack_out
      assign out_type[2*g +: 2]           = p_out_type[g];
      assign out_dx[DX_W*g +: DX_W]       = p_out_dx[g];
      assign out_dy[DY_W*g +: DY_W]       = p_out_dy[g];
      assign out_data[DATA_W*g +: DATA_W] = p_out_data[g];
    end
  endgenerate

  // in_ready[i]: input i is accepted this cycle iff it's the granted
  // input for whichever output it wants, and that output is ready
  reg ready_i [0:4];
  always @(*)
  begin
    for (i = 0; i < 5; i = i + 1)
    begin
      ready_i[i] = want_valid[i] &&
             grant_valid[want_out[i]] &&
             (grant_input[want_out[i]] == i) &&
             out_ready[want_out[i]];
    end
  end
  assign in_ready = {ready_i[L], ready_i[W], ready_i[E], ready_i[S], ready_i[N]};

  // ---------------------------------------------------------------
  // Sequential: route-hold state and round-robin pointers
  // ---------------------------------------------------------------
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      for (i = 0; i < 5; i = i + 1)
      begin
        route_active[i] <= 1'b0;
        route_dest[i]   <= 3'd0;
      end
      for (j = 0; j < 5; j = j + 1)
        rr_ptr[j] <= 2'd0;
    end
    else
    begin
      for (i = 0; i < 5; i = i + 1)
      begin
        if (ready_i[i] && in_valid[i])
        begin
          if (p_in_type[i] == HEAD)
          begin
            route_active[i] <= 1'b1;
            route_dest[i]   <= want_out[i];
          end
          else if (p_in_type[i] == TAIL || p_in_type[i] == HEADTAIL)
          begin
            route_active[i] <= 1'b0;
          end
        end
      end
      for (j = 0; j < 5; j = j + 1)
      begin
        if (grant_valid[j] && out_ready[j])
          rr_ptr[j] <= grant_slot[j] + 2'd1;
      end
    end
  end


endmodule
