;===============================================================================
; CROCOMIRE PLAYER RENDERER
; Prototype v0.004
;
; Included immediately after bank_A4.asm.
; Bank A4 free space begins at $A4F6C0.
;
; IMPORTANT:
; Nothing in this file is hooked into the game yet.
; The current playable Crocomire prototype remains untouched.
;===============================================================================

;-------------------------------------------------------------------------------
; Constants
;-------------------------------------------------------------------------------

CrocomirePlayer_FacingLeft  = $0000
CrocomirePlayer_FacingRight = $0001

CrocomirePlayer_WalkFrameCount = $000C


;-------------------------------------------------------------------------------
; Renderer entry point
;
; Currently unused.
; Later this routine will replace the vanilla Crocomire BG2 renderer.
;-------------------------------------------------------------------------------

CrocomirePlayer_Render:
    PHP
    PHB
    PHK
    PLB

    REP #$30

    ; Samus is invisible, so reserve her sprite VRAM for Crocomire tests
    STZ.W SamusTiles_TopHalfFlag
    STZ.W SamusTiles_BottomHalfFlag

    ; Load our test Crocomire tiles into player VRAM
    JSR.W CrocomirePlayer_QueueTestTiles

    ; Force Crocomire sprite palette 7
    JSR.W CrocomirePlayer_LoadTestPalette

    ; X position on screen = Samus X - camera X + 80 px
    LDA.W SamusXPosition
    SEC
    SBC.W Layer1XPosition
    CLC
    ADC.W #$0050
    STA.B DP_Temp14

    ; Y = Crocomire foot-aligned origin - camera Y
    LDA.W SamusYPosition
    CLC
    ADC.W SamusYRadius
    SEC
    SBC.W #$0038
    SEC
    SBC.W Layer1YPosition
    STA.B DP_Temp12

    ; Our custom tiles start at OBJ tile 0
    STZ.B DP_Temp00

    ; Sprite palette 7
    LDA.W #$0E00
    STA.B DP_Temp03

    ; Draw one independent 16x16 Crocomire piece
    LDY.W #CrocomirePlayer_TestSpritemap
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22

    PLB
    PLP
    RTL

;-------------------------------------------------------------------------------
; Load four Crocomire tiles into Samus/player VRAM
;
; Original Crocomire tile E4 is a 16x16 sprite composed of:
; E4 E5
; F4 F5
;
; We remap those four tiles to:
; 00 01
; 10 11
;-------------------------------------------------------------------------------

CrocomirePlayer_QueueTestTiles:
    LDX.W VRAMWriteStack

    ;---------------------------------------------------------------
    ; Crocomire spritemap tile $E4
    ;
    ; Crocomire graphics begin at effective OBJ tile $D0.
    ; $E4 - $D0 = $14
    ; $14 * $20 bytes = $0280
    ;
    ; Tiles_Crocomire = $AD8000
    ; Source = $AD8280
    ; Destination = player OBJ tile $00
    ;---------------------------------------------------------------

    LDA.W #$0020
    STA.B VRAMWrite.size,X
    LDA.W #$8280
    STA.B VRAMWrite.src,X
    LDA.W #$00AD
    STA.B VRAMWrite.src+2,X
    LDA.W #$6000
    STA.B VRAMWrite.dest,X

    TXA
    CLC
    ADC.W #$0007
    TAX

    ;---------------------------------------------------------------
    ; Crocomire tile $E5
    ; $E5 - $D0 = $15
    ; Source = $AD82A0
    ; Destination = player OBJ tile $01
    ;---------------------------------------------------------------

    LDA.W #$0020
    STA.B VRAMWrite.size,X
    LDA.W #$82A0
    STA.B VRAMWrite.src,X
    LDA.W #$00AD
    STA.B VRAMWrite.src+2,X
    LDA.W #$6010
    STA.B VRAMWrite.dest,X

    TXA
    CLC
    ADC.W #$0007
    TAX

    ;---------------------------------------------------------------
    ; Crocomire tile $F4
    ; $F4 - $D0 = $24
    ; Source = $AD8480
    ; Destination = player OBJ tile $10
    ;---------------------------------------------------------------

    LDA.W #$0020
    STA.B VRAMWrite.size,X
    LDA.W #$8480
    STA.B VRAMWrite.src,X
    LDA.W #$00AD
    STA.B VRAMWrite.src+2,X
    LDA.W #$6100
    STA.B VRAMWrite.dest,X

    TXA
    CLC
    ADC.W #$0007
    TAX

    ;---------------------------------------------------------------
    ; Crocomire tile $F5
    ; Source = $AD84A0
    ; Destination = player OBJ tile $11
    ;---------------------------------------------------------------

    LDA.W #$0020
    STA.B VRAMWrite.size,X
    LDA.W #$84A0
    STA.B VRAMWrite.src,X
    LDA.W #$00AD
    STA.B VRAMWrite.src+2,X
    LDA.W #$6110
    STA.B VRAMWrite.dest,X

    TXA
    CLC
    ADC.W #$0007
    STA.W VRAMWriteStack

    RTS


;-------------------------------------------------------------------------------
; Temporary Crocomire player palette
;-------------------------------------------------------------------------------

CrocomirePlayer_LoadTestPalette:
    LDX.W #$001E

  .loop:
    LDA.L Palette_Crocomire,X
    STA.L Palettes_SpriteP7,X
    STA.L TargetPalettes_SpriteP7,X

    DEX
    DEX
    BPL .loop

    RTS

;-------------------------------------------------------------------------------
; Vanilla Crocomire walking frames
;
; These are the 12 existing extended spritemaps used by Crocomire's
; charge / step animation. For now this is only a reference table.
;-------------------------------------------------------------------------------

CrocomirePlayer_WalkFrames:
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_0
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_1
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_2
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_3
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_4
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_5
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_6
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_7
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_8
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_9
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_A
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_B


;-------------------------------------------------------------------------------
; Idle frame
;-------------------------------------------------------------------------------

CrocomirePlayer_IdleFrame:
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_0


;-------------------------------------------------------------------------------
; Prevent this module from overflowing Bank A4
;-------------------------------------------------------------------------------



;-------------------------------------------------------------------------------
; Independent Crocomire player test sprite
;
; One 16x16 sprite using player tiles:
;
; 00 01
; 10 11
;-------------------------------------------------------------------------------

CrocomirePlayer_TestSpritemap:
    dw $0001
    %spritemapEntry(1, $0000, $00, 0, 0, 3, 0, $00)

warnpc $A50000