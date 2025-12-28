`include "lib/defines.vh"

module IF(
    input wire clk,
    input wire rst,
    input wire [`StallBus-1:0] stall,
    input wire [`BR_WD-1:0] br_bus,

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus,

    output wire inst_sram_en,
    output wire [3:0] inst_sram_wen,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata
);

    reg [31:0] pc_r;
    reg [31:0] pc_for_id_r;
    reg if_valid_r;

    wire br_e;
    wire [31:0] br_addr;
    assign {br_e, br_addr} = br_bus;

    wire [31:0] pc_plus_4;
    assign pc_plus_4 = pc_r + 32'h4;

    wire [31:0] pc_next;
    assign pc_next = br_e ? br_addr : pc_plus_4;

    always @(posedge clk) begin
        if (rst) begin
            pc_r <= 32'hbfc00000;
            pc_for_id_r <= 32'hbfc00000;
            if_valid_r <= 1'b0;
        end
        else if (stall[0] == `NoStop) begin
            pc_for_id_r <= pc_r;
            pc_r <= pc_next;
            if_valid_r <= 1'b1;
        end
    end

    assign inst_sram_en    = 1'b1;
    assign inst_sram_wen   = 4'b0000;
    assign inst_sram_addr  = pc_r;
    assign inst_sram_wdata = 32'b0;

    assign if_to_id_bus = {if_valid_r, pc_for_id_r};

endmodule