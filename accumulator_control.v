`timescale 1ns / 1ps

// ============================================================
// DESIGN: Accumulator and Register Control Unit
// ============================================================

module accumulator_control (
    input  wire       clk,
    input  wire       rst,
    input  wire       flag_en,
    input  wire [1:0] op,
    input  wire [7:0] data_in,

    output reg  [7:0] acc,
    output reg        Z,
    output reg        N,
    output reg        C,
    output reg        V
);

    localparam HOLD = 2'b00,
               LOAD = 2'b01,
               ADD  = 2'b10,
               SUB  = 2'b11;

    reg [7:0] result;
    reg [8:0] extended_result;
    reg       carry_next;
    reg       overflow_next;

    // Calculate the next result and arithmetic flags.
    always @(*) begin
        result          = acc;
        extended_result = 9'b0;
        carry_next      = 1'b0;
        overflow_next   = 1'b0;

        case (op)
            HOLD: result = acc;

            LOAD: result = data_in;

            ADD: begin
                extended_result = {1'b0, acc}
                                + {1'b0, data_in};

                result     = extended_result[7:0];
                carry_next = extended_result[8];

                overflow_next = (~(acc[7] ^ data_in[7]))
                              & (result[7] ^ acc[7]);
            end

            SUB: begin
                result = acc - data_in;

                // C = 1 means no unsigned borrow.
                carry_next = (acc >= data_in);

                overflow_next = (acc[7] ^ data_in[7])
                              & (result[7] ^ acc[7]);
            end

            default: result = acc;
        endcase
    end

    // Synchronous active-high reset.
    always @(posedge clk) begin
        if (rst) begin
            acc <= 8'h00;
            Z   <= 1'b1;
            N   <= 1'b0;
            C   <= 1'b0;
            V   <= 1'b0;
        end
        else if (op != HOLD) begin
            acc <= result;

            if (flag_en) begin
                Z <= (result == 8'h00);
                N <= result[7];
                C <= carry_next;
                V <= overflow_next;
            end
        end
    end

endmodule
