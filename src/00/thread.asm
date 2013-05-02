; Returns the ID of the thread that will launch next
getNextThreadID:
    push hl ; Don't care about the data getThreadEntry provides
        push bc
            ld a, (lastThreadId)
_:          inc a
            and threadRangeMask
            ld b, a ; Don't want the error getThreadEntry provides
            call getThreadEntry
            ld a, b
            jr z, -_
        pop bc
    pop hl
    ret

getCurrentThreadID:
    push hl
        ld a, (currentThreadIndex)
        cp nullThread
        jr z, +_
        cp 0xFE
        jr z, ++_
        add a, a
        add a, a
        add a, a
        ld h, 0x80
        ld l, a
        ld a, (hl)
    pop hl
    ret
_:  pop hl
    jp getNextThreadID ; call \ ret
_:  pop hl
    ld a, 0xFE ; TODO: Dynamic library deallocation
    ret
    
; Inputs:
; HL: Pointer to code
; B: Stack size to allocate / 2
; A: Thread flags
; Outputs:
; A: Thread ID of new thread, or error (with Z reset)
startThread:
    push af
        ld a, (activeThreads)
        cp maxThreads
        jr c, _
        jr z, _
        ld a, errTooManyThreads
    inc sp \ inc sp
    ret
_:      di
        ex de, hl
        ld a, (currentThreadIndex)
        push af
            ld a, (activeThreads)
            ld (currentThreadIndex), a ; Set the current thread to the new one so that allocated memory is owned appropraitely
            add a, a \ add a, a \ add a, a
            ld hl, threadTable
            add a, l
            ld l, a
            call getNextThreadID
            ld (lastThreadId), a
            ; A is now a valid thread id, and hl points to the next-to-last entry
            ; DE is address of code, B is stack size / 2
            ld (hl), a \ inc hl ; *hl++ = a
            ld (hl), e \ inc hl \ ld (hl), d \ inc hl
            ; Allocate a stack
            push hl
                push ix
                    ld a, b
                    add a, b
                    ld b, 0
                    add a, 24 ; Required minimum stack size for system use
                    ld c, a
                    jr nc, $+3 \ inc b
                    call malloc
                    jr nz, startThread_mem
                    push ix \ pop hl
                    dec ix \ dec ix
                    ld c, (ix) \ ld b, (ix + 1)
                    dec bc
                    add hl, bc
                    push de
                        ld de, killCurrentThread
                        ld (hl), d \ dec hl \ ld (hl), e ; Put return point on stack
                    pop de
                    dec hl \ ld (hl), d \ dec hl \ ld (hl), e ; Put entry point on stack
                    ld bc, 20 ; Size of registers on the stack
                    or a \ sbc hl, bc
                    ld b, h \ ld c, l
                pop ix
            pop hl
        pop af
        ld (currentThreadIndex), a
        ld (hl), c \ inc hl \ ld (hl), b \ inc hl ; Stack address
    pop af \ ld (hl), a \ inc hl ; Flags
    ld a, l
    sub 6
    ld l, a
    ld a, (activeThreads)
    inc a \ ld (activeThreads), a
    ld a, (hl)
    cp a
    ret
    
startThread_mem: ; Out of memory
                pop af
            pop af
        pop af
        ld (currentThreadIndex), a
    pop af
    ld a, errOutOfMem
    or 1
    ret
    
; Kills the executing thread
killCurrentThread:
    di
    ; The stack is going to be deallocated, so let's move it
    ld sp, userMemory ; end of kernelGarbage
    ld a, (currentThreadIndex)
    add a, a
    add a, a
    add a, a
    ld hl, threadTable
    add a, l
    ld l, a
    ld a, (hl)
    ; HL points to old thread in table
    push af
        push hl
            ld a, (currentThreadIndex)
            inc a
            add a, a
            add a, a
            add a, a
            ld hl, threadTable
            add a, l
            ld l, a
            push hl
                push hl \ pop bc
                ld hl, threadTable + threadTableSize
                or a
                sbc hl, bc
                push hl \ pop bc
            pop hl
        pop de
        ldir

    pop af
    ; A = Old thread ID
    ; Deallocate all memory belonging to the thread
killCurrentThread_Deallocate:
    ld ix, userMemory
killCurrentThread_DeallocationLoop:
    cp (ix)
    inc ix
    ld c, (ix)
    inc ix
    ld b, (ix)
    inc ix
    jr nz, _
    call free
    jr killCurrentThread_Deallocate
_:  inc ix \ inc ix
    inc bc \ inc bc
    add ix, bc
    dec ix \ dec ix
    jr c, killCurrentThread_DeallocationDone
    jr killCurrentThread_DeallocationLoop

killCurrentThread_DeallocationDone:
    ld hl, activeThreads
    dec (hl)
    xor a
    ld (currentThreadIndex), a
    jp contextSwitch_search
    
; Inputs:    A: Thread ID
; Kills a specific thread
killThread:
    push bc
    ld c, a
    push af
    ld a, i
    push af
    push hl
    push de
    push ix
    di
    ld hl, threadTable
    ld a, (activeThreads)
    ld b, a
    ld d, 0
killThread_SearchLoop:
    ld a, (hl)
    cp c
    jr z,++_
    ld a, 8
    add a, l
    ld l, a
    inc d
    djnz killThread_SearchLoop
    ; Thread ID not found
    pop ix
    pop de
    pop hl
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    or a
    ld a, errNoSuchThread
    ret
        
_:  ; HL points to old thread in table
    push af
    push hl
        ld a, d
        inc a
        add a, a
        add a, a
        add a, a
        ld hl, threadTable
        add a, l
        ld l, a
        push hl
            push hl \ pop bc
            ld hl, threadTable + threadTableSize
            or a
            sbc hl, bc
            push hl \ pop bc
        pop hl
    pop de
    ldir
    pop af
    ; A = Old thread ID
    ; Deallocate all memory belonging to the thread
    ld ix, userMemory
killThread_DeallocationLoop:
    cp (ix)
    inc ix
    ld c, (ix)
    inc ix
    ld b, (ix)
    inc ix
    jr nz, _
    call free
_:  inc ix \ inc ix
    inc bc \ inc bc
    add ix, bc
    dec ix \ dec ix
    jr c, killThread_DeallocationDone
    jr killThread_DeallocationLoop

killThread_DeallocationDone:
    ld hl, activeThreads
    dec (hl)
    ld b, (hl)
    ld a, (currentThreadIndex)
    dec b
    cp a
    jr nz, _
    dec a
    ld (currentThreadIndex), a
_:  pop ix
    pop de
    pop hl
    pop af
    jp po, _
    ei
_:  pop af
    pop bc
    cp a
    ret

; Inputs:    DE: Pointer to full path of program
; Outputs:     A: Thread ID
; Launches program in new thread

; TODO: Errors
launchProgram:
    push bc
    ld a, i
    push af
    di
    push hl
    push de
    push ix
        call openFileRead
        
        push de
            call getStreamInfo
            dec bc
            dec bc
            ld a, (currentThreadIndex)
            push af
                ld a, nullThread
                ld (currentThreadIndex), a ; The null thread will allocate memory to the next thread
                call malloc
            pop af
            ld (currentThreadIndex), a
        pop de
        
        push ix
            call streamReadByte ; Thread flags
            push af
                call streamReadByte ; Stack size
                ld c, a
                push bc
                    call streamReadToEnd ; Read entire file into memory
                    call closeStream
                pop bc
                ld b, c
            pop af
        pop hl
        call startThread
    ld b, a
    pop ix
    pop de
    pop hl
    pop af
    jp po, _
    ei
_:  ld a, b
    pop bc
    ret
    
; Input:  A: Thread ID
; Output: HL: Thread entry
getThreadEntry:
    push bc
        ld c, a
        ld b, maxThreads
        ld hl, threadTable
_:      ld a, (hl)
        cp c
        jr nz, _
        pop bc
        ret
_:      ld a, 8
        add a, l
        ld l, a
        djnz --_
    pop bc
    or 1
    ld a, errNoSuchThread
    ret

; Input: HL: Return address
;        A: Thread Id    
setReturnPoint:
    push de
    push bc
        ex de, hl
        call getThreadEntry
        jr z, _
        pop bc
        pop de
        ret
_:      inc hl \ inc hl \ inc hl
        ld c, (hl) \ inc hl \ ld b, (hl)
        push bc \ pop ix
        call memSeekToStart
        dec ix \ dec ix
        ld c, (ix) \ ld b, (ix + 1)
        add ix, bc
        ld (ix), e
        ld (ix + 1), d
    pop bc
    pop de
    ret
    
; Sets the initial value of DE on start up.
; Input: HL: Start value
;        A: Thread Id
setInitialDE:
    push hl
        push bc
            ex de, hl
            call getThreadEntry
            jr z, _
            ex de, hl
        pop bc
    pop hl
    ret
_:          inc hl \ inc hl \ inc hl
            ld c, (hl) \ inc hl \ ld b, (hl)
            push bc \ pop ix
            call memSeekToStart
            dec ix \ dec ix
            ld c, (ix) \ ld b, (ix + 1)
            add ix, bc
            ld (ix + -8), e
            ld (ix + -7), d
        pop bc
    pop hl
    ret
    
; Sets the initial value of HL on start up.
; Input: HL: Start value
;        A: Thread Id
setInitialHL:
    push de
        push bc
            ex de, hl
            call getThreadEntry
            jr z, _
            ex de, hl
        pop bc
    pop de
    ret
_:          inc hl \ inc hl \ inc hl
            ld c, (hl) \ inc hl \ ld b, (hl)
            push bc \ pop ix
            call memSeekToStart
            dec ix \ dec ix
            ld c, (ix) \ ld b, (ix + 1)
            add ix, bc
            ld (ix + -10), e
            ld (ix + -9), d
        pop bc
    pop de
    ret
    
; Sets the initial value of A on start up.
; Input: H: Start value
;        A: Thread Id
setInitialA:
    push de
        push bc
            ex de, hl
            call getThreadEntry
            jr z, _
            ex de, hl
        pop bc
    pop de
    ret
_:          inc hl \ inc hl \ inc hl
            ld c, (hl) \ inc hl \ ld b, (hl)
            push bc \ pop ix
            call memSeekToStart
            dec ix \ dec ix
            ld c, (ix) \ ld b, (ix + 1)
            add ix, bc
            ld (ix + -3), d
        pop bc
    pop de
    ret
    
suspendCurrentThread:
    push hl
    push af
        call getCurrentThreadId
        call getThreadEntry
        ld a, 5
        add a, l
        ld l, a
        set 2, (hl)
        ei \ halt
    pop af
    pop hl
    ret
    
; TODO: Errors
resumeThread:
    push hl
    push af
        call getThreadEntry
        ld a, 5
        add a, l
        ld l, a
        res 2, (hl)
    pop af
    pop hl
    ret
    
