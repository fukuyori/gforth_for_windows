\ Windows advanced interactive feature gate

\ This file is part of the Windows-native interactive recovery work.
\ Loading it does not enable ekey/history/status/locate behavior by itself.
\ The current compact Windows image is intentionally treated as reduced mode.
\ Keep this file as top-level code for now: the current compact image can
\ interpret these checks safely, but compiling some of them into new words is
\ not stable enough to use as a startup contract yet.

s" GFORTH_WIN_ADVANCED" getenv s" 1" compare 0= [IF]
    ." Windows advanced interactive readiness:" cr

    s" ekey" find-name 0= [IF]
        ." ekey missing" cr
    [ELSE]
        ." ekey present" cr
    [THEN]

    s" history-cold" find-name 0= [IF]
        ." history-cold missing" cr
    [ELSE]
        ." history-cold present" cr
    [THEN]

    s" locate" find-name 0= [IF]
        ." locate missing" cr
    [ELSE]
        ." locate present" cr
    [THEN]

    s" see" find-name 0= [IF]
        ." see missing" cr
    [ELSE]
        ." see present" cr
    [THEN]

    s" +status" find-name 0= [IF]
        ." +status missing" cr
    [ELSE]
        ." +status present" cr
    [THEN]
[THEN]
