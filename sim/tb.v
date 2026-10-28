// The whole retro-6502 machine (retro6502.v) with the KS2's 2 MB SRAM, its
// pads, the FT232H and PS/2 models. Wiring after retro-z80's sim/tb.v.
//
// Plusargs:
//   +rom=FILE      boot ROM image ($readmemh, 16-bit words; default boot.hex)
//   +ram=FILE      load FILE into the SRAM first (16-bit words, from word 0)
//   +pass=HEX      PASS when the 65C02 loops on itself at this address
//   +boot=N        PASS when the boot ROM has shown N "seconds" on the serial
//                  link with both IRQ modes seen (the FAST ROM)
//   +max=N         give up after N CPU cycles
//
// Checks, every cycle (spec 1, section 11):
//   - no read is late: its byte is in before the cen edge that loads DI
//   - every byte the core takes from SRAM or the boot ROM is the memory's
//   - a DUMMY read makes no access
`timescale 1ns/1ps
module tb;
    localparam [5:0] CHIPMB = 6'd2;

    reg clk = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    // 27 MHz and 135 MHz pixel clocks (rising edges lined up), as retro-z80
    reg clk_pix = 1'b0, clk_pix5 = 1'b0;
    initial begin : pixclocks
        integer k;
        k = 0;
        forever begin
            #(1000.0 / 270.0);
            clk_pix5 = ~clk_pix5;
            if (clk_pix5) begin
                if (k == 0) clk_pix = 1'b1;
                k = (k + 1) % 5;
            end else if (k == 3) clk_pix = 1'b0;
        end
    end

    reg por = 1'b1;
    initial #2001 por = 1'b0;

    // ---------------------------------------------------------------- DUT
    wire [20:0] a;
    wire        ce_n, ub_n, lb_n, oe_r, oe_f, we_r, we_f, t_r, t_f;
    wire [15:0] dq_o, dq;
    wire        ft_rxf_n, ft_txe_n, ft_d_oe, ft_rd_n, ft_wr_n, ft_siwu_n;
    wire [7:0]  ft_d, ft_d_o;
    wire        dma_ack, dma_rvalid;
    wire [15:0] dma_rdata;
    wire [3:0]  sc;
    wire [23:0] vrgb;
    wire        vhs, vvs, vde;
    wire        ps2_clk_low, ps2_data_low;
    wire [7:0]  keyb_row_low;
    wire        joy_sel;

    reg [8*128-1:0] romfile, ramfile;
    initial if (!$value$plusargs("rom=%s", romfile)) romfile = "boot.hex";

    retro6502 #(.CHIPMB(CHIPMB)) dut (
        .clk(clk), .por(por),
        .btn_reset_n(1'b1), .buttons(2'b00),
        .sram_a(a), .sram_ce_n(ce_n), .sram_ub_n(ub_n), .sram_lb_n(lb_n),
        .sram_oe_n_r(oe_r), .sram_oe_n_f(oe_f), .sram_we_n_r(we_r), .sram_we_n_f(we_f),
        .sram_dq_o(dq_o), .sram_dq_t_r(t_r), .sram_dq_t_f(t_f), .sram_dq_i(dq),
        .ft_rxf_n(ft_rxf_n), .ft_txe_n(ft_txe_n), .ft_d_i(ft_d), .ft_d_o(ft_d_o),
        .ft_d_oe(ft_d_oe), .ft_rd_n(ft_rd_n), .ft_wr_n(ft_wr_n), .ft_siwu_n(ft_siwu_n),
        .dma_req(1'b0), .dma_we(1'b0), .dma_addr(21'd0), .dma_wdata(16'd0),
        .dma_be(2'b00), .dma_ack(dma_ack), .dma_rvalid(dma_rvalid), .dma_rdata(dma_rdata),
        .clk_pix(clk_pix), .clk_pix5(clk_pix5), .vid_rgb(vrgb), .vid_hsync(vhs), .vid_vsync(vvs), .vid_de(vde),
        .ps2_clk_i(1'b1), .ps2_data_i(1'b1), .ps2_clk_low(ps2_clk_low), .ps2_data_low(ps2_data_low),
        .keyb_row_low(keyb_row_low), .keyb_col_i(7'h7F), .joy_pin_n(6'h3F), .joy_sel(joy_sel), .joy_p7(),
        .audio_l(), .audio_r(), .audio_m(),
        .dbg_sc(sc)
    );

    reg [15:0] rom_ref [0:16383];
    initial begin
        #1;
        $readmemh(romfile, dut.rom.mem);
        $readmemh(romfile, rom_ref);
        if ($value$plusargs("ram=%s", ramfile)) $readmemh(ramfile, sram.mem);
    end

    // ---------------------------------------------------------------- SRAM pads (as retro-z80)
    reg  [20:0] pa;   reg pce_n = 1, pub_n = 1, plb_n = 1;  reg [15:0] pdq;
    always @(posedge clk) begin
        pa    <= #1 a;
        pce_n <= #1 ce_n;
        pub_n <= #1 ub_n;
        plb_n <= #1 lb_n;
        pdq   <= #1 dq_o;
    end
    wire poe_n, pwe_n, pt;
    oddr #(.INIT(1'b1)) o_oe (.clk(clk), .d_r(oe_r), .d_f(oe_f), .q(poe_n));
    oddr #(.INIT(1'b1)) o_we (.clk(clk), .d_r(we_r), .d_f(we_f), .q(pwe_n));
    oddr #(.INIT(1'b1)) o_t  (.clk(clk), .d_r(t_r),  .d_f(t_f),  .q(pt));
    assign dq = pt ? 16'hzzzz : pdq;
    sram_model sram (.a(pa), .dq(dq), .ce_n(pce_n), .oe_n(poe_n), .we_n(pwe_n),
                     .ub_n(pub_n), .lb_n(plb_n), .fpga_drives(!pt));

    assign ft_d = ft_d_oe ? ft_d_o : 8'hzz;
    ft232h_model ft (.d(ft_d), .rxf_n(ft_rxf_n), .txe_n(ft_txe_n),
                     .rd_n(ft_rd_n), .wr_n(ft_wr_n), .siwu_n(ft_siwu_n));

    // ---------------------------------------------------------------- checks
    integer cycles = 0, errors = 0, reads_chk = 0, dummies = 0, accs = 0;
    integer ser_wr = 0, ser_acc = 0;
    integer vreqs = 0, acks = 0, vec_reads = 0, plain_reads = 0, colours = 0;
    integer max, pass_given, boot_secs;
    reg [15:0] pass;
    reg        exp_ok;                 // this cycle's byte is checked
    reg [7:0]  exp_b;
    reg [15:0] exp_a;
    reg [15:0] last_pc;
    integer    same = 0, secs_seen = 0;

    initial begin
        if (!$value$plusargs("max=%d", max)) max = 2000000;
        pass_given = $value$plusargs("pass=%h", pass);
        if (!$value$plusargs("boot=%d", boot_secs)) boot_secs = 0;
        last_pc = 16'hFFFF;
        exp_ok  = 1'b0;
    end

    wire [9:0] pg = dut.bif.we_s ? dut.mmu_wpage : dut.mmu_rpage;

    always @(posedge clk) if (!por) begin
        // The access, at E + 3: what the byte must be
        if (dut.bif.acc && !dut.bif.we_s) begin
            exp_a  = dut.bif.a_s;
            exp_ok = 1'b1;
            if (dut.bif.sysblk || pg == 10'h3F8 || (pg[9] && pg[9:2] != 8'hFF))
                exp_ok = 1'b0;                              // registers, NONE: not checked here
            else if (!pg[9])                                // SRAM (2 MB: page bit 8 ignored)
                exp_b = dut.bif.a_s[0] ? sram.mem[{pg[7:0], dut.bif.a_s[12:1]}][15:8]
                                       : sram.mem[{pg[7:0], dut.bif.a_s[12:1]}][7:0];
            else                                            // boot ROM
                exp_b = dut.bif.a_s[0] ? rom_ref[{pg[1:0], dut.bif.a_s[12:1]}][15:8]
                                       : rom_ref[{pg[1:0], dut.bif.a_s[12:1]}][7:0];
            accs = accs + 1;
        end
        if (dut.bif.acc && dut.bif.we_s) accs = accs + 1;
        if (dut.bif.acc_dummy) begin
            dummies = dummies + 1;
            if (dut.cpu_req || dut.rom_en || dut.bif.q_rd) begin
                $display("%t ERROR: a DUMMY read made an access", $realtime);
                errors = errors + 1;
            end
        end
        if (dut.bif.late) begin
            $display("%t ERROR: a read was late (%h)", $realtime, exp_a);
            errors = errors + 1;
        end
        if (dut.int_vreq) vreqs = vreqs + 1;
        if (dut.int_ack)  acks = acks + 1;
        if (dut.bif.acc && dut.bif.a_s == 16'hFFD0) vec_reads = vec_reads + 1;
        if (dut.bif.acc && dut.bif.a_s == 16'hFFFE && dut.bif.int_pend) plain_reads = plain_reads + 1;

        // The cen edge: the byte the core gets
        if (dut.cen) begin
            cycles = cycles + 1;
            if (exp_ok && dut.bif.rd_cyc) begin
                // DI is loaded at this edge: compare on the next clock
                reads_chk = reads_chk + 1;
            end
        end
    end
    // DI is loaded at the cen edge: check it just after
    reg chk_d;
    always @(posedge clk) begin
        chk_d <= !por && dut.cen && exp_ok && dut.bif.rd_cyc;
        if (chk_d) begin
            if (dut.c_di !== exp_b) begin
                if (errors < 20)
                    $display("%t ERROR: read %h gave %h, memory holds %h", $realtime, exp_a, dut.c_di, exp_b);
                errors = errors + 1;
            end
            exp_ok = 1'b0;
        end
    end

    // ---------------------------------------------------------------- serial and colours
    reg [8*80-1:0] line;
    always @(posedge clk) if (!por) begin
        if (dut.rb_wr && dut.rb_addr == 13'h0053 && !dut.cw_req) begin
            ser_wr = ser_wr + 1;                    // (ft232h_model prints the byte)
        end
        if (dut.bif.acc && dut.bif.we_s && dut.bif.a_s == 16'hFE53) ser_acc = ser_acc + 1;
        if (dut.rb_wr && dut.rb_addr == 13'h1006) colours = colours + 1;
    end

    // Seconds, from the ROM's own counter, and the IRQ modes seen
    always @(posedge clk) if (!por && boot_secs != 0) begin
        if (dut.bif.acc && dut.bif.we_s && dut.bif.a_s == 16'h0002) secs_seen = dut.bif.do_s;
    end

    // ---------------------------------------------------------------- the end
    always @(posedge clk) if (!por && dut.cen) begin
        // A loop on itself: SYNC is high in the cycle after the opcode fetch
        if (dut.c_sync) begin
            same = (dut.c_ab - 16'd1 == last_pc) ? same + 1 : 0;
            last_pc = dut.c_ab - 16'd1;
            if (same == 3 && pass_given) finish(last_pc == pass, "looped");
        end
        if (boot_secs != 0 && secs_seen >= boot_secs)
            finish(vec_reads > 0 && plain_reads > 0 && vreqs == acks + (dut.bif.int_pend ? 1 : 0), "boot");
        if (cycles >= max) finish(1'b0, "out of cycles");
    end

    task finish(input ok, input [8*16-1:0] why);
        begin
            $display("");
            $display("%0d cycles, %0d accesses (%0d reads checked), %0d DUMMY reads skipped", cycles, accs, reads_chk, dummies);
            $display("serial: %0d writes from %0d stores", ser_wr, ser_acc);
            $display("IRQ: %0d vector requests, %0d acks, %0d vectored, %0d plain; %0d colours", vreqs, acks, vec_reads, plain_reads, colours);
            if (ok && errors == 0) $display("PASS: %0s at %h", why, last_pc);
            else                   $display("FAIL: %0s at %h, %0d errors", why, last_pc, errors);
            $finish;
        end
    endtask
endmodule
