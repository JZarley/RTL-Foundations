`timescale 1ns/1ps

module sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 4
) (
    input logic clk,
    input logic reset,

    input logic in_valid,
    output logic in_ready,
    input logic [DATA_WIDTH-1:0] in_data,

    output logic out_valid,
    input logic out_ready,
    output logic [DATA_WIDTH-1:0] out_data
);

    localparam int PTR_WIDTH = (DEPTH<=1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_WIDTH = (DEPTH<=1) ? 1 : $clog2(DEPTH+1);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] read_ptr;
    logic [PTR_WIDTH-1:0] write_ptr;
    logic [COUNT_WIDTH-1:0] count;

    logic in_transfer;
    logic out_transfer;

    always_ff @(posedge clk) begin
        if (reset) begin
            read_ptr <= '0;
            write_ptr <= '0;
            count <= '0;
        end
        else begin
            if (in_transfer) begin
                mem[write_ptr] <= in_data;
                if (write_ptr == PTR_WIDTH'(DEPTH-1)) begin
                    write_ptr <= '0;
                end
                else begin
                    write_ptr <= write_ptr + 1;
                end
            end
            if (out_transfer) begin
                if (read_ptr == PTR_WIDTH'(DEPTH-1)) begin
                    read_ptr <= '0;
                end
                else begin
                    read_ptr <= read_ptr + 1;
                end
            end
            unique case ({in_transfer, out_transfer})
                2'b01: begin
                    count <= count - 1;
                end
                2'b10: begin
                    count <= count + 1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        out_data = mem[read_ptr];
        out_valid = count != '0;
        in_ready = (count != COUNT_WIDTH'(DEPTH)) || out_ready;

        in_transfer = in_ready && in_valid;
        out_transfer = out_ready && out_valid;
    end
endmodule