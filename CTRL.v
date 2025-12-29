`include "lib/defines.vh"
module CTRL(
    input wire rst,
    input wire stallreq_for_load,
    input wire stallreq_from_ex, 

    output reg [`StallBus-1:0] stall
);

    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0;
        end
        else if (stallreq_from_ex) begin
            // EX请求暂停（除法）：暂停 PC, IF, ID, EX
            stall = 6'b001111; 
        end
        else if (stallreq_for_load) begin
            // Load请求暂停：暂停 PC, IF, ID
            stall = 6'b000111;
        end
        else begin
            stall = `StallBus'b0;
        end
    end

endmodule
