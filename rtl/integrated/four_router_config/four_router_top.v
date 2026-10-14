// Includes are relative to the repo root; compile with `iverilog -I.` from
// there (the Makefile does this). No absolute paths -- they break on every
// machine except the one that wrote them.

//`include "rtl/router/noc_router.v"
//`include "rtl/router/link_buffer.v"
//`include "rtl/router/end_buff.v"
//`include "rtl/network_interface/address_decoder.v"
//`include "rtl/network_interface/ni.v"
//`include "rtl/core/picorv32.v"

// TODO: need to add BIST module later once the single tile seems to work fine

module four_router_top #(
    parameter DX_W   = 4,
    parameter DY_W   = 4,
    parameter DATA_W = 32,
    parameter TOTAL_ROUTERS = 4
  )(
    input clk,
    input rst_n,
    output wire [3:0] tile_trap   // one per tile -- bring these out to LEDs
  );

  localparam N = 0, S = 1, E = 2, W = 3, L = 4;


  // ---- per-tile core wires (picorv32 native memory interface) ----
  wire        r00_mem_valid, r00_mem_instr, r00_mem_ready;
  wire [31:0] r00_mem_addr, r00_mem_wdata, r00_mem_rdata;
  wire [ 3:0] r00_mem_wstrb;
  wire        r10_mem_valid, r10_mem_instr, r10_mem_ready;
  wire [31:0] r10_mem_addr, r10_mem_wdata, r10_mem_rdata;
  wire [ 3:0] r10_mem_wstrb;
  wire        r01_mem_valid, r01_mem_instr, r01_mem_ready;
  wire [31:0] r01_mem_addr, r01_mem_wdata, r01_mem_rdata;
  wire [ 3:0] r01_mem_wstrb;
  wire        r11_mem_valid, r11_mem_instr, r11_mem_ready;
  wire [31:0] r11_mem_addr, r11_mem_wdata, r11_mem_rdata;
  wire [ 3:0] r11_mem_wstrb;

  // r00 ROUTER CODE:1
  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] to_r00_in_router_code_flit;
  wire [4:0] to_r00_in_valid, to_r00_in_ready;
  wire [9:0] to_r00_in_type;
  wire [5*DX_W-1:0] to_r00_in_dx;
  wire [5*DY_W-1:0] to_r00_in_dy;
  wire [5*DATA_W-1:0] to_r00_in_data;

  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] from_r00_out_router_code_flit;
  wire [4:0] from_r00_out_valid, from_r00_out_ready;
  wire [9:0] from_r00_out_type;
  wire [5*DX_W-1:0] from_r00_out_dx;
  wire [5*DY_W-1:0] from_r00_out_dy;
  wire [5*DATA_W-1:0] from_r00_out_data;

  noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(0),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00 (
               .clk(clk), .rst_n(rst_n),
               .in_router_code_flit(to_r00_in_router_code_flit),
               .in_valid(to_r00_in_valid), .in_ready(to_r00_in_ready), .in_type(to_r00_in_type),
               .in_dx(to_r00_in_dx), .in_dy(to_r00_in_dy), .in_data(to_r00_in_data),
               .out_router_code_flit(from_r00_out_router_code_flit),
               .out_valid(from_r00_out_valid), .out_ready(from_r00_out_ready), .out_type(from_r00_out_type),
               .out_dx(from_r00_out_dx), .out_dy(from_r00_out_dy), .out_data(from_r00_out_data)
             );

  // r01 ROUTER CODE: 2
  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] to_r01_in_router_code_flit;
  wire [4:0] to_r01_in_valid, to_r01_in_ready;
  wire [9:0] to_r01_in_type;
  wire [5*DX_W-1:0] to_r01_in_dx;
  wire [5*DY_W-1:0] to_r01_in_dy;
  wire [5*DATA_W-1:0] to_r01_in_data;

  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] from_r01_out_router_code_flit;
  wire [4:0] from_r01_out_valid, from_r01_out_ready;
  wire [9:0] from_r01_out_type;
  wire [5*DX_W-1:0] from_r01_out_dx;
  wire [5*DY_W-1:0] from_r01_out_dy;
  wire [5*DATA_W-1:0] from_r01_out_data;

  noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(2),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01 (
               .clk(clk), .rst_n(rst_n),
               .in_router_code_flit(to_r01_in_router_code_flit),
               .in_valid(to_r01_in_valid), .in_ready(to_r01_in_ready), .in_type(to_r01_in_type),
               .in_dx(to_r01_in_dx), .in_dy(to_r01_in_dy), .in_data(to_r01_in_data),
               .out_router_code_flit(from_r01_out_router_code_flit),
               .out_valid(from_r01_out_valid), .out_ready(from_r01_out_ready), .out_type(from_r01_out_type),
               .out_dx(from_r01_out_dx), .out_dy(from_r01_out_dy), .out_data(from_r01_out_data)
             );


  // r10 ROUTER CODE: 3
  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] to_r10_in_router_code_flit;
  wire [4:0] to_r10_in_valid, to_r10_in_ready;
  wire [9:0] to_r10_in_type;
  wire [5*DX_W-1:0] to_r10_in_dx;
  wire [5*DY_W-1:0] to_r10_in_dy;
  wire [5*DATA_W-1:0] to_r10_in_data;

  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] from_r10_out_router_code_flit;
  wire [4:0] from_r10_out_valid, from_r10_out_ready;
  wire [9:0] from_r10_out_type;
  wire [5*DX_W-1:0] from_r10_out_dx;
  wire [5*DY_W-1:0] from_r10_out_dy;
  wire [5*DATA_W-1:0] from_r10_out_data;

  noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(1),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10 (
               .clk(clk), .rst_n(rst_n),
               .in_router_code_flit(to_r10_in_router_code_flit),
               .in_valid(to_r10_in_valid), .in_ready(to_r10_in_ready), .in_type(to_r10_in_type),
               .in_dx(to_r10_in_dx), .in_dy(to_r10_in_dy), .in_data(to_r10_in_data),
               .out_router_code_flit(from_r10_out_router_code_flit),
               .out_valid(from_r10_out_valid), .out_ready(from_r10_out_ready), .out_type(from_r10_out_type),
               .out_dx(from_r10_out_dx), .out_dy(from_r10_out_dy), .out_data(from_r10_out_data)
             );

  // r11 ROUTER CODE: 4
  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] to_r11_in_router_code_flit;
  wire [4:0] to_r11_in_valid, to_r11_in_ready;
  wire [9:0] to_r11_in_type;
  wire [5*DX_W-1:0] to_r11_in_dx;
  wire [5*DY_W-1:0] to_r11_in_dy;
  wire [5*DATA_W-1:0] to_r11_in_data;

  wire [5*($clog2(TOTAL_ROUTERS)+1)-1:0] from_r11_out_router_code_flit;
  wire [4:0] from_r11_out_valid, from_r11_out_ready;
  wire [9:0] from_r11_out_type;
  wire [5*DX_W-1:0] from_r11_out_dx;
  wire [5*DY_W-1:0] from_r11_out_dy;
  wire [5*DATA_W-1:0] from_r11_out_data;

  noc_router #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(3),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11 (
               .clk(clk), .rst_n(rst_n),
               .in_router_code_flit(to_r11_in_router_code_flit),
               .in_valid(to_r11_in_valid), .in_ready(to_r11_in_ready), .in_type(to_r11_in_type),
               .in_dx(to_r11_in_dx), .in_dy(to_r11_in_dy), .in_data(to_r11_in_data),
               .out_router_code_flit(from_r11_out_router_code_flit),
               .out_valid(from_r11_out_valid), .out_ready(from_r11_out_ready), .out_type(from_r11_out_type),
               .out_dx(from_r11_out_dx), .out_dy(from_r11_out_dy), .out_data(from_r11_out_data)
             );


  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00_to_r01_s_n (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r00_out_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r00_out_valid[S]), .in_ready(from_r00_out_ready[S]), .in_type(from_r00_out_type[2*S+1:2*S]),
                .in_dx(from_r00_out_dx[(S+1)*DX_W-1:S*DX_W]), .in_dy(from_r00_out_dy[(S+1)*DY_W-1:S*DY_W]), .in_data(from_r00_out_data[(S+1)*DATA_W-1:S*DATA_W]),
                .out_router_code_flit(to_r01_in_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r01_in_valid[N]), .out_ready(to_r01_in_ready[N]), .out_type(to_r01_in_type[2*N+1:2*N]),
                .out_dx(to_r01_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r01_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r01_in_data[(N+1)*DATA_W-1:N*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01_to_r00_n_s (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r01_out_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r01_out_valid[N]), .in_ready(from_r01_out_ready[N]), .in_type(from_r01_out_type[2*N+1:2*N]),
                .in_dx(from_r01_out_dx[(N+1)*DX_W-1:N*DX_W]), .in_dy(from_r01_out_dy[(N+1)*DY_W-1:N*DY_W]), .in_data(from_r01_out_data[(N+1)*DATA_W-1:N*DATA_W]),
                .out_router_code_flit(to_r00_in_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r00_in_valid[S]), .out_ready(to_r00_in_ready[S]), .out_type(to_r00_in_type[2*S+1:2*S]),
                .out_dx(to_r00_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r00_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r00_in_data[(S+1)*DATA_W-1:S*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10_to_r11_s_n (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r10_out_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r10_out_valid[S]), .in_ready(from_r10_out_ready[S]), .in_type(from_r10_out_type[2*S+1:2*S]),
                .in_dx(from_r10_out_dx[(S+1)*DX_W-1:S*DX_W]), .in_dy(from_r10_out_dy[(S+1)*DY_W-1:S*DY_W]), .in_data(from_r10_out_data[(S+1)*DATA_W-1:S*DATA_W]),
                .out_router_code_flit(to_r11_in_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r11_in_valid[N]), .out_ready(to_r11_in_ready[N]), .out_type(to_r11_in_type[2*N+1:2*N]),
                .out_dx(to_r11_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r11_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r11_in_data[(N+1)*DATA_W-1:N*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11_to_r10_n_s (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r11_out_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r11_out_valid[N]), .in_ready(from_r11_out_ready[N]), .in_type(from_r11_out_type[2*N+1:2*N]),
                .in_dx(from_r11_out_dx[(N+1)*DX_W-1:N*DX_W]), .in_dy(from_r11_out_dy[(N+1)*DY_W-1:N*DY_W]), .in_data(from_r11_out_data[(N+1)*DATA_W-1:N*DATA_W]),
                .out_router_code_flit(to_r10_in_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r10_in_valid[S]), .out_ready(to_r10_in_ready[S]), .out_type(to_r10_in_type[2*S+1:2*S]),
                .out_dx(to_r10_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r10_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r10_in_data[(S+1)*DATA_W-1:S*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00_to_r10_e_w (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r00_out_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r00_out_valid[E]), .in_ready(from_r00_out_ready[E]), .in_type(from_r00_out_type[2*E+1:2*E]),
                .in_dx(from_r00_out_dx[(E+1)*DX_W-1:E*DX_W]), .in_dy(from_r00_out_dy[(E+1)*DY_W-1:E*DY_W]), .in_data(from_r00_out_data[(E+1)*DATA_W-1:E*DATA_W]),
                .out_router_code_flit(to_r10_in_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r10_in_valid[W]), .out_ready(to_r10_in_ready[W]), .out_type(to_r10_in_type[2*W+1:2*W]),
                .out_dx(to_r10_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r10_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r10_in_data[(W+1)*DATA_W-1:W*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10_to_r00_w_e (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r10_out_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r10_out_valid[W]), .in_ready(from_r10_out_ready[W]), .in_type(from_r10_out_type[2*W+1:2*W]),
                .in_dx(from_r10_out_dx[(W+1)*DX_W-1:W*DX_W]), .in_dy(from_r10_out_dy[(W+1)*DY_W-1:W*DY_W]), .in_data(from_r10_out_data[(W+1)*DATA_W-1:W*DATA_W]),
                .out_router_code_flit(to_r00_in_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r00_in_valid[E]), .out_ready(to_r00_in_ready[E]), .out_type(to_r00_in_type[2*E+1:2*E]),
                .out_dx(to_r00_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r00_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r00_in_data[(E+1)*DATA_W-1:E*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01_to_r11_e_w (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r01_out_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r01_out_valid[E]), .in_ready(from_r01_out_ready[E]), .in_type(from_r01_out_type[2*E+1:2*E]),
                .in_dx(from_r01_out_dx[(E+1)*DX_W-1:E*DX_W]), .in_dy(from_r01_out_dy[(E+1)*DY_W-1:E*DY_W]), .in_data(from_r01_out_data[(E+1)*DATA_W-1:E*DATA_W]),
                .out_router_code_flit(to_r11_in_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r11_in_valid[W]), .out_ready(to_r11_in_ready[W]), .out_type(to_r11_in_type[2*W+1:2*W]),
                .out_dx(to_r11_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r11_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r11_in_data[(W+1)*DATA_W-1:W*DATA_W])
              );

  link_buffer #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11_to_r01_w_e (
                .clk(clk), .rst_n(rst_n),
                .in_router_code_flit(from_r11_out_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
                .in_valid(from_r11_out_valid[W]), .in_ready(from_r11_out_ready[W]), .in_type(from_r11_out_type[2*W+1:2*W]),
                .in_dx(from_r11_out_dx[(W+1)*DX_W-1:W*DX_W]), .in_dy(from_r11_out_dy[(W+1)*DY_W-1:W*DY_W]), .in_data(from_r11_out_data[(W+1)*DATA_W-1:W*DATA_W]),
                .out_router_code_flit(to_r01_in_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
                .out_valid(to_r01_in_valid[E]), .out_ready(to_r01_in_ready[E]), .out_type(to_r01_in_type[2*E+1:2*E]),
                .out_dx(to_r01_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r01_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r01_in_data[(E+1)*DATA_W-1:E*DATA_W])
              );


  // WHEN ADDING BIST, REPLACE END BUFFERS AS AND WHEN REQUIRED. for now added only end buffers for all

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00_n (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r00_in_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r00_in_valid[N]), .out_ready(from_r00_out_ready[N]), .out_type(to_r00_in_type[2*N+1:2*N]),
               .out_dx(to_r00_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r00_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r00_in_data[(N+1)*DATA_W-1:N*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00_w (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r00_in_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r00_in_valid[W]), .out_ready(from_r00_out_ready[W]), .out_type(to_r00_in_type[2*W+1:2*W]),
               .out_dx(to_r00_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r00_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r00_in_data[(W+1)*DATA_W-1:W*DATA_W])
             );


  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01_s (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r01_in_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r01_in_valid[S]), .out_ready(from_r01_out_ready[S]), .out_type(to_r01_in_type[2*S+1:2*S]),
               .out_dx(to_r01_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r01_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r01_in_data[(S+1)*DATA_W-1:S*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01_w (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r01_in_router_code_flit[(W+1)*($clog2(TOTAL_ROUTERS)+1)-1:W*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r01_in_valid[W]), .out_ready(from_r01_out_ready[W]), .out_type(to_r01_in_type[2*W+1:2*W]),
               .out_dx(to_r01_in_dx[(W+1)*DX_W-1:W*DX_W]), .out_dy(to_r01_in_dy[(W+1)*DY_W-1:W*DY_W]), .out_data(to_r01_in_data[(W+1)*DATA_W-1:W*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10_n (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r10_in_router_code_flit[(N+1)*($clog2(TOTAL_ROUTERS)+1)-1:N*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r10_in_valid[N]), .out_ready(from_r10_out_ready[N]), .out_type(to_r10_in_type[2*N+1:2*N]),
               .out_dx(to_r10_in_dx[(N+1)*DX_W-1:N*DX_W]), .out_dy(to_r10_in_dy[(N+1)*DY_W-1:N*DY_W]), .out_data(to_r10_in_data[(N+1)*DATA_W-1:N*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10_e (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r10_in_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r10_in_valid[E]), .out_ready(from_r10_out_ready[E]), .out_type(to_r10_in_type[2*E+1:2*E]),
               .out_dx(to_r10_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r10_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r10_in_data[(E+1)*DATA_W-1:E*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11_s (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r11_in_router_code_flit[(S+1)*($clog2(TOTAL_ROUTERS)+1)-1:S*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r11_in_valid[S]), .out_ready(from_r11_out_ready[S]), .out_type(to_r11_in_type[2*S+1:2*S]),
               .out_dx(to_r11_in_dx[(S+1)*DX_W-1:S*DX_W]), .out_dy(to_r11_in_dy[(S+1)*DY_W-1:S*DY_W]), .out_data(to_r11_in_data[(S+1)*DATA_W-1:S*DATA_W])
             );

  end_buff #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11_e (
               .clk(clk), .rst_n(rst_n),
               .out_router_code_flit(to_r11_in_router_code_flit[(E+1)*($clog2(TOTAL_ROUTERS)+1)-1:E*($clog2(TOTAL_ROUTERS)+1)]),
               .out_valid(to_r11_in_valid[E]), .out_ready(from_r11_out_ready[E]), .out_type(to_r11_in_type[2*E+1:2*E]),
               .out_dx(to_r11_in_dx[(E+1)*DX_W-1:E*DX_W]), .out_dy(to_r11_in_dy[(E+1)*DY_W-1:E*DY_W]), .out_data(to_r11_in_data[(E+1)*DATA_W-1:E*DATA_W])
             );

  //TODO: ADD NI

  ni #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(0),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r00_ni (
       .clk(clk), .rst_n(rst_n),
       .mem_valid(r00_mem_valid), .mem_instr(r00_mem_instr), .mem_ready(r00_mem_ready),
       .mem_addr(r00_mem_addr), .mem_wdata(r00_mem_wdata), .mem_wstrb(r00_mem_wstrb),
       .mem_rdata(r00_mem_rdata),
       .in_router_code_flit(from_r00_out_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .in_valid(from_r00_out_valid[L]), .in_ready(from_r00_out_ready[L]), .in_type(from_r00_out_type[2*L+1:2*L]),
       .in_dx(from_r00_out_dx[(L+1)*DX_W-1:L*DX_W]), .in_dy(from_r00_out_dy[(L+1)*DY_W-1:L*DY_W]), .in_data(from_r00_out_data[(L+1)*DATA_W-1:L*DATA_W]),
       .out_router_code_flit(to_r00_in_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .out_valid(to_r00_in_valid[L]), .out_ready(to_r00_in_ready[L]), .out_type(to_r00_in_type[2*L+1:2*L]),
       .out_dx(to_r00_in_dx[(L+1)*DX_W-1:L*DX_W]), .out_dy(to_r00_in_dy[(L+1)*DY_W-1:L*DY_W]), .out_data(to_r00_in_data[(L+1)*DATA_W-1:L*DATA_W])

       // MAY NEED TO ADD EXTRA PORTS HERE
     );

  ni #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(2),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r01_ni (
       .clk(clk), .rst_n(rst_n),
       .mem_valid(r01_mem_valid), .mem_instr(r01_mem_instr), .mem_ready(r01_mem_ready),
       .mem_addr(r01_mem_addr), .mem_wdata(r01_mem_wdata), .mem_wstrb(r01_mem_wstrb),
       .mem_rdata(r01_mem_rdata),
       .in_router_code_flit(from_r01_out_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .in_valid(from_r01_out_valid[L]), .in_ready(from_r01_out_ready[L]), .in_type(from_r01_out_type[2*L+1:2*L]),
       .in_dx(from_r01_out_dx[(L+1)*DX_W-1:L*DX_W]), .in_dy(from_r01_out_dy[(L+1)*DY_W-1:L*DY_W]), .in_data(from_r01_out_data[(L+1)*DATA_W-1:L*DATA_W]),
       .out_router_code_flit(to_r01_in_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .out_valid(to_r01_in_valid[L]), .out_ready(to_r01_in_ready[L]), .out_type(to_r01_in_type[2*L+1:2*L]),
       .out_dx(to_r01_in_dx[(L+1)*DX_W-1:L*DX_W]), .out_dy(to_r01_in_dy[(L+1)*DY_W-1:L*DY_W]), .out_data(to_r01_in_data[(L+1)*DATA_W-1:L*DATA_W])

       // MAY NEED TO ADD EXTRA PORTS HERE
     );

  ni #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(1),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r10_ni (
       .clk(clk), .rst_n(rst_n),
       .mem_valid(r10_mem_valid), .mem_instr(r10_mem_instr), .mem_ready(r10_mem_ready),
       .mem_addr(r10_mem_addr), .mem_wdata(r10_mem_wdata), .mem_wstrb(r10_mem_wstrb),
       .mem_rdata(r10_mem_rdata),
       .in_router_code_flit(from_r10_out_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .in_valid(from_r10_out_valid[L]), .in_ready(from_r10_out_ready[L]), .in_type(from_r10_out_type[2*L+1:2*L]),
       .in_dx(from_r10_out_dx[(L+1)*DX_W-1:L*DX_W]), .in_dy(from_r10_out_dy[(L+1)*DY_W-1:L*DY_W]), .in_data(from_r10_out_data[(L+1)*DATA_W-1:L*DATA_W]),
       .out_router_code_flit(to_r10_in_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .out_valid(to_r10_in_valid[L]), .out_ready(to_r10_in_ready[L]), .out_type(to_r10_in_type[2*L+1:2*L]),
       .out_dx(to_r10_in_dx[(L+1)*DX_W-1:L*DX_W]), .out_dy(to_r10_in_dy[(L+1)*DY_W-1:L*DY_W]), .out_data(to_r10_in_data[(L+1)*DATA_W-1:L*DATA_W])

       // MAY NEED TO ADD EXTRA PORTS HERE
     );

  ni #(.DX_W(DX_W), .DY_W(DY_W), .DATA_W(DATA_W),.ROUTER_CODE(3),.TOTAL_ROUTERS(TOTAL_ROUTERS)) r11_ni (
       .clk(clk), .rst_n(rst_n),
       .mem_valid(r11_mem_valid), .mem_instr(r11_mem_instr), .mem_ready(r11_mem_ready),
       .mem_addr(r11_mem_addr), .mem_wdata(r11_mem_wdata), .mem_wstrb(r11_mem_wstrb),
       .mem_rdata(r11_mem_rdata),
       .in_router_code_flit(from_r11_out_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .in_valid(from_r11_out_valid[L]), .in_ready(from_r11_out_ready[L]), .in_type(from_r11_out_type[2*L+1:2*L]),
       .in_dx(from_r11_out_dx[(L+1)*DX_W-1:L*DX_W]), .in_dy(from_r11_out_dy[(L+1)*DY_W-1:L*DY_W]), .in_data(from_r11_out_data[(L+1)*DATA_W-1:L*DATA_W]),
       .out_router_code_flit(to_r11_in_router_code_flit[(L+1)*($clog2(TOTAL_ROUTERS)+1)-1:L*($clog2(TOTAL_ROUTERS)+1)]),
       .out_valid(to_r11_in_valid[L]), .out_ready(to_r11_in_ready[L]), .out_type(to_r11_in_type[2*L+1:2*L]),
       .out_dx(to_r11_in_dx[(L+1)*DX_W-1:L*DX_W]), .out_dy(to_r11_in_dy[(L+1)*DY_W-1:L*DY_W]), .out_data(to_r11_in_data[(L+1)*DATA_W-1:L*DATA_W])

       // MAY NEED TO ADD EXTRA PORTS HERE
     );


  // ---- compute cores: one picorv32 per tile ----

  picorv32 #(
      .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
      .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
      .PROGADDR_RESET(32'h00000100),
      .STACKADDR(32'h00001000)
  ) r00_core (
      .clk(clk), .resetn(rst_n), .trap(tile_trap[0]),
      .mem_valid(r00_mem_valid), .mem_instr(r00_mem_instr), .mem_ready(r00_mem_ready),
      .mem_addr(r00_mem_addr), .mem_wdata(r00_mem_wdata), .mem_wstrb(r00_mem_wstrb),
      .mem_rdata(r00_mem_rdata),
      .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
      .irq(32'b0)
  );

  picorv32 #(
      .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
      .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
      .PROGADDR_RESET(32'h00001100),
      .STACKADDR(32'h00002000)
  ) r10_core (
      .clk(clk), .resetn(rst_n), .trap(tile_trap[1]),
      .mem_valid(r10_mem_valid), .mem_instr(r10_mem_instr), .mem_ready(r10_mem_ready),
      .mem_addr(r10_mem_addr), .mem_wdata(r10_mem_wdata), .mem_wstrb(r10_mem_wstrb),
      .mem_rdata(r10_mem_rdata),
      .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
      .irq(32'b0)
  );

  picorv32 #(
      .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
      .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
      .PROGADDR_RESET(32'h00002100),
      .STACKADDR(32'h00003000)
  ) r01_core (
      .clk(clk), .resetn(rst_n), .trap(tile_trap[2]),
      .mem_valid(r01_mem_valid), .mem_instr(r01_mem_instr), .mem_ready(r01_mem_ready),
      .mem_addr(r01_mem_addr), .mem_wdata(r01_mem_wdata), .mem_wstrb(r01_mem_wstrb),
      .mem_rdata(r01_mem_rdata),
      .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
      .irq(32'b0)
  );

  picorv32 #(
      .ENABLE_COUNTERS(0), .ENABLE_MUL(0), .ENABLE_DIV(0), .ENABLE_IRQ(0),
      .COMPRESSED_ISA(0), .BARREL_SHIFTER(0),
      .PROGADDR_RESET(32'h00003100),
      .STACKADDR(32'h00004000)
  ) r11_core (
      .clk(clk), .resetn(rst_n), .trap(tile_trap[3]),
      .mem_valid(r11_mem_valid), .mem_instr(r11_mem_instr), .mem_ready(r11_mem_ready),
      .mem_addr(r11_mem_addr), .mem_wdata(r11_mem_wdata), .mem_wstrb(r11_mem_wstrb),
      .mem_rdata(r11_mem_rdata),
      .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
      .irq(32'b0)
  );

endmodule
