# RISC-V Pipelined Processor

![Verilog](https://img.shields.io/badge/HDL-Verilog-blueviolet?style=flat-square)
![Architecture](https://img.shields.io/badge/ISA-RISC--V%20RV32I-blue?style=flat-square)
![Pipeline](https://img.shields.io/badge/Pipeline-5--Stage-green?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)
![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square)

A 32-bit, **5-stage pipelined RISC-V processor** implemented in Verilog, supporting a subset of the RV32I base integer instruction set along with the **M-extension** multiply instruction. Features full data forwarding, load-use hazard detection, and early branch resolution.

---

## Table of Contents

- [Features](#features)
- [Architecture Overview](#architecture-overview)
- [Pipeline Diagram](#pipeline-diagram)
- [Pipeline Registers](#pipeline-registers)
- [Hazard Handling](#hazard-handling)
- [Supported Instructions](#supported-instructions)
- [Module Structure](#module-structure)
- [Getting Started](#getting-started)
- [Future Improvements](#future-improvements)

---

## Features

| Feature | Details |
|---|---|
| **ISA** | RISC-V RV32I (subset) + M-extension MUL |
| **Pipeline Depth** | 5 stages (IF → ID → EX → MEM → WB) |
| **Data Width** | 32-bit |
| **Register File** | 32 × 32-bit general-purpose registers (x0 hardwired to 0) |
| **Data Forwarding** | Full forwarding from EX/MEM and MEM/WB stages |
| **Hazard Detection** | Load-use hazard stall (1-cycle bubble insertion) |
| **Branch Resolution** | Resolved in EX stage with 2-slot flush on taken branches |
| **Memory** | Separate instruction memory (`imem`) and data memory (`dmem`) |
| **Custom Instruction** | `HALT` (`opcode 7'b1111111`) for simulation control |

---

## Architecture Overview

The processor follows a classic **5-stage RISC pipeline** with Harvard memory architecture (separate instruction and data memories). Pipeline registers latch all state between stages, enabling overlapped execution of up to 5 instructions simultaneously.

Key design decisions:

- **Branch resolution in EX stage** — reduces branch penalty to 2 cycles (2 instructions flushed on a taken branch) rather than waiting until MEM.
- **Full data forwarding network** — results from EX/MEM and MEM/WB are forwarded back to the EX stage inputs, eliminating most RAW data hazards without stalling.
- **Load-use stall** — the one unavoidable hazard: when a `LW` result is immediately consumed by the next instruction, a single pipeline bubble is inserted by freezing IF/ID and injecting a NOP into ID/EX.
- **x0 protection** — writes to register `x0` are suppressed at both the WB stage and the forwarding logic, maintaining the hardwired-zero invariant.

---

## Pipeline Diagram

```
  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
  │    IF    │     │    ID    │     │    EX    │     │   MEM    │     │    WB    │
  │          │     │          │     │          │     │          │     │          │
  │ • Fetch  │     │ • Decode │     │ • ALU    │     │ • D-Mem  │     │ • RegWr  │
  │   instr  │     │ • RegRd  │     │   ops    │     │   read   │     │   (ALU/  │
  │   from   │     │ • Imm    │     │ • Addr   │     │   (LW)   │     │   Load)  │
  │  imem    │     │   extend │     │   calc   │     │ • D-Mem  │     │          │
  │ • PC+4   │     │ • Hazard │     │ • Branch │     │   write  │     │          │
  │          │     │   detect │     │   eval   │     │   (SW)   │     │          │
  └────┬─────┘     └────┬─────┘     └────┬─────┘     └────┬─────┘     └──────────┘
       │                │                │                 │
  ┌────▼─────┐     ┌────▼─────┐     ┌────▼─────┐     ┌────▼─────┐
  │  IF/ID   │     │  ID/EX   │     │  EX/MEM  │     │  MEM/WB  │
  │  IR,NPC  │     │  A,B,Imm │     │  ALUOut  │     │  ALUOut  │
  │          │     │  IR,NPC  │     │  B, IR   │     │  LMD, IR │
  │          │     │  type,f3 │     │  cond    │     │  type    │
  └──────────┘     └──────────┘     └──────────┘     └──────────┘

  ─────────────────────── Data Forwarding Paths ───────────────────────
  
  EX/MEM.ALUOut ──────────────────────────────────────► EX (rs1/rs2)
  MEM/WB.(ALUOut|LMD) ────────────────────────────────► EX (rs1/rs2)
  MEM/WB.(ALUOut|LMD) ────────────────────────────────► ID (rs1/rs2) [WB→ID]

  ─────────────────────── Branch / Hazard Control ──────────────────────

  Load-Use Hazard:  Stall IF+ID, inject NOP into ID/EX (1 cycle)
  Branch Taken:     Flush IF/ID → NOP, redirect PC to branch_target_ex
```

---

## Pipeline Registers

| Register | Fields | Description |
|---|---|---|
| `IF/ID` | `IR`, `NPC` | Fetched instruction & PC+4 |
| `ID/EX` | `A`, `B`, `Imm`, `IR`, `NPC`, `funct3`, `funct7`, `type` | Decoded operands & control |
| `EX/MEM` | `ALUOut`, `B`, `IR`, `cond`, `type` | ALU result, store data, branch cond |
| `MEM/WB` | `ALUOut`, `LMD`, `IR`, `type` | ALU result or loaded memory data |

---

## Hazard Handling

### Data Hazards — Full Forwarding

The forwarding unit monitors destination and source register addresses across pipeline stages and redirects data at the EX stage inputs:

```
Priority (highest → lowest):
  1. EX/MEM forward  (result from 1 cycle ago)
  2. MEM/WB forward  (result from 2 cycles ago)
  3. Register file   (no hazard)
```

A secondary WB→ID forward path handles the edge case where the write-back value is available just as the next-next instruction reads the register file.

### Load-Use Hazard — Stall

When an instruction immediately following `LW` reads the loaded register, forwarding alone cannot resolve the hazard (the data is not ready until after MEM). The hazard detection unit:

1. **Freezes** the `PC` and `IF/ID` register for one cycle.
2. **Injects a NOP** (`ADDI x0, x0, 0`) into `ID/EX`.
3. Resumes normal operation on the next cycle.

### Control Hazards — Branch Flush

Branches are evaluated in the **EX stage**. On a taken branch:

1. `PC` is updated to `branch_target_ex = ID_EX_NPC - 4 + ID_EX_Imm`.
2. The instruction currently in `IF/ID` is **flushed** (replaced with NOP).
3. The instruction currently in `ID/EX` is **flushed** via the stall/branch reset path.

This yields a **2-cycle branch penalty** only when the branch is taken.

---

## Supported Instructions

### R-Type — `opcode 0110011`

| Instruction | funct7 | funct3 | Operation | Extension |
|---|---|---|---|---|
| `ADD rd, rs1, rs2` | `0000000` | `000` | rd = rs1 + rs2 | RV32I |
| `SUB rd, rs1, rs2` | `0100000` | `000` | rd = rs1 − rs2 | RV32I |
| `AND rd, rs1, rs2` | `0000000` | `111` | rd = rs1 & rs2 | RV32I |
| `OR  rd, rs1, rs2` | `0000000` | `110` | rd = rs1 \| rs2 | RV32I |
| `SLT rd, rs1, rs2` | `0000000` | `010` | rd = (rs1 < rs2) ? 1 : 0 (signed) | RV32I |
| `MUL rd, rs1, rs2` | `0000001` | `000` | rd = rs1 × rs2 (lower 32 bits) | RV32M |

### I-Type — `opcode 0010011`

| Instruction | funct3 | Operation |
|---|---|---|
| `ADDI rd, rs1, imm` | `000` | rd = rs1 + sign_ext(imm[11:0]) |
| `SLTI rd, rs1, imm` | `010` | rd = (rs1 < sign_ext(imm)) ? 1 : 0 (signed) |
| `ANDI rd, rs1, imm` | `111` | rd = rs1 & sign_ext(imm) |
| `ORI  rd, rs1, imm` | `110` | rd = rs1 \| sign_ext(imm) |

### Load — `opcode 0000011`

| Instruction | funct3 | Operation |
|---|---|---|
| `LW rd, imm(rs1)` | `010` | rd = Mem[ rs1 + sign_ext(imm) ] |

### Store — `opcode 0100011`

| Instruction | funct3 | Operation |
|---|---|---|
| `SW rs2, imm(rs1)` | `010` | Mem[ rs1 + sign_ext(imm) ] = rs2 |

### Branch — `opcode 1100011`

| Instruction | funct3 | Operation |
|---|---|---|
| `BEQ rs1, rs2, offset` | `000` | if (rs1 == rs2) PC += sign_ext(offset) |
| `BNE rs1, rs2, offset` | `001` | if (rs1 != rs2) PC += sign_ext(offset) |

### Custom

| Instruction | opcode | Operation |
|---|---|---|
| `HALT` | `1111111` | Sets `HALTED` flag; freezes all pipeline stages |

---

## Module Structure

```
riscv_processor.v
│
├── riscv_processor          # Top-level: pipeline registers, control, forwarding
│   ├── instruction_memory   # imem_inst — ROM-style, read on PC
│   └── data_memory          # dmem_inst — synchronous write, async read
```

### Port List

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 | System clock |
| `reset` | Input | 1 | Active-high synchronous reset |

---

## Getting Started

### Prerequisites

- Any Verilog simulator: [Icarus Verilog](http://iverilog.icarus.com/), ModelSim, Vivado, etc.
- An `instruction_memory` and `data_memory` module (or stubs for simulation).

### Simulation (Icarus Verilog)

```bash
# Compile
iverilog -o riscv_sim riscv_processor.v instruction_memory.v data_memory.v tb_riscv.v

# Run
vvp riscv_sim

# View waveforms (optional)
gtkwave dump.vcd
```

### Reset Behaviour

Assert `reset` high for at least one clock cycle. All pipeline registers are cleared, the PC is set to `0x00000000`, and the register file is zeroed. De-assert `reset` to begin execution.

---

## Future Improvements

### 1. Hardware Performance Counters

A set of **on-chip performance monitoring registers** accessible via custom CSR (`Control and Status Register`) instructions, providing real-time microarchitectural telemetry without external instrumentation.

**Planned counters:**

| Counter | CSR Address | Description |
|---|---|---|
| `cycle` | `0xC00` | Total clock cycles elapsed |
| `instret` | `0xC02` | Instructions retired (committed to WB) |
| `stall_count` | `0xC03` | Cycles lost to load-use stalls |
| `branch_taken` | `0xC04` | Number of taken branches (flush events) |
| `branch_total` | `0xC05` | Total branch instructions executed |
| `mem_reads` | `0xC06` | Data memory read operations |
| `mem_writes` | `0xC07` | Data memory write operations |

**Implementation plan:**
- Add a `csr_regfile` module with 32-bit registers indexed by CSR address.
- Introduce `CSRRS`/`CSRRW` instructions (`opcode 1110011`) for reading/writing counters.
- Increment counters combinationally from pipeline stage control signals (e.g., increment `stall_count` when `load_use_hazard` is asserted).
- Expose IPC = `instret / cycle` for benchmarking.

---

### 2. Custom ISA Extension — `DOTPROD`

A **single-cycle dot product instruction** targeting signal processing and ML inference kernels, reducing a 4-element 8-bit dot product from ~12 instructions to 1.

**Instruction Encoding:**

```
 31      25 24    20 19    15 14  12 11     7 6       0
┌──────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000010  │  rs2   │  rs1   │ 000  │   rd   │ 0001011 │
└──────────┴────────┴────────┴──────┴────────┴─────────┘
  funct7      rs2     rs1    funct3    rd       opcode
               │       │                │
               └───────┘                └─ Destination register
         Packed 4×8-bit vectors
```

**Operation:**

```
rd = (rs1[7:0]   × rs2[7:0])   +
     (rs1[15:8]  × rs2[15:8])  +
     (rs1[23:16] × rs2[23:16]) +
     (rs1[31:24] × rs2[31:24])
```

Each register holds four packed 8-bit unsigned integers. The instruction computes a 32-bit accumulate of four 8-bit products in a single EX-stage cycle.

**Integration steps:**
1. Add `OP_CUSTOM0 = 7'b0001011` opcode parameter.
2. In the **ID stage**, decode `OP_CUSTOM0` → `RR_ALU` type, read `rs1`/`rs2` normally.
3. In the **EX stage**, add a `DOTPROD` case in the ALU that instantiates four 8×8 multipliers and a 4-input adder tree.
4. All existing forwarding, hazard detection, and WB logic works unchanged — the custom instruction is transparent to the pipeline control.

**Expected speedup:** For a 128-element dot product, instruction count drops from ~384 (3 instructions/element: `ANDI`, `MUL`, `ADD`) to ~32 (`DOTPROD` per group of 4 elements) — a **12× reduction** in instruction count.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

*Designed and implemented in Verilog as part of a computer architecture study. Contributions and issue reports are welcome.*
