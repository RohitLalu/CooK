//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Wed Oct 28 15:07:23 2026
//Host        : LAPTOP-0O737P11 running 64-bit major release  (build 9200)
//Command     : generate_target cook_gw_sim_wrapper.bd
//Design      : cook_gw_sim_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module cook_gw_sim_wrapper
   (clk50,
    dma_ctrl_araddr,
    dma_ctrl_arready,
    dma_ctrl_arvalid,
    dma_ctrl_awaddr,
    dma_ctrl_awready,
    dma_ctrl_awvalid,
    dma_ctrl_bready,
    dma_ctrl_bresp,
    dma_ctrl_bvalid,
    dma_ctrl_rdata,
    dma_ctrl_rready,
    dma_ctrl_rresp,
    dma_ctrl_rvalid,
    dma_ctrl_wdata,
    dma_ctrl_wready,
    dma_ctrl_wvalid,
    mm2s_axis_tdata,
    mm2s_axis_tkeep,
    mm2s_axis_tlast,
    mm2s_axis_tready,
    mm2s_axis_tvalid,
    mm2s_introut,
    rst_n,
    s2mm_axis_tdata,
    s2mm_axis_tkeep,
    s2mm_axis_tlast,
    s2mm_axis_tready,
    s2mm_axis_tvalid,
    s2mm_introut);
  input clk50;
  input [9:0]dma_ctrl_araddr;
  output dma_ctrl_arready;
  input dma_ctrl_arvalid;
  input [9:0]dma_ctrl_awaddr;
  output dma_ctrl_awready;
  input dma_ctrl_awvalid;
  input dma_ctrl_bready;
  output [1:0]dma_ctrl_bresp;
  output dma_ctrl_bvalid;
  output [31:0]dma_ctrl_rdata;
  input dma_ctrl_rready;
  output [1:0]dma_ctrl_rresp;
  output dma_ctrl_rvalid;
  input [31:0]dma_ctrl_wdata;
  output dma_ctrl_wready;
  input dma_ctrl_wvalid;
  output [31:0]mm2s_axis_tdata;
  output [3:0]mm2s_axis_tkeep;
  output mm2s_axis_tlast;
  input mm2s_axis_tready;
  output mm2s_axis_tvalid;
  output mm2s_introut;
  input rst_n;
  input [31:0]s2mm_axis_tdata;
  input [3:0]s2mm_axis_tkeep;
  input s2mm_axis_tlast;
  output s2mm_axis_tready;
  input s2mm_axis_tvalid;
  output s2mm_introut;

  wire clk50;
  wire [9:0]dma_ctrl_araddr;
  wire dma_ctrl_arready;
  wire dma_ctrl_arvalid;
  wire [9:0]dma_ctrl_awaddr;
  wire dma_ctrl_awready;
  wire dma_ctrl_awvalid;
  wire dma_ctrl_bready;
  wire [1:0]dma_ctrl_bresp;
  wire dma_ctrl_bvalid;
  wire [31:0]dma_ctrl_rdata;
  wire dma_ctrl_rready;
  wire [1:0]dma_ctrl_rresp;
  wire dma_ctrl_rvalid;
  wire [31:0]dma_ctrl_wdata;
  wire dma_ctrl_wready;
  wire dma_ctrl_wvalid;
  wire [31:0]mm2s_axis_tdata;
  wire [3:0]mm2s_axis_tkeep;
  wire mm2s_axis_tlast;
  wire mm2s_axis_tready;
  wire mm2s_axis_tvalid;
  wire mm2s_introut;
  wire rst_n;
  wire [31:0]s2mm_axis_tdata;
  wire [3:0]s2mm_axis_tkeep;
  wire s2mm_axis_tlast;
  wire s2mm_axis_tready;
  wire s2mm_axis_tvalid;
  wire s2mm_introut;

  cook_gw_sim cook_gw_sim_i
       (.clk50(clk50),
        .dma_ctrl_araddr(dma_ctrl_araddr),
        .dma_ctrl_arready(dma_ctrl_arready),
        .dma_ctrl_arvalid(dma_ctrl_arvalid),
        .dma_ctrl_awaddr(dma_ctrl_awaddr),
        .dma_ctrl_awready(dma_ctrl_awready),
        .dma_ctrl_awvalid(dma_ctrl_awvalid),
        .dma_ctrl_bready(dma_ctrl_bready),
        .dma_ctrl_bresp(dma_ctrl_bresp),
        .dma_ctrl_bvalid(dma_ctrl_bvalid),
        .dma_ctrl_rdata(dma_ctrl_rdata),
        .dma_ctrl_rready(dma_ctrl_rready),
        .dma_ctrl_rresp(dma_ctrl_rresp),
        .dma_ctrl_rvalid(dma_ctrl_rvalid),
        .dma_ctrl_wdata(dma_ctrl_wdata),
        .dma_ctrl_wready(dma_ctrl_wready),
        .dma_ctrl_wvalid(dma_ctrl_wvalid),
        .mm2s_axis_tdata(mm2s_axis_tdata),
        .mm2s_axis_tkeep(mm2s_axis_tkeep),
        .mm2s_axis_tlast(mm2s_axis_tlast),
        .mm2s_axis_tready(mm2s_axis_tready),
        .mm2s_axis_tvalid(mm2s_axis_tvalid),
        .mm2s_introut(mm2s_introut),
        .rst_n(rst_n),
        .s2mm_axis_tdata(s2mm_axis_tdata),
        .s2mm_axis_tkeep(s2mm_axis_tkeep),
        .s2mm_axis_tlast(s2mm_axis_tlast),
        .s2mm_axis_tready(s2mm_axis_tready),
        .s2mm_axis_tvalid(s2mm_axis_tvalid),
        .s2mm_introut(s2mm_introut));
endmodule
