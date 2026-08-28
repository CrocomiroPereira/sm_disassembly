;===============================================================================
; CROCOMIRE PLAYER RENDERER
; Prototype v0.004
;
; Included immediately after bank_A4.asm.
; Bank A4 free space begins at $A4F6C0.
;
; Current goal:
; - keep the proven persistent OAM pieces (arm + two leg components)
; - test one correctly extracted BG body section as persistent OBJ graphics
; - do not replace the vanilla Crocomire boss renderer yet
;===============================================================================

;-------------------------------------------------------------------------------
; Constants
;-------------------------------------------------------------------------------

CrocomirePlayer_FacingLeft      = $0000
CrocomirePlayer_FacingRight     = $0001
CrocomirePlayer_WalkFrameCount  = $000C


;-------------------------------------------------------------------------------
; Renderer entry point
;-------------------------------------------------------------------------------

CrocomirePlayer_Render:
    PHP
    PHB
    PHK
    PLB

    REP #$30

    ; Samus is invisible, so reserve her normal sprite tile updates
    STZ.W SamusTiles_TopHalfFlag
    STZ.W SamusTiles_BottomHalfFlag

    ;===========================================================================
    ; Load Crocomire graphics once, AFTER the room transition has finished.
    ;
    ; GameState $0008 = normal gameplay.
    ;
    ; $0A02 is unused Samus RAM. We use it to remember the last RoomPointer
    ; for which the Crocomire player graphics were queued.
    ;
    ; Important:
    ; Do NOT update the stored RoomPointer during the door transition.
    ;===========================================================================

    LDA.W GameState
    CMP.W #$0008
    BNE .crocomireGraphicsDone

    LDA.W RoomPointer
    CMP.W StartSamusRAM_Unused0A02
    BEQ .crocomireGraphicsDone

    STA.W StartSamusRAM_Unused0A02
    JSR.W CrocomirePlayer_QueueTestTiles

  .crocomireGraphicsDone:

    ; Enemy/OAM Crocomire palette -> sprite palette 7
    JSR.W CrocomirePlayer_LoadTestPalette

    ; Crocomire BG palette 7 -> temporary sprite palette 6
    JSR.W CrocomirePlayer_LoadBGPalette


    ;===========================================================================
    ; OAM component 3 (persistent arm section)
    ;===========================================================================

    ; X = Samus screen X + 80 px
    ; ExtendedTilemap_Crocomire_3 vanilla position:
    ; (-3, -11) relative to Spritemap_Crocomire_3

    LDA.W SamusXPosition
    SEC
    SBC.W Layer1XPosition
    CLC
    ADC.W #$002D          ; $50 - 3
    STA.B DP_Temp14

    LDA.W SamusYPosition
    CLC
    ADC.W SamusYRadius
    SEC
    SBC.W #$002C
    SEC
    SBC.W Layer1YPosition
    SEC
    SBC.W #$0001
    STA.B DP_Temp12

    ; Player OBJ tile base $00
    STZ.B DP_Temp00

    ; Sprite palette 7
    LDA.W #$0E00
    STA.B DP_Temp03

    LDY.W #CrocomirePlayer_TestSpritemap
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22


    ;===========================================================================
    ; OAM component B (first leg section)
    ;
    ; Vanilla extended-frame offsets:
    ; Spritemap_3 = (+3, +11)
    ; Spritemap_B = ( 0, +38)
    ; Relative: X - 3, Y + 27
    ;===========================================================================

    LDA.B DP_Temp14
    SEC
    SBC.W #$0003
    STA.B DP_Temp14

    LDA.B DP_Temp12
    CLC
    ADC.W #$001B
    STA.B DP_Temp12

    ; Player OBJ tile base $40
    LDA.W #$001C
    STA.B DP_Temp00

    LDY.W #CrocomirePlayer_TestSpritemap_B
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22


    ;===========================================================================
    ; OAM component 5 (second leg section)
    ;
    ; Vanilla offset relative to B: X - 29, same Y
    ;===========================================================================

    LDA.B DP_Temp14
    SEC
    SBC.W #$001D
    STA.B DP_Temp14

    LDY.W #CrocomirePlayer_TestSpritemap_5
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22

    ;===========================================================================
    ; Full static Crocomire BG body
    ;===========================================================================

    LDA.W SamusXPosition
    SEC
    SBC.W Layer1XPosition
    CLC
    ADC.W #$FFF5
    STA.B DP_Temp14

    LDA.W SamusYPosition
    CLC
    ADC.W SamusYRadius
    SEC
    SBC.W #$002C
    SEC
    SBC.W Layer1YPosition
    SEC
    SBC.W #$004B
    STA.B DP_Temp12

    STZ.B DP_Temp00

    ; Crocomire BG palette in sprite palette 6
    LDA.W #$0C00
    STA.B DP_Temp03

    LDY.W #CrocomirePlayer_FullBodySpritemap
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22

    PLB
    PLP
    RTL


;-------------------------------------------------------------------------------
; Queue persistent Crocomire graphics to VRAM
;
; Every entry:
;     dw size, source_low_word, destination_vram
;
; All sources currently live in ROM bank $AD.
;-------------------------------------------------------------------------------

CrocomirePlayer_QueueTestTiles:
    LDX.W VRAMWriteStack

    LDA.W #$1800
    STA.B VRAMWrite.size,X

    LDA.W #CrocomirePlayer_FullStaticTiles
    STA.B VRAMWrite.src,X

    LDA.W #$00B8
    STA.B VRAMWrite.src+2,X

    LDA.W #$6000
    STA.B VRAMWrite.dest,X

    TXA
    CLC
    ADC.W #$0007
    STA.W VRAMWriteStack

    RTS


CrocomirePlayer_TestTileTransfers:

    ;===========================================================================
    ; Compact persistent Crocomire OAM graphics
    ;
    ; Component 3:
    ;   $0380 bytes -> VRAM $6000
    ;
    ; Components B / 5:
    ;   $02C0 bytes -> VRAM $6400
    ;
    ; This replaces the many small DMA entries used previously.
    ;===========================================================================

    dw $0380,CrocomirePlayer_OAMArmTiles,$6000
    dw $02C0,CrocomirePlayer_OAMLegTiles,$6400

    ; BGPart3 torso test
    dw $0400,CrocomirePlayer_BGPart3Tiles,$6600

    dw $FFFF


;-------------------------------------------------------------------------------
; Crocomire enemy/OAM palette -> sprite palette 7
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
; Crocomire room BG palette 7 -> temporary sprite palette 6
;
; Values are the last 16 colours of decompressed Palettes_1B_Crocomire.
;-------------------------------------------------------------------------------

CrocomirePlayer_BGPalette:
    dw $0000,$7FFF,$0DFF,$08BF,$0895,$086C,$0447,$6B7E
    dw $571E,$3A58,$2171,$0CCB,$039F,$023A,$0176,$0000


CrocomirePlayer_LoadBGPalette:
    LDX.W #$001E

  .loop:
    LDA.W CrocomirePlayer_BGPalette,X
    STA.L Palettes_SpriteP6,X
    STA.L TargetPalettes_SpriteP6,X

    DEX
    DEX
    BPL .loop

    RTS


;-------------------------------------------------------------------------------
; Vanilla Crocomire walking-frame references
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


CrocomirePlayer_IdleFrame:
    dw ExtendedSpritemap_Crocomire_ChargeForward_StepBack_0


;-------------------------------------------------------------------------------
; Persistent remap of vanilla Spritemap_Crocomire_3
; Base tile number when drawn: $00
;-------------------------------------------------------------------------------

CrocomirePlayer_TestSpritemap:
    dw $0009

    ; Vanilla $FF -> player $0C
    %spritemapEntry(0, $00,  $08, 0, 1, 3, 0, $0C)

    ; Vanilla $EF -> player $0D
    %spritemapEntry(0, $08,  $F8, 0, 1, 3, 0, $0D)

    ; Vanilla $ED -> player $00
    %spritemapEntry(1, $08,  $00, 0, 1, 3, 0, $00)

    ; Vanilla $10D -> player $02
    %spritemapEntry(1, $1F8, $F8, 0, 1, 3, 0, $02)

    ; Vanilla $E4 -> player $04
    %spritemapEntry(1, $1D5, $11, 0, 0, 3, 0, $04)

    ; Vanilla $100 -> player $06
    %spritemapEntry(1, $1C5, $11, 0, 0, 3, 0, $06)

    ; Vanilla $102 -> player $08
    %spritemapEntry(1, $02,  $03, 0, 0, 3, 0, $08)

    ; Vanilla $104 -> player $0A
    %spritemapEntry(1, $1F2, $0D, 0, 0, 3, 0, $0A)

    ; Vanilla $102 -> player $08
    %spritemapEntry(1, $1E4, $0D, 0, 0, 3, 0, $08)


;-------------------------------------------------------------------------------
; Persistent remap of vanilla Spritemap_Crocomire_B
; Base tile number when drawn: $40
;-------------------------------------------------------------------------------

CrocomirePlayer_TestSpritemap_B:
    dw $0008

    %spritemapEntry(1, $10,  $F9, 0, 0, 3, 0, $02)
    %spritemapEntry(1, $0B,  $F9, 0, 1, 3, 0, $04)

    %spritemapEntry(0, $20,  $09, 0, 0, 3, 0, $0A)
    %spritemapEntry(0, $18,  $09, 0, 0, 3, 0, $09)
    %spritemapEntry(0, $10,  $09, 0, 0, 3, 0, $08)
    %spritemapEntry(0, $08,  $09, 0, 0, 3, 0, $07)
    %spritemapEntry(0, $00,  $09, 0, 0, 3, 0, $06)

    %spritemapEntry(1, $03,  $F9, 0, 1, 3, 0, $00)


;-------------------------------------------------------------------------------
; Persistent remap of vanilla Spritemap_Crocomire_5
; Uses the same graphics as component B
;-------------------------------------------------------------------------------

CrocomirePlayer_TestSpritemap_5:
    dw $0008

    %spritemapEntry(0, $02,  $09, 0, 0, 3, 0, $0A)
    %spritemapEntry(0, $1FA, $09, 0, 0, 3, 0, $09)
    %spritemapEntry(0, $1F2, $09, 0, 0, 3, 0, $08)
    %spritemapEntry(0, $1EA, $09, 0, 0, 3, 0, $07)
    %spritemapEntry(0, $1E2, $09, 0, 0, 3, 0, $06)

    %spritemapEntry(1, $1F2, $F9, 0, 0, 3, 0, $02)
    %spritemapEntry(1, $1F6, $F9, 0, 0, 3, 0, $04)
    %spritemapEntry(1, $01,  $F9, 0, 0, 3, 0, $00)


;-------------------------------------------------------------------------------
; ExtendedTilemap_Crocomire_3 converted to four 16x16 OBJ sprites
;
; The packed asset is arranged so local bases $00,$02,$04,$06 form:
;
;   [00] [02]
;   [04] [06]
;
; DP_Temp00 supplies the real OBJ base tile ($60 for VRAM $6600).
;-------------------------------------------------------------------------------

   

CrocomirePlayer_FullBodySpritemap:
    dw $0038

    %spritemapEntry(1, $30, $00, 0, 0, 3, 0, $40)
    %spritemapEntry(1, $40, $00, 0, 0, 3, 0, $42)
    %spritemapEntry(1, $20, $08, 0, 0, 3, 0, $44)
    %spritemapEntry(1, $10, $10, 0, 0, 3, 0, $46)
    %spritemapEntry(1, $30, $10, 0, 0, 3, 0, $48)
    %spritemapEntry(1, $40, $10, 0, 0, 3, 0, $4A)
    %spritemapEntry(1, $50, $10, 0, 0, 3, 0, $4C)
    %spritemapEntry(1, $20, $18, 0, 0, 3, 0, $4E)

    %spritemapEntry(1, $00, $20, 0, 0, 3, 0, $60)
    %spritemapEntry(1, $10, $20, 0, 0, 3, 0, $62)
    %spritemapEntry(1, $30, $20, 0, 0, 3, 0, $64)
    %spritemapEntry(1, $40, $20, 0, 0, 3, 0, $66)
    %spritemapEntry(1, $50, $20, 0, 0, 3, 0, $68)
    %spritemapEntry(1, $20, $28, 0, 0, 3, 0, $6A)

    %spritemapEntry(1, $10, $30, 0, 0, 3, 0, $6C)
    %spritemapEntry(1, $30, $30, 0, 0, 3, 0, $6E)
    %spritemapEntry(1, $40, $30, 0, 0, 3, 0, $80)
    %spritemapEntry(1, $50, $30, 0, 0, 3, 0, $82)
    %spritemapEntry(1, $20, $38, 0, 0, 3, 0, $84)

    %spritemapEntry(1, $08, $40, 0, 0, 3, 0, $86)
    %spritemapEntry(1, $30, $40, 0, 0, 3, 0, $88)
    %spritemapEntry(1, $40, $40, 0, 0, 3, 0, $8A)
    %spritemapEntry(1, $18, $48, 0, 0, 3, 0, $8C)

    %spritemapEntry(1, $08, $50, 0, 0, 3, 0, $8E)
    %spritemapEntry(1, $28, $50, 0, 0, 3, 0, $A0)
    %spritemapEntry(1, $38, $50, 0, 0, 3, 0, $A2)
    %spritemapEntry(1, $48, $50, 0, 0, 3, 0, $A4)
    %spritemapEntry(1, $18, $58, 0, 0, 3, 0, $A6)

    %spritemapEntry(1, $28, $60, 0, 0, 3, 0, $A8)
    %spritemapEntry(1, $48, $60, 0, 0, 3, 0, $AA)
    %spritemapEntry(1, $58, $60, 0, 0, 3, 0, $AC)

    %spritemapEntry(0, $50, $08, 0, 0, 3, 0, $32)
    %spritemapEntry(0, $08, $18, 0, 0, 3, 0, $33)
    %spritemapEntry(0, $18, $40, 0, 0, 3, 0, $34)
    %spritemapEntry(0, $50, $40, 0, 0, 3, 0, $35)
    %spritemapEntry(0, $58, $40, 0, 0, 3, 0, $36)
    %spritemapEntry(0, $28, $48, 0, 0, 3, 0, $37)
    %spritemapEntry(0, $50, $48, 0, 0, 3, 0, $38)

    %spritemapEntry(0, $08, $60, 0, 0, 3, 0, $39)
    %spritemapEntry(0, $10, $60, 0, 0, 3, 0, $3A)
    %spritemapEntry(0, $38, $60, 0, 0, 3, 0, $3B)
    %spritemapEntry(0, $40, $60, 0, 0, 3, 0, $3C)
    %spritemapEntry(0, $68, $60, 0, 0, 3, 0, $3D)
    %spritemapEntry(0, $70, $60, 0, 0, 3, 0, $3E)

    %spritemapEntry(0, $10, $68, 0, 0, 3, 0, $3F)
    %spritemapEntry(0, $18, $68, 0, 0, 3, 0, $AE)
    %spritemapEntry(0, $20, $68, 0, 0, 3, 0, $AF)
    %spritemapEntry(0, $38, $68, 0, 0, 3, 0, $BE)
    %spritemapEntry(0, $78, $68, 0, 0, 3, 0, $BF)

    ;---------------------------------------------------------------------------
    ; Iteration 8 - restored body tiles
    ;
    ; These seven OBJ tile slots already existed inside $6000-$6BFF but were
    ; not referenced by the arm or leg spritemaps.
    ;---------------------------------------------------------------------------

    %spritemapEntry(0, $00, $18, 0, 0, 3, 0, $0E)
    %spritemapEntry(0, $40, $68, 0, 0, 3, 0, $0F)
    %spritemapEntry(0, $58, $08, 0, 0, 3, 0, $27)
    %spritemapEntry(0, $50, $00, 0, 0, 3, 0, $28)
    %spritemapEntry(0, $28, $00, 0, 0, 3, 0, $29)
    %spritemapEntry(0, $70, $68, 0, 0, 3, 0, $2A)
    %spritemapEntry(0, $18, $08, 0, 0, 3, 0, $2B)


;-------------------------------------------------------------------------------
; Prevent player-renderer code/data from overflowing bank A4
;-------------------------------------------------------------------------------

warnpc $A50000


;===============================================================================
; CROCOMIRE PLAYER GRAPHICS DATA
; Bank AD free space starts at $ADF444
;===============================================================================

org $ADF444

CrocomirePlayer_BGPart3Tiles:
    incbin "../data/CrocomirePlayer_BGPart3.bin"

CrocomirePlayer_OAMArmTiles:
    incbin "../data/CrocomirePlayer_OAMArm.bin"

CrocomirePlayer_OAMLegTiles:
    incbin "../data/CrocomirePlayer_OAMLegs.bin"

warnpc $AE0000

;===============================================================================
; CROCOMIRE PLAYER FULL STATIC GRAPHICS
; Iteration 6
; Bank B8 is free for this prototype asset
;===============================================================================

org $B88000

CrocomirePlayer_FullStaticTiles:
    incbin "../data/CrocomirePlayer_FullStatic.bin"

warnpc $B90000