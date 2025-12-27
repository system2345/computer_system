module decoder_2_4(
    input  wire [1:0] in,
    output wire [3:0] out
);

    genvar i;
    generate
        for(i=0; i<4; i=i+1) begin : decoder_2_4_gen
            assign out[i] = (in == i);
        end
    endgenerate

endmodule