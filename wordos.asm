; WorDOS - a DOS clone of the popular word guessing game 'Wordle'
; (C) 2022 Martin J. Fiedler <keyj@emphy.de>
; original game (C) 2021-2022 Josh Wardle

; This file is in the public domain.

; assemble with: yasm -fbin -owordos.com wordos.asm
; Other assemblers might work, but haven't been tested.

BITS 16
CPU 8086
ORG 0100h

    ; entry point -> jump over the word list data
    mov ax, main
    jmp ax

; screen layout:
;    0         1         2         3
;    0123456789012345678901234567890123456789
;  0 ........................................
;  1 ..............W.O.R.D.O.S............... y=1  x0=14
;  2 ........................................
;  3 ........................................
;  4 ...............#.#.#.#.#................ y=4  x0=15
;  5 ........................................
;  6 ...............#.#.#.#.#................ y=6  x0=15
;  7 ........................................
;  8 ...............#.#.#.#.#................ y=8  x0=15
;  9 ........................................
; 10 ...............#.#.#.#.#................ y=10 x0=15
; 11 ........................................
; 12 ...............#.#.#.#.#................ y=12 x0=15
; 13 ........................................
; 14 ...............#.#.#.#.#................ y=14 x0=15
; 15 ........................................
; 16 ........................................ 
; 17 ..........status-status-status.......... y=17 centered
; 18 .................SOLVE.................. y=18 x0=17
; 19 ........................................
; 20 ........................................ 
; 21 .......A.B.C.D.E.F.G.H.I.J.K.L.M........ y=21 x0=7
; 22 ........................................  
; 23 .......N.O.P.Q.R.S.T.U.V.W.X.Y.Z........ y=23 x0=7
; 24 ........................................

; variables
currline:   db 0                 ; current input line (in screen coordinates)
title:      db "W O R D O S", 0  ; string constant (put here b/c it looks nice)
guessbuf:   db "KeyJ^"           ; 5-byte buffer for the current guess
wordbuf:    db "TRBL",0          ; solution word (last byte must be < 'A')
            db 0                 ; null terminator so wordbuf can be printed

; "bitmap" (actually a byte-oriented table) of flags for each letter
bitmap      equ 254 - 'Z'        ; put it into the end of the PSP
BM_GUESSED  equ 1                ; "has been guessed already" flag
BM_INWORD   equ 2                ; "letter is present in the word" flag
BM_CORRECT  equ 4                ; "letter has been correctly guessed" flag

; end message
    db 13,10
endmsg:
    db "WorDOS - a DOS clone of the popular word guessing game 'Wordle'", 13,10
    db "WorDOS (C) 2022 Martin J. Fiedler <keyj@emphy.de>", 13,10
    db "Wordle (C) 2021-2022 Josh Wardle", 13,10
    db 13, 10

; word list (and end of end message before it)
%include "wordlist.inc"

; attribute and other video constants
attr_start: ;  color, mono   ; 'mono' will be copied over to 'color' if needed
xoffset:    db 0,     20     ; horizontal screen offset
A_input:    db 1Fh,   07h    ; input fields
A_confirm:  db 08h,   07h    ; confirmation prompt; also used for grid
A_wrong_w:  db 8Fh,   07h    ; wrong letter in word
A_wrong_l:  db 8Fh,   00h    ; wrong letter in letter list
A_present:  db 6Fh,   01h    ; present letter in word and letter list
A_correct:  db 2Fh,   70h    ; fully correct letter in word and letter list
A_unknown:  db 7Fh,   07h    ; unknown (not yet guessed) letter in letter list
oldmode:    db 03h,   07h    ; old video mode
attr_count  equ ($ - attr_start) / 2


; #################################### CODE ###################################

main:
    ; reset global variables
    mov byte [currline], 4

    ; - - - - - - - - - - - - - - - - - - - - video setup / draw initial screen

    ; check current video mode
    mov ah, 0Fh
    int 10h
    cmp al, 07h  ; MDA/Hercules text mode?
    je mono_hw

color_hw:
    ; set 40x25 text mode
    mov ax, 01h
    int 10h

    ; check for EGA using "get EGA info" call
    mov ah, 12h
    mov bl, 10h
    int 10h
    cmp bl, 10h   ; BL unmodified?
    je .noega     ; if so, the call failed, and we're not on EGA
    ; we're on EGA, so disable blinking
    mov ax, 1003h
    xor bx, bx
    int 10h
    ; and replace brown by dark yellow
    mov ax, 1000h
    mov bx, 0606h
    int 10h
    jmp .egaend
.noega:
    ; no EGA -> can't disable blinking or modify palette
    ; use black instead of dark gray background
    mov byte [A_wrong_w], 0Fh
    mov byte [A_wrong_l], 0Fh
.egaend:

    ; set full-height cursor (constant value, as EGA/VGA do size translation)
    mov ah, 1
    mov cx, 0007h
    int 10h

    jmp drawtitle

mono_hw:
    ; reset video mode
    mov ax, 7
    int 10h

    ; copy attribute constants
    mov cx, attr_count
    mov bx, attr_start
.copy_attr:
    mov al, [bx+1]
    mov [bx], al
    inc bx
    inc bx
    loop .copy_attr

    ; set full-height cursor (MDA/Hercules doen't do size translation)
    mov ah, 1
    mov cx, 000Dh
    int 10h

drawtitle:
    ; title text
    mov ah, 0Fh
    mov dx, 010Eh
    mov si, title
    call DrawStringAt

    ; guessing grid
    mov dx, 040Fh
.ggridloop:
    mov ah, [A_confirm]
    mov al, 176
    call DrawCharAt
    inc dx
    inc dx
    cmp dl, 24
    jl .ggridloop
    mov dl, 15
    add dh, 2
    cmp dh, 15
    jl .ggridloop

    ; - - - - - - - - - - - - - - - - - - - - - - - - - -  select word to guess

    ; are we running in "random" mode?
    cmp byte [wordbuf+4], 'A'
    jl wotd  ; no, use word of the day
    push ds
    xor ax, ax
    mov ds, ax
    mov ax, [046Ch]   ; timer should be random enough ...
    pop ds
    jmp loadword

wotd:
    ; get current date and compute "pseudo Julian Day Number" from it
    mov ah, 2Ah
    int 21h  ; CX = year, DH = month, DL = day
    ; subtract year offset so numbers don't become too large
    sub cx, 1968
    ; move January and February into the year before
    cmp dh, 3
    jge .march
    dec cx
    add dh, 12
.march:
    ; result = 979 * month - 2918
    push dx
    xor ax, ax
    mov al, dh
    mov bx, 979
    mul bx
    pop dx
    sub ax, 2918
    ; result >>= 5
    push cx
    mov cl, 5
    shr ax, cl
    pop cx
    ; result += d
    xor dh, dh
    add ax, dx
    ; result += year * 365
    push ax
    mov ax, cx
    mov bx, 365
    mul bx
    pop bx
    add ax, bx
    ; result += year >> 2
    shr cx, 1
    shr cx, 1
    add ax, cx
    ; subtract fixed offset to match our pseudo-JDN with the puzzle number
    sub ax, DATE_ADJUST

loadword:
    ; modulo word count
    xor dx, dx
    mov bx, CHALLENGE_WORDS
    div bx
    mov ax, dx

    ; compute address of the word
    mov bx, ax
    shl ax, 1
    add bx, ax
    add bx, words

    ; load first two thirds of the word
    mov ax, [bx]
    mov cx, 26   ; division constant
    ; reconstruct first letter
    xor dx, dx
    div cx
    add dl, 65
    mov [wordbuf+0], dl
    ; reconstruct second letter
    xor dx, dx
    div cx
    add dl, 65
    mov [wordbuf+1], dl
    ; reconstruct third letter
    xor dx, dx
    div cx
    add dl, 65
    mov [wordbuf+2], dl
    ; load final third of the word
    mov ah, al
    mov al, [bx+2]
    ; reconstruct fourth letter
    xor dx, dx
    div cx
    add dl, 65
    mov [wordbuf+3], dl
    ; reconstruct fifth letter
    xor dx, dx
    div cx
    add dl, 65
    mov [wordbuf+4], dl

    ; clear the bitmap
    mov di, bitmap + 'A'
    mov cx, 26
    mov al, '0'
    rep stosb

    ; mark the used letters in the bitmap
    mov si, wordbuf
    xor ax, ax
    mov cx, 5
.markloop:
    lodsb
    mov bx, ax
    or byte [bitmap+bx], BM_INWORD
    loop .markloop

    ; finally, draw the letter grid
    call DrawLetterGrid

    ; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  guess editor
guessinput:

    ; draw the (initially empty) guess line
    mov dh, [currline]
    mov dl, 15
    mov cx, 5
.drawempty:
    mov ah, [A_input]
    mov al, 20h
    call DrawCharAt
    inc dx
    inc dx
    loop .drawempty

    ; set current position to beginning of line and start editing
    xor bx, bx
    ; persistent registers used throughout this block:
    ; BX = index of cursor inside guessbuf (5 = wait for confirmation)
    ; DX = this letter's cursor position
editloop:

    ; do we need to draw the confirmation prompt?
    cmp bl, 5
    jl .noprompt
    mov ah, [A_confirm]
    mov dl, 25
    mov si, s_confirm
    call DrawStringAt
    jmp .waitkey

.noprompt:
    ; blank target field and wait for keypress
    mov dl, bl
    add dl, dl
    add dl, 15
    mov ax, 1F20h
    call DrawCharAt

.waitkey:
    ; wait for keypress
    xor ax, ax
    int 16h

    ; clear confirmation prompt
    cmp bl, 5
    jl .noclear
    push ax
    mov ah, [A_confirm]
    mov al, 20h
    mov dl, 25
    mov cx, S_CONFIRM_LENGTH
    call FillCharAt
    pop ax
.noclear:

    ; handle permanent hotkeys (Esc / F5)
    cmp al, 27
    jne .noquit
    jmp quit  ; quit is too far away for a short jump
.noquit:
    cmp ah, 3Fh
    jne .noreload
    jmp main  ; main is too far away for a short jump
.noreload:

    ; lowercase letter -> convert to uppercase
    cmp al, 'a'
    jl .nolowcase
    cmp al, 'z'
    jg .nolowcase
    sub al, 20h
.nolowcase:

    ; is that a letter and are we allowed to enter one?
    cmp al, 'A'
    jl .noletter
    cmp al, 'Z'
    jg .noletter
    cmp bl, 5
    jge .noletter
    ; new letter entered
    mov ah, [A_input]
    call DrawCharAt
    mov [guessbuf+bx], al
    inc bx
    jmp editloop
    ; continue switch-case
.noletter:

    ; is that backspace, and are we allowed to use it?
    cmp al, 8
    jne .noback
    or bx, bx
    jz .noback
    ; backspace: go back one letter
    dec bx
    ; clear "not in word list" message that might still be there
    call ClearStatus
    jmp editloop
.noback:

    ; is that Enter, and are we allowed to press it?
    cmp al, 13
    jne .noenter
    cmp bl, 5
    je guesscheck
.noenter:

    ; unrecognized key
    jmp editloop

    ; - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  guess checking
guesscheck:

    ; encode guessed word
    mov cx, 26  ; multiplication constant
    ; load fifth letter
    mov al, [guessbuf+4]
    sub al, 65
    xor ah, ah
    ; add fourth letter
    mul cx
    mov bl, [guessbuf+3]
    sub bl, 65
    xor bh, bh
    add ax, bx
    ; store final third and rotate
    push ax
    mov al, ah
    xor ah, ah
    ; add third letter
    mul cx
    mov bl, [guessbuf+2]
    sub bl, 65
    xor bh, bh
    add ax, bx
    ; add second letter
    mul cx
    mov bl, [guessbuf+1]
    sub bl, 65
    xor bh, bh
    add ax, bx
    ; add first letter
    mul cx
    mov bl, [guessbuf+0]
    sub bl, 65
    xor bh, bh
    add ax, bx
    ; restore final third -- whole code is not in DL:AX
    pop dx

    ; search loop
    mov cx, TOTAL_WORDS
    mov bx, words
.gsearch:
    cmp ax, [bx]    ; compare
    jne .nomatch
    cmp dl, [bx+2]
    je guesseval    ; word found
.nomatch:           ; go to next word
    add bx, 3
    loop .gsearch

    ; word not found -> return to editor
    mov si, s_unknown
    call SetStatus
    mov bx, 5
    mov dh, [currline]
    jmp editloop

    ; - - - - - - - - - - - - - - - - - - - - - - - - - - - -  guess evaluation
guesseval:

    ; initialize letter iteration loop
    mov dh, [currline]
    mov dl, 15
    xor bx, bx
.letterloop:

    ; load the letters, load the bitmap, mark as guessed
    mov al, [guessbuf+bx]
    mov cl, [wordbuf+bx]
    push bx
    xor bx, bx
    mov bl, al
    mov ch, [bitmap+bx]
    or ch, BM_GUESSED
    cmp al, cl
    jne .notcorrect
    or ch, BM_CORRECT
.notcorrect:
    mov [bitmap+bx], ch
    pop bx

    ; determine attribute
    cmp al, cl          ; correct letter at correct position = green
    jne .la1_notcorrect
    mov ah, [A_correct]
    jmp .drawletter1
.la1_notcorrect:
    test ch, BM_INWORD  ; letter somewhere in word = yellow
    jz .la1_notinword
    mov ah, [A_present]
    jmp .drawletter1
.la1_notinword:
    mov ah, [A_wrong_w]

    ; draw the letter
.drawletter1:
    call DrawCharAt

    ; mark next letter
    inc dx
    inc dx
    inc bx
    cmp bl, 5
    jl .letterloop

    ; update the letter grid
    call DrawLetterGrid

    ; compare the words one last time
    mov si, guessbuf
    mov di, wordbuf
    mov cx, 5
    repe cmpsb
    jne nextguess

    ; determine message by current row
winner:
    xor bx, bx
    mov bl, [currline]
    mov si, [winmsgs-4+bx]
    call SetStatus
    jmp waitquit
    
    ; no match -> continue with next guess
nextguess:
    mov al, [currline]
    inc al
    inc al
    cmp al, 15
    jg gameover
    mov [currline], al
    jmp guessinput

    ; "game over" message
gameover:
    mov si, s_gameover
    call SetStatus
    ; reveal solution
    mov dx, 1211h
    mov ah, 0Fh
    mov si, wordbuf
    call DrawStringAt

    ; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -  quit program
waitquit:
    ; make cursor invisible
    mov ah, 2
    xor bh, bh
    mov dx, 1900h
    int 10h

    ; wait for one last keypress
    xor ax, ax
    int 16h

    ; check for F5
    cmp ah, 3Fh
    jne .noreload2
    jmp main  ; main is too far away for a short jump
.noreload2:

quit:
    ; restore video mode, show end message and quit program
    xor ah, ah
    mov al, [oldmode]
    int 10h
    mov ah, 9
    mov dx, endmsg
    int 21h
    ret

; -----------------------------------------------------------------------------
; FUNCTION: DrawCharAt - draw single character at position
; in AH = attribute
; in AL = character (ASCII)
; in DH = line (0=top)
; in DL = column (0=left)
DrawCharAt:
    push dx
    push cx
    push bx
    push ax
    push ax
    ; set cursor position
    mov ah, 2
    xor bh, bh
    add dl, [xoffset]
    int 10h
    ; draw character
    pop ax
    mov bl, ah
    mov ah, 9
    xor cx, cx
    inc cx
    int 10h
    ; restore registers
    pop ax
    pop bx
    pop cx
    pop dx
    ret

; -----------------------------------------------------------------------------
; FUNCTION: FillCharAt - draw repeated character at position
; in AH = attribute
; in AL = character (ASCII)
; in DH = line (0=top)
; in DL = column (0=left)
; in CX = count
FillCharAt:
    push dx
    push cx
    push bx
    push ax
    push ax
    ; set cursor position
    mov ah, 2
    xor bh, bh
    add dl, [xoffset]
    int 10h
    ; draw character
    pop ax
    mov bl, ah
    mov ah, 9
    int 10h
    ; restore registers
    pop ax
    pop bx
    pop cx
    pop dx
    ret

; -----------------------------------------------------------------------------
; FUNCTION: DrawStringAt - draw null-terminated string of text
; in AH = attribute
; in [DS:SI] = string
; in DH = line (0=top)
; in DL = column (0=left)
; out DX = final cursor position
; out SI = terminator byte address
DrawStringAt:
    lodsb
    or al, al
    jz .stringend
    call DrawCharAt
    inc dx
    jmp DrawStringAt
.stringend:
    ret

; -----------------------------------------------------------------------------
; FUNCTION: ClearStatus - clear the status bar
ClearStatus:
    push ax
    push cx
    push dx
    ; perform fill
    mov ax, 0720h
    mov dx, 1100h
    mov cx, 40
    call FillCharAt
    ; restore registers
    pop dx
    pop cx
    pop ax
    ret

; -----------------------------------------------------------------------------
; FUNCTION: SetStatus - set the status text
; in SI = status text
SetStatus:
    push ax
    push cx
    push dx
    ; clear status first
    call ClearStatus
    ; strlen()
    push si
    mov dl, 41
.strlen_loop:
    dec dl
    lodsb
    or al, al
    jnz .strlen_loop
    pop si
    ; center and draw
    shr dl, 1
    mov dh, 17
    mov ah, 07h
    call DrawStringAt
    ; restore registers
    pop dx
    pop cx
    pop ax
    ret

; -----------------------------------------------------------------------------
; FUNCTION: DrawLetterGrid - draw the letter grid
DrawLetterGrid:
    mov dx, 1507h
    mov al, 'A'
    mov si, bitmap + 'A'
.nextletter:

    ; load letter status from bitmap into AH (but keep AL intact)
    mov ah, al
    lodsb
    xchg al, ah

    ; determine attribute
    test ah, BM_CORRECT               ; "correct" bit set?
    jz .lnotcorrect
    mov ah, [A_correct]
    jmp .lgdraw
.lnotcorrect
    cmp ah, '0'+BM_INWORD+BM_GUESSED  ; letter present *and* guessed?
    jl .lnotused
    mov ah, [A_present]
    jmp .lgdraw
.lnotused
    test ah, BM_GUESSED               ; letter already guessed?
    jz .lnotguessed
    mov ah, [A_wrong_l]
    jmp .lgdraw
.lnotguessed
    mov ah, [A_unknown]               ; letter completely untouched
    
    ; draw the letter and advance to the next one
.lgdraw:
    call DrawCharAt
    inc ax
    inc dx
    inc dx
    cmp dl, 32
    jl .nextletter
    mov dx, 1707h
    cmp al, 'Z'
    jle .nextletter
    ret

; ################################## STRINGS ##################################

; table of offsets to winning messages
winmsgs: dw s_winmsg1, s_winmsg2, s_winmsg3, s_winmsg4, s_winmsg5, s_winmsg6

s_confirm: db "(Enter)  "
S_CONFIRM_LENGTH equ $ - s_confirm
            db 0  ; terminator for s_confirm
s_gameover: db "Game Over! The word was:", 0
s_unknown:  db "Not in word list.", 0
s_winmsg1:  db "Genius!",0
s_winmsg2:  db "Magnificent!",0
s_winmsg3:  db "Impressive!",0
s_winmsg4:  db "Splendid!",0
s_winmsg5:  db "Great!",0
s_winmsg6:  db "Phew!",0
