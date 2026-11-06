// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Fri Nov  6 23:31:07 2026
// Host        : LAPTOP-0O737P11 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ cook_gw_sim_bram_0_sim_netlist.v
// Design      : cook_gw_sim_bram_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7a100tcsg324-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "cook_gw_sim_bram_0,blk_mem_gen_v8_4_12,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_12,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
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
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_blk_mem_gen_v8_4_12 U0
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 53424)
`pragma protect data_block
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
nmHIfFO+Z+kEHF85IGTB
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
