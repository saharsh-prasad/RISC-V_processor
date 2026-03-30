module riscv_processor(clk,reset);
input clk,reset;

reg [31:0] register_bank[0:31]; // register file

reg [31:0] PC,IF_ID_IR,IF_ID_NPC;
reg [31:0] ID_EX_A,ID_EX_B,ID_EX_IR,ID_EX_NPC,ID_EX_Imm;
reg [2:0] ID_EX_funct3;
reg [7:0] ID_EX_funct7; // 
reg [31:0] EX_MEM_ALUOut,EX_MEM_B,EX_MEM_IR;
reg EX_MEM_cond;
reg [31:0] MEM_WB_LMD,MEM_WB_ALUOut,MEM_WB_IR;
reg [2:0] ID_EX_type,EX_MEM_type,MEM_WB_type;

parameter
    OP_RTYPE  = 7'b0110011,  // ADD,SUB,AND,OR,SLT,MUL
    OP_ITYPE  = 7'b0010011,  // ADDI,SLTI,ANDI,ORI
    OP_LOAD   = 7'b0000011,  // LW
    OP_STORE  = 7'b0100011,  // SW
    OP_BRANCH = 7'b1100011,  // BEQ,BNE
    OP_HALT   = 7'b1111111;  // custom halt

// funct3 parameters:
parameter
    F3_ADD_SUB = 3'b000,
    F3_MUL     = 3'b000,
    F3_AND     = 3'b111,
    F3_OR      = 3'b110,
    F3_SLT     = 3'b010,
    F3_BEQ     = 3'b000,
    F3_BNE     = 3'b001,
    F3_LW_SW   = 3'b010;
//funct7 parameters:
parameter
    F7_ADD  = 7'b0000000,
    F7_SUB  = 7'b0100000,
    F7_MUL  = 7'b0000001,
    F7_AND = 7'b0000000,
    F7_OR  = 7'b0000000,
    F7_SLT = 7'b0000000;
// Instruction type parameters
parameter RR_ALU = 3'b000,
          RM_ALU = 3'b001,
          LOAD   = 3'b010,
          STORE  = 3'b011,
          BRANCH = 3'b100,
          HALT   = 3'b101;

reg HALTED,TAKEN_BRANCH;

wire [31:0] imem_data;
wire [31:0] dmem_read_data;
wire mem_write_en = (EX_MEM_type == STORE) && (!HALTED) && (!TAKEN_BRANCH);
instruction_memory imem_inst (.pc(PC), .instruction(imem_data));
data_memory dmem_inst (.clk(clk), .mem_write(mem_write_en), .address(EX_MEM_ALUOut), .write_data(EX_MEM_B), .read_data(dmem_read_data));
// Initialize register bank to 0
integer i;
initial begin 
    for(i=0; i<32; i=i+1) 
    register_bank[i] = 0;
end
//-------------------------------------------------------IF Stage------------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        PC <= 0;
        IF_ID_IR <= 0;
        IF_ID_NPC <= 0;
        TAKEN_BRANCH <= 0;
        HALTED <= 0;
    end
        else if (!HALTED) begin
            if ((EX_MEM_IR[6:0]==OP_BRANCH) && (EX_MEM_cond)) begin  //branch taken from EX stage
                TAKEN_BRANCH <=  1;
                IF_ID_NPC <=  EX_MEM_ALUOut;  // branch target
                PC <=  EX_MEM_ALUOut;  // update PC to branch target
                IF_ID_IR <= 0;  // flush the instruction in IF/ID pipeline register
            end
            else begin
                IF_ID_IR <= imem_data;  // fetch instruction
                TAKEN_BRANCH <= 0;
                IF_ID_NPC <=  PC + 4;  // next instruction
                PC <=  PC + 4;  // increment PC
            end
        end
    end
//--------------------------------------------------------ID Stage------------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        ID_EX_IR <= 0;
        ID_EX_NPC <= 0;
        ID_EX_A <= 0;
        ID_EX_B <= 0;
        ID_EX_Imm <= 0;
        ID_EX_funct3 <= 0;
        ID_EX_funct7 <= 0;
        ID_EX_type <= 3'b000;
    end
    else if (!HALTED) begin
    ID_EX_IR <= IF_ID_IR;  // decode instruction
    ID_EX_NPC <= IF_ID_NPC;
    ID_EX_funct3  <= IF_ID_IR[14:12];
    ID_EX_funct7 <= IF_ID_IR[31:25];
    case (IF_ID_IR[6:0])  // opcode
        OP_RTYPE: begin
            ID_EX_A <= register_bank[IF_ID_IR[19:15]];  // rs1
            ID_EX_B <= register_bank[IF_ID_IR[24:20]];  // rs2
            ID_EX_Imm <= 0;  // no immediate for R-type
            ID_EX_type <=  RR_ALU;
        end
        OP_ITYPE: begin
            ID_EX_A <= register_bank[IF_ID_IR[19:15]];  // rs1
            ID_EX_Imm  <= {{20{IF_ID_IR[31]}}, IF_ID_IR[31:20]};  // sign-extend immediate
            ID_EX_B <= 0;  // no second register operand for I-type
            ID_EX_type <= RM_ALU;
        end
        OP_LOAD: begin
            ID_EX_A <= register_bank[IF_ID_IR[19:15]];  // rs1=base
            ID_EX_Imm  <= {{20{IF_ID_IR[31]}}, IF_ID_IR[31:20]};  // sign-extend offset
            ID_EX_B <= 0;  
            ID_EX_type <= LOAD;
            
        end
        OP_STORE: begin
            ID_EX_A <=  register_bank[IF_ID_IR[19:15]];  // rs1=base
            ID_EX_B <= register_bank[IF_ID_IR[24:20]];  // rs2 (value to store)
            ID_EX_Imm  <= {{20{IF_ID_IR[31]}}, IF_ID_IR[31:25], IF_ID_IR[11:7]};  // sign-extend offset
            ID_EX_type <= STORE;
        end
        OP_BRANCH: begin
            ID_EX_A <= register_bank[IF_ID_IR[19:15]];  // rs1
            ID_EX_B    <= register_bank[IF_ID_IR[24:20]]; // rs2
            ID_EX_Imm  <= {{19{IF_ID_IR[31]}},
                               IF_ID_IR[31], IF_ID_IR[7],
                               IF_ID_IR[30:25], IF_ID_IR[11:8],
                               1'b0};
            
            ID_EX_type <= BRANCH;
        end
        OP_HALT: begin
            HALTED <= 1;
            ID_EX_type <= HALT;
        end
        default: ID_EX_type <= HALT;  // treat unknown instructions as halt
    endcase
    end
end
//-----------------------------------------------------------------EX Stage-------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        EX_MEM_IR <= 0;
        EX_MEM_ALUOut <= 0;
        EX_MEM_B <= 0;
        EX_MEM_cond <= 0;
        EX_MEM_type <= 3'b000;
    end
    else begin
    EX_MEM_IR <= ID_EX_IR;
    EX_MEM_B <= ID_EX_B;  // for store instruction
    if (!HALTED) begin
        case (ID_EX_type)
        RR_ALU: begin
            case ({ID_EX_funct7, ID_EX_funct3})  // opcode
                {F7_ADD,F3_ADD_SUB}: EX_MEM_ALUOut <= ID_EX_A + ID_EX_B;  //ADD
                {F7_SUB,F3_ADD_SUB}: EX_MEM_ALUOut <= ID_EX_A - ID_EX_B;  //SUB
                {F7_AND,F3_AND}: EX_MEM_ALUOut <= ID_EX_A & ID_EX_B; //AND
                {F7_OR,F3_OR}: EX_MEM_ALUOut <= ID_EX_A | ID_EX_B;  //OR
                {F7_SLT,F3_SLT}: EX_MEM_ALUOut <= ($signed(ID_EX_A) < $signed(ID_EX_B)) ? 1 : 0;  //SLT
                {F7_MUL,F3_MUL}: EX_MEM_ALUOut <= ID_EX_A * ID_EX_B; //MUL
                default: EX_MEM_ALUOut <= 32'b0; 
            endcase
            EX_MEM_type <= RR_ALU;
        end
        RM_ALU: begin
            case (ID_EX_funct3)
                F3_ADD_SUB: EX_MEM_ALUOut <= ID_EX_A + ID_EX_Imm; // ADDI
                F3_SLT : EX_MEM_ALUOut <= ($signed(ID_EX_A) < $signed(ID_EX_Imm)) ? 1 : 0; // SLTI
                F3_AND: EX_MEM_ALUOut <= ID_EX_A & ID_EX_Imm; // ANDI
                F3_OR: EX_MEM_ALUOut <= ID_EX_A | ID_EX_Imm;  // ORI
                default: EX_MEM_ALUOut <= 32'b0;
            endcase
            EX_MEM_type <= RM_ALU;
        end
        LOAD, STORE: begin
            EX_MEM_ALUOut <= ID_EX_A + ID_EX_Imm;  // calculate memory address
            EX_MEM_B <= ID_EX_B;  // for store instruction
            if (ID_EX_type == LOAD)
                EX_MEM_type <= LOAD;
            else
                EX_MEM_type <= STORE;
        end
        BRANCH: begin
            case (ID_EX_funct3)
            F3_BEQ: EX_MEM_cond <= (ID_EX_A == ID_EX_B) ? 1:0;
            F3_BNE: EX_MEM_cond <= (ID_EX_A != ID_EX_B) ? 1:0;
            default: EX_MEM_cond <= 0;
            endcase
            // B-type: target = PC + imm 
            EX_MEM_ALUOut <= ID_EX_NPC - 4 + ID_EX_Imm;
            EX_MEM_type   <= BRANCH;
            end
        HALT: HALTED <= 1;
        default: EX_MEM_type <= HALT;
        endcase
    end
end
end
//-----------------------------------------------------------------MEM Stage-------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        MEM_WB_IR <= 0;
        MEM_WB_ALUOut <= 0;
        MEM_WB_LMD <= 0;
        MEM_WB_type <= 3'b000;
    end else begin
    MEM_WB_IR <= EX_MEM_IR;
    if (!HALTED) begin
        case (EX_MEM_type)
            RR_ALU, RM_ALU: begin
                MEM_WB_ALUOut <= EX_MEM_ALUOut;
                MEM_WB_type <= EX_MEM_type;
            end
            LOAD: begin
                MEM_WB_LMD <= dmem_read_data;  // read from memory
                MEM_WB_type <= LOAD;
                
            end
            STORE: begin
                MEM_WB_type <= STORE;
            end
            BRANCH: ;  // no memory operation for branch
            HALT: HALTED <= 1;
            default: MEM_WB_type <= HALT;
        endcase
    end
    end
end
//-----------------------------------------------------------------WB Stage-------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
    end else if (!TAKEN_BRANCH) begin     // only write back if not a taken branch
        case (MEM_WB_type)
            RR_ALU,RM_ALU: if (MEM_WB_IR[11:7] != 5'b0)  // never write x0 register
            register_bank[MEM_WB_IR[11:7]] <= MEM_WB_ALUOut;
            
            LOAD: if (MEM_WB_IR[11:7] != 5'b0)
            register_bank[MEM_WB_IR[11:7]] <= MEM_WB_LMD;
            
            BRANCH, STORE, HALT: ;  // no write back for branch, store, or halt
        endcase
        end
    end
endmodule