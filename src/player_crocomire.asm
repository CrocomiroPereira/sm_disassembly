;===============================================================================
; CROCOMIRE PLAYER RENDERER
; Prototype v0.0059 PROGRESS - isolate three suspect OAM pieces from IT1
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

; Frames to wait after detecting a new room before queuing the VRAM load.
; See PauseMenu_UnusedAnimationTimer0731 below for why this exists.
CrocomirePlayer_SettleFrames    = $0008

; CrocomirePlayer_Render reuses neverRead09E8 (genuinely dead vanilla RAM,
; see memory.asm) to remember the OAMStack byte-offset it last drew into,
; so next frame's OAM clear can target exactly that spot regardless of
; where OAMStack naturally is this frame.

; Frame counter reuses PauseMenu_UnusedAnimationTimer0731 directly - an
; abandoned pause-menu RAM cell (slot 5 of an animation-timer table,
; explicitly marked "Unused" and only ever STZ'd at boot/pause-open, never
; touched during GameState $0008 gameplay) - as a scratch frame counter.


;-------------------------------------------------------------------------------
; Renderer entry point
;-------------------------------------------------------------------------------

CrocomirePlayer_Render:
    PHP
    PHB
    PHK
    PLB

    REP #$30

    ;---------------------------------------------------------------------------
    ; Clear the exact OAM slots WE ourselves wrote to last frame, remembered
    ; in neverRead09E8 (neverRead09E8 - genuinely dead vanilla
    ; RAM, see memory.asm), before drawing anything new this frame.
    ;
    ; Confirmed 2026-09-06 via live OAM inspection in Mesen's Sprite Viewer:
    ; a stray fragment kept appearing near the tail, overlapping our real
    ; tail tip but not part of its tile data - a leftover OAM entry from a
    ; previous frame that our own drawing never touched again.
    ;
    ; Root cause: DrawSamusSprites is fully replaced by this function (see
    ; bank_90.asm), so by the time we run, OAMStack already reflects however
    ; many sprites every OTHER system (enemies, HUD, background objects)
    ; drew earlier that same frame - a value that drifts with unrelated game
    ; state. A first fix cleared "39 slots starting from wherever OAMStack is
    ; now", which clears the right COUNT of slots but not necessarily the
    ; same slots we used on some earlier frame when OAMStack happened to be
    ; different, so a stale entry from that earlier frame could survive
    ; indefinitely. A second fix forced OAMStack to a fixed high slot range
    ; (89-127) every frame - but that range turned out to already be in use
    ; by another game system (broke rendering entirely: reverted).
    ;
    ; This version claims no OAM territory of its own: it just remembers
    ; wherever IT happened to draw last frame and cleans up exactly that
    ; spot before drawing wherever OAMStack naturally is THIS frame - so a
    ; stale entry can never survive more than one frame, regardless of how
    ; much OAMStack drifts, and no other system's slots are ever touched.
    ;---------------------------------------------------------------------------

    LDX.W neverRead09E8
    SEP #$20
    LDY.W #$0027            ; 39 slots: 8 (leg overlay) + 31 (body)

  .clearOwnOAMFootprint:
    LDA.B #$F0
    STA.W OAMLow+1,X
    INX
    INX
    INX
    INX
    CPX.W #$0200
    BNE .clearNoWrap
    LDX.W #$0000

  .clearNoWrap:
    DEY
    BNE .clearOwnOAMFootprint

    REP #$20

    ; Samus is invisible, so reserve her normal sprite tile updates
    STZ.W SamusTiles_TopHalfFlag
    STZ.W SamusTiles_BottomHalfFlag

    JSR.W CrocomirePlayer_HandleLandingShake

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
    ;
    ; Wait CrocomirePlayer_SettleFrames frames after a new room is detected
    ; before actually queuing the VRAM load.
    ;
    ; Bug found 2026-09-05: on the very first room after booting the ROM
    ; (before any door has been used), this load shares the frame with the
    ; game's own much larger initial VRAM setup (Samus tiles, HUD, room
    ; tileset, etc). Our transfer is queued through the same VRAMWriteStack
    ; as everything else, and on that one specific frame there's enough
    ; competing traffic that it can be processed past whatever the engine's
    ; per-frame DMA budget allows, silently truncating our graphics (the
    ; recovered tail tip - the last, smallest tiles in the transfer - never
    ; arrives in VRAM, and shows leftover boot-time VRAM garbage instead).
    ; Every later room change works fine because by then the frame is no
    ; longer that congested. Waiting a handful of frames sidesteps the
    ; problem entirely instead of trying to win the race every time.
    ;===========================================================================

    LDA.W GameState
    CMP.W #$0008
    BNE .crocomireGraphicsDone

    LDA.W RoomPointer
    CMP.W StartSamusRAM_Unused0A02
    BNE .roomChangeDetected
    BRA .crocomireGraphicsDone

  .roomChangeDetected:
    LDA.W PauseMenu_UnusedAnimationTimer0731
    INC A
    STA.W PauseMenu_UnusedAnimationTimer0731
    CMP.W #CrocomirePlayer_SettleFrames
    BMI .crocomireGraphicsDone

    STZ.W PauseMenu_UnusedAnimationTimer0731
    LDA.W RoomPointer
    STA.W StartSamusRAM_Unused0A02
    STZ.W neverRead09E8
    JSR.W CrocomirePlayer_QueueTestTiles

  .crocomireGraphicsDone:

    ; Enemy/OAM Crocomire palette -> sprite palette 7
    JSR.W CrocomirePlayer_LoadTestPalette

    ; Crocomire BG palette 7 -> temporary sprite palette 6
    JSR.W CrocomirePlayer_LoadBGPalette

    ; Drawn first so it lands on top of everything else this frame (same
    ; priority level => lower OAM index wins => earlier-drawn is on top).
    JSR.W CrocomirePlayer_DrawHitboxOutline

    ; Remember where OUR OWN footprint (leg overlay + body, drawn below)
    ; starts THIS frame, for next frame's self-clear. Captured here - after
    ; the hitbox outline has already advanced OAMStack past its own entries
    ; - not at function entry, so it actually matches where we end up
    ; writing, not wherever OAMStack happened to be before the outline ran.
    LDA.W OAMStack
    STA.W neverRead09E8


    ;===========================================================================
    ; OAM component 3 (persistent arm section)
    ;===========================================================================


    ;===========================================================================
    ; Crocomire Player 80%
    ;
    ; Both layers share one origin:
    ;   body  -> sprite palette 6
    ;   limbs -> sprite palette 7
    ;
    ; The 80% image was generated from the complete Crocomire composition.
    ;===========================================================================

    ;---------------------------------------------------------------------------
    ; TELEPATHY
    ;
    ; While active (neverRead0AA4, set by EnemyTouch_TriggerTelepathy in
    ; bank_A0.asm when Samus touches a TelepathyZoomer), Croc freezes at
    ; whatever screen position he was already standing at, and Samus's real
    ; (invisible) position is synced to the tracked enemy every frame, so
    ; her actual hitbox/collision follows it instead of Croc's frozen body.
    ; Ends the moment that enemy walks back within Croc's frozen footprint.
    ;
    ; neverRead0E48 holds the tracked enemy's Enemy-struct byte offset.
    ; PauseMenu_UnusedAnimationFrame/_UnusedAnimationMode (only otherwise
    ; touched by pause-menu setup, never during normal gameplay) hold
    ; Croc's frozen screen X/Y - refreshed every frame TELEPATHY is NOT
    ; active, so they're always wherever Croc last stood the moment it
    ; triggers.
    ;---------------------------------------------------------------------------

    LDA.W neverRead0AA4
    BEQ .noTelepathy

    LDX.W neverRead0E48
    LDA.W Enemy.XPosition,X
    STA.W SamusXPosition
    SEC
    SBC.W PauseMenu_UnusedAnimationFrame
    BPL +
    EOR.W #$FFFF
    INC A
+   CMP.W #$0010
    BPL .stillActive

    LDA.W Enemy.YPosition,X
    STA.W SamusYPosition
    SEC
    SBC.W PauseMenu_UnusedAnimationMode
    BPL +
    EOR.W #$FFFF
    INC A
+   CMP.W #$0018
    BPL .stillActive

    STZ.W neverRead0AA4
    BRA .useFrozenOrigin

  .stillActive:
    LDA.W Enemy.YPosition,X
    STA.W SamusYPosition

  .useFrozenOrigin:
    LDA.W PauseMenu_UnusedAnimationFrame
    STA.B DP_Temp14
    LDA.W PauseMenu_UnusedAnimationMode
    STA.B DP_Temp12
    BRA .originDone

  .noTelepathy:

    ;---------------------------------------------------------------------------
    ; Shared X origin
    ;
    ; Current centered full-size body origin was -11 px.
    ; The original composite extended 6 px farther left than the body,
    ; so the new scaled composite origin is approximately -16 px.
    ;---------------------------------------------------------------------------

    LDA.W SamusXPosition
    SEC
    SBC.W Layer1XPosition
    CLC
    ADC.W #$FFF0
    STA.B DP_Temp14
    STA.W PauseMenu_UnusedAnimationFrame

    ;---------------------------------------------------------------------------
    ; Shared Y origin
    ;
    ; Aligns the composite's feet (the bottom edge of the spritemap's bounding
    ; box, 96px / $60 below its own top-left origin) with Samus's own feet
    ; (SamusYPosition + SamusYRadius), instead of an empirically-tuned offset.
    ;---------------------------------------------------------------------------

    LDA.W SamusYPosition
    CLC
    ADC.W SamusYRadius
    SEC
    SBC.W Layer1YPosition
    SEC
    SBC.W #$0060
    STA.B DP_Temp12
    STA.W PauseMenu_UnusedAnimationMode

  .originDone:

    ;---------------------------------------------------------------------------
    ; v0.0055 IT1 - merged Crocomire composite
    ;
    ; Body and limb palettes have the same visible colours, so both layers are
    ; merged into one sprite raster. This removes overlapping OAM pieces and
    ; reduces per-scanline OBJ pressure.
    ;---------------------------------------------------------------------------

    STZ.B DP_Temp00

    LDA.W #$0C00
    STA.B DP_Temp03

    ;---------------------------------------------------------------------------
    ; Face the same way Samus is currently facing.
    ;
    ; PoseXDirection ($0A1E): $08 = facing right, $04 = facing left. It's the
    ; game's own already-resolved facing signal (set from the per-Pose
    ; PoseDefinitions.XDirection table whenever Pose changes), not something
    ; we need to derive ourselves.
    ;
    ; The composite artwork faces left natively, so mirror it (spritemap
    ; entries with x-flip set and x-offsets mirrored around the same bounding
    ; box) only when Samus is facing right.
    ;---------------------------------------------------------------------------

    ;---------------------------------------------------------------------------
    ; Walk-cycle leg overlay - first pass, facing-left only.
    ;
    ; Drawn BEFORE the static body below on purpose: on SNES OBJ hardware,
    ; when two sprites share the same priority value, the one added to OAM
    ; FIRST (lower OAM index) is displayed on top. Drawing this first makes
    ; the moving leg win over the static body's overlapping foot tiles
    ; instead of being hidden underneath it.
    ;
    ; The static composite below had its two outermost foot tiles removed
    ; (they're redundant with this overlay - see the comments by the removed
    ; entries), so this overlay must always draw something when facing left,
    ; even when standing still - otherwise the feet would be missing a chunk
    ; while idle. MovementType $01 = walking (same check the earlier
    ; enemy-driven v0.004 prototype used): idle uses the neutral position
    ; (overlay 0, timer held at 0); walking ping-pongs smoothly through all
    ; 6 positions extracted from the vanilla walk cycle, wrapping the timer
    ; every 10 steps (80 frames) so there's no dead pause at the loop point.
    ; Facing-right is skipped for now (that composite kept its own static
    ; feet untouched) - mirroring this overlay is follow-up work.
    ;
    ; UnusedMode7RotationAngle is reused as a free-running frame timer (only
    ; otherwise touched by Mode7 setup, which doesn't run during normal
    ; GameState $0008 gameplay).
    ;---------------------------------------------------------------------------

    LDA.W PoseXDirection
    AND.W #$00FF
    CMP.W #$0008
    BEQ .walkOverlayDone

    LDA.W MovementType
    AND.W #$00FF
    CMP.W #$0001
    BNE .idleOverlay

    LDA.W UnusedMode7RotationAngle
    INC A
    CMP.W #$0050            ; 80 = 10 steps * 8 frames/step
    BNE .noWrap
    LDA.W #$0000
  .noWrap:
    STA.W UnusedMode7RotationAngle
    LSR A
    LSR A
    LSR A
    BRA .haveOverlayIndex

  .idleOverlay:
    LDA.W #$0000

  .haveOverlayIndex:
    ASL A
    TAX
    LDA.W CrocomirePlayer_WalkPingPong,X
    ASL A
    TAX
    LDA.W CrocomirePlayer_WalkOverlayPointers,X
    TAY
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22

  .walkOverlayDone:

    LDY.W #CrocomirePlayer80v55_CompositeSpritemap
    LDA.W PoseXDirection
    AND.W #$00FF
    CMP.W #$0008
    BNE .render
    LDY.W #CrocomirePlayer80v55_CompositeSpritemap_FacingRight

  .render:
    JSL.L AddSpritemapToOAM_WithBaseTileNumber_8B22

    PLB
    PLP
    RTL

;-------------------------------------------------------------------------------
; Debug: draw Samus's REAL hitbox as a 1px white outline, permanently visible
; on top of the Crocomire composite. Recomputed fresh every frame from
; SamusXRadius/SamusYRadius, so it tracks whatever pose Samus is actually in
; (standing, jumping, crouching, morph ball, etc. - YRadius comes from
; PoseDefinitions_YRadius per pose; XRadius is always a fixed 5, i.e. a
; constant 10px box width).
;
; Built from free composite tiles $B0-$B9 (palette 6, same as everything
; else - index 1 in CrocomirePlayer_BGPalette is pure white):
;     $B0-$B6 - vertical segment, opaque for the top 1-7 rows (for whatever
;                remainder is left after tiling full 8px segments)
;     $B7     - vertical segment, opaque for all 8 rows
;     $B8     - horizontal segment, opaque for all 8 columns
;     $B9     - horizontal segment, opaque for the first 2 columns only
;                (box width is always exactly 10px = one $B8 + one $B9)
;
; Self-clears its own previous frame's OAM footprint via neverRead0A18 -
; same self-remembering technique as CrocomirePlayer_Render's own footprint
; (neverRead09E8), kept as a separate scratch word so the two never collide.
;-------------------------------------------------------------------------------

CrocomirePlayer_DrawHitboxOutline:
    LDX.W neverRead0A18
    SEP #$20
    LDY.W #$0018            ; 24 slots safety margin (worst case needs 16:
                             ; max YRadius seen is 24 -> height 48 -> 6+6
                             ; full vertical tiles both sides + 4 horizontal)

  .clearHitboxFootprint:
    LDA.B #$F0
    STA.W OAMLow+1,X
    INX
    INX
    INX
    INX
    CPX.W #$0200
    BNE .clearHBNoWrap
    LDX.W #$0000

  .clearHBNoWrap:
    DEY
    BNE .clearHitboxFootprint

    REP #$20

    LDX.W OAMStack
    STX.W neverRead0A18

    LDA.W SamusXPosition
    SEC
    SBC.W SamusXRadius
    SEC
    SBC.W Layer1XPosition
    STA.B DP_Temp12          ; left

    LDA.W SamusYPosition
    SEC
    SBC.W SamusYRadius
    SEC
    SBC.W Layer1YPosition
    STA.B DP_Temp14          ; top

    LDA.W SamusYRadius
    ASL A
    STA.B DP_Temp16          ; height

    LDA.W SamusXRadius
    ASL A
    STA.B DP_Temp18          ; width

    ; --- top edge (2 tiles: 8px + 2px = 10px) ---
    LDA.W #$00B8
    STA.B DP_Temp1A
    LDY.B DP_Temp14
    LDA.B DP_Temp12
    JSR .putEntry

    LDA.W #$00B9
    STA.B DP_Temp1A
    LDY.B DP_Temp14
    LDA.B DP_Temp12
    CLC
    ADC.W #$0008
    JSR .putEntry

    ; --- bottom edge ---
    LDA.B DP_Temp14
    CLC
    ADC.B DP_Temp16
    SEC
    SBC.W #$0001
    STA.B DP_Temp1C          ; bottomY

    LDA.W #$00B8
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp12
    JSR .putEntry

    LDA.W #$00B9
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp12
    CLC
    ADC.W #$0008
    JSR .putEntry

    ; --- left edge: tile every 8px, then one partial tile for the remainder ---
    LDA.B DP_Temp14
    STA.B DP_Temp1C          ; y cursor
    LDA.B DP_Temp16
    STA.B DP_Temp1E          ; remaining height

  .leftLoop:
    LDA.B DP_Temp1E
    CMP.W #$0008
    BMI .leftRemainder
    LDA.W #$00B7
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp12
    JSR .putEntry
    LDA.B DP_Temp1C
    CLC
    ADC.W #$0008
    STA.B DP_Temp1C
    LDA.B DP_Temp1E
    SEC
    SBC.W #$0008
    STA.B DP_Temp1E
    BRA .leftLoop

  .leftRemainder:
    LDA.B DP_Temp1E
    BEQ .leftDone
    CLC
    ADC.W #$00AF             ; remainder (1..7) -> tile $B0..$B6
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp12
    JSR .putEntry

  .leftDone:

    ; --- right edge ---
    LDA.B DP_Temp12
    CLC
    ADC.B DP_Temp18
    SEC
    SBC.W #$0001
    STA.B DP_Temp16          ; rightX (height no longer needed, reuse slot)

    LDA.B DP_Temp14
    STA.B DP_Temp1C
    LDA.W SamusYRadius
    ASL A
    STA.B DP_Temp1E

  .rightLoop:
    LDA.B DP_Temp1E
    CMP.W #$0008
    BMI .rightRemainder
    LDA.W #$00B7
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp16
    JSR .putEntry
    LDA.B DP_Temp1C
    CLC
    ADC.W #$0008
    STA.B DP_Temp1C
    LDA.B DP_Temp1E
    SEC
    SBC.W #$0008
    STA.B DP_Temp1E
    BRA .rightLoop

  .rightRemainder:
    LDA.B DP_Temp1E
    BEQ .rightDone
    CLC
    ADC.W #$00AF
    STA.B DP_Temp1A
    LDY.B DP_Temp1C
    LDA.B DP_Temp16
    JSR .putEntry

  .rightDone:
    STX.W OAMStack           ; hand off our advanced cursor - otherwise the
                             ; leg overlay/body draws that run right after us
                             ; start from the old position and immediately
                             ; overwrite everything we just drew.
    RTS

  .putEntry:
    ; In: A = screen X, Y = screen Y (both 16-bit), DP_Temp1A = tile number.
    ; Uses/advances the shared X register as the OAM write cursor.
    STA.W OAMLow,X
    TYA
    SEP #$20
    STA.W OAMLow+1,X
    REP #$20
    LDA.B DP_Temp1A
    ORA.W #$3C00             ; priority 3, palette 6
    STA.W OAMLow+2,X
    INX
    INX
    INX
    INX
    CPX.W #$0200
    BNE +
    LDX.W #$0000
+   RTS

;-------------------------------------------------------------------------------
; Queue persistent Crocomire graphics to VRAM
;
; Every entry:
;     dw size, source_low_word, destination_vram
;
; All sources currently live in ROM bank $AD.
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Landing shake: reuse the game's own generic environment shake - the same
; one any Super Missile impact against a wall uses, anywhere, any room (see
; bank_93.asm's projectile explosion handler: EarthquakeType $14, Timer $1E)
; - every time Samus (visually Crocomire) touches solid ground while
; falling, from a jump or off any ledge of any height.
;
; Confirmed 2026-09-06 via live memory watch in Mesen: checking
; SamusSolidVerticalCollisionResult == 1 here never worked, because that
; flag is set AND consumed/reset entirely within Samus's own movement/pose
; update (Execute_SamusMovementHandler -> immediately followed by
; SetProspectiveSamusPoseAccordingToSolidVerticalCollision_PSP in the same
; per-frame call chain) - all of which runs and finishes before rendering
; (Draw_Samus_Projectiles_Enemies_and_Enemy_Projectiles, which is what
; reaches us) even starts. By the time we run, it's already back to 0.
;
; SamusYSpeed itself doesn't get consumed/reset that early - it's still
; whatever the movement step left it at when we read it - so instead we
; track it across frames ourselves: landing = previous frame's Y speed was
; positive (genuinely falling) and this frame it's back to exactly 0 (just
; stopped). neverRead0AA4 is also written by Enable_Horizontal_Slope_
; Detection elsewhere, but only while Samus is already grounded (where
; Y speed is 0 anyway), and we unconditionally overwrite it with the real
; current value at the end of every one of our own calls, so that stray
; write can't desync us from one of our own frames to the next.
;-------------------------------------------------------------------------------

CrocomirePlayer_HandleLandingShake:
    LDA.W neverRead0AA4
    BEQ .updateOnly
    BMI .updateOnly

    LDA.W SamusYSpeed
    BNE .updateOnly

    LDA.W #$0014
    STA.W EarthquakeType
    LDA.W #$001E
    STA.W EarthquakeTimer

  .updateOnly:
    LDA.W SamusYSpeed
    STA.W neverRead0AA4
    RTS

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

CrocomirePlayer80v55_CompositeSpritemap:
    dw $001F
    %spritemapEntry(1, $10, $00, 0, 0, 3, 0, $00)
    %spritemapEntry(1, $20, $00, 0, 0, 3, 0, $02)
    %spritemapEntry(1, $30, $00, 0, 0, 3, 0, $04)
    %spritemapEntry(1, $40, $00, 0, 0, 3, 0, $06)
    %spritemapEntry(1, $00, $10, 0, 0, 3, 0, $08)
    %spritemapEntry(1, $10, $10, 0, 0, 3, 0, $0A)
    %spritemapEntry(1, $20, $10, 0, 0, 3, 0, $0C)
    %spritemapEntry(1, $30, $10, 0, 0, 3, 0, $0E)
    %spritemapEntry(1, $40, $10, 0, 0, 3, 0, $20)
    %spritemapEntry(1, $00, $20, 0, 0, 3, 0, $22)
    %spritemapEntry(1, $10, $20, 0, 0, 3, 0, $24)
    %spritemapEntry(1, $20, $20, 0, 0, 3, 0, $26)
    %spritemapEntry(1, $30, $20, 0, 0, 3, 0, $28)
    %spritemapEntry(1, $40, $20, 0, 0, 3, 0, $2A)
    %spritemapEntry(1, $50, $20, 0, 0, 3, 0, $2C)
    %spritemapEntry(1, $00, $30, 0, 0, 3, 0, $2E)
    %spritemapEntry(1, $10, $30, 0, 0, 3, 0, $40)
    %spritemapEntry(1, $20, $30, 0, 0, 3, 0, $42)
    %spritemapEntry(1, $30, $30, 0, 0, 3, 0, $44)
    %spritemapEntry(1, $40, $30, 0, 0, 3, 0, $46)
    %spritemapEntry(1, $00, $40, 0, 0, 3, 0, $48)
    %spritemapEntry(1, $10, $40, 0, 0, 3, 0, $4A)
    %spritemapEntry(1, $20, $40, 0, 0, 3, 0, $4C)
    %spritemapEntry(1, $30, $40, 0, 0, 3, 0, $4E)
    %spritemapEntry(1, $40, $40, 0, 0, 3, 0, $60)
    %spritemapEntry(1, $50, $40, 0, 0, 3, 0, $62)
    ; $00,$50->$64 and $50,$50->$6E removed: redundant with the walk-cycle
    ; leg overlay below (confirmed safe to drop offline - no visible gap).
    %spritemapEntry(1, $10, $50, 0, 0, 3, 0, $66)
    %spritemapEntry(1, $20, $50, 0, 0, 3, 0, $68)
    %spritemapEntry(1, $30, $50, 0, 0, 3, 0, $6A)
    %spritemapEntry(1, $40, $50, 0, 0, 3, 0, $6C)

    ;---------------------------------------------------------------------------
    ; Recovered tail tip
    ;
    ; Lost when the body+limb layers were merged into one raster (v0.0055 IT1):
    ; the merge only kept 32 of the original 48 blocks, silently dropping the
    ; tail's outermost segment. Restored here from the original unmerged
    ; CrocomirePlayer_80pct.bin tiles $84/$85 (screen position x=$60,y=$50).
    ;
    ; Placed at tile $80 - reusing free space already inside the existing
    ; 192-tile / $1800-byte VRAM budget - instead of appending past it.
    ; Appending past tile $BF (tried first) silently corrupted whatever sits
    ; next in VRAM after this graphics block, since the DMA queued by
    ; CrocomirePlayer_QueueTestTiles below is sized to exactly that budget.
    ;
    ; The tile data at $80/$81/$90/$91 is now blanked (see
    ; CrocomirePlayer_QueueTestTiles' source .bin - cleared 2026-09-06: this
    ; was the actual stray fragment, confirmed live in Mesen), so this entry
    ; draws nothing regardless of position. Left at its original recovered
    ; position ($60,$50) per request, rather than the $50 gap-closing fix
    ; tried earlier - moot while the tile is blank, but keeps this ready to
    ; restore if the tip graphic ever comes back.
    ;---------------------------------------------------------------------------

    %spritemapEntry(1, $60, $50, 0, 0, 3, 0, $80)

;-------------------------------------------------------------------------------
; Facing-right mirror of CrocomirePlayer80v55_CompositeSpritemap.
;
; Generated from the entry above: x-offsets mirrored around the shared 112px
; ($70) bounding box (new_x = $60 - old_x), x-flip set, same tile numbers -
; the SNES OBJ hardware handles the subtile swap for 16x16 sprites on its
; own, so no new graphics data is needed, only re-flowed coordinates.
;-------------------------------------------------------------------------------

CrocomirePlayer80v55_CompositeSpritemap_FacingRight:
    dw $0021
    %spritemapEntry(1, $50, $00, 0, 1, 3, 0, $00)
    %spritemapEntry(1, $40, $00, 0, 1, 3, 0, $02)
    %spritemapEntry(1, $30, $00, 0, 1, 3, 0, $04)
    %spritemapEntry(1, $20, $00, 0, 1, 3, 0, $06)
    %spritemapEntry(1, $60, $10, 0, 1, 3, 0, $08)
    %spritemapEntry(1, $50, $10, 0, 1, 3, 0, $0A)
    %spritemapEntry(1, $40, $10, 0, 1, 3, 0, $0C)
    %spritemapEntry(1, $30, $10, 0, 1, 3, 0, $0E)
    %spritemapEntry(1, $20, $10, 0, 1, 3, 0, $20)
    %spritemapEntry(1, $60, $20, 0, 1, 3, 0, $22)
    %spritemapEntry(1, $50, $20, 0, 1, 3, 0, $24)
    %spritemapEntry(1, $40, $20, 0, 1, 3, 0, $26)
    %spritemapEntry(1, $30, $20, 0, 1, 3, 0, $28)
    %spritemapEntry(1, $20, $20, 0, 1, 3, 0, $2A)
    %spritemapEntry(1, $10, $20, 0, 1, 3, 0, $2C)
    %spritemapEntry(1, $60, $30, 0, 1, 3, 0, $2E)
    %spritemapEntry(1, $50, $30, 0, 1, 3, 0, $40)
    %spritemapEntry(1, $40, $30, 0, 1, 3, 0, $42)
    %spritemapEntry(1, $30, $30, 0, 1, 3, 0, $44)
    %spritemapEntry(1, $20, $30, 0, 1, 3, 0, $46)
    %spritemapEntry(1, $60, $40, 0, 1, 3, 0, $48)
    %spritemapEntry(1, $50, $40, 0, 1, 3, 0, $4A)
    %spritemapEntry(1, $40, $40, 0, 1, 3, 0, $4C)
    %spritemapEntry(1, $30, $40, 0, 1, 3, 0, $4E)
    %spritemapEntry(1, $20, $40, 0, 1, 3, 0, $60)
    %spritemapEntry(1, $10, $40, 0, 1, 3, 0, $62)
    %spritemapEntry(1, $60, $50, 0, 1, 3, 0, $64)
    %spritemapEntry(1, $50, $50, 0, 1, 3, 0, $66)
    %spritemapEntry(1, $40, $50, 0, 1, 3, 0, $68)
    %spritemapEntry(1, $30, $50, 0, 1, 3, 0, $6A)
    %spritemapEntry(1, $20, $50, 0, 1, 3, 0, $6C)
    %spritemapEntry(1, $10, $50, 0, 1, 3, 0, $6E)
    %spritemapEntry(1, $00, $50, 0, 1, 3, 0, $80)

;-------------------------------------------------------------------------------
; Walk-cycle leg overlay tables
;
; 6 static positions per leg, extracted from the vanilla ChargeForward/StepBack
; walk cycle (Spritemap_Crocomire_5..A for the front leg, _B..10 for the back leg,
; tile $DF x-offset per frame), scaled x0.8. Legs move in opposite phase (one
; extends while the other retracts), matching the original.
;
; The leg artwork itself (not just its position) is downscaled x0.8 from the
; vanilla tiles using majority-color voting (avoids introducing off-palette
; colours) - 5 source 8x8 tiles -> 4 tiles. See tools/ for the one-off script.
;
; Anchors were tuned by eye against the existing static feet - not exact, first pass.
;-------------------------------------------------------------------------------

CrocomirePlayer_WalkOverlay_0:
    dw $0008
    %spritemapEntry(0, $04, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $0C, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $14, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $1C, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $40, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $48, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $50, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $58, $56, 0, 0, 3, 0, $85)

CrocomirePlayer_WalkOverlay_1:
    dw $0008
    %spritemapEntry(0, $06, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $0E, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $16, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $1E, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $39, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $41, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $49, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $51, $56, 0, 0, 3, 0, $85)

CrocomirePlayer_WalkOverlay_2:
    dw $0008
    %spritemapEntry(0, $08, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $10, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $18, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $20, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $34, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $3C, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $44, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $4C, $56, 0, 0, 3, 0, $85)

CrocomirePlayer_WalkOverlay_3:
    dw $0008
    %spritemapEntry(0, $0C, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $14, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $1C, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $24, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $30, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $38, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $40, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $48, $56, 0, 0, 3, 0, $85)

CrocomirePlayer_WalkOverlay_4:
    dw $0008
    %spritemapEntry(0, $10, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $18, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $20, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $28, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $2C, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $34, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $3C, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $44, $56, 0, 0, 3, 0, $85)

CrocomirePlayer_WalkOverlay_5:
    dw $0008
    %spritemapEntry(0, $15, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $1D, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $25, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $2D, $56, 0, 0, 3, 0, $85)
    %spritemapEntry(0, $2A, $56, 0, 0, 3, 0, $82)
    %spritemapEntry(0, $32, $56, 0, 0, 3, 0, $83)
    %spritemapEntry(0, $3A, $56, 0, 0, 3, 0, $84)
    %spritemapEntry(0, $42, $56, 0, 0, 3, 0, $85)

; Ping-pong index (0..9) -> leg table step (0..5): step forward then back,
; no dead pause - the timer above wraps every 10 steps to match this exactly.
CrocomirePlayer_WalkPingPong:
    dw $0000,$0001,$0002,$0003,$0004,$0005,$0004,$0003
    dw $0002,$0001

CrocomirePlayer_WalkOverlayPointers:
    dw CrocomirePlayer_WalkOverlay_0
    dw CrocomirePlayer_WalkOverlay_1
    dw CrocomirePlayer_WalkOverlay_2
    dw CrocomirePlayer_WalkOverlay_3
    dw CrocomirePlayer_WalkOverlay_4
    dw CrocomirePlayer_WalkOverlay_5

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

    incbin "../data/CrocomirePlayer_80pct_v0055_it1_composite.bin"

warnpc $B90000