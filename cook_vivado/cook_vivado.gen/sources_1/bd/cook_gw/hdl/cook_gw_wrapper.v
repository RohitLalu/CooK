//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Wed Oct 28 15:06:46 2026
//Host        : LAPTOP-0O737P11 running 64-bit major release  (build 9200)
//Command     : generate_target cook_gw_wrapper.bd
//Design      : cook_gw_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module cook_gw_wrapper
   (clk200,
    clk50,
    ddr2_sdram_addr,
    ddr2_sdram_ba,
    ddr2_sdram_cas_n,
    ddr2_sdram_ck_n,
    ddr2_sdram_ck_p,
    ddr2_sdram_cke,
    ddr2_sdram_cs_n,
    ddr2_sdram_dm,
    ddr2_sdram_dq,
    ddr2_sdram_dqs_n,
    ddr2_sdram_dqs_p,
    ddr2_sdram_odt,
    ddr2_sdram_ras_n,
    ddr2_sdram_we_n,
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
    init_calib_complete,
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
  input clk200;
  input clk50;
  output [12:0]ddr2_sdram_addr;
  output [2:0]ddr2_sdram_ba;
  output ddr2_sdram_cas_n;
  output [0:0]ddr2_sdram_ck_n;
  output [0:0]ddr2_sdram_ck_p;
  output [0:0]ddr2_sdram_cke;
  output [0:0]ddr2_sdram_cs_n;
  output [1:0]ddr2_sdram_dm;
  inout [15:0]ddr2_sdram_dq;
  inout [1:0]ddr2_sdram_dqs_n;
  inout [1:0]ddr2_sdram_dqs_p;
  output [0:0]ddr2_sdram_odt;
  output ddr2_sdram_ras_n;
  output ddr2_sdram_we_n;
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
  output init_calib_complete;
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

  wire clk200;
  wire clk50;
  wire [12:0]ddr2_sdram_addr;
  wire [2:0]ddr2_sdram_ba;
  wire ddr2_sdram_cas_n;
  wire [0:0]ddr2_sdram_ck_n;
  wire [0:0]ddr2_sdram_ck_p;
  wire [0:0]ddr2_sdram_cke;
  wire [0:0]ddr2_sdram_cs_n;
  wire [1:0]ddr2_sdram_dm;
  wire [15:0]ddr2_sdram_dq;
  wire [1:0]ddr2_sdram_dqs_n;
  wire [1:0]ddr2_sdram_dqs_p;
  wire [0:0]ddr2_sdram_odt;
  wire ddr2_sdram_ras_n;
  wire ddr2_sdram_we_n;
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
  wire init_calib_complete;
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

  cook_gw cook_gw_i
       (.clk200(clk200),
        .clk50(clk50),
        .ddr2_sdram_addr(ddr2_sdram_addr),
        .ddr2_sdram_ba(ddr2_sdram_ba),
        .ddr2_sdram_cas_n(ddr2_sdram_cas_n),
        .ddr2_sdram_ck_n(ddr2_sdram_ck_n),
        .ddr2_sdram_ck_p(ddr2_sdram_ck_p),
        .ddr2_sdram_cke(ddr2_sdram_cke),
        .ddr2_sdram_cs_n(ddr2_sdram_cs_n),
        .ddr2_sdram_dm(ddr2_sdram_dm),
        .ddr2_sdram_dq(ddr2_sdram_dq),
        .ddr2_sdram_dqs_n(ddr2_sdram_dqs_n),
        .ddr2_sdram_dqs_p(ddr2_sdram_dqs_p),
        .ddr2_sdram_odt(ddr2_sdram_odt),
        .ddr2_sdram_ras_n(ddr2_sdram_ras_n),
        .ddr2_sdram_we_n(ddr2_sdram_we_n),
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
        .init_calib_complete(init_calib_complete),
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
