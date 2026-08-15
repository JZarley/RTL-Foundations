`timescale 1ns/1ps

module rv_buffer #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  reset,

    input  logic                  in_valid,
    output logic                  in_ready,
    input  logic [DATA_WIDTH-1:0] in_data,

    output logic                  out_valid,
    input  logic                  out_ready,
    output logic [DATA_WIDTH-1:0] out_data
);

    logic full_reg;
    logic [DATA_WIDTH-1:0] data_reg;

    logic in_transfer;
    logic out_transfer;

    always_ff @(posedge clk) begin
        if (reset) begin
            full_reg <= 1'b0;
        end
        else begin
            unique case ({in_transfer, out_transfer})
                2'b00:
                    full_reg <= full_reg;
                2'b01:
                    full_reg <= 1'b0;
                2'b10:
                    full_reg <= 1'b1;
                2'b11:
                    full_reg <= 1'b1;
            endcase
            if (in_transfer) begin
                data_reg <= in_data;
            end
        end
    end

    always_comb begin
        out_valid = full_reg;
        out_data = data_reg;
        in_ready = !full_reg || out_ready;
        
        in_transfer = in_ready && in_valid;
        out_transfer = out_valid && out_ready;
    end

endmodule