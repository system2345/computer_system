`include "lib/defines.vh"
module EX(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,
    
    // --- 之前修复: 暂停请求输出端口 ---
    output wire stallreq, 

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,

    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);
    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;
        end
    end

    wire [31:0] ex_pc, inst;
    wire [4:0] mem_op;
    wire [11:0] alu_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;
    reg is_in_delayslot;

    assign {
        mem_op,
        ex_pc,          // 148:117
        inst,           // 116:85
        alu_op,         // 84:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,      // 63:32
        rf_rdata2       // 31:0
    } = id_to_ex_bus_r;

    // --- 解码逻辑 (之前添加) ---
    wire [5:0] ex_op = inst[31:26];
    wire [5:0] ex_func = inst[5:0];
    
    wire inst_mult  = (ex_op == 6'b000000) & (ex_func == 6'b011000);
    wire inst_multu = (ex_op == 6'b000000) & (ex_func == 6'b011001);
    wire inst_div_decode   = (ex_op == 6'b000000) & (ex_func == 6'b011010);
    wire inst_divu_decode  = (ex_op == 6'b000000) & (ex_func == 6'b011011);
    wire inst_mfhi  = (ex_op == 6'b000000) & (ex_func == 6'b010000);
    wire inst_mflo  = (ex_op == 6'b000000) & (ex_func == 6'b010010);
    wire inst_mthi  = (ex_op == 6'b000000) & (ex_func == 6'b010001);
    wire inst_mtlo  = (ex_op == 6'b000000) & (ex_func == 6'b010011);

    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]};
    assign imm_zero_extend = {16'b0, inst[15:0]};
    assign sa_zero_extend = {27'b0,inst[10:6]};

    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;
    
    alu u_alu(
    	.alu_control (alu_op ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );

    // --- HI/LO 寄存器 (之前添加) ---
    reg [31:0] hi;
    reg [31:0] lo;

    // --- 输出选择逻辑 ---
    assign ex_result = inst_mfhi ? hi :
                       inst_mflo ? lo :
                       alu_result;
    
    // --- 本次修改重点：SB/SH/SW 的写使能与数据对齐处理 ---
    wire inst_sb, inst_sh, inst_sw;
    reg [3:0] data_sram_wen_r;
    reg [31:0] data_sram_wdata_r;

    assign {
        inst_sb,
        inst_sh,
        inst_sw
    } = data_ram_wen[2:0];

    // 获取地址低两位，用于判断写入位置
    wire [1:0] addr_offset = alu_result[1:0];

    always @(*) begin
        data_sram_wen_r = 4'b0000;
        data_sram_wdata_r = 32'b0;
        
        if (inst_sw) begin
            // sw: 写整个字 (4字节)
            data_sram_wen_r = 4'b1111;
            data_sram_wdata_r = rf_rdata2;
        end
        else if (inst_sh) begin
            // sh: 写半字 (2字节)
            if (addr_offset[1] == 1'b0) begin // 地址是对齐到 0x...0
                data_sram_wen_r = 4'b0011;
                data_sram_wdata_r = {16'b0, rf_rdata2[15:0]};
            end
            else begin // 地址是对齐到 0x...2
                data_sram_wen_r = 4'b1100;
                data_sram_wdata_r = {rf_rdata2[15:0], 16'b0};
            end
        end
        else if (inst_sb) begin
            // sb: 写字节 (1字节)
            case (addr_offset)
                2'b00: begin
                    data_sram_wen_r = 4'b0001;
                    data_sram_wdata_r = {24'b0, rf_rdata2[7:0]};
                end
                2'b01: begin
                    data_sram_wen_r = 4'b0010;
                    data_sram_wdata_r = {16'b0, rf_rdata2[7:0], 8'b0};
                end
                2'b10: begin
                    data_sram_wen_r = 4'b0100;
                    data_sram_wdata_r = {8'b0, rf_rdata2[7:0], 16'b0};
                end
                2'b11: begin
                    data_sram_wen_r = 4'b1000;
                    data_sram_wdata_r = {rf_rdata2[7:0], 24'b0};
                end
            endcase
        end
    end
    // ----------------------------------------------------

    assign data_sram_en = data_ram_en;
    assign data_sram_wen = data_sram_wen_r;
    assign data_sram_addr = alu_result; 
    assign data_sram_wdata = data_sram_wdata_r;
    assign ex_to_mem_bus = {
        mem_op,
        ex_pc,          // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };

    // MUL part
    wire [63:0] mul_result;
    wire mul_signed;
    assign mul_signed = inst_mult; 

    mul u_mul(
    	.clk        (clk            ),
        .resetn     (~rst           ),
        .mul_signed (mul_signed     ),
        .ina        (rf_rdata1      ), 
        .inb        (rf_rdata2      ), 
        .result     (mul_result     ) 
    );

    // DIV part
    wire [63:0] div_result;
    wire inst_div, inst_divu;
    assign inst_div = inst_div_decode;
    assign inst_divu = inst_divu_decode;
    
    wire div_ready_i;
    reg stallreq_for_div;
    
    // 之前修复: 连接暂停信号
    assign stallreq = stallreq_for_div;

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    div u_div(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_div_i (signed_div_o ),
        .opdata1_i    (div_opdata1_o    ),
        .opdata2_i    (div_opdata2_o    ),
        .start_i      (div_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (div_result     ), 
        .ready_o      (div_ready_i      )
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin // div
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin // divu
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    // --- HI/LO 寄存器写入逻辑 (之前修复) ---
    always @(posedge clk) begin
        if (rst) begin
            hi <= 32'b0;
            lo <= 32'b0;
        end
        else if (div_ready_i == `DivResultReady) begin
            hi <= div_result[63:32];
            lo <= div_result[31:0];
        end
        else if (stall[2] == `NoStop) begin 
            if (inst_mthi) begin
                hi <= rf_rdata1;
            end
            else if (inst_mtlo) begin
                lo <= rf_rdata1;
            end
            else if (inst_mult || inst_multu) begin
                hi <= mul_result[63:32];
                lo <= mul_result[31:0];
            end
        end
    end

endmodule