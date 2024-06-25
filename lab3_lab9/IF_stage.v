`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // from ws
    input                          ws_ex ,
    input                          ws_eret ,
    input  [31:0]                  epc ,
    // inst sram interface
    output        inst_sram_en   ,
    output [ 3:0] inst_sram_wen  ,
    output [31:0] inst_sram_addr ,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata
);
wire        fs_ex_adel;
wire [31:0] fs_badaddr;

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;
wire [31:0] ex_pc;

wire         br_taken;
wire [ 31:0] br_target;
wire         bd_inst;
wire         fs_bd ;

assign {bd_inst,br_taken,br_target} = br_bus;
assign fs_bd    = bd_inst && !(ws_ex|ws_eret) ;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;
assign fs_to_ds_bus = {fs_bd,
                       fs_badaddr, 
                       fs_inst ,
                       fs_pc   };

// pre-IF stage
assign to_fs_valid  = ~reset;
assign seq_pc       = fs_pc + 3'h4;
assign ex_pc        = 32'hbfc00380;
assign nextpc       = ws_eret ? epc : 
                        ws_ex ? ex_pc : 
                     br_taken ? br_target : 
                                seq_pc; 

// IF stage
assign fs_ready_go    = 1'b1;
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin || (ws_ex|ws_eret);
assign fs_to_ds_valid =  fs_valid && fs_ready_go && !ws_eret && !ws_ex;
always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'hbfbffffc;  //trick: to make nextpc be 0xbfc00000 during reset 
    end
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

assign inst_sram_en    = to_fs_valid && fs_allowin;
assign inst_sram_wen   = 4'h0;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;
assign fs_inst         = inst_sram_rdata;
assign fs_ex_adel      = inst_sram_en && |inst_sram_addr[1:0] ;
assign fs_badaddr      = fs_pc ;
endmodule
