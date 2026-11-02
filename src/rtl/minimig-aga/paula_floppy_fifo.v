//2048 words deep, 16 bits wide, fifo
//data is written into the fifo when wr=1
//reading is more or less asynchronous if you read during the rising edge of clk
//because the output data is updated at the falling edge of the clk
//when rd=1, the next data word is selected 


module paula_floppy_fifo
(
	input		  clk, // bus clock
	input		  clk7_en,
	input		  reset, // reset 
	input [15:0]	  in, // data in
	output     [15:0] out, // data out
	input		  rd, // read from fifo
	input		  wr, // write to fifo
	output		  empty, // fifo is empty (a net: it is driven by an assign below)
	output		  full  // fifo is full
);

//local signals and registers
reg 	[15:0] mem [2047:0];	// 2048 words by 16 bit wide fifo memory (for 2 MFM-encoded sectors)
reg	[11:0] in_ptr;		// fifo input pointer
reg	[11:0] out_ptr;		// fifo output pointer

// check lower 11 bits of pointer to generate equal signal
wire   equal = (in_ptr[10:0]==out_ptr[10:0]);
assign empty = (equal && (in_ptr[11] == out_ptr[11]));
assign full =  (equal && (in_ptr[11] != out_ptr[11]));

// karabas: the memory as a block RAM (ISE built it from LUTs, ~1.1k). The output is either the
// RAM read register or a bypass register with the input word, exactly as NanoMig's 'out':
// - read with the head advancing and no bypass: the RAM reads mem[out_ptr+1] (read-first, as the
//   non-blocking read of the original) and keeps it until the next such read;
// - write into an empty fifo, or a read right after it: the input word, through the bypass.
reg        empty_write;
reg [15:0] ram_q;        // RAM read register
reg [15:0] bypass_q;     // input word written into an empty fifo
reg        bypass_sel;
wire       ram_rd = clk7_en && !reset && rd && !empty && !empty_write;
wire       ram_wr = clk7_en && !reset && wr && !full;

always @(posedge clk) begin
   if (ram_wr) mem[in_ptr[10:0]] <= in;
   if (ram_rd) ram_q <= mem[out_ptr[10:0] + 11'd1];
end

assign out = bypass_sel ? bypass_q : ram_q;

always @(posedge clk) begin
   if (clk7_en) begin
      empty_write <= 1'b0;
      
      if (reset) begin
  	 in_ptr <= 12'd0;
  	 out_ptr <= 12'd0;
	 empty_write <= 1'b0;
      end else begin
  	 if(rd && !empty) begin
	    // karabas: a read of the only word with a write in the same cycle: the new head is the
	    // word being written, which the read-first RAM does not return yet (it gave a stale word,
	    // the read errors of a physical drive, whose fifo holds 0-1 words)
	    if(empty_write || (wr && !full && in_ptr == out_ptr + 12'd1)) begin bypass_q <= in; bypass_sel <= 1'b1; end
	    else            bypass_sel <= 1'b0;    // ram_q <= mem[out_ptr + 1]
  	    out_ptr <= out_ptr + 12'd1;
	 end
	 if(wr && !full) begin
  	    in_ptr <= in_ptr + 12'd1;              // mem[in_ptr] <= in
	    if(empty) begin
	       bypass_q <= in;
	       bypass_sel <= 1'b1;
	       empty_write <= 1'b1;	       
	    end
	 end
      end
   end
end
   
endmodule

