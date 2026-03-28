module mips32_processor(clk1,clk2);
input clk1,clk2;

reg [31:0] register_bank[0:31]; // register file
reg [31:0] mem [0:1023];  // memory

reg [31:0] PC,IF_ID_IR,IF_ID_NPC;
reg [31:0] ID_EX_A,ID_EX_B,ID_EX_IR,ID_EX_NPC,ID_EX_Imm;
reg [31:0] EX_MEM_ALUOut,EX_MEM_B,EX_MEM_IR;
reg EX_MEM_cond;
reg [31:0] MEM_WB_LMD,MEM_WB_ALUOut,MEM_WB_IR;
reg [2:0] ID_EX_type,EX_MEM_type,MEM_WB_type;

//Assumed opcode of instructions
parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011,
          SLT=6'b000100, MUL=6'b000101, HLT=6'b111111, LW=6'b000110,
          SW=6'b001001, ADDI=6'b001010, SUBI=6'b001011, SLTI=6'b001100,
          BNEQZ=6'b001101, BEQZ=6'b001110;

reg HALTED,TAKEN_BRANCH;
parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010, STORE=3'b011, BRANCH=3'b100, HALT=3'b101;  // instruction types
//IF Stage
always @(posedge clk1) begin
        if (!HALTED) begin
            IF_ID_IR <= mem[PC];  // fetch instruction
            if (((EX_MEM_IR[31:26]==BNEQZ) & (EX_MEM_cond))|((EX_MEM_IR[31:26]==BEQZ) & (EX_MEM_cond))) begin
                TAKEN_BRANCH <= #2 1;
                IF_ID_NPC <= #2 EX_MEM_ALUOut;  // branch target
                PC <= #2 EX_MEM_ALUOut;  // update PC to branch target
            end
            else begin
                TAKEN_BRANCH <= 0;
                IF_ID_NPC <= #2 PC + 4;  // next instruction
                PC <= #2 PC + 4;  // increment PC
            end
        end
    end
//ID Stage
always @(posedge clk2) begin
    if (!HALTED) begin
    ID_EX_IR <= #2 IF_ID_IR;  // decode instruction
    ID_EX_NPC <= #2 IF_ID_NPC;
    case (IF_ID_IR[31:26])  // opcode
        ADD, SUB, AND, OR, SLT, MUL: begin
            ID_EX_A <= #2 register_bank[IF_ID_IR[25:21]];  // rs
            ID_EX_B <= #2 register_bank[IF_ID_IR[20:16]];  // rt
            ID_EX_type <= #2 RR_ALU;
        end
        ADDI, SUBI, SLTI: begin
            ID_EX_A <= #2 register_bank[IF_ID_IR[25:21]];  // rs
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};  // sign-extend immediate
            ID_EX_type <= #2 RM_ALU;
        end
        LW, SW: begin
            ID_EX_A <= #2 register_bank[IF_ID_IR[25:21]];  // base register
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};  // sign-extend offset
            if (IF_ID_IR[31:26] == LW)
                ID_EX_type <= #2 LOAD;
            else
                ID_EX_type <= #2 STORE;
        end
        BNEQZ, BEQZ: begin
            ID_EX_A <= #2 register_bank[IF_ID_IR[25:21]];  // rs
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};  // sign-extend offset
            ID_EX_type <= #2 BRANCH;
        end
        HLT: begin
            HALTED <= 1;
            ID_EX_type <= #2 HALT;
        end
        default: ID_EX_type <= #2 HALT;  // treat unknown instructions as halt
    endcase
    end
end
//EX Stage
always @(posedge clk1) begin
    EX_MEM_IR <= #2 ID_EX_IR;
    EX_MEM_B <= #2 ID_EX_B;  // for store instruction
    if (!HALTED) begin
        case (ID_EX_type)
        RR_ALU: begin
            case (ID_EX_IR[31:26])  // opcode
                ADD: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
                SUB: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
                AND: EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
                OR: EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
                SLT: EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_B) ? 1 : 0;
                MUL: EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
            endcase
            EX_MEM_type <= #2 RR_ALU;
        end
        RM_ALU: begin
            case (ID_EX_IR[31:26])  // opcode
                ADDI: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                SUBI: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
                SLTI: EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_Imm) ? 1 : 0;
            endcase
            EX_MEM_type <= #2 RM_ALU;
        end
        LOAD, STORE: begin
            EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;  // calculate memory address
            EX_MEM_B <= #2 ID_EX_B;  // store rt value for SW
            if (ID_EX_type == LOAD)
                EX_MEM_type <= #2 LOAD;
            else
                EX_MEM_type <= #2 STORE;
        end
        BRANCH: begin
            if ((ID_EX_IR[31:26] == BNEQZ && ID_EX_A != 0) || (ID_EX_IR[31:26] == BEQZ && ID_EX_A == 0)) begin
                EX_MEM_cond <= #2 1;  // branch taken
                EX_MEM_ALUOut <= #2 ID_EX_NPC + (ID_EX_Imm << 2);  // calculate branch target
            end else begin
                EX_MEM_cond <= #2 0;  // branch not taken
            end
            EX_MEM_type <= #2 BRANCH;
        end
        HALT: HALTED <= #2 1;
        default: EX_MEM_type <= #2 HALT;
    endcase
    end
end
//MEM Stage
always @(posedge clk2) begin
    MEM_WB_IR <= #2 EX_MEM_IR;
    if (!HALTED) begin
        case (EX_MEM_type)
            RR_ALU, RM_ALU: begin
                MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
                MEM_WB_type <= #2 EX_MEM_type;
            end
            LOAD: begin
                MEM_WB_LMD <= #2 mem[EX_MEM_ALUOut];  // read from memory
                MEM_WB_type <= #2 LOAD;
            end
            STORE: begin
                if (!TAKEN_BRANCH) mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;  // write to memory only if not a taken branch
                MEM_WB_type <= #2 STORE;
            end
            BRANCH: ;  // no memory operation for branch
            HALT: HALTED <= #2 1;
        endcase
    end
end
//WB Stage
always @(posedge clk1) begin
        if (!TAKEN_BRANCH) begin     // only write back if not a taken branch
        case (MEM_WB_type)
            RR_ALU: register_bank[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;  // write back to rd
            RM_ALU: register_bank[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;  // write back to rt
            LOAD: register_bank[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;  // write back to rt
            BRANCH, STORE, HALT: ;  // no write back for branch, store, or halt
        endcase
        end
    end
endmodule