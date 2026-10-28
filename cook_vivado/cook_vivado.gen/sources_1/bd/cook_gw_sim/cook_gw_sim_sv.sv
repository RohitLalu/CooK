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

// MODULE VLNV: amd.com:blockdesign:cook_gw_sim:1.0

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module cook_gw_sim_sv (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl" *)
  (* X_INTERFACE_MODE = "slave dma_ctrl" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME dma_ctrl, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ 50000000, ID_WIDTH 0, ADDR_WIDTH 16, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 0, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 1, PHASE 0.0, CLK_DOMAIN cook_gw_sim_clk50, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_axi4_lite_v1_0.slave dma_ctrl,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis" *)
  (* X_INTERFACE_MODE = "master mm2s_axis" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME mm2s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN cook_gw_sim_clk50, LAYERED_METADATA undef, INSERT_VIP 0" *)
  vivado_axis_v1_0.master mm2s_axis,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis" *)
  (* X_INTERFACE_MODE = "slave s2mm_axis" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s2mm_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN cook_gw_sim_clk50, LAYERED_METADATA undef, INSERT_VIP 0" *)
  vivado_axis_v1_0.slave s2mm_axis,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire clk50,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire rst_n,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire mm2s_introut,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire s2mm_introut
);

  // interface wire assignments
  assign mm2s_axis.TDEST = 0;
  assign mm2s_axis.TID = 0;
  assign mm2s_axis.TSTRB = 0;
  assign mm2s_axis.TUSER = 0;

  cook_gw_sim inst (
    .clk50(clk50),
    .rst_n(rst_n),
    .mm2s_introut(mm2s_introut),
    .s2mm_introut(s2mm_introut),
    .dma_ctrl_araddr(dma_ctrl.ARADDR),
    .dma_ctrl_arready(dma_ctrl.ARREADY),
    .dma_ctrl_arvalid(dma_ctrl.ARVALID),
    .dma_ctrl_awaddr(dma_ctrl.AWADDR),
    .dma_ctrl_awready(dma_ctrl.AWREADY),
    .dma_ctrl_awvalid(dma_ctrl.AWVALID),
    .dma_ctrl_bready(dma_ctrl.BREADY),
    .dma_ctrl_bresp(dma_ctrl.BRESP),
    .dma_ctrl_bvalid(dma_ctrl.BVALID),
    .dma_ctrl_rdata(dma_ctrl.RDATA),
    .dma_ctrl_rready(dma_ctrl.RREADY),
    .dma_ctrl_rresp(dma_ctrl.RRESP),
    .dma_ctrl_rvalid(dma_ctrl.RVALID),
    .dma_ctrl_wdata(dma_ctrl.WDATA),
    .dma_ctrl_wready(dma_ctrl.WREADY),
    .dma_ctrl_wvalid(dma_ctrl.WVALID),
    .mm2s_axis_tdata(mm2s_axis.TDATA),
    .mm2s_axis_tkeep(mm2s_axis.TKEEP),
    .mm2s_axis_tlast(mm2s_axis.TLAST),
    .mm2s_axis_tready(mm2s_axis.TREADY),
    .mm2s_axis_tvalid(mm2s_axis.TVALID),
    .s2mm_axis_tdata(s2mm_axis.TDATA),
    .s2mm_axis_tkeep(s2mm_axis.TKEEP),
    .s2mm_axis_tlast(s2mm_axis.TLAST),
    .s2mm_axis_tready(s2mm_axis.TREADY),
    .s2mm_axis_tvalid(s2mm_axis.TVALID)
  );

endmodule
