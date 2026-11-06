// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Fri Nov  6 23:31:08 2026
// Host        : LAPTOP-0O737P11 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               c:/Users/pikum/OneDrive/Desktop/MajorProject/CooK/CooK/cook_vivado/cook_vivado.gen/sources_1/bd/cook_gw_sim/ip/cook_gw_sim_bram_0/cook_gw_sim_bram_0_sim_netlist.v
// Design      : cook_gw_sim_bram_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7a100tcsg324-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "cook_gw_sim_bram_0,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module cook_gw_sim_bram_0
   (clka,
    rsta,
    ena,
    wea,
    addra,
    dina,
    douta,
    rsta_busy);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_mode = "slave BRAM_PORTA" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE BRAM_CTRL, READ_WRITE_MODE READ_WRITE, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA RST" *) input rsta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [3:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [31:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;
  output rsta_busy;

  wire [31:0]addra;
  wire clka;
  wire [31:0]dina;
  wire [31:0]douta;
  wire ena;
  wire rsta;
  wire rsta_busy;
  wire [3:0]wea;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [31:0]NLW_U0_doutb_UNCONNECTED;
  wire [31:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "32" *) 
  (* C_ADDRB_WIDTH = "32" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "8" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "0" *) 
  (* C_COUNT_36K_BRAM = "2" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "1" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "1" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     5.3746 mW" *) 
  (* C_FAMILY = "artix7" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "0" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "1" *) 
  (* C_HAS_RSTB = "0" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "NONE" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "0" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "2048" *) 
  (* C_READ_DEPTH_B = "2048" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "1" *) 
  (* C_USE_BYTE_WEA = "1" *) 
  (* C_USE_BYTE_WEB = "1" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "4" *) 
  (* C_WEB_WIDTH = "4" *) 
  (* C_WRITE_DEPTH_A = "2048" *) 
  (* C_WRITE_DEPTH_B = "2048" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "artix7" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  cook_gw_sim_bram_0_blk_mem_gen_v8_4_12 U0
       (.addra({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,addra[12:2],1'b0,1'b0}),
        .addrb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .clka(clka),
        .clkb(1'b0),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(douta),
        .doutb(NLW_U0_doutb_UNCONNECTED[31:0]),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[31:0]),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(rsta),
        .rsta_busy(rsta_busy),
        .rstb(1'b0),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[31:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web({1'b0,1'b0,1'b0,1'b0}));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2025.2"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
YqH9kwIC39+qbZg4PSfFsXuB9k9wnuxNryS/CfnEri6Ci9fSC6fsrQ/T/hnt3u/yolbJ8DJa1Qu6
Qnm24A9jLbA+fu3Nsmm6/rM6a4vU6OfVl/gTFd/CiWDutv6Dhn6Lim4uUNPahoOR/A2Yc4Zo2tdI
kMLO9gn9WlH2l3O2oXs=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
XJYO2VHd/cnMxQd3i7/2qRhl57dl+doEKuhAunQyv3vpGRG/jlNxj8PqrgLoF0HMdqE3qJUVE/oq
kBSapqjVjLDMOrNGQ+Tc6VGsKMZH8FE/TXHQJ/IM5Iuiu2eozEwwVUomF+7cfqn+9OsVsqCONQ1M
g0oRlangiqasJDhhMfnlGGqwAwmgWRGQA6dmhTuua1s8zdvIv540zY6p5au8cAKVhqyyKK7wbxEE
SGuFqX+NYoyRV+rfWCcWM+hJEmnWS8LNAKkd13YE2+17sPYzUdZ23DmTxXK6KlAxKFW27CBySUfg
qdNXp2DSs2KAQYih27pBNMuHfGbM/ATFPWFvxg==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
lYoEi/e8HsDTz6N11EDe/B/iitERmeYndlCklmCluwgb0N4W80JUGVlkd7NlRZHRNhxaNBJPkcjC
n61nO0tb17NwsMwjbY5TF8JWRYTNw1JXCFacvQYrdKv4/7QNQEtwVGiCLxFhOA8aHlWMZIrc2fri
VRMVWaEBcPwCGorlVIM=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QEw9fEsWFbdX0OQLvYs/gl+zyEOW3ak9TdQVaq+0AXXOT3LIqF7wDxJ6ZBnlf9mNbdsUVH5tAz1o
H8u7ihJl1L3THEvugW+TS8hkvVbEA9rKO2vV15KAj4Lla7UdFT/xDfe79RFarlLI7yGrubjgdoRi
QWy//UKsffG7IWNwmoSuppWiWB4ZHJtkunNyIkm70JPGyZF62VxJg1MTT+5LUbZG5vZjjuHZud9w
xJaKv1tFP/x8RVqLU5gPOqGqTW7/nKO2S+450Vo4D9vAmBVVcXpaL1EbSmCvQ+qJmcQKtf9qYFRV
Zko08hbpHjPxstqvTDro01jRzB8592m4xU2TWA==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
TC7q853CWBPPJgbRfgDV1lmjUwSAtliljShAyNFg8sfRfwDzchthzoSPH1UCHV++E2JXacEKq1lB
UWsNP92U4Xh0/Gu+6esOI0pJb8I+TRTxyBN1I4cRQEfQHcwfhbSdeH3yX9OV3opLEqYmT37hWU+J
zCawYnxVESI0FtRzEXve9gdEWlrKKckrT/hp4mvxxOjvOkOSQBvy0elgUOqh6mEOZl+JnUbsR+Wm
CoZLE1eefMZy3FnVmyDNPv3JPXi88aLXMyimal0MYFkTiS4XJiGT3eAIMIbksehXY+eYi/KFpZWQ
GHpX+lG3UmiWWLwyPakFwKEHbrBc70AlJ2eV9g==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2025.1-2029.x", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
j9nmCKgjPWNChPbpSW6EWLrMA6oCG2JGPoum8px09v0PEAh0DRXZi0J8HPzXUsZgOEMcKpA7X54u
YFcDDCLAQ+urha/eSPbQYHQh4yGCursxAQ1C6LEyNQ2wJ0eLlO2bJeAl/gof06zqsYVM2lLJVNv5
wao1k2bmgPdfpfY3c9vPD0fSMuZPS41EoRS0cQhO5GTZnKdjxm6tEUL3GnTjB8ynSCIbCJUsMtAX
4FRHNa52gudx5B5fagR+lXgFhE7e++rWTJELr7SYB+r5Es8qZLTpCH8TrQxEkV0rY/+e4sAjNE2D
gHw8GD7VcUtc15B8y1BbVmh29qc8Nd3V2i/miA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
UkCD6I/Vye4qNoNoa3hIexBXG3xyKUJPAHAjIo7UcNVCDXpMQiYEtPDqExZMfiPlJn2nswCYIfIJ
FYWqMCloKSQyyI/7yZ2EtbyWEklb/P5IyZyvGi6hhFUo/JFTb12b4bK0gZPr+bCDdlVQKTx5GVHz
wptdUJO2omSj8axVMPbLRRtVzlJIZ29dTJ2ATXVXAcBxPnFfHRAMnYYKLeeLExX61vQvpqrkLQHm
XG7hpVzJi56gYKAzxa2BLq072OCVpVS70bfWlhlSTVcSlCrUf+EcarEk4FD8+Ih2NCvrqremG6yn
TtcBn8Xr8M/6zhOYvLi6AD6eArDMKA8n+Ccv8A==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
A5y5QVZU8yjPexRVPioSiAGohCHD5DX5FVobuMyhcgQRExLUhPvnnS8HOtxTj/2IapEcz68gFMGG
Hpi+m725u85/om/Vze9pGIW9Mn328Kz2FIg3W5EvGstfGwY+48LiAGAmTR269JS4lJGVYWYOz7Xk
S8cEsFd2m7j8iyKtARJzD90+UdXq/cIIh725jC9i8nbgxB364zddvm1Z/DF3JRw1qFp6GGcuRai1
KNcJ1j8c9wtIgktpsteU3e5+bxHEw8NT3gWXUFYjm00NDq97Jals8Jjktmum2nQxoF7ivPacfEey
gnSF6jRMkTsZObzc30hAhs0CEtc33hZLhPLHSn8pQ0WyvKJLHdd5s2yckgTZtqxC1Sbwe7WEgNXe
ZMX3pIkz+aoXsAL7GBLyVBMVQcyMoF0w8QGAaTe8sqatABwPqXidYRqNROTf62IYcMpV89XYgaTv
EwIn/oni9KOFd2BFVxRZbFGGC4IjvigsTBUijI+Dk6kVnDh240clGcc4

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Omtp+lCaqUx7Z4qdFj2zrN8LpCkit2eX4hlMtig+ielGm/x4FSZkpjoFmiqdKFPi2eg0pg09MSai
XyGH68UzAR7Xrj8f1jlIoUmMKp4GcxfdqfTeuu7kWGOJEP6cvgTjSJFj2gawDv7f4yZcltnK2x0L
e4GW/rBTmGvZtKWb2ahjINLxPuh3dDaSaWdb+zVgbtyrI5FrjxBkq+aOxSjyNsqnCx1L0uWbxnkl
88NbXN3dTaECXHNm/fsleayM5hKis7kTv9BFajJMGy+BhQlmIYpE+F5zchnTTFUFJZCz1sX9Fc8e
HcY7irB8mR3ajdzjUZLBQEMktp096Nheq3U75A==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
hpeBLwN9x2ZFDwroYLlUe5GjjDepHik2l0c2s3/6S7JPCRkzQSyt2V1Ad/JewAs/QNp5SXSbYYB4
rQl0My1LDMF3xw43r0g2IbcyHVpPhGp0W5msuQdF67afnsRv90iJYWLMI3QkYGCTWAzl4HrLxFSg
3z8XZRK670IcxznOrlvgHmIKsvubZrBkuc1EynrVb9Nw16QnIx2rc4WgcEXeFf+4i1RoYLDd3gXK
NFCNMdtaRYUThunFP6Z4ViZ5UnDmKq+IMhd31jTaqIlWOBDxPI1+v5RJYxIyTbn4rxlKR2fNbl5/
z4OUjBTd+1GH3I2OXlqmAOvIhpe2Z2HH7nZu/A==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Mt2RhTSUwEIEWeNARbyL+EdfS1UF6nPaL/fKl/7oO2gina93egwCWDLl1fbBtkfaPco0cu4MJ9K3
OraAsyHRlY+MNShmJ1LzAIA1LjZx4y55lu9dlQqSUXR7AW7wVbkg1864mK+hM/1XygU0jvebKNW9
B7xSER+asLO6pxi0mt7uC2PHxLPAYEszFhmnap82TtbDGdQ2qtyekY+ngs+N2fAdsblxVwJruiMl
e6XJ127M8N1mYwhWU2HtRpBOSnnKoHgD9fG51XK/rhk8DxT66QnX9uLPB+H25eDupBJGi1Y5o6x8
hOwZiSUVlBLh7brfzevh7+eRn+7es6wBas0+3w==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 53360)
`pragma protect data_block
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
nbbY7xz3Dyk=
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
