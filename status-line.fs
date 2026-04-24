\ status line, inspired by seedForth

\ Authors: Bernd Paysan
\ Copyright (C) 2020,2021,2022,2023,2024,2025 Free Software Foundation, Inc.

\ This file is part of Gforth.

\ Gforth is free software; you can redistribute it and/or
\ modify it under the terms of the GNU General Public License
\ as published by the Free Software Foundation, either version 3
\ of the License, or (at your option) any later version.

\ This program is distributed in the hope that it will be useful,
\ but WITHOUT ANY WARRANTY; without even the implied warranty of
\ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
\ GNU General Public License for more details.

\ You should have received a copy of the GNU General Public License
\ along with this program. If not, see http://www.gnu.org/licenses/.

0 Value status-offset

[IFDEF] screenw
    : status-screenw ( -- addr )  screenw ;
[ELSE]
    Variable status-screenw
[THEN]

[IFUNDEF] save-cursor-position
    Defer save-cursor-position
    ' noop is save-cursor-position
    0 Constant status-has-save-cursor?
[ELSE]
    -1 Constant status-has-save-cursor?
[THEN]

[IFUNDEF] restore-cursor-position
    Defer restore-cursor-position
    ' noop is restore-cursor-position
    0 Constant status-has-restore-cursor?
[ELSE]
    -1 Constant status-has-restore-cursor?
[THEN]

[IFUNDEF] erase-display
    Defer erase-display
    ' drop is erase-display
    0 Constant status-has-erase-display?
[ELSE]
    -1 Constant status-has-erase-display?
[THEN]

status-has-save-cursor?
status-has-restore-cursor? and
status-has-erase-display? and
Constant status-terminal-ready?

[IFUNDEF] is-color-terminal?
    0 Constant is-color-terminal?
[THEN]

[IFDEF] {
    [IFDEF] translator-max-offset#
	Create status-colors
	' status-color ,
	' compile-color ,
	' postpone-color ,
	' error-color ,
	' error-color ,
	' error-color ,
	' error-color ,
	' error-color ,
	' error-color ,
	' error-color ,
	DOES> state @ abs translator-max-offset# umin th@ execute ;
    [ELSE]
	Defer status-colors
	' noop is status-colors
    [THEN]

    : redraw-status ( addr u -- )
	save-cursor-position
	0 rows 1 - at-xy
	status-colors type default-color
	restore-cursor-position ;
    : .unstatus-line ( -- )
	0 erase-display
	0 to status-offset ;
    : replace-char ( c1 c2 addr u -- )
	bounds U+DO
	    over I c@ = IF  dup I c!  THEN
	LOOP  2drop ;

    [IFUNDEF] -scan
	: -scan ( addr u char -- addr' u' )
	    >r  BEGIN  dup  WHILE  1- 2dup + c@ r@ =  UNTIL  THEN
	    rdrop ;
    [THEN]

    0 Value wide?

    : .base ( -- )
	base @ #10 <> IF  wide? IF  ." base="  ELSE  ." b="  THEN
	    [IFDEF] base-execute
		base @ 0 ['] .r #10 base-execute
	    [ELSE]
		base @ .
	    [THEN]
	    cr  THEN ;
    [IFDEF] .s
	: .stacks ( -- )
	    .s cr ;
    [ELSE]
    [IFDEF] f.s-precision
	: .stacks ( -- )
	    f.s-precision >r
	    wide? IF  #14  ELSE  #10  THEN  to f.s-precision
	    ... cr
	    r> to f.s-precision ;
    [ELSE]
	: .stacks ( -- ) ;
    [THEN]
    [THEN]

    [IFDEF] order
	: .order ( -- )
	    wide? IF  ."  order: " ELSE  ." o:" THEN  order ;
    [ELSE]
	: .order ( -- ) ;
    [THEN]

    10 stack: status-xts
    \ status line prints a stack of status words
    ' .base ' .stacks ' .order 3 status-xts set-stack

    : .status-line ( -- ) { | w^ status$ }
	cols #100 > to wide?
	[: status-xts $@ cell MEM+DO  I perform  LOOP ;] status$ $exec
	#lf '|' status$ $@ replace-char
	#cr bl status$ $@ replace-char
	cols status$ $@ x-width - dup 0> IF
	    ['] spaces $tmp
	    status$ dup $@ '|' -scan nip $ins
	ELSE  0< IF
		0 status$ $@ bounds U+DO
		    I xc@+ swap >r
		    dup #tab = IF  drop 1+ dfaligned  ELSE  xc-width +  THEN
		    dup cols u> IF  rdrop I status$ $@ drop - status$ $!len
			leave  THEN
		r> I - +LOOP  drop
	    THEN
	THEN
	cr edit-linew @ status-screenw @ dup 0= IF  $100 +  THEN  mod -1 at-deltaxy
	status$ $@ redraw-status
	status$ $free
	1 to status-offset ;

    : +status ( -- ) \ gforth
	\G Turn on the status bar at the bottom of the screen
	['] .status-line is .status ['] .unstatus-line is .unstatus ;
[ELSE]
    ' noop Alias +status ( -- ) \ gforth
[THEN]

[IFDEF] {
    : -status ( -- ) \ gforth
	\G Turn off the status bar at the bottom of the screen
	['] noop is .status ['] noop is .unstatus ;
[ELSE]
    ' noop Alias -status ( -- ) \ gforth
[THEN]

[IFDEF] getenv
    : win-status-requested? ( -- flag )
	s" GFORTH_WIN_STATUS" getenv s" 1" str= ;

    : status-auto-enabled? ( -- flag )
	win-status-requested? IF
	    status-terminal-ready?
	ELSE
	    is-color-terminal?
	THEN ;
[ELSE]
    : status-auto-enabled? ( -- flag )
	is-color-terminal? ;
[THEN]

[IFDEF] getenv
    :noname
	defers bootmessage
	status-auto-enabled? IF  +status  ELSE  -status  THEN ;
    is bootmessage
[THEN]
