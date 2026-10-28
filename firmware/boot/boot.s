; retro-6502 boot ROM 0.1: the first bring-up on the KS2.
;
; The 65C02 starts here through its reset vector, from boot ROM page 3 in
; window 7 ($E000-$FFFF; spec 7, section 4.2). This first ROM shows, on the
; screen's background colour (BGCOLOR), that the machine works:
;
;   blue     start-up and, at power-on, the self-test (a few ms)
;   red      the self-test failed; the serial link says which check
;   green    a flash: the self-test passed
;   then     the colour cycles, driven by the VBLANK interrupt (50 Hz):
;            4 s a rainbow (vectored IRQs, INTCON.VECTOR set: the handler
;            is the table entry at $FFD0), then 4 s a blue pulse (plain
;            IRQs: one handler at $FFFE that reads INTID), and so on
;
; and on the USB serial link (when an FT232H is fitted, spec 10) a banner,
; then each second a line with the second count and the IRQ mode.
;
; Build: ca65 boot.s; ld65 -C rom.cfg (the Makefile). -D FAST=1 makes a
; "second" 2 frames, for the simulation. -D KLAUS=1 builds the
; simulation's variant: no self-test; it maps SRAM page 7 into window 7 and
; runs the test program the testbench put in SRAM pages 0-7, from $0400.

        .setcpu "65C02"
        .include "hw.inc"

; ---------------------------------------------------------------- the map
; The register page in window 6 ($C000): the custom block at $D000
REGWIN  = $C000
CUSTOM  = REGWIN + REGS_CUSTOM
; The window the self-test moves over the SRAM
TESTWIN = $A000
INTCON_VECTOR = $02             ; INTCON bit 1 (spec 1, section 7.1)
.ifdef FAST
FRAMES_PER_SEC = 2              ; the simulation's "second"
.else
FRAMES_PER_SEC = 50
.endif

; Zero page
frames  = $00                   ; VBLANK count, 16 bits
secs    = $02                   ; seconds, 16 bits
colour  = $04                   ; colour step
tick    = $05                   ; frames in this second
mode    = $06                   ; 0 vectored, 1 plain
ptr     = $08                   ; 2 bytes
spurious = $0A                  ; IRQs at $FFFE that were not VBLANK

        .segment "CODE"

; ---------------------------------------------------------------- start-up
reset:  sei
        cld
        ldx     #$FF
        txs
        ; The register page into window 6, so the custom block is reachable
        lda     #<REGSPAGE
        sta     SYSREGS+MMU6_0
        lda     #>REGSPAGE
        sta     SYSREGS+MMU6_0+1        ; commits read and write page
        ldx     #col_blue-cols          ; blue while it starts
        jsr     setbg
        lda     #VIDCON_EN_M            ; the beam on
        sta     CUSTOM+VIDCON
        lda     #SERCON_EN_M | SERCON_CTLEN_M | SERCON_TXDROP_M
        sta     SYSREGS+SERCON          ; link on, control commands on, never wait for a PC

.ifdef KLAUS
        jmp     klaus
.endif
        ; The identity, through the $FE00 page
        lda     SYSREGS+SYSID
        cmp     #$36                    ; "6"
        beq     :+
        lda     #$01
        jmp     fail
:       lda     SYSREGS+RESETWHY        ; the self-test at power-on only
        and     #RESETWHY_POWER_M
        beq     passed
        jsr     selftest                ; returns with A = 0, or the failed check

        beq     passed
        jmp     fail

passed: ldx     #col_green-cols
        jsr     setbg
        ldx     #<banner
        ldy     #>banner
        jsr     puts

        ; The VBLANK interrupt, vectored: table at $FFD0 (VECBASE $D0)
        stz     frames
        stz     frames+1
        stz     secs
        stz     secs+1
        stz     colour
        stz     tick
        stz     mode
        stz     spurious
        lda     #$D0
        sta     SYSREGS+VECBASE
        lda     #VIDINTEN_VBLANK_M
        sta     CUSTOM+VIDINTEN
        lda     #INTENA_SETCLR_M | (1 << INTB_VBLANK)
        sta     SYSREGS+INTENA0
        lda     #INTCON_MASTER_M | INTCON_VECTOR
        sta     SYSREGS+INTCON
        cli

; ---------------------------------------------------------------- the main loop
; Each second: a line on the serial link; every 4 seconds the IRQ mode
; changes, through INTCON.VECTOR
main:   lda     tick
        cmp     #FRAMES_PER_SEC
        bcc     main
        stz     tick
        inc     secs
        bne     :+
        inc     secs+1
:       lda     secs
        and     #3
        bne     @line
        lda     mode                    ; every 4 s: the other IRQ mode
        eor     #1
        sta     mode
        lda     #INTCON_MASTER_M        ; mode 1: plain
        ldx     mode
        bne     :+
        ora     #INTCON_VECTOR          ; mode 0: vectored
:       sta     SYSREGS+INTCON
@line:  ldx     #<s_sec
        ldy     #>s_sec
        jsr     puts
        lda     secs+1
        jsr     puthex
        lda     secs
        jsr     puthex
        ldx     #<s_vec
        ldy     #>s_vec
        lda     mode
        beq     :+
        ldx     #<s_plain
        ldy     #>s_plain
:       jsr     puts
        bra     main

; ---------------------------------------------------------------- interrupts
; Vectored: the VBLANK entry of the table (source 0, $FFD0)
vblank: pha
        phx
        lda     #VIDSTAT_VBLANK_M       ; W1C
        sta     CUSTOM+VIDSTAT
        jsr     frame
        ldx     colour                  ; the rainbow: blue, green, then red,
        lda     rainbow+32,x            ; which commits the colour
        sta     CUSTOM+BGCOLOR0
        lda     rainbow+16,x
        sta     CUSTOM+BGCOLOR0+1
        lda     rainbow,x
        sta     CUSTOM+BGCOLOR0+2
        plx
        pla
        rti

; Plain: every IRQ and BRK at $FFFE; INTID says which source
irqbrk: pha
        phx
        tsx
        lda     $0103,x                 ; the pushed P
        and     #$10                    ; B: a BRK
        bne     @brk
        lda     SYSREGS+INTID
        bne     @other                  ; not VBLANK (0)
        lda     #VIDSTAT_VBLANK_M
        sta     CUSTOM+VIDSTAT
        jsr     frame
        lda     colour                  ; a blue pulse
        and     #$0F
        tax
        lda     pulse,x
        sta     CUSTOM+BGCOLOR0
        stz     CUSTOM+BGCOLOR0+1
        stz     CUSTOM+BGCOLOR0+2       ; red last: commits
        plx
        pla
        rti
@other: inc     spurious                ; NONE (23) or a source not turned on
@brk:   plx
        pla
        rti

; Both: count the frame, step the colour every 4 frames
frame:  inc     frames
        bne     :+
        inc     frames+1
:       inc     tick
        lda     frames
        and     #3
        bne     :+
        lda     colour
        inc     a
        and     #$0F
        sta     colour
:       rts

nmi:    rti

; ---------------------------------------------------------------- the self-test
; Power-on only. Leaves windows 0-5 and 7 as they were. A = 0 if it passed,
; or the check that failed: $10 data lines, $11 address lines (pages)
selftest:
        ; Data lines: walking ones and their inverse, through window 5 on page 1
        lda     #$01
        sta     SYSREGS+MMU5_0
        stz     SYSREGS+MMU5_0+1
        ldx     #0
@dl:    lda     bits,x
        sta     TESTWIN,x
        eor     #$FF
        sta     TESTWIN+$100,x
        inx
        cpx     #8
        bne     @dl
        ldx     #0
@dc:    lda     TESTWIN,x
        cmp     bits,x
        bne     @dfail
        lda     TESTWIN+$100,x
        eor     #$FF
        cmp     bits,x
        bne     @dfail
        inx
        cpx     #8
        bne     @dc
        ; Address lines: each SRAM page 1-255 gets its number at offsets 0
        ; and $1FFF; then each is read back (an alias would overwrite one)
        ldy     #1
@aw:    sty     SYSREGS+MMU5_0
        stz     SYSREGS+MMU5_0+1
        sty     TESTWIN
        tya
        eor     #$FF
        sta     TESTWIN+$1FFF
        iny
        bne     @aw
        ldy     #1
@ar:    sty     SYSREGS+MMU5_0
        stz     SYSREGS+MMU5_0+1
        cpy     TESTWIN
        bne     @afail
        tya
        eor     #$FF
        cmp     TESTWIN+$1FFF
        bne     @afail
        iny
        bne     @ar
        lda     #5                      ; window 5 back to SRAM page 5
        sta     SYSREGS+MMU5_0
        stz     SYSREGS+MMU5_0+1
        lda     #0
        rts
@dfail: lda     #$10
        rts
@afail: lda     #$11
        rts

; A failed check (in A): red, a line on the serial link, and stop
fail:   pha
        ldx     #col_red-cols
        jsr     setbg
        ldx     #<s_fail
        ldy     #>s_fail
        jsr     puts
        pla
        jsr     puthex
        jsr     crlf
:       bra     :-

; ---------------------------------------------------------------- helpers
; The background colour from cols + X: blue, green, red (red commits)
setbg:  lda     cols,x
        sta     CUSTOM+BGCOLOR0
        lda     cols+1,x
        sta     CUSTOM+BGCOLOR0+1
        lda     cols+2,x
        sta     CUSTOM+BGCOLOR0+2
        rts

; Send the string at Y:X (ends with 0)
puts:   stx     ptr
        sty     ptr+1
        ldy     #0
:       lda     (ptr),y
        beq     :+
        jsr     putc
        iny
        bne     :-
:       rts

crlf:   lda     #13
        jsr     putc
        lda     #10
        ; fall through

; Send A; SERCON.TXDROP drops it when no PC listens
putc:   sta     SYSREGS+SERDATA
        rts

puthex: pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
        and     #$0F
@nib:   cmp     #10
        bcc     :+
        adc     #6                      ; C is set: + 7
:       adc     #'0'
        jmp     putc

; ---------------------------------------------------------------- the simulation's variant
.ifdef KLAUS
; The test program is in SRAM pages 0-7 (the testbench put it there); pages
; 0-6 are already in windows 0-6. A trampoline at $0300 maps page 7 into
; window 7 and jumps to $0400, as the ROM in window 7 cannot change its own
; window.
klaus:  ldx     #tramp_end-tramp-1
:       lda     tramp,x
        sta     $0300,x
        dex
        bpl     :-
        jmp     $0300
tramp:  lda     #7
        sta     SYSREGS+MMU7_0
        stz     SYSREGS+MMU7_0+1
        jmp     $0400
tramp_end:
.endif

; ---------------------------------------------------------------- data
        .segment "RODATA"
cols:
col_blue:  .byte $FF, $00, $00
col_green: .byte $00, $FF, $00
col_red:   .byte $00, $00, $FF
bits:   .byte $01, $02, $04, $08, $10, $20, $40, $80
; 16 steps of a colour wheel: red, green and blue
rainbow:
        .byte $FF,$FF,$FF,$FF,$C0,$80,$40,$00,$00,$00,$00,$00,$40,$80,$C0,$FF
        .byte $00,$40,$80,$C0,$FF,$FF,$FF,$FF,$C0,$80,$40,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$40,$80,$C0,$FF,$FF,$FF,$FF,$C0,$80,$40
pulse:  .byte $20,$40,$60,$80,$A0,$C0,$E0,$FF,$FF,$E0,$C0,$A0,$80,$60,$40,$20

banner: .byte 13, 10, "retro-6502 boot ROM 0.1  65C02 at 10 MHz", 13, 10, 0
s_sec:  .byte "second $", 0
s_vec:  .byte "  IRQ vectored", 13, 10, 0
s_plain: .byte "  IRQ plain", 13, 10, 0
s_fail: .byte 13, 10, "selftest FAIL ", 0

; ---------------------------------------------------------------- vectors
; The IRQ vector table at $FFD0 (spec 7, section 4.2): with VECBASE = $D0,
; source n at $FFD0 + 2n; entries 21-23 are the NMI, reset and IRQ/BRK
; vectors themselves
        .segment "VECTORS"
        .word   vblank                  ; 0  VBLANK
        .res    20*2, $FF               ; 1-20: not used by this ROM
        .word   nmi                     ; 21 $FFFA NMI
        .word   reset                   ; 22 $FFFC reset
        .word   irqbrk                  ; 23 $FFFE IRQ/BRK (plain IRQs; NONE)
