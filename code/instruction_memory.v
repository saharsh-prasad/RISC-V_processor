module instruction_memory(
    input  [31:0] pc,
    output [31:0] instruction
);
reg [31:0] imem [0:1023]; 
integer i;
initial begin
    for (i=0; i<1024; i=i+1)
    imem[i] = 32'b0;
    end
assign instruction = imem[pc[31:2]];
endmodule