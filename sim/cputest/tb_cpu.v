// Runs a 64 KB test image on cpu_65c02 with a synchronous memory (read data
// the clock after the address, as the core expects) until the program loops
// on itself (JMP * or a branch to itself), then reports where.
// +image=<file.hex> (one byte per line, 65536 lines), +pass=<hex address>,
// +start=<hex address> (put in the reset vector), +max=<cycles>,
// +cen=<clocks per CPU cycle> (default 1; 10 as at 10 MHz on the machine).
// The byte after a read the core marks DUMMY is garbage, not the memory's:
// if the core ever used such a byte, the tests would fail.
`timescale 1ns/1ps
module tb_cpu;
    reg         clk = 0;
    reg         reset = 1;
    wire [15:0] AB;
    reg  [7:0]  DI;
    wire [7:0]  DO;
    wire        WE, SYNC, DUMMY;
    reg         cen = 0;
    integer     period = 1, ccount = 0, dummies = 0;
    reg  [7:0]  mem [0:65535];

    cpu_65c02 cpu (.clk(clk), .reset(reset), .AB(AB), .DI(DI), .DO(DO),
                   .WE(WE), .IRQ(1'b0), .NMI(1'b0), .RDY(1'b1), .SYNC(SYNC),
                   .cen(cen), .DUMMY(DUMMY));

    // cen: one clock in every `period`
    always @(posedge clk) begin
        ccount <= (ccount + 1 >= period) ? 0 : ccount + 1;
        cen    <= (ccount + 1 >= period);
    end

    always #5 clk = ~clk;

    always @(posedge clk) if (cen) begin
        if (WE) mem[AB] <= DO;
        if (!WE && DUMMY) begin
            DI <= 8'hA5 ^ cycles[7:0];          // garbage: must never be used
            dummies = dummies + 1;
        end else
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
        if (!$value$plusargs("cen=%d", period)) period = 1;
        $readmemh(image, mem);
        mem[16'hFFFC] = start[7:0];
        mem[16'hFFFD] = start[15:8];
        cycles = 0; same = 0; last_pc = 16'hFFFF;
        repeat (4 * period + 4) @(posedge clk);
        reset <= 0;
    end

    always @(posedge clk) if (!reset && cen) begin
        cycles = cycles + 1;
        // SYNC is high in the cycle after the opcode fetch, when the opcode
        // is at DI and AB is already the next byte: the opcode was at AB - 1.
        if (SYNC) begin
            same = (AB - 16'd1 == last_pc) ? same + 1 : 0;
            last_pc = AB - 16'd1;
            if (same == 3) begin
                if (last_pc == pass) $display("PASS: looped at %h after %0d cycles (%0d dummy reads)", last_pc, cycles, dummies);
                else                 $display("FAIL: trapped at %h after %0d cycles", last_pc, cycles);
                $finish;
            end
        end
        if (cycles == max) begin
            $display("FAIL: no trap after %0d cycles (PC %h)", cycles, AB);
            $finish;
        end
    end
endmodule
