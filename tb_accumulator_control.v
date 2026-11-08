`timescale 1ns / 1ps

// ============================================================
// TESTBENCH: 24 Directed Tests
// ============================================================

module tb_accumulator_control;

    reg        clk;
    reg        rst;
    reg        flag_en;
    reg  [1:0] op;
    reg  [7:0] data_in;

    wire [7:0] acc;
    wire       Z, N, C, V;

    integer tests;
    integer errors;

    localparam HOLD = 2'b00,
               LOAD = 2'b01,
               ADD  = 2'b10,
               SUB  = 2'b11;

    accumulator_control dut (
        .clk(clk),
        .rst(rst),
        .flag_en(flag_en),
        .op(op),
        .data_in(data_in),
        .acc(acc),
        .Z(Z),
        .N(N),
        .C(C),
        .V(V)
    );

    // Clock period = 10 ns.
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Apply inputs before the active clock edge.
    task drive;
        input       reset_value;
        input [1:0] operation;
        input [7:0] operand;
        input       update_flags;

        begin
            @(negedge clk);
            rst     = reset_value;
            op      = operation;
            data_in = operand;
            flag_en = update_flags;

            @(posedge clk);
            #1;
        end
    endtask

    // Compare actual results with expected results.
    // Flag order: Z, N, C, V.
    task check;
        input [7:0]   expected_acc;
        input [3:0]   expected_flags;
        input [511:0] test_name;

        begin
            tests = tests + 1;

            if ((acc !== expected_acc) ||
                ({Z, N, C, V} !== expected_flags)) begin

                errors = errors + 1;

                $display(
                    "FAIL %0d: %0s",
                    tests, test_name
                );

                $display(
                    "  Actual: ACC=%h ZNCV=%b | Expected: ACC=%h ZNCV=%b",
                    acc, {Z, N, C, V},
                    expected_acc, expected_flags
                );
            end
            else begin
                $display(
                    "PASS %0d: %0s | ACC=%h ZNCV=%b",
                    tests, test_name, acc, {Z, N, C, V}
                );
            end
        end
    endtask

    initial begin
        rst     = 1'b1;
        flag_en = 1'b0;
        op      = HOLD;
        data_in = 8'h00;
        tests   = 0;
        errors  = 0;

        $display("Accumulator Control Unit Simulation");
        $display("Flag order: Z N C V");
        $display("");

        // ----------------------------------------------------
        // RESET: Tests 1-2
        // ----------------------------------------------------

        drive(1'b1, HOLD, 8'h00, 1'b0);
        check(8'h00, 4'b1000, "Reset at startup");

        // Setup: change both accumulator and flags.
        drive(1'b0, LOAD, 8'h7F, 1'b1);
        drive(1'b0, ADD,  8'h01, 1'b1);

        drive(1'b1, ADD, 8'h01, 1'b0);
        check(8'h00, 4'b1000, "Reset overrides ADD and flag disable");

        // ----------------------------------------------------
        // LOAD: Tests 3-7
        // ----------------------------------------------------

        drive(1'b0, LOAD, 8'h00, 1'b1);
        check(8'h00, 4'b1000, "Load 00");

        drive(1'b0, LOAD, 8'h01, 1'b1);
        check(8'h01, 4'b0000, "Load 01");

        drive(1'b0, LOAD, 8'h7F, 1'b1);
        check(8'h7F, 4'b0000, "Load 7F");

        drive(1'b0, LOAD, 8'h80, 1'b1);
        check(8'h80, 4'b0100, "Load 80");

        drive(1'b0, LOAD, 8'hFF, 1'b1);
        check(8'hFF, 4'b0100, "Load FF");

        // ----------------------------------------------------
        // HOLD: Test 8
        // ----------------------------------------------------

        drive(1'b0, HOLD, 8'h55, 1'b1);
        check(8'hFF, 4'b0100, "Hold preserves data and flags");

        // ----------------------------------------------------
        // ADDITION: Tests 9-14
        // ----------------------------------------------------

        drive(1'b0, LOAD, 8'h05, 1'b1);
        drive(1'b0, ADD,  8'h03, 1'b1);
        check(8'h08, 4'b0000, "05 + 03: normal addition");

        drive(1'b0, LOAD, 8'h25, 1'b1);
        drive(1'b0, ADD,  8'h00, 1'b1);
        check(8'h25, 4'b0000, "25 + 00: add zero");

        drive(1'b0, LOAD, 8'hFF, 1'b1);
        drive(1'b0, ADD,  8'h02, 1'b1);
        check(8'h01, 4'b0010, "FF + 02: unsigned carry");

        drive(1'b0, LOAD, 8'h7F, 1'b1);
        drive(1'b0, ADD,  8'h01, 1'b1);
        check(8'h80, 4'b0101, "7F + 01: positive signed overflow");

        drive(1'b0, LOAD, 8'h80, 1'b1);
        drive(1'b0, ADD,  8'hFF, 1'b1);
        check(8'h7F, 4'b0011, "80 + FF: negative signed overflow");

        drive(1'b0, LOAD, 8'hFF, 1'b1);
        drive(1'b0, ADD,  8'h01, 1'b1);
        check(8'h00, 4'b1010, "FF + 01: zero and carry");

        // ----------------------------------------------------
        // SUBTRACTION: Tests 15-20
        // ----------------------------------------------------

        drive(1'b0, LOAD, 8'h08, 1'b1);
        drive(1'b0, SUB,  8'h03, 1'b1);
        check(8'h05, 4'b0010, "08 - 03: normal subtraction");

        drive(1'b0, LOAD, 8'h25, 1'b1);
        drive(1'b0, SUB,  8'h00, 1'b1);
        check(8'h25, 4'b0010, "25 - 00: subtract zero");

        drive(1'b0, LOAD, 8'h05, 1'b1);
        drive(1'b0, SUB,  8'h05, 1'b1);
        check(8'h00, 4'b1010, "05 - 05: equal operands");

        drive(1'b0, LOAD, 8'h00, 1'b1);
        drive(1'b0, SUB,  8'h01, 1'b1);
        check(8'hFF, 4'b0100, "00 - 01: unsigned borrow");

        drive(1'b0, LOAD, 8'h7F, 1'b1);
        drive(1'b0, SUB,  8'hFF, 1'b1);
        check(8'h80, 4'b0101, "7F - FF: positive signed overflow");

        drive(1'b0, LOAD, 8'h80, 1'b1);
        drive(1'b0, SUB,  8'h01, 1'b1);
        check(8'h7F, 4'b0011, "80 - 01: negative signed overflow");

        // ----------------------------------------------------
        // FLAG ENABLE: Tests 21-24
        // ----------------------------------------------------

        // Setup: ACC=00, ZNCV=1010.
        drive(1'b0, LOAD, 8'hFF, 1'b1);
        drive(1'b0, ADD,  8'h01, 1'b1);

        drive(1'b0, ADD, 8'h01, 1'b0);
        check(8'h01, 4'b1010, "ADD with flags disabled");

        drive(1'b0, SUB, 8'h02, 1'b0);
        check(8'hFF, 4'b1010, "SUB with flags disabled");

        drive(1'b0, LOAD, 8'h80, 1'b0);
        check(8'h80, 4'b1010, "LOAD with flags disabled");

        drive(1'b0, ADD, 8'h01, 1'b1);
        check(8'h81, 4'b0100, "Re-enable flag updates");

        // ----------------------------------------------------
        // FINAL SUMMARY
        // ----------------------------------------------------

        $display("");
        $display("Tests executed: %0d", tests);
        $display("Errors:         %0d", errors);

        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: TESTS FAILED");

        $finish;
    end

endmodule
