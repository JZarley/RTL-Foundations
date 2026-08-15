`timescale 1ns/1ps

module rv_buffer_tb;

    localparam int DATA_WIDTH = 32;

    logic clk;
    logic reset;

    logic in_valid;
    logic in_ready;
    logic [DATA_WIDTH-1:0] in_data;

    logic out_valid;
    logic out_ready;
    logic [DATA_WIDTH-1:0] out_data;

    rv_buffer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk,
        .reset,
        .in_valid,
        .in_ready,
        .in_data,
        .out_valid,
        .out_ready,
        .out_data
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int input_xfers;
    int output_xfers;
    int stall_cycles;
    int simultaneous_xfers;

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(1, "rtl/rv_buffer.sv");
    end

    property stalled_output_stable;
        @(posedge clk)
        disable iff (reset)
        (out_valid && !out_ready) |=> (out_valid && $stable(out_data));
    endproperty

    assert property (stalled_output_stable)
        else $fatal(1, "Output changed while stalled");

    task reset_dut();
        reset = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;
    endtask

    task send_data(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        in_data = data;
        in_valid = 1'b1;

        do begin
            @(posedge clk);
        end while (!in_ready);

        @(negedge clk);
        in_valid = 1'b0;
    endtask

    logic [DATA_WIDTH-1:0] expected_queue[$];

    always @(posedge clk) begin
        if (reset) begin
            expected_queue.delete();
        end
        else begin
            if (in_valid && in_ready) begin
                expected_queue.push_back(in_data);
            end

            if (out_valid && out_ready) begin
                logic [DATA_WIDTH-1:0] expected;

                assert (expected_queue.size() > 0)
                    else $fatal(1, "Unexpected output");

                expected = expected_queue.pop_front();

                assert (out_data == expected)
                    else $fatal(1,
                        "Scoreboard mismatch: expected=%h actual=%h",
                        expected, out_data);
            end
        end
    end

    task consume_data();
        @(negedge clk);
        out_ready = 1'b1;

        do begin
            @(posedge clk);
        end while (!out_valid);

        @(negedge clk);
        out_ready = 1'b0;
    endtask

    task random_producer(input int cycles);
        bit pending;

        pending = 0;

        repeat (cycles) begin
            @(negedge clk);

            if (!pending) begin
                if ($urandom_range(1, 0) == 1) begin
                    in_valid = 1'b1;
                    in_data  = $urandom;
                    pending  = 1'b1;
                end
                else begin
                    in_valid = 1'b0;
                end
            end

            @(posedge clk);

            if (in_valid && in_ready) begin
                pending = 1'b0;
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
    endtask

    task random_consumer(input int cycles);
        repeat (cycles) begin
            @(negedge clk);
            out_ready = ($urandom_range(1, 0) == 1);
        end

        @(negedge clk);
        out_ready = 1'b0;
    endtask

    task drain();
        @(negedge clk);
        in_valid  = 1'b0;
        out_ready = 1'b1;

        while (expected_queue.size() != 0) begin
            @(negedge clk);
        end

        out_ready = 1'b0;
    endtask

    always @(posedge clk) begin
        if (reset) begin
            expected_queue.delete();

            input_xfers       = 0;
            output_xfers      = 0;
            stall_cycles      = 0;
            simultaneous_xfers = 0;
        end
        else begin
            if (in_valid && in_ready) begin
                input_xfers++;
                expected_queue.push_back(in_data);
            end

            if (out_valid && out_ready) begin
                logic [DATA_WIDTH-1:0] expected;

                output_xfers++;

                assert (expected_queue.size() > 0)
                    else $fatal(1, "Unexpected output");

                expected = expected_queue.pop_front();

                assert (out_data == expected)
                    else $fatal(
                        1,
                        "Scoreboard mismatch: expected=%h actual=%h",
                        expected, out_data
                    );
            end

            if (out_valid && !out_ready)
                stall_cycles++;

            if ((in_valid && in_ready) &&
                (out_valid && out_ready))
                simultaneous_xfers++;
        end
    end

    initial begin
        reset     = 1'b0;
        in_valid  = 1'b0;
        in_data   = '0;
        out_ready = 1'b0;

        reset_dut();

        assert (out_valid == 1'b0)
            else $fatal(1, "Buffer not empty after reset");

        assert (in_ready == 1'b1)
            else $fatal(1, "Buffer not ready after reset");

        send_data(32'h1234_ABCD);
        consume_data();

        send_data(32'hAAAA_AAAA);

        fork
            begin
                send_data(32'hBBBB_BBBB);
            end

            begin
                repeat (3) begin
                    @(posedge clk);

                    assert (out_valid)
                        else $fatal(1, "Stall failure: out_valid dropped");

                    assert (out_data == 32'hAAAA_AAAA)
                        else $fatal(
                            1,
                            "Stall failure: expected=%h actual=%h",
                            32'hAAAA_AAAA,
                            out_data
                        );

                    assert (!in_ready)
                        else $fatal(
                            1,
                            "Backpressure failure: in_ready asserted while stalled"
                        );
                end

                consume_data();
            end
        join

        consume_data();

        fork
            random_producer(100);
            random_consumer(100);
        join

        drain();

        assert (expected_queue.size() == 0)
            else $fatal(
                1,
                "Test ended with %0d pending transactions",
                expected_queue.size()
            );


        $display("Coverage: in=%0d out=%0d stalls=%0d simultaneous=%0d",
        input_xfers,
        output_xfers,
        stall_cycles,
        simultaneous_xfers);
        $finish;
    end

endmodule