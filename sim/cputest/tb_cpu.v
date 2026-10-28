// Runs a 64 KB test image on cpu_65c02 with a synchronous memory (read data
// the clock after the address, as the core expects) until the program loops
// on itself (JMP * or a branch to itself), then reports where.
// +image=<file.hex> (one byte per line, 65536 lines), +pass=<hex address>,
// +start=<hex address> (put in the reset vector), +max=<cycles>.
`timescale 1ns/1ps
module tb_cpu;
    reg         clk = 0;
    reg         reset = 1;
    wire [15:0] AB;
    reg  [7:0]  DI;
    wire [7:0]  DO;
    wire        WE, SYNC;
    reg  [7:0]  mem [0:65535];

    cpu_65c02 cpu (.clk(clk), .reset(reset), .AB(AB), .DI(DI), .DO(DO),
                   .WE(WE), .IRQ(1'b0), .NMI(1'b0), .RDY(1'b1), .SYNC(SYNC));

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (WE) mem[AB] <= DO;
        DI <= mem[AB];
    end

    reg [1023:0] image;
    reg [15:0]   pass, start, last_pc;
    integer      max, cycles, same;

    initial begin
        if (!$value$plusargs("image=%s", image)) begin $display("FAIL: no +image"); $finish; end
        if (!$value$plusargs("pass=%h", pass)) begin $display("FAIL: no +pass"); $finish; end
        if (!$value$plusargs("start=%h", start)) start = 16'h0400;
        if (!$value$plusargs("max=%d", max)) max = 200000000;
        $readmemh(image, mem);
        mem[16'hFFFC] = start[7:0];
        mem[16'hFFFD] = start[15:8];
        cycles = 0; same = 0; last_pc = 16'hFFFF;
        repeat (4) @(posedge clk);
        reset <= 0;
    end

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (SYNC) begin
            same = (AB == last_pc) ? same + 1 : 0;
            last_pc = AB;
            if (same == 3) begin
                if (AB == pass) $display("PASS: looped at %h after %0d cycles", AB, cycles);
                else            $display("FAIL: trapped at %h after %0d cycles", AB, cycles);
                $finish;
            end
        end
        if (cycles == max) begin
            $display("FAIL: no trap after %0d cycles (PC %h)", cycles, AB);
            $finish;
        end
    end
endmodule
