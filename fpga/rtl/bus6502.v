// CPU bus interface for the 65C02 (spec 1): the clock enable, and the
// core's cycles turned into requests on the chipset buses, so that the
// 6502 never waits. retro-6502's own, after retro-z80's bus_if.v.
//
// Timing (spec 1, sections 3 and 5). A CPU cycle is n slots (CPUSPEED DIV
// + 1); cen is high in the clock before slot edge 0 of every n-th slot, so
// every cycle starts on slot edge 0 (edge E). In the cycle's first slot:
//   E + 2  AB, WE, DO and DUMMY sampled (2 clocks after the core's
//          registers change: a multicycle path)
//   E + 3  the access starts, by the page the MMU gives for the window:
//            SRAM      a request to the scheduler; cycle 2 is issued at
//                      E + 4 and the word is back at E + 8
//            boot ROM  the block RAM, one clock
//            REGS      one register bus strobe (E + 4 if the copper has
//                      the bus), data the clock after
//            NONE ...  0xFF
//          $FE00-$FEFF is the system block whatever window 7 maps: a
//          register bus access at 0x000 + A7-A0. Registers 0x1F and 0xFE
//          (Spectrum extras, not built) are never strobed and read 0xFF.
//          A DUMMY read makes no access at all (spec 1, section 6.4).
//   cen    the byte read is loaded into DI at the cen edge that ends the
//          cycle, for the core to use in the next one. A write is on the
//          SRAM pins long before.
//
// The IRQ response (spec 1, section 7.1): a count of stack writes in a row;
// the third, with DO bit 4 clear, is the P push of an IRQ or NMI response.
// A copy of the core's NMI edge flag (same rule, same cen clocks) tells
// which. NMI: nmi_ack. IRQ: int_vreq at E + 3, so INTID is set; with
// INTCON.VECTOR (vec_on, taken at that moment) the next two reads, of
// $FFFE and $FFFF, go to $FF00 + vector and $FF00 + vector + 1. int_ack
// after the second.
//
// The CPU's capture of live counters (spec 3, rule 4) is retro-z80's.
`include "regmap.vh"

module bus6502 (
    input  wire        clk,
    input  wire        rst,            // with the core's reset
    input  wire [3:0]  sc,             // slot edge counter (timebase.v)
    input  wire [3:0]  cpuspeed,       // CPUSPEED: DIV (3-0)
    output wire        cen,            // the core's clock enable; runs in reset too, so the
                                       // core's own synchronous resets act

    // The core (cpu_65c02.v)
    input  wire [15:0] AB,
    input  wire        WE,
    input  wire [7:0]  DO,
    input  wire        DUMMY,
    input  wire        nmi,            // the core's NMI input
    output reg  [7:0]  DI,

    // MMU (mmu.v)
    output wire [2:0]  mmu_win,
    input  wire [9:0]  mmu_rpage,
    input  wire [9:0]  mmu_wpage,

    // Scheduler (dmac.v), CPU channel
    output reg         cpu_req,
    output reg         cpu_we,
    output reg  [21:1] cpu_addr,
    output reg  [15:0] cpu_wdata,
    output reg  [1:0]  cpu_be,
    input  wire        cpu_ack,
    input  wire        cpu_rvalid,
    input  wire [15:0] mem_rdata,

    // Boot ROM (bootrom.v)
    input  wire        romwe,          // SYSCON.ROMWE
    output reg         rom_en,
    output reg  [1:0]  rom_we,
    output reg  [14:1] rom_addr,
    output reg  [15:0] rom_wdata,
    input  wire [15:0] rom_rdata,

    // Register bus, CPU as master
    output reg  [12:0] rb_addr,
    output wire        rb_rd,
    output wire        rb_wr,
    output reg  [7:0]  rb_wdata,
    input  wire [7:0]  rb_rdata,
    input  wire        rb_hit,
    input  wire [31:0] rb_cdata,
    input  wire        rb_cap,
    input  wire        cw_busy,        // the copper has the register bus this clock

    // Interrupt controller (intc.v)
    output reg         int_vreq,       // 1 clock at E + 3 of an IRQ response's P push
    input  wire [7:0]  int_vec,        // the vector byte, from the clock after int_vreq
    input  wire        vec_on,         // INTCON.VECTOR
    output reg         int_ack,        // 1 clock: the response's vector reads are done
    output reg         nmi_ack,        // 1 clock: the NMI response's P push seen

    // Checks for the testbench
    output reg         late,           // a read's byte was not in by its cen edge
    output reg         acc,            // 1 clock at E + 3: this cycle made an access
    output reg         acc_dummy       // 1 clock at E + 3: a DUMMY read, skipped
);
    // ---------------------------------------------------------------- clock enable
    reg [3:0] per;                     // slots per cycle
    reg [3:0] scnt;                    // slot within the cycle
    assign cen = (sc == 4'd9) && (scnt == per - 4'd1);
    wire first_slot = (scnt == 4'd0);

    always @(posedge clk)
        if (rst) begin
            per  <= 4'd1;                          // 10 MHz
            scnt <= 4'd0;
        end else if (sc == 4'd9) begin
            if (cen) begin
                scnt <= 4'd0;
                per  <= (cpuspeed > 4'd9) ? 4'd10 : cpuspeed + 4'd1;
            end else
                scnt <= scnt + 4'd1;
        end

    // Cycles since reset was released, to the end of the reset sequence
    reg [2:0] rcyc;
    always @(posedge clk)
        if (rst)                        rcyc <= 3'd0;
        else if (cen && rcyc != 3'd7)   rcyc <= rcyc + 3'd1;

    // ---------------------------------------------------------------- the sample, E + 2
    wire at2 = first_slot && (sc == 4'd1);     // the clock that ends at E + 2
    wire at3 = first_slot && (sc == 4'd2);     // ... at E + 3

    reg  [15:0] a_s;                   // the address used (after the vector change)
    reg         we_s, dm_s, ok_s;      // write; DUMMY; a cycle to serve (not in reset)
    reg  [7:0]  do_s;

    // The IRQ response
    reg  [1:0]  stk;                   // stack writes in a row, up to 3
    reg         nmi_c, nmi_d;          // the copy of the core's NMI edge flag, and NMI last cen
    reg         pp_cur, pp_last;       // this cycle, the last cycle, was a P push
    reg  [1:0]  vrd;                   // the response's vector reads still to come
    reg         vsub;                  // ... are changed (VECTOR was on)
    reg  [7:0]  vec;
    reg         vreq_d;

    // The address the core's read really goes to: $FF00 + vector for the
    // vector reads of a vectored IRQ response
    wire [15:0] a_eff = (vsub && vrd == 2'd2 && AB == 16'hFFFE && !WE) ? {8'hFF, vec} :
                        (vsub && vrd == 2'd1 && AB == 16'hFFFF && !WE) ? {8'hFF, vec + 8'd1} : AB;

    assign mmu_win = a_s[15:13];
    wire [9:0] page    = we_s ? mmu_wpage : mmu_rpage;
    wire       sysblk  = (a_s[15:8] == 8'hFE);
    wire       pg_sram = !page[9];
    wire       pg_rom  = (page[9:2] == 8'hFF);
    wire       pg_regs = (page == 10'h3F8);
    // The register bus address, and whether it is one retro-6502 builds
    wire [12:0] r_addr = sysblk ? {5'd0, a_s[7:0]} : a_s[12:0];
    wire        r_spx  = (r_addr == 13'h001F) || (r_addr == 13'h00FE);   // Spectrum extras

    // ---------------------------------------------------------------- the capture (spec 3, rule 4)
    reg        cap_valid;
    reg [12:0] cap_tag;
    reg [2:0]  cap_n;
    reg [31:0] cap_data;
    wire [12:0] cap_d    = rb_addr - cap_tag;
    wire        cap_hit  = cap_valid && cap_d != 13'd0 && cap_d < {10'd0, cap_n};
    wire [7:0]  cap_byte = cap_data[8 * cap_d[1:0] +: 8];

    // ---------------------------------------------------------------- the cycle
    reg  [7:0] rbyte;                  // the byte read, waiting for the cen edge
    reg        rd_wait;                // a read waits for its byte
    reg        rd_cyc;                 // this cycle reads (and not DUMMY): DI takes rbyte at cen
    reg        rd_hi;
    reg        rom_rd;
    reg        io_rd_d;
    reg        q_rd, q_wr, d_rd, d_wr; // the register bus strobe, and moved a clock by the copper
    assign rb_rd = (q_rd && !cw_busy) || d_rd;
    assign rb_wr = (q_wr && !cw_busy) || d_wr;

    // int_ack: after the cycle in which the second vector read was sampled
    reg int_pend;                      // an IRQ response has asked for its vector
    wire int_ack_due = int_pend && vrd == 2'd0;
    always @(posedge clk)
        if (rst)                   int_pend <= 1'b0;
        else if (int_vreq)         int_pend <= 1'b1;
        else if (cen && int_ack_due) int_pend <= 1'b0;

    always @(posedge clk) begin
        rom_en   <= 1'b0;
        rom_we   <= 2'b00;
        rom_rd   <= rom_en && rom_we == 2'b00;
        q_rd     <= 1'b0;
        q_wr     <= 1'b0;
        d_rd     <= q_rd && cw_busy;
        d_wr     <= q_wr && cw_busy;
        late     <= 1'b0;
        acc      <= 1'b0;
        acc_dummy <= 1'b0;
        int_vreq <= 1'b0;
        int_ack  <= 1'b0;
        nmi_ack  <= 1'b0;
        vreq_d   <= int_vreq;
        if (vreq_d) vec <= int_vec;

        if (rst) begin
            cpu_req   <= 1'b0;
            cpu_we    <= 1'b0;
            rd_wait   <= 1'b0;
            rd_cyc    <= 1'b0;
            io_rd_d   <= 1'b0;
            d_rd      <= 1'b0;
            d_wr      <= 1'b0;
            ok_s      <= 1'b0;
            stk       <= 2'd0;
            nmi_c     <= 1'b0;
            nmi_d     <= 1'b0;
            pp_cur    <= 1'b0;
            pp_last   <= 1'b0;
            vrd       <= 2'd0;
            vsub      <= 1'b0;
            cap_valid <= 1'b0;
            rb_addr   <= 13'd0;
            DI        <= 8'hFF;
        end else begin
            if (cpu_ack) cpu_req <= 1'b0;

            // The core's NMI edge flag, copied: set by a rising edge of NMI
            // seen at a cen edge, cleared at the cen edge that ends the
            // cycle reading the NMI vector (spec 1, section 7.1). Reset's
            // own sequence clears it too, at its vector read (the fourth
            // cycle), as the core does.
            if (cen) begin
                nmi_d <= nmi;
                pp_last <= pp_cur;
                if (nmi_c && ((ok_s && !we_s && a_s == 16'hFFFA && pp_last) || rcyc == 3'd3))
                    nmi_c <= 1'b0;
                else if (nmi && !nmi_d)
                    nmi_c <= 1'b1;
            end

            // E + 2: sample the core's outputs
            if (at2) begin
                a_s  <= a_eff;
                we_s <= WE;
                do_s <= DO;
                dm_s <= DUMMY && !WE;
                ok_s <= 1'b1;
                // The response watcher
                pp_cur <= WE && AB[15:8] == 8'h01 && stk == 2'd2;
                if (WE && AB[15:8] == 8'h01) begin
                    if (stk != 2'd3) stk <= stk + 2'd1;
                    if (stk == 2'd2 && !DO[4]) begin   // the P push of an IRQ or NMI
                        if (nmi_c) nmi_ack <= 1'b1;
                        else begin
                            vrd  <= 2'd2;
                            vsub <= vec_on;
                        end
                    end
                end else
                    stk <= 2'd0;
                // A vector read done (changed or not)
                if (vrd != 2'd0 && !(WE && AB[15:8] == 8'h01)) begin
                    vrd <= vrd - 2'd1;
                    if (vrd == 2'd1) vsub <= 1'b0;
                end
            end

            // E + 3: the access
            if (at3 && ok_s) begin
                if (vrd == 2'd2 && we_s) int_vreq <= 1'b1;      // the P push (vrd set at E + 2)
                rd_cyc <= !we_s && !dm_s;
                rd_hi  <= a_s[0];
                if (dm_s) begin
                    acc_dummy <= 1'b1;                          // no access (spec 1, section 6.4)
                end else begin
                    acc <= 1'b1;
                    if (sysblk || pg_regs) begin
                        rb_addr  <= r_addr;
                        rb_wdata <= do_s;
                        if (r_spx) begin
                            if (!we_s) rbyte <= 8'hFF;
                        end else begin
                            q_rd <= !we_s;
                            q_wr <= we_s;
                            if (!we_s) rd_wait <= 1'b1;
                        end
                    end else if (pg_sram) begin
                        cpu_req   <= 1'b1;
                        cpu_we    <= we_s;
                        cpu_addr  <= {page[8:0], a_s[12:1]};
                        cpu_be    <= we_s ? (a_s[0] ? 2'b10 : 2'b01) : 2'b11;
                        cpu_wdata <= {do_s, do_s};
                        if (!we_s) rd_wait <= 1'b1;
                    end else if (pg_rom) begin
                        if (!we_s) begin
                            rom_en   <= 1'b1;
                            rom_addr <= {page[1:0], a_s[12:1]};
                            rd_wait  <= 1'b1;
                        end else if (romwe) begin
                            rom_en    <= 1'b1;
                            rom_we    <= a_s[0] ? 2'b10 : 2'b01;
                            rom_addr  <= {page[1:0], a_s[12:1]};
                            rom_wdata <= {do_s, do_s};
                        end
                    end else if (!we_s)
                        rbyte <= 8'hFF;                         // NONE, reserved
                end
            end

            // The byte comes back
            if (cpu_rvalid && rd_wait) begin
                rbyte   <= rd_hi ? mem_rdata[15:8] : mem_rdata[7:0];
                rd_wait <= 1'b0;
            end
            if (rom_rd && rd_wait) begin
                rbyte   <= rd_hi ? rom_rdata[15:8] : rom_rdata[7:0];
                rd_wait <= 1'b0;
            end
            if (rb_rd) io_rd_d <= 1'b1;
            if (io_rd_d) begin
                rbyte <= cap_hit ? cap_byte : rb_hit ? rb_rdata : 8'hFF;
                if (rb_cap) begin
                    cap_valid <= 1'b1;
                    cap_tag   <= rb_addr;
                    cap_n     <= `RM_CAP_N(rb_addr);
                    cap_data  <= rb_cdata;
                end
                io_rd_d <= 1'b0;
                rd_wait <= 1'b0;
            end

            // The cen edge: the byte into DI for the next cycle
            if (cen) begin
                if (ok_s && rd_cyc) DI <= rbyte;
                if (ok_s && rd_cyc && rd_wait) late <= 1'b1;
                rd_cyc <= 1'b0;
                // The IRQ response is over after its second vector read
                if (int_ack_due) int_ack <= 1'b1;
            end
        end
    end

endmodule
