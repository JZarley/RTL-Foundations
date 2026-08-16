# RTL Design and Verification Foundation
## Project purpose
This project develops reusable RTL blocks from explicit specifications, with emphasis on interface contracts, backpressure, parameterization, verification, debugging, and synthesis.

Designs are implemented in SystemVerilog and verified using directed testing, assertions, reference models, randomized traffic, and seeded regression.

## Toolchain
- SystemVerilog
- Verilator
- Yosys
- GTKWave
- Bash

## Implemented Blocks
### Ready/Valid One-Entry Buffer
#### Architecture
`DATA_WIDTH`-parameterized one-entry buffer using a ready/valid interface.

A handshake occurs only when `valid && ready` is true. The buffer stores one payload and applies backpressure
when it cannot store additional data. Output data and validity are maintained while the downstream consumer is
stalled.
#### Verificaton
Verified:
- reset behavior
- basic enqueue/dequeue operation
- producer and consumer stalls
- backpressure
- payload stability during stalls
- data integrity across transactions
### Parameterized Synchronous FIFO
#### Architecture
Parameterized by `DATA_WIDTH` and `DEPTH`.

The FIFO uses:
- an internal data array
- independent read and write pointers
- an occupancy counter
- ready/valid input and output interfaces

Input transfers occur when `in_valid && in_ready`; output transfers occur when `out_valid && out_ready`.

Enqueue-only operations increment occupancy, dequeue-only operations decrement occupancy, and simultaneous enqueue/dequeue transactions leave occupancy unchanged while advancing their respective pointers.

The design supports both full and empty boundary conditions, backpressure, sustained simultaneous transfers, pointer wraparound, and reset after prior activity.
#### Verification
Verified:
- reset behavior
- reset after prior FIFO activity
- post-reset transactions
- basic enqueue/dequeue operation
- sustained simultaneous enqueue/dequeue
- producer and consumer stalls
- backpressure
- payload stability during stalls
- full-boundary behavior and pointer wraparound
- data integrity across transactions
- randomized producer/consumer traffic
- long-sequence reference queue scoreboard checking
- concurrent assertations
- seeded multi-run regression

Manual functional coverage tracks the following:
- reaching empty
- reaching full
- read pointer wraparound
- write pointer wraparound
- output stalls
- simultaneous transfers
- input transactions
- output transactions

Note that input transactions will not equal output transactions if the FIFO is reset while not empty.

SystemVerilog functional coverage was not implemented due to incompatibility with the current Verilator testbench.
#### Verification Validation
To verify that the testbench detects real design failures, the following bugs were injected.

A stuck write pointer caused data corruption and was detected by a the scoreboard's expected output data check.

Incorrect occupancy counter modification on dequeue transaction was detected by the directed single-entry test since the FIFO did not return to an empty state when the expected queue was empty.

These bugs were removed after verification.
#### Synthesis
The FIFO was synthesized with Yosys.

For `DATA_WIDTH=32` and `DEPTH=4`, the design contains 128 bits of FIFO storage. Yosys synthesized this design into enabled flip-flops rather than using a memory primitive. Additional sequential logic implements FIFO state such as the read and write pointers as well as the occupancy counter, with combinational MUX and control logic supporting the state elements.  
## Verification Infrastructure
The project uses reusable verification infrastructure rather than relying exclusively on design-specific directed tests.
### Reference Model and Scoreboard
Testbench automatically maintains an independent model of expected DUT behavior. Expected transactions on the DUT update the reference model, and DUT outputs are compared against expected results.
### Assertions
SystemVerilog property assertions are used to continuously check interface and design invariants, including conditions such as data stability during stalls and legal FIFO boundary behavior.
### Randomized Testing
Random producers and consumers are told how many transactions to enact, but data sent is randomized and the producer/consumer decides whether or not to send/recieve data on a given cycle. This generates varying transaction and stall patterns to cover interactions that directed tests may not target.
### Seeded Regression
The regression script executes the verification flow across multiple seeds, providing greater diversity of state and transaction sequences while preserving reproducibility of failures. The script stops upon the failure of any seed, and each seed's output is logged individually.
### Coverage
Coverage is used to distinguish successful assertations from actually verifying edge behaviors. The current environment uses explicit counters and flags to confirm that critical states and transitions occurred.
## Running the Flow
Run the standard flow for a given module with `./scripts/run_flow.sh <design> <seed (optional; default = 1)>`. Run a regression for a given module with `./scripts/run_flow.sh <design> <num_cycles (optional; default = 1)>`. Simulation logs, waveforms, and synthesis are generated by these scripts for inspection and debugging.
## Current Status
Completed:
- ready/valid one-entry buffer
- parameterized synchronous FIFO with directed and randomized verification, assertions, coverage tracking, multi-seed regression, bug injection, and synthesis inspection