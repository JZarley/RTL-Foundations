`timescale 1ns/1ps

module sync_fifo_tb;

    localparam int DATA_WIDTH = 32;
    localparam int DEPTH = 4;

    logic clk;
    logic reset;

    logic in_valid;
    logic in_ready;
    logic [DATA_WIDTH-1:0] in_data;

    logic out_valid;
    logic out_ready;
    logic [DATA_WIDTH-1:0] out_data;

    logic [DATA_WIDTH-1:0] expected_queue [$];

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH
    ) dut (
        .*
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int input_xfers = 0;
    int output_xfers = 0;
    int stall_cycles = 0;
    int simultaneous_xfers = 0;
    logic reached_empty = 1'b0;
    logic reached_full = 1'b0;
    logic read_wrap = 1'b0;
    logic write_wrap = 1'b0;

    /* Overall note for the following tasks: these tasks generally assume they will be entered at a falling edge
    and will return to a falling edge. This allows us to send or consume data consecutively, rather than skipping
    cycles in between. reset_dut() is an exception, since it is an initialization helper, and will perform its
    own initial edge wait
    */
    task reset_dut();
        @(negedge clk);
        reset = 1'b1;
        in_valid = 1'b0;

        repeat (2) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;
    endtask

    task send_one(logic [DATA_WIDTH-1:0] data);
        in_data = data;
        in_valid = 1'b1;

        do begin
            @(posedge clk);
        end while (!in_ready);

        @(negedge clk);
        in_valid = 1'b0;
    endtask

    task consume_one();
        out_ready = 1'b1;

        do begin
            @(posedge clk);
        end while (!out_valid);

        @(negedge clk);
        out_ready = 1'b0;
    endtask

    // This task sends n pieces of unique data to the DUT
    task send_n(logic [DATA_WIDTH-1:0] data, int n);
        for (int i = 0; i < n; i++) begin
            send_one(data + DATA_WIDTH'(i));
        end
    endtask

    task consume_n(int n);
        repeat (n) begin
            consume_one;
        end
    endtask

    // This task waits until a valid transaction is presented, then stalls that transaction for num_cycles
    task stall_consumer(int num_cycles);
        if (num_cycles <= 0)
            $fatal(1, "stall_consumer requires num_cycles >= 1");

        out_ready = 1'b0;

        while (!out_valid) begin
            @(negedge clk);
        end

        repeat (num_cycles) @(posedge clk);

        @(negedge clk);
    endtask

    /* The random producer may or may not produce valid data on a given clock cycle. If it chooses to produce
    data, that data will be randomized. It will produce as many instances of data as you request, eventually
    */
    task random_producer(int num_transactions);
        in_valid = 1'b0;

        while (num_transactions > 0) begin
            if ($urandom_range(1, 0) == '0) begin
                @(negedge clk);
            end
            else begin
                send_one($urandom);
                num_transactions--;
            end
        end
    endtask

    /* The random consumer may or may be ready to consume data on a given clock cycle, but will eventually consume
    as much data as it is requested to. There is no protection against attempting to consume more data than will be
    available
    */
    task random_consumer(int num_transactions);
        out_ready = 1'b0;

        while (num_transactions > 0) begin
            if ($urandom_range(1, 0) == '0) begin
                @(negedge clk);
            end
            else begin
                consume_one();
                num_transactions--;
            end
        end
    endtask

    // Consumes all remaining data, clearing the DUT
    task drain();
        in_valid = 1'b0;
        out_ready = 1'b1;

        while (expected_queue.size() != 0) begin
            @(negedge clk);
        end

        out_ready = 1'b0;
    endtask

    property output_stall_stability;
        @(posedge clk)
        disable iff (reset)
        out_valid && !out_ready |=> out_valid && $stable(out_data);
    endproperty
    assert property (output_stall_stability)
        else $fatal(1, "Output changed while stalled");

    property input_stall_stability;
        @(posedge clk)
        disable iff (reset)
        in_valid && !in_ready |=> in_valid && $stable(in_data);
    endproperty
    assert property (input_stall_stability)
        else $fatal(1, "Input changed while stalled");

    property no_output_if_empty;
        @(posedge clk)
        disable iff (reset)
        expected_queue.size() == 0 |-> out_valid == 0;
    endproperty
    assert property (no_output_if_empty)
        else $fatal(1, "DUT claimed valid output when queue should have been empty");

    property no_illegal_occupancy;
        @(posedge clk)
        disable iff (reset)
        DEPTH >= dut.count;
    endproperty
    assert property (no_illegal_occupancy)
        else $fatal(1, "DUT's count size not within expected bounds");

    property full_ready_relationship;
        @(posedge clk)
        disable iff (reset)
        (expected_queue.size() == DEPTH && !out_ready) |-> in_ready == 0;
    endproperty
    assert property (full_ready_relationship)
        else $fatal(1, "DUT claimed to have space when queue should have been full");

    always @(posedge clk) begin
        unique case ({in_ready && in_valid, out_ready && out_valid})
            2'b00: ;
            2'b01: begin
                output_xfers++;
                if (dut.count == 1) begin
                    reached_empty = 1'b1;
                end
                if (int'(dut.read_ptr) == DEPTH - 1) begin
                    read_wrap = 1'b1;
                end
            end
            2'b10: begin
                input_xfers++;
                if (int'(dut.count) == DEPTH-1) begin
                    reached_full = 1'b1;
                end
                if (int'(dut.write_ptr) == DEPTH - 1) begin
                    write_wrap = 1'b1;
                end
            end
            2'b11: begin
                simultaneous_xfers++;
                input_xfers++;
                output_xfers++;
                if (int'(dut.read_ptr) == DEPTH - 1) begin
                    read_wrap = 1'b1;
                end
                if (int'(dut.write_ptr) == DEPTH - 1) begin
                    write_wrap = 1'b1;
                end
            end
        endcase
        if (out_valid && !out_ready) begin
            stall_cycles++;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            expected_queue.delete();
        end
        else begin
            logic [DATA_WIDTH-1:0] expected_data;
            if (in_ready && in_valid) begin
                expected_queue.push_back(in_data);
            end
            if (out_ready && out_valid) begin
                assert (expected_queue.size() > 0)
                    else $fatal(1, "Attempted DUT output when empty");

                expected_data = expected_queue.pop_front();
                assert(expected_data == out_data)
                    else $fatal(1, "Scoreboard mismatch: expected=%h actual=%h", expected_data, out_data);
            end
        end
    end

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(1, sync_fifo_tb);
    end

    initial begin
        // intentionally blank for the time being
        $display("");
        $finish;
    end
endmodule