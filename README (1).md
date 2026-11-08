# Accumulator and Register Control Unit

An 8-bit accumulator with a 2-bit operation select and four status flags (Zero, Negative, Carry, Overflow), written in synthesizable Verilog, together with a self-checking testbench of 24 directed tests.

---

## Table of Contents

1. [Overview](#overview)
2. [Files](#files)
3. [Module Interface](#module-interface)
4. [Operations](#operations)
5. [Status Flags](#status-flags)
6. [Behavior Details](#behavior-details)
7. [Internal Architecture](#internal-architecture)
8. [Testbench](#testbench)
9. [Test Plan](#test-plan)
10. [Running the Simulation](#running-the-simulation)
11. [Expected Output](#expected-output)
12. [Synthesis Notes](#synthesis-notes)
13. [Design Notes and Limitations](#design-notes-and-limitations)
14. [Possible Extensions](#possible-extensions)

---

## Overview

`accumulator_control` models the core of a simple CPU datapath: a single 8-bit accumulator register that can hold its value, load an external value, or add/subtract an external operand. After each operation, the module can optionally update a set of condition flags (Z, N, C, V) that describe the result.

Key characteristics:

- **8-bit** accumulator and data input
- **Four operations**: HOLD, LOAD, ADD, SUB
- **Four flags**: Zero (Z), Negative (N), Carry (C), Overflow (V)
- **Synchronous, active-high reset**
- **Flag-enable control** so flags can be frozen independently of the accumulator
- **Single clock domain**, rising-edge triggered
- **Combinational next-state logic** separated from the **sequential register update**

---

## Files

```
.
├── README.md
├── accumulator_control.v       # Design (synthesizable)
└── tb_accumulator_control.v    # Self-checking testbench (simulation only)
```

| File | Contents |
|------|----------|
| `accumulator_control.v` | The synthesizable design module `accumulator_control` |
| `tb_accumulator_control.v` | The testbench module `tb_accumulator_control` with 24 directed tests |
| `README.md` | This documentation |

> The design and testbench are in separate files. Synthesize only `accumulator_control.v`. The testbench is for simulation only and instantiates the design as `dut`, so both files must be compiled together.

---

## Module Interface

```verilog
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
```

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | Clock. All state updates occur on the rising edge. |
| `rst` | in | 1 | Synchronous, active-high reset. Takes priority over everything else. |
| `flag_en` | in | 1 | When high, flags are updated along with the accumulator. When low, flags keep their previous values. |
| `op` | in | 2 | Operation select (see [Operations](#operations)). |
| `data_in` | in | 8 | External operand used by LOAD, ADD and SUB. Ignored for HOLD. |
| `acc` | out | 8 | Accumulator register value. |
| `Z` | out | 1 | Zero flag. |
| `N` | out | 1 | Negative flag. |
| `C` | out | 1 | Carry flag (carry-out for ADD, no-borrow for SUB). |
| `V` | out | 1 | Signed overflow flag. |

---

## Operations

| `op` | Name | Action on `acc` |
|------|------|-----------------|
| `2'b00` | HOLD | `acc` unchanged |
| `2'b01` | LOAD | `acc <= data_in` |
| `2'b10` | ADD | `acc <= acc + data_in` |
| `2'b11` | SUB | `acc <= acc - data_in` |

---

## Status Flags

Flags are always listed in the order **Z N C V** (this is also the bit order used in the testbench, e.g. `4'b1010` means Z=1, N=0, C=1, V=0).

### Z: Zero

Set when the result is `8'h00`.

```
Z = (result == 8'h00)
```

### N: Negative

Copy of the result's most significant bit (the sign bit in two's complement).

```
N = result[7]
```

### C: Carry

Meaning depends on the operation:

| Operation | Meaning of C |
|-----------|--------------|
| ADD | Carry-out of bit 7 (unsigned overflow). `C = 1` when the 9-bit sum exceeds 255. |
| SUB | **No borrow** convention. `C = 1` when `acc >= data_in` (unsigned). `C = 0` means a borrow occurred. |
| LOAD | Cleared to 0 (when flags are enabled). |

This "C = no borrow" convention for subtraction matches ARM-style processors (and is the inverse of the borrow convention used by x86).

### V: Signed Overflow

Set when the true signed result does not fit in 8 bits (range -128 to +127).

| Operation | Condition for V = 1 |
|-----------|---------------------|
| ADD | Both operands have the **same** sign, and the result's sign differs from them |
| SUB | Operands have **different** signs, and the result's sign differs from the original `acc` sign |
| LOAD | Cleared to 0 (when flags are enabled) |

Equations used in the RTL:

```verilog
// ADD
overflow_next = (~(acc[7] ^ data_in[7])) & (result[7] ^ acc[7]);

// SUB
overflow_next = (acc[7] ^ data_in[7]) & (result[7] ^ acc[7]);
```

---

## Behavior Details

Priority of actions on each rising clock edge:

1. **Reset** (`rst = 1`): `acc = 00`, `Z = 1`, `N = 0`, `C = 0`, `V = 0`. Overrides `op` and `flag_en`.
2. **HOLD** (`op = 00`): nothing changes. Both `acc` **and the flags** are preserved, even if `flag_en = 1`.
3. **LOAD / ADD / SUB** (`op != 00`): `acc` always takes the new result. The flags take their new values only if `flag_en = 1`; otherwise they keep their old values.

Summary table:

| `rst` | `op` | `flag_en` | `acc` | Flags |
|-------|------|-----------|-------|-------|
| 1 | any | any | cleared to 00 | reset to Z=1, N=0, C=0, V=0 |
| 0 | HOLD | any | unchanged | unchanged |
| 0 | LOAD/ADD/SUB | 0 | updated | unchanged |
| 0 | LOAD/ADD/SUB | 1 | updated | updated |

---

## Internal Architecture

The design is split into two always blocks.

### 1. Combinational block: `always @(*)`

Computes the next accumulator value (`result`) and the next arithmetic flags (`carry_next`, `overflow_next`) from the current `acc`, `data_in` and `op`.

Internal signals:

| Signal | Width | Purpose |
|--------|-------|---------|
| `result` | 8 | Next accumulator value |
| `extended_result` | 9 | Zero-extended sum used to capture the ADD carry-out |
| `carry_next` | 1 | Next C value |
| `overflow_next` | 1 | Next V value |

All outputs of this block are assigned defaults at the top, so no latches are inferred. The `default` case in the `case (op)` statement also maps unexpected values to HOLD behavior.

ADD datapath:

```verilog
extended_result = {1'b0, acc} + {1'b0, data_in};
result          = extended_result[7:0];
carry_next      = extended_result[8];
```

SUB datapath:

```verilog
result     = acc - data_in;
carry_next = (acc >= data_in);
```

### 2. Sequential block: `always @(posedge clk)`

Registers `acc`, `Z`, `N`, `C` and `V`. Implements the reset / HOLD / flag-enable priority described above. Z and N are derived directly from `result` at update time.

### Block diagram (conceptual)

```
                +------------------------------+
 acc ---------->|                              |
 data_in ------>|   Combinational ALU logic    |--> result
 op ----------->|  (HOLD / LOAD / ADD / SUB)   |--> carry_next
                |                              |--> overflow_next
                +------------------------------+
                               |
                               v
                +------------------------------+
 clk ---------->|  Register + flag update      |--> acc
 rst ---------->|  (sync reset, flag_en gate)  |--> Z, N, C, V
 flag_en ------>|                              |
                +------------------------------+
                               |
                               +--> acc fed back to ALU
```

---

## Testbench

Module: `tb_accumulator_control`

The testbench is self-checking: it applies directed stimulus, compares the accumulator and flags against expected values, prints PASS/FAIL per test, and prints a final summary.

### Clock

10 ns period (100 MHz), generated with `always #5 clk = ~clk;`.

### Tasks

**`drive(reset_value, operation, operand, update_flags)`**
Waits for a falling clock edge, applies the inputs, then waits for the next rising edge plus 1 ns. Inputs change away from the active edge, which avoids race conditions between stimulus and the DUT.

**`check(expected_acc, expected_flags, test_name)`**
Increments the test counter and compares `acc` and `{Z, N, C, V}` with expected values using `!==` (so X/Z values are treated as failures). Prints either:

```
PASS <n>: <name> | ACC=<hex> ZNCV=<bits>
```

or

```
FAIL <n>: <name>
  Actual: ACC=<hex> ZNCV=<bits> | Expected: ACC=<hex> ZNCV=<bits>
```

### Counters

- `tests`: total checks executed
- `errors`: number of failed checks

The run ends with `RESULT: ALL TESTS PASSED` or `RESULT: TESTS FAILED`, followed by `$finish`.

---

## Test Plan

Flag column order is **ZNCV**.

### Reset (Tests 1-2)

| # | Description | Expected ACC | Expected ZNCV |
|---|-------------|--------------|---------------|
| 1 | Reset at startup | 00 | 1000 |
| 2 | Reset overrides ADD and flag-disable (after loading 7F and adding 01) | 00 | 1000 |

### LOAD (Tests 3-7)

| # | Description | ACC | ZNCV |
|---|-------------|-----|------|
| 3 | Load 00 | 00 | 1000 |
| 4 | Load 01 | 01 | 0000 |
| 5 | Load 7F | 7F | 0000 |
| 6 | Load 80 | 80 | 0100 |
| 7 | Load FF | FF | 0100 |

### HOLD (Test 8)

| # | Description | ACC | ZNCV |
|---|-------------|-----|------|
| 8 | Hold preserves data and flags (`data_in = 55`, `flag_en = 1`) | FF | 0100 |

### ADD (Tests 9-14)

| # | Operation | ACC | ZNCV | What it exercises |
|---|-----------|-----|------|-------------------|
| 9 | 05 + 03 | 08 | 0000 | Normal addition |
| 10 | 25 + 00 | 25 | 0000 | Adding zero |
| 11 | FF + 02 | 01 | 0010 | Unsigned carry |
| 12 | 7F + 01 | 80 | 0101 | Positive signed overflow |
| 13 | 80 + FF | 7F | 0011 | Negative signed overflow (with carry) |
| 14 | FF + 01 | 00 | 1010 | Zero result with carry |

### SUB (Tests 15-20)

| # | Operation | ACC | ZNCV | What it exercises |
|---|-----------|-----|------|-------------------|
| 15 | 08 - 03 | 05 | 0010 | Normal subtraction (C=1, no borrow) |
| 16 | 25 - 00 | 25 | 0010 | Subtract zero |
| 17 | 05 - 05 | 00 | 1010 | Equal operands, zero result |
| 18 | 00 - 01 | FF | 0100 | Unsigned borrow (C=0) |
| 19 | 7F - FF | 80 | 0101 | Positive signed overflow |
| 20 | 80 - 01 | 7F | 0011 | Negative signed overflow |

### Flag Enable (Tests 21-24)

Setup: ACC = 00, ZNCV = 1010 (from FF + 01).

| # | Description | ACC | ZNCV |
|---|-------------|-----|------|
| 21 | ADD 01 with flags disabled | 01 | 1010 (frozen) |
| 22 | SUB 02 with flags disabled | FF | 1010 (frozen) |
| 23 | LOAD 80 with flags disabled | 80 | 1010 (frozen) |
| 24 | ADD 01 with flags re-enabled | 81 | 0100 |

### Coverage summary

| Area | Tests |
|------|-------|
| Reset | 2 |
| LOAD | 5 |
| HOLD | 1 |
| ADD | 6 |
| SUB | 6 |
| Flag enable | 4 |
| **Total** | **24** |

---

## Running the Simulation

Compile both files together, with the design and the testbench. The top-level module for simulation is `tb_accumulator_control`.

### Icarus Verilog

```bash
iverilog -o accumulator_sim accumulator_control.v tb_accumulator_control.v
vvp accumulator_sim
```

### ModelSim / Questa

```tcl
vlib work
vlog accumulator_control.v tb_accumulator_control.v
vsim -c tb_accumulator_control -do "run -all; quit"
```

### Xilinx Vivado (xsim, command line)

```bash
xvlog accumulator_control.v tb_accumulator_control.v
xelab tb_accumulator_control -s accumulator_sim
xsim accumulator_sim -runall
```

### Vivado GUI

1. Create a project, add `accumulator_control.v` as a design source and `tb_accumulator_control.v` as a simulation source.
2. Set `tb_accumulator_control` as the simulation top module.
3. Run Behavioral Simulation.

### Optional waveform dump

The testbench does not dump waveforms by default. To view them in GTKWave, add this inside the testbench's first `initial` block (or in a separate `initial` block):

```verilog
$dumpfile("accumulator.vcd");
$dumpvars(0, tb_accumulator_control);
```

Then open the file:

```bash
gtkwave accumulator.vcd
```

---

## Expected Output

A passing run should print lines in this format (first few shown, then the summary):

```
Accumulator Control Unit Simulation
Flag order: Z N C V

PASS 1: Reset at startup | ACC=00 ZNCV=1000
PASS 2: Reset overrides ADD and flag disable | ACC=00 ZNCV=1000
PASS 3: Load 00 | ACC=00 ZNCV=1000
...
PASS 24: Re-enable flag updates | ACC=81 ZNCV=0100

Tests executed: 24
Errors:         0
RESULT: ALL TESTS PASSED
```

---

## Synthesis Notes

- Synthesize only `accumulator_control.v`. The testbench (`tb_accumulator_control.v`) uses `$display`, `$finish`, delays, and a 512-bit string argument, none of which are synthesizable.
- The design is fully synchronous with a single clock and a synchronous reset, so it maps cleanly to FPGA flip-flops (including the reset-to-register mapping on Xilinx and Intel devices).
- Register count: 8 (`acc`) + 4 (flags) = 12 flip-flops.
- The combinational logic is an 8-bit adder/subtractor plus a small mux and comparator. The `acc >= data_in` comparison used for the SUB carry may be implemented through the subtractor's carry chain by the synthesis tool.
- No latches are inferred, because every output is assigned a default value at the beginning of the combinational block.
- The `timescale 1ns / 1ps` directive is only relevant to simulation.

---

## Design Notes and Limitations

- **Outputs before reset:** `acc` and the flags have no initial value, so they are unknown (X) in simulation until the first reset. The testbench applies reset at startup for this reason. In real hardware, assert `rst` after power-up.
- **HOLD freezes flags:** even with `flag_en = 1`, HOLD does not recompute flags. If you want HOLD to refresh Z/N from the current accumulator, the sequential block must be changed.
- **LOAD affects C and V:** when `flag_en = 1`, LOAD sets C and V to 0 (and updates Z and N from the loaded value).
- **Subtraction carry convention:** C = 1 means *no borrow*. Be careful if you compare against reference models that use the opposite (borrow) convention.
- **`op` default case:** since `op` is 2 bits wide and all four values are defined, the `default` branch is unreachable in practice. It is kept for safety, and to cover X/Z inputs in simulation.
- **Testbench scope:** the tests are directed, not randomized. Combinations not covered include back-to-back operations with changing `flag_en`, reset in the middle of flag-disabled operations, and a broad sweep of operand values.
- **Reset test caveat:** Test 2 checks that reset overrides `flag_en = 0` and a non-HOLD op, but it does not separately check reset with HOLD.

---

## Possible Extensions

- Additional operations: AND, OR, XOR, NOT, shift left/right, increment/decrement
- Add-with-carry (ADC) and subtract-with-borrow (SBC) using the stored C flag, for multi-byte arithmetic
- Parameterized data width (`parameter WIDTH = 8`)
- Randomized or constrained-random testbench with a reference model and scoreboard
- Waveform dumping and coverage collection built into the testbench
- Formal verification of flag equations against an arithmetic reference
- A top-level wrapper for FPGA boards, with switches for `data_in` and LEDs for `acc` and flags
