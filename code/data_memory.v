module data_memory(
    input         clk,
    input         mem_write,
    input  [31:0] address,
    input  [31:0] write_data,
    output [31:0] read_data
);
reg [31:0] dmem [0:1023];
integer i;
initial begin  // Initialize data memory to 0
    for (i=0; i<1024; i=i+1)
    dmem[i] = 32'b0;
    end
assign read_data = dmem[address[31:2]]; 
always @(posedge clk) if (mem_write) dmem[address[31:2]] <= write_data;
endmodule