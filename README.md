# RISC-V Pipelined Processor

A 5-stage pipelined RISC-V processor (RV32IM subset) implemented in Verilog RTL.  
Supports data forwarding, load-use hazard stall insertion, and branch resolution in the EX stage.

---

## Pipeline Architecture

```
          ┌──────────────────────────────────────────────────────────────────────────────────┐
          │                     5-Stage RISC-V Pipeline                                      │
          └──────────────────────────────────────────────────────────────────────────────────┘

 ┌─────────────┐   IF/ID    ┌─────────────┐   ID/EX    ┌─────────────┐   EX/MEM   ┌─────────────┐   MEM/WB   ┌─────────────┐
 │     IF      │ ─────────► │     ID      │ ─────────► │     EX      │ ─────────► │     MEM     │ ─────────► │     WB      │
 │  (Fetch)    │            │  (Decode)   │            │  (Execute)  │            │  (Memory)   │            │ (Write-Back)│
 │             │            │             │            │             │            │             │            │             │
 │ imem_data   │            │ Reg Read    │            │ ALU         │            │ dmem R/W    │            │ Reg Write   │
 │ PC + 4      │            │ Imm Extend  │            │ Branch Res  │            │             │            │             │
 └─────────────┘            └─────────────┘            └─────────────┘            └─────────────┘            └─────────────┘
        │                                                     │                          │                          │
        │◄────────── Branch Flush (PC ← branch target) ───────┘                          │                          │
        │                                                                                 │                          │
        │                   ┌─────────────────────────────────────────────────────────────┘                          │
        │                   │                   Forwarding: MEM/WB → EX                                              │
        │                   │          ┌─────────────────────────────────────────────────────────────────────────────┘
        │                   │          │            Forwarding: MEM/WB → EX (wb_write_data → ID read)
        │                   │          │
        │         ┌──────────▼──────────▼──────────────────────┐
        │         │          Forwarding Unit                    │
        │         │  EX/MEM  ──► EX  (RR_ALU / RM_ALU results) │
        │         │  MEM/WB  ──► EX  (ALU result or Load data)  │
        │         │  MEM/WB  ──► ID  (WB write-back → reg read) │
        │         └────────────────────────────────────────────┘
        │
        │         ┌────────────────────────────────────────────┐
        │         │          Hazard Detection Unit             │
        └─────────│  Load-Use: stall 1 cycle + bubble in ID    │
                  └────────────────────────────────────────────┘
```

### Pipeline Registers

| Register  | Fields Carried Forward                                          |
|-----------|-----------------------------------------------------------------|
| `IF/ID`   | `IR` (instruction), `NPC` (PC+4)                               |
| `ID/EX`   | `IR`, `NPC`, `A`, `B`, `Imm`, `funct3`, `funct7`, `type`       |
| `EX/MEM`  | `IR`, `ALUOut`, `B`, `cond` (branch taken), `type`             |
| `MEM/WB`  | `IR`, `ALUOut`, `LMD` (load memory data), `type`               |

### Hazard Handling Summary

| Hazard Type        | Detection                             | Resolution                                  |
|--------------------|---------------------------------------|---------------------------------------------|
| ALU → ALU          | Forwarding unit (EX/MEM or MEM/WB)   | Data forwarded to EX stage; no stall        |
| Load → Use         | `ID_EX_type == LOAD` + dest == src   | Stall 1 cycle, insert NOP bubble in ID/EX  |
| Branch (taken)     | Resolved in EX stage                  | Flush IF and ID stages; redirect PC         |

---

## Supported Instructions

### R-Type (opcode `0110011`)

| Instruction | funct7      | funct3  | Operation                      |
|-------------|-------------|---------|--------------------------------|
| `ADD`       | `0000000`   | `000`   | rd = rs1 + rs2                 |
| `SUB`       | `0100000`   | `000`   | rd = rs1 − rs2                 |
| `AND`       | `0000000`   | `111`   | rd = rs1 & rs2                 |
| `OR`        | `0000000`   | `110`   | rd = rs1 \| rs2                |
| `SLT`       | `0000000`   | `010`   | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| `MUL`       | `0000001`   | `000`   | rd = rs1 × rs2 (low 32 bits)  |

### I-Type (opcode `0010011`)

| Instruction | funct3  | Operation                               |
|-------------|---------|-----------------------------------------|
| `ADDI`      | `000`   | rd = rs1 + sign\_ext(imm[11:0])         |
| `SLTI`      | `010`   | rd = (rs1 < sign\_ext(imm)) ? 1 : 0 (signed) |
| `ANDI`      | `111`   | rd = rs1 & sign\_ext(imm)               |
| `ORI`       | `110`   | rd = rs1 \| sign\_ext(imm)              |

### Load (opcode `0000011`)

| Instruction | funct3  | Operation                                      |
|-------------|---------|------------------------------------------------|
| `LW`        | `010`   | rd = Mem[rs1 + sign\_ext(imm[11:0])] (32-bit) |

### Store (opcode `0100011`)

| Instruction | funct3  | Operation                                       |
|-------------|---------|--------------------------------------------------|
| `SW`        | `010`   | Mem[rs1 + sign\_ext(imm)] = rs2 (32-bit)        |

### Branch (opcode `1100011`)

| Instruction | funct3  | Operation                                  |
|-------------|---------|--------------------------------------------|
| `BEQ`       | `000`   | if (rs1 == rs2) PC ← PC + sign\_ext(imm)  |
| `BNE`       | `001`   | if (rs1 ≠ rs2)  PC ← PC + sign\_ext(imm)  |

### Custom

| Instruction | opcode    | Operation            |
|-------------|-----------|----------------------|
| `HALT`      | `1111111` | Stop pipeline execution |

---

## Module Overview

| Module               | File                    | Description                                      |
|----------------------|-------------------------|--------------------------------------------------|
| `riscv_processor`    | `code/riscv_processor.v`| Top-level 5-stage pipelined processor            |
| `instruction_memory` | `code/instruction_memory.v` | Asynchronous read-only instruction memory (1K words) |
| `data_memory`        | `code/data_memory.v`    | Synchronous read/write data memory (1K words)    |

### Memory

- **Instruction Memory**: 1024 × 32-bit words, asynchronous read, word-addressed via `pc[11:2]`
- **Data Memory**: 1024 × 32-bit words, synchronous write, asynchronous read, word-addressed via `address[11:2]`
- **Register File**: 32 × 32-bit registers; `x0` is hardwired to zero (never written)

---

## Key Design Details

- **ISA Base**: RV32I with M-extension (`MUL`)
- **Pipeline depth**: 5 stages (IF → ID → EX → MEM → WB)
- **Forwarding paths**: EX/MEM → EX, MEM/WB → EX, MEM/WB → ID (WB bypass)
- **Branch penalty**: 2 cycles on taken branch (IF and ID stages flushed)
- **Immediate formats**: I, S, B-type immediates correctly sign-extended per RISC-V spec
- **Reset**: Synchronous; clears PC, pipeline registers, and register file
