//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Wed Oct 28 15:06:46 2026
//Host        : LAPTOP-0O737P11 running 64-bit major release  (build 9200)
//Command     : generate_target cook_gw.bd
//Design      : cook_gw
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "cook_gw,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=cook_gw,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=5,numReposBlks=5,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "cook_gw.hwdef" *) 
module cook_gw
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
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.CLK200 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.CLK200, CLK_DOMAIN cook_gw_clk200, FREQ_HZ 200000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input clk200;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.CLK50 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.CLK50, ASSOCIATED_BUSIF dma_ctrl:mm2s_axis:s2mm_axis, ASSOCIATED_RESET rst_n, CLK_DOMAIN cook_gw_clk50, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input clk50;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram ADDR" *) (* X_INTERFACE_MODE = "Master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ddr2_sdram, AXI_ARBITRATION_SCHEME TDM, BURST_LENGTH 8, CAN_DEBUG false, CAS_LATENCY 11, CAS_WRITE_LATENCY 11, CS_ENABLED true, DATA_MASK_ENABLED true, DATA_WIDTH 8, MEMORY_TYPE COMPONENTS, MEM_ADDR_MAP ROW_COLUMN_BANK, SLOT Single, TIMEPERIOD_PS 1250" *) output [12:0]ddr2_sdram_addr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram BA" *) output [2:0]ddr2_sdram_ba;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram CAS_N" *) output ddr2_sdram_cas_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram CK_N" *) output [0:0]ddr2_sdram_ck_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram CK_P" *) output [0:0]ddr2_sdram_ck_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram CKE" *) output [0:0]ddr2_sdram_cke;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram CS_N" *) output [0:0]ddr2_sdram_cs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram DM" *) output [1:0]ddr2_sdram_dm;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram DQ" *) inout [15:0]ddr2_sdram_dq;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram DQS_N" *) inout [1:0]ddr2_sdram_dqs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram DQS_P" *) inout [1:0]ddr2_sdram_dqs_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram ODT" *) output [0:0]ddr2_sdram_odt;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram RAS_N" *) output ddr2_sdram_ras_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 ddr2_sdram WE_N" *) output ddr2_sdram_we_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl ARADDR" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME dma_ctrl, ADDR_WIDTH 16, ARUSER_WIDTH 0, AWUSER_WIDTH 0, BUSER_WIDTH 0, CLK_DOMAIN cook_gw_clk50, DATA_WIDTH 32, FREQ_HZ 50000000, HAS_BRESP 1, HAS_BURST 0, HAS_CACHE 0, HAS_LOCK 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0, HAS_RRESP 1, HAS_WSTRB 0, ID_WIDTH 0, INSERT_VIP 0, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_READ_THREADS 1, NUM_WRITE_OUTSTANDING 1, NUM_WRITE_THREADS 1, PHASE 0.0, PROTOCOL AXI4LITE, READ_WRITE_MODE READ_WRITE, RUSER_BITS_PER_BYTE 0, RUSER_WIDTH 0, SUPPORTS_NARROW_BURST 0, WUSER_BITS_PER_BYTE 0, WUSER_WIDTH 0" *) input [9:0]dma_ctrl_araddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl ARREADY" *) output dma_ctrl_arready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl ARVALID" *) input dma_ctrl_arvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl AWADDR" *) input [9:0]dma_ctrl_awaddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl AWREADY" *) output dma_ctrl_awready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl AWVALID" *) input dma_ctrl_awvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl BREADY" *) input dma_ctrl_bready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl BRESP" *) output [1:0]dma_ctrl_bresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl BVALID" *) output dma_ctrl_bvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl RDATA" *) output [31:0]dma_ctrl_rdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl RREADY" *) input dma_ctrl_rready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl RRESP" *) output [1:0]dma_ctrl_rresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl RVALID" *) output dma_ctrl_rvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl WDATA" *) input [31:0]dma_ctrl_wdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl WREADY" *) output dma_ctrl_wready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 dma_ctrl WVALID" *) input dma_ctrl_wvalid;
  output init_calib_complete;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis TDATA" *) (* X_INTERFACE_MODE = "Master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME mm2s_axis, CLK_DOMAIN cook_gw_clk50, FREQ_HZ 50000000, HAS_TKEEP 1, HAS_TLAST 1, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) output [31:0]mm2s_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis TKEEP" *) output [3:0]mm2s_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis TLAST" *) output mm2s_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis TREADY" *) input mm2s_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 mm2s_axis TVALID" *) output mm2s_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 INTR.MM2S_INTROUT INTERRUPT" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME INTR.MM2S_INTROUT, PortWidth 1, SENSITIVITY LEVEL_HIGH" *) output mm2s_introut;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.RST_N RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.RST_N, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input rst_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis TDATA" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s2mm_axis, CLK_DOMAIN cook_gw_clk50, FREQ_HZ 50000000, HAS_TKEEP 1, HAS_TLAST 1, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) input [31:0]s2mm_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis TKEEP" *) input [3:0]s2mm_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis TLAST" *) input s2mm_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis TREADY" *) output s2mm_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s2mm_axis TVALID" *) input s2mm_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 INTR.S2MM_INTROUT INTERRUPT" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME INTR.S2MM_INTROUT, PortWidth 1, SENSITIVITY LEVEL_HIGH" *) output s2mm_introut;

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
  wire [31:0]dma_M_AXI_MM2S_ARADDR;
  wire [1:0]dma_M_AXI_MM2S_ARBURST;
  wire [3:0]dma_M_AXI_MM2S_ARCACHE;
  wire [7:0]dma_M_AXI_MM2S_ARLEN;
  wire [2:0]dma_M_AXI_MM2S_ARPROT;
  wire dma_M_AXI_MM2S_ARREADY;
  wire [2:0]dma_M_AXI_MM2S_ARSIZE;
  wire dma_M_AXI_MM2S_ARVALID;
  wire [31:0]dma_M_AXI_MM2S_RDATA;
  wire dma_M_AXI_MM2S_RLAST;
  wire dma_M_AXI_MM2S_RREADY;
  wire [1:0]dma_M_AXI_MM2S_RRESP;
  wire dma_M_AXI_MM2S_RVALID;
  wire [31:0]dma_M_AXI_S2MM_AWADDR;
  wire [1:0]dma_M_AXI_S2MM_AWBURST;
  wire [3:0]dma_M_AXI_S2MM_AWCACHE;
  wire [7:0]dma_M_AXI_S2MM_AWLEN;
  wire [2:0]dma_M_AXI_S2MM_AWPROT;
  wire dma_M_AXI_S2MM_AWREADY;
  wire [2:0]dma_M_AXI_S2MM_AWSIZE;
  wire dma_M_AXI_S2MM_AWVALID;
  wire dma_M_AXI_S2MM_BREADY;
  wire [1:0]dma_M_AXI_S2MM_BRESP;
  wire dma_M_AXI_S2MM_BVALID;
  wire [31:0]dma_M_AXI_S2MM_WDATA;
  wire dma_M_AXI_S2MM_WLAST;
  wire dma_M_AXI_S2MM_WREADY;
  wire [3:0]dma_M_AXI_S2MM_WSTRB;
  wire dma_M_AXI_S2MM_WVALID;
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
  wire mig_mmcm_locked;
  wire mig_ui_clk;
  wire [31:0]mm2s_axis_tdata;
  wire [3:0]mm2s_axis_tkeep;
  wire mm2s_axis_tlast;
  wire mm2s_axis_tready;
  wire mm2s_axis_tvalid;
  wire mm2s_introut;
  wire [0:0]rst50_peripheral_aresetn;
  wire rst_n;
  wire [0:0]rstui_peripheral_aresetn;
  wire [31:0]s2mm_axis_tdata;
  wire [3:0]s2mm_axis_tkeep;
  wire s2mm_axis_tlast;
  wire s2mm_axis_tready;
  wire s2mm_axis_tvalid;
  wire s2mm_introut;
  wire [26:0]sc_M00_AXI_ARADDR;
  wire [1:0]sc_M00_AXI_ARBURST;
  wire [3:0]sc_M00_AXI_ARCACHE;
  wire [7:0]sc_M00_AXI_ARLEN;
  wire [0:0]sc_M00_AXI_ARLOCK;
  wire [2:0]sc_M00_AXI_ARPROT;
  wire [3:0]sc_M00_AXI_ARQOS;
  wire sc_M00_AXI_ARREADY;
  wire [2:0]sc_M00_AXI_ARSIZE;
  wire sc_M00_AXI_ARVALID;
  wire [26:0]sc_M00_AXI_AWADDR;
  wire [1:0]sc_M00_AXI_AWBURST;
  wire [3:0]sc_M00_AXI_AWCACHE;
  wire [7:0]sc_M00_AXI_AWLEN;
  wire [0:0]sc_M00_AXI_AWLOCK;
  wire [2:0]sc_M00_AXI_AWPROT;
  wire [3:0]sc_M00_AXI_AWQOS;
  wire sc_M00_AXI_AWREADY;
  wire [2:0]sc_M00_AXI_AWSIZE;
  wire sc_M00_AXI_AWVALID;
  wire sc_M00_AXI_BREADY;
  wire [1:0]sc_M00_AXI_BRESP;
  wire sc_M00_AXI_BVALID;
  wire [63:0]sc_M00_AXI_RDATA;
  wire sc_M00_AXI_RLAST;
  wire sc_M00_AXI_RREADY;
  wire [1:0]sc_M00_AXI_RRESP;
  wire sc_M00_AXI_RVALID;
  wire [63:0]sc_M00_AXI_WDATA;
  wire sc_M00_AXI_WLAST;
  wire sc_M00_AXI_WREADY;
  wire [7:0]sc_M00_AXI_WSTRB;
  wire sc_M00_AXI_WVALID;

  cook_gw_dma_0 dma
       (.axi_resetn(rst50_peripheral_aresetn),
        .m_axi_mm2s_aclk(clk50),
        .m_axi_mm2s_araddr(dma_M_AXI_MM2S_ARADDR),
        .m_axi_mm2s_arburst(dma_M_AXI_MM2S_ARBURST),
        .m_axi_mm2s_arcache(dma_M_AXI_MM2S_ARCACHE),
        .m_axi_mm2s_arlen(dma_M_AXI_MM2S_ARLEN),
        .m_axi_mm2s_arprot(dma_M_AXI_MM2S_ARPROT),
        .m_axi_mm2s_arready(dma_M_AXI_MM2S_ARREADY),
        .m_axi_mm2s_arsize(dma_M_AXI_MM2S_ARSIZE),
        .m_axi_mm2s_arvalid(dma_M_AXI_MM2S_ARVALID),
        .m_axi_mm2s_rdata(dma_M_AXI_MM2S_RDATA),
        .m_axi_mm2s_rlast(dma_M_AXI_MM2S_RLAST),
        .m_axi_mm2s_rready(dma_M_AXI_MM2S_RREADY),
        .m_axi_mm2s_rresp(dma_M_AXI_MM2S_RRESP),
        .m_axi_mm2s_rvalid(dma_M_AXI_MM2S_RVALID),
        .m_axi_s2mm_aclk(clk50),
        .m_axi_s2mm_awaddr(dma_M_AXI_S2MM_AWADDR),
        .m_axi_s2mm_awburst(dma_M_AXI_S2MM_AWBURST),
        .m_axi_s2mm_awcache(dma_M_AXI_S2MM_AWCACHE),
        .m_axi_s2mm_awlen(dma_M_AXI_S2MM_AWLEN),
        .m_axi_s2mm_awprot(dma_M_AXI_S2MM_AWPROT),
        .m_axi_s2mm_awready(dma_M_AXI_S2MM_AWREADY),
        .m_axi_s2mm_awsize(dma_M_AXI_S2MM_AWSIZE),
        .m_axi_s2mm_awvalid(dma_M_AXI_S2MM_AWVALID),
        .m_axi_s2mm_bready(dma_M_AXI_S2MM_BREADY),
        .m_axi_s2mm_bresp(dma_M_AXI_S2MM_BRESP),
        .m_axi_s2mm_bvalid(dma_M_AXI_S2MM_BVALID),
        .m_axi_s2mm_wdata(dma_M_AXI_S2MM_WDATA),
        .m_axi_s2mm_wlast(dma_M_AXI_S2MM_WLAST),
        .m_axi_s2mm_wready(dma_M_AXI_S2MM_WREADY),
        .m_axi_s2mm_wstrb(dma_M_AXI_S2MM_WSTRB),
        .m_axi_s2mm_wvalid(dma_M_AXI_S2MM_WVALID),
        .m_axis_mm2s_tdata(mm2s_axis_tdata),
        .m_axis_mm2s_tkeep(mm2s_axis_tkeep),
        .m_axis_mm2s_tlast(mm2s_axis_tlast),
        .m_axis_mm2s_tready(mm2s_axis_tready),
        .m_axis_mm2s_tvalid(mm2s_axis_tvalid),
        .mm2s_introut(mm2s_introut),
        .s2mm_introut(s2mm_introut),
        .s_axi_lite_aclk(clk50),
        .s_axi_lite_araddr(dma_ctrl_araddr),
        .s_axi_lite_arready(dma_ctrl_arready),
        .s_axi_lite_arvalid(dma_ctrl_arvalid),
        .s_axi_lite_awaddr(dma_ctrl_awaddr),
        .s_axi_lite_awready(dma_ctrl_awready),
        .s_axi_lite_awvalid(dma_ctrl_awvalid),
        .s_axi_lite_bready(dma_ctrl_bready),
        .s_axi_lite_bresp(dma_ctrl_bresp),
        .s_axi_lite_bvalid(dma_ctrl_bvalid),
        .s_axi_lite_rdata(dma_ctrl_rdata),
        .s_axi_lite_rready(dma_ctrl_rready),
        .s_axi_lite_rresp(dma_ctrl_rresp),
        .s_axi_lite_rvalid(dma_ctrl_rvalid),
        .s_axi_lite_wdata(dma_ctrl_wdata),
        .s_axi_lite_wready(dma_ctrl_wready),
        .s_axi_lite_wvalid(dma_ctrl_wvalid),
        .s_axis_s2mm_tdata(s2mm_axis_tdata),
        .s_axis_s2mm_tkeep(s2mm_axis_tkeep),
        .s_axis_s2mm_tlast(s2mm_axis_tlast),
        .s_axis_s2mm_tready(s2mm_axis_tready),
        .s_axis_s2mm_tvalid(s2mm_axis_tvalid));
  cook_gw_mig_0 mig
       (.aresetn(rstui_peripheral_aresetn),
        .ddr2_addr(ddr2_sdram_addr),
        .ddr2_ba(ddr2_sdram_ba),
        .ddr2_cas_n(ddr2_sdram_cas_n),
        .ddr2_ck_n(ddr2_sdram_ck_n),
        .ddr2_ck_p(ddr2_sdram_ck_p),
        .ddr2_cke(ddr2_sdram_cke),
        .ddr2_cs_n(ddr2_sdram_cs_n),
        .ddr2_dm(ddr2_sdram_dm),
        .ddr2_dq(ddr2_sdram_dq),
        .ddr2_dqs_n(ddr2_sdram_dqs_n),
        .ddr2_dqs_p(ddr2_sdram_dqs_p),
        .ddr2_odt(ddr2_sdram_odt),
        .ddr2_ras_n(ddr2_sdram_ras_n),
        .ddr2_we_n(ddr2_sdram_we_n),
        .init_calib_complete(init_calib_complete),
        .mmcm_locked(mig_mmcm_locked),
        .s_axi_araddr(sc_M00_AXI_ARADDR),
        .s_axi_arburst(sc_M00_AXI_ARBURST),
        .s_axi_arcache(sc_M00_AXI_ARCACHE),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen(sc_M00_AXI_ARLEN),
        .s_axi_arlock(sc_M00_AXI_ARLOCK),
        .s_axi_arprot(sc_M00_AXI_ARPROT),
        .s_axi_arqos(sc_M00_AXI_ARQOS),
        .s_axi_arready(sc_M00_AXI_ARREADY),
        .s_axi_arsize(sc_M00_AXI_ARSIZE),
        .s_axi_arvalid(sc_M00_AXI_ARVALID),
        .s_axi_awaddr(sc_M00_AXI_AWADDR),
        .s_axi_awburst(sc_M00_AXI_AWBURST),
        .s_axi_awcache(sc_M00_AXI_AWCACHE),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen(sc_M00_AXI_AWLEN),
        .s_axi_awlock(sc_M00_AXI_AWLOCK),
        .s_axi_awprot(sc_M00_AXI_AWPROT),
        .s_axi_awqos(sc_M00_AXI_AWQOS),
        .s_axi_awready(sc_M00_AXI_AWREADY),
        .s_axi_awsize(sc_M00_AXI_AWSIZE),
        .s_axi_awvalid(sc_M00_AXI_AWVALID),
        .s_axi_bready(sc_M00_AXI_BREADY),
        .s_axi_bresp(sc_M00_AXI_BRESP),
        .s_axi_bvalid(sc_M00_AXI_BVALID),
        .s_axi_rdata(sc_M00_AXI_RDATA),
        .s_axi_rlast(sc_M00_AXI_RLAST),
        .s_axi_rready(sc_M00_AXI_RREADY),
        .s_axi_rresp(sc_M00_AXI_RRESP),
        .s_axi_rvalid(sc_M00_AXI_RVALID),
        .s_axi_wdata(sc_M00_AXI_WDATA),
        .s_axi_wlast(sc_M00_AXI_WLAST),
        .s_axi_wready(sc_M00_AXI_WREADY),
        .s_axi_wstrb(sc_M00_AXI_WSTRB),
        .s_axi_wvalid(sc_M00_AXI_WVALID),
        .sys_clk_i(clk200),
        .sys_rst(rst_n),
        .ui_clk(mig_ui_clk));
  cook_gw_rst50_0 rst50
       (.aux_reset_in(1'b1),
        .dcm_locked(1'b1),
        .ext_reset_in(rst_n),
        .mb_debug_sys_rst(1'b0),
        .peripheral_aresetn(rst50_peripheral_aresetn),
        .slowest_sync_clk(clk50));
  cook_gw_rstui_0 rstui
       (.aux_reset_in(1'b1),
        .dcm_locked(mig_mmcm_locked),
        .ext_reset_in(rst_n),
        .mb_debug_sys_rst(1'b0),
        .peripheral_aresetn(rstui_peripheral_aresetn),
        .slowest_sync_clk(mig_ui_clk));
  cook_gw_sc_0 sc
       (.M00_AXI_araddr(sc_M00_AXI_ARADDR),
        .M00_AXI_arburst(sc_M00_AXI_ARBURST),
        .M00_AXI_arcache(sc_M00_AXI_ARCACHE),
        .M00_AXI_arlen(sc_M00_AXI_ARLEN),
        .M00_AXI_arlock(sc_M00_AXI_ARLOCK),
        .M00_AXI_arprot(sc_M00_AXI_ARPROT),
        .M00_AXI_arqos(sc_M00_AXI_ARQOS),
        .M00_AXI_arready(sc_M00_AXI_ARREADY),
        .M00_AXI_arsize(sc_M00_AXI_ARSIZE),
        .M00_AXI_arvalid(sc_M00_AXI_ARVALID),
        .M00_AXI_awaddr(sc_M00_AXI_AWADDR),
        .M00_AXI_awburst(sc_M00_AXI_AWBURST),
        .M00_AXI_awcache(sc_M00_AXI_AWCACHE),
        .M00_AXI_awlen(sc_M00_AXI_AWLEN),
        .M00_AXI_awlock(sc_M00_AXI_AWLOCK),
        .M00_AXI_awprot(sc_M00_AXI_AWPROT),
        .M00_AXI_awqos(sc_M00_AXI_AWQOS),
        .M00_AXI_awready(sc_M00_AXI_AWREADY),
        .M00_AXI_awsize(sc_M00_AXI_AWSIZE),
        .M00_AXI_awvalid(sc_M00_AXI_AWVALID),
        .M00_AXI_bready(sc_M00_AXI_BREADY),
        .M00_AXI_bresp(sc_M00_AXI_BRESP),
        .M00_AXI_bvalid(sc_M00_AXI_BVALID),
        .M00_AXI_rdata(sc_M00_AXI_RDATA),
        .M00_AXI_rlast(sc_M00_AXI_RLAST),
        .M00_AXI_rready(sc_M00_AXI_RREADY),
        .M00_AXI_rresp(sc_M00_AXI_RRESP),
        .M00_AXI_rvalid(sc_M00_AXI_RVALID),
        .M00_AXI_wdata(sc_M00_AXI_WDATA),
        .M00_AXI_wlast(sc_M00_AXI_WLAST),
        .M00_AXI_wready(sc_M00_AXI_WREADY),
        .M00_AXI_wstrb(sc_M00_AXI_WSTRB),
        .M00_AXI_wvalid(sc_M00_AXI_WVALID),
        .S00_AXI_araddr(dma_M_AXI_MM2S_ARADDR),
        .S00_AXI_arburst(dma_M_AXI_MM2S_ARBURST),
        .S00_AXI_arcache(dma_M_AXI_MM2S_ARCACHE),
        .S00_AXI_arlen(dma_M_AXI_MM2S_ARLEN),
        .S00_AXI_arlock(1'b0),
        .S00_AXI_arprot(dma_M_AXI_MM2S_ARPROT),
        .S00_AXI_arqos({1'b0,1'b0,1'b0,1'b0}),
        .S00_AXI_arready(dma_M_AXI_MM2S_ARREADY),
        .S00_AXI_arsize(dma_M_AXI_MM2S_ARSIZE),
        .S00_AXI_arvalid(dma_M_AXI_MM2S_ARVALID),
        .S00_AXI_rdata(dma_M_AXI_MM2S_RDATA),
        .S00_AXI_rlast(dma_M_AXI_MM2S_RLAST),
        .S00_AXI_rready(dma_M_AXI_MM2S_RREADY),
        .S00_AXI_rresp(dma_M_AXI_MM2S_RRESP),
        .S00_AXI_rvalid(dma_M_AXI_MM2S_RVALID),
        .S01_AXI_awaddr(dma_M_AXI_S2MM_AWADDR),
        .S01_AXI_awburst(dma_M_AXI_S2MM_AWBURST),
        .S01_AXI_awcache(dma_M_AXI_S2MM_AWCACHE),
        .S01_AXI_awlen(dma_M_AXI_S2MM_AWLEN),
        .S01_AXI_awlock(1'b0),
        .S01_AXI_awprot(dma_M_AXI_S2MM_AWPROT),
        .S01_AXI_awqos({1'b0,1'b0,1'b0,1'b0}),
        .S01_AXI_awready(dma_M_AXI_S2MM_AWREADY),
        .S01_AXI_awsize(dma_M_AXI_S2MM_AWSIZE),
        .S01_AXI_awvalid(dma_M_AXI_S2MM_AWVALID),
        .S01_AXI_bready(dma_M_AXI_S2MM_BREADY),
        .S01_AXI_bresp(dma_M_AXI_S2MM_BRESP),
        .S01_AXI_bvalid(dma_M_AXI_S2MM_BVALID),
        .S01_AXI_wdata(dma_M_AXI_S2MM_WDATA),
        .S01_AXI_wlast(dma_M_AXI_S2MM_WLAST),
        .S01_AXI_wready(dma_M_AXI_S2MM_WREADY),
        .S01_AXI_wstrb(dma_M_AXI_S2MM_WSTRB),
        .S01_AXI_wvalid(dma_M_AXI_S2MM_WVALID),
        .aclk(clk50),
        .aclk1(mig_ui_clk),
        .aresetn(rst50_peripheral_aresetn));
endmodule
