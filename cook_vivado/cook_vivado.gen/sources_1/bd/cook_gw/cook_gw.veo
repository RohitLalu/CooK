// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: amd.com:blockdesign:cook_gw:1.0

// The following must be inserted into your Verilog file for this
// module to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

// INST_TAG     ------ Begin cut for INSTANTIATION Template ------
cook_gw your_instance_name (
  .clk50(clk50), // input wire clk50
  .rst_n(rst_n), // input wire rst_n
  .mm2s_introut(mm2s_introut), // output wire mm2s_introut
  .s2mm_introut(s2mm_introut), // output wire s2mm_introut
  .dma_ctrl_araddr(dma_ctrl_araddr), // input wire [9:0] dma_ctrl_araddr
  .dma_ctrl_arready(dma_ctrl_arready), // output wire dma_ctrl_arready
  .dma_ctrl_arvalid(dma_ctrl_arvalid), // input wire dma_ctrl_arvalid
  .dma_ctrl_awaddr(dma_ctrl_awaddr), // input wire [9:0] dma_ctrl_awaddr
  .dma_ctrl_awready(dma_ctrl_awready), // output wire dma_ctrl_awready
  .dma_ctrl_awvalid(dma_ctrl_awvalid), // input wire dma_ctrl_awvalid
  .dma_ctrl_bready(dma_ctrl_bready), // input wire dma_ctrl_bready
  .dma_ctrl_bresp(dma_ctrl_bresp), // output wire [1:0] dma_ctrl_bresp
  .dma_ctrl_bvalid(dma_ctrl_bvalid), // output wire dma_ctrl_bvalid
  .dma_ctrl_rdata(dma_ctrl_rdata), // output wire [31:0] dma_ctrl_rdata
  .dma_ctrl_rready(dma_ctrl_rready), // input wire dma_ctrl_rready
  .dma_ctrl_rresp(dma_ctrl_rresp), // output wire [1:0] dma_ctrl_rresp
  .dma_ctrl_rvalid(dma_ctrl_rvalid), // output wire dma_ctrl_rvalid
  .dma_ctrl_wdata(dma_ctrl_wdata), // input wire [31:0] dma_ctrl_wdata
  .dma_ctrl_wready(dma_ctrl_wready), // output wire dma_ctrl_wready
  .dma_ctrl_wvalid(dma_ctrl_wvalid), // input wire dma_ctrl_wvalid
  .mm2s_axis_tdata(mm2s_axis_tdata), // output wire [31:0] mm2s_axis_tdata
  .mm2s_axis_tkeep(mm2s_axis_tkeep), // output wire [3:0] mm2s_axis_tkeep
  .mm2s_axis_tlast(mm2s_axis_tlast), // output wire mm2s_axis_tlast
  .mm2s_axis_tready(mm2s_axis_tready), // input wire mm2s_axis_tready
  .mm2s_axis_tvalid(mm2s_axis_tvalid), // output wire mm2s_axis_tvalid
  .s2mm_axis_tdata(s2mm_axis_tdata), // input wire [31:0] s2mm_axis_tdata
  .s2mm_axis_tkeep(s2mm_axis_tkeep), // input wire [3:0] s2mm_axis_tkeep
  .s2mm_axis_tlast(s2mm_axis_tlast), // input wire s2mm_axis_tlast
  .s2mm_axis_tready(s2mm_axis_tready), // output wire s2mm_axis_tready
  .s2mm_axis_tvalid(s2mm_axis_tvalid), // input wire s2mm_axis_tvalid
  .clk200(clk200), // input wire clk200
  .init_calib_complete(init_calib_complete), // output wire init_calib_complete
  .ddr2_sdram_dq(ddr2_sdram_dq), // inout wire [15:0] ddr2_sdram_dq
  .ddr2_sdram_dqs_p(ddr2_sdram_dqs_p), // inout wire [1:0] ddr2_sdram_dqs_p
  .ddr2_sdram_dqs_n(ddr2_sdram_dqs_n), // inout wire [1:0] ddr2_sdram_dqs_n
  .ddr2_sdram_addr(ddr2_sdram_addr), // output wire [12:0] ddr2_sdram_addr
  .ddr2_sdram_ba(ddr2_sdram_ba), // output wire [2:0] ddr2_sdram_ba
  .ddr2_sdram_ras_n(ddr2_sdram_ras_n), // output wire ddr2_sdram_ras_n
  .ddr2_sdram_cas_n(ddr2_sdram_cas_n), // output wire ddr2_sdram_cas_n
  .ddr2_sdram_we_n(ddr2_sdram_we_n), // output wire ddr2_sdram_we_n
  .ddr2_sdram_ck_p(ddr2_sdram_ck_p), // output wire [0:0] ddr2_sdram_ck_p
  .ddr2_sdram_ck_n(ddr2_sdram_ck_n), // output wire [0:0] ddr2_sdram_ck_n
  .ddr2_sdram_cke(ddr2_sdram_cke), // output wire [0:0] ddr2_sdram_cke
  .ddr2_sdram_cs_n(ddr2_sdram_cs_n), // output wire [0:0] ddr2_sdram_cs_n
  .ddr2_sdram_dm(ddr2_sdram_dm), // output wire [1:0] ddr2_sdram_dm
  .ddr2_sdram_odt(ddr2_sdram_odt) // output wire [0:0] ddr2_sdram_odt
);
// INST_TAG_END ------  End cut for INSTANTIATION Template  ------

// You must compile the wrapper file cook_gw.v when simulating
// the module, cook_gw. When compiling the wrapper file, be sure to
// reference the Verilog simulation library.
