`include "lib/defines.vh"
module MEM(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,

    input wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,
    input wire [31:0] data_sram_rdata,

    output wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus
);
    reg [`EX_TO_MEM_WD-1:0] ex_to_mem_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        end
        // else if (flush) begin
        //     ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        // end
        else if (stall[3]==`Stop && stall[4]==`NoStop) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        end
        else if (stall[3]==`NoStop) begin
            ex_to_mem_bus_r <= ex_to_mem_bus;
        end
    end

    wire [31:0] mem_pc;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire sel_rf_res;
    wire [4:0] mem_op;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire [31:0] ex_result;
    wire [31:0] mem_result;

    assign {
        mem_op,
        mem_pc,         // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    } =  ex_to_mem_bus_r;

    wire inst_lb,inst_lbu,inst_lh,inst_lhu,inst_lw;
    assign {
        inst_lb,
        inst_lbu,
        inst_lh,
        inst_lhu,
        inst_lw
    } = mem_op;

    // Load Data Processing Logic
    // 这里修改了原来的简单 assign，增加了对字节/半字的 selection 和 extension
    reg [31:0] mem_result_r;
    
    always @(*) begin
        mem_result_r = 32'b0; // 默认值
        case (1'b1)
            inst_lw: begin
                mem_result_r = data_sram_rdata;
            end
            inst_lb: begin
                case(ex_result[1:0]) // Little Endian Byte Selection
                    2'b00: mem_result_r = {{24{data_sram_rdata[7]}},  data_sram_rdata[7:0]};
                    2'b01: mem_result_r = {{24{data_sram_rdata[15]}}, data_sram_rdata[15:8]};
                    2'b10: mem_result_r = {{24{data_sram_rdata[23]}}, data_sram_rdata[23:16]};
                    2'b11: mem_result_r = {{24{data_sram_rdata[31]}}, data_sram_rdata[31:24]};
                endcase
            end
            inst_lbu: begin
                case(ex_result[1:0])
                    2'b00: mem_result_r = {24'b0, data_sram_rdata[7:0]};
                    2'b01: mem_result_r = {24'b0, data_sram_rdata[15:8]};
                    2'b10: mem_result_r = {24'b0, data_sram_rdata[23:16]};
                    2'b11: mem_result_r = {24'b0, data_sram_rdata[31:24]};
                endcase
            end
            inst_lh: begin
                case(ex_result[1]) // Half-word Selection
                    1'b0: mem_result_r = {{16{data_sram_rdata[15]}}, data_sram_rdata[15:0]};
                    1'b1: mem_result_r = {{16{data_sram_rdata[31]}}, data_sram_rdata[31:16]};
                endcase
            end
            inst_lhu: begin
                case(ex_result[1])
                    1'b0: mem_result_r = {16'b0, data_sram_rdata[15:0]};
                    1'b1: mem_result_r = {16'b0, data_sram_rdata[31:16]};
                endcase
            end
            default: begin
                mem_result_r = 32'b0;
            end
        endcase
    end

    assign mem_result = mem_result_r;
    assign rf_wdata = sel_rf_res ? mem_result : ex_result;

    assign mem_to_wb_bus = {
        mem_pc,     // 69:38
        rf_we,      // 37
        rf_waddr,   // 36:32
        rf_wdata    // 31:0
    };
    
endmodule