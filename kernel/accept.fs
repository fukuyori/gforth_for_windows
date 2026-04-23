\ Input                                                13feb93py

\ Authors: Bernd Paysan, Anton Ertl, Jens Wilke, Neal Crook
\ Copyright (C) 1995,1996,1997,1999,2003,2004,2005,2006,2007,2016,2017,2018,2019,2021 Free Software Foundation, Inc.

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

user-o edit-out

0 0
umethod insert-char
umethod insert-string
umethod edit-control
umethod everychar
umethod everyline
umethod edit-update ( span addr pos1 -- span addr pos1 )
umethod ctrlkeys
umethod altkeys
cell uvar edit-linew

$80000017 Constant k-winch

: win-env?
    getenv dup 0= IF
	2drop false EXIT
    THEN
    2drop true ;

: win-interactive?
    s" GFORTH_WIN_INTERACTIVE" win-env? ;

1024 Constant win-history-line-max
Create win-history-line win-history-line-max chars allot
Variable win-history-line-len
Variable win-history-edit-max
Variable win-history-edit-addr
Variable win-history-edit-len
Variable win-history-index
Variable win-history-count
Variable win-history-target
Variable win-history-seen

: (ins) ( max span addr pos1 key -- max span addr pos2 )
    >r  2over = IF  rdrop bell  EXIT  THEN
    2dup + r> swap c! 1+ rot 1+ -rot ;
: (ins-string) ( max span addr pos1 addr1 u1 -- max span addr pos2 )
    2>r  2over r@ + u> IF  2rdrop bell  EXIT  THEN
    2dup + 2r@ rot swap move  2r@ type r@ + rot r> + -rot rdrop ;
: (bs) ( max span addr pos1 -- max span addr pos2 flag )
    dup IF
	#bs emit space #bs emit 1- rot 1- -rot -1 edit-linew +!
    THEN false ;
: (ret) ( max span addr pos1 -- max span addr pos2 flag )
    true ;
: (edit-control) ( max span addr pos1 ctrl-key -- max span addr pos2 flag )
    cells ctrlkeys + perform ;

Create std-ctrlkeys
    ' false a, ' false a, ' false a, ' false a, 
    ' false a, ' false a, ' false a, ' false a,

    ' (bs)  a, ' false a, ' (ret) a, ' false a, 
    ' false a, ' (ret) a, ' false a, ' false a,

    ' false a, ' false a, ' false a, ' false a, 
    ' false a, ' false a, ' false a, ' false a,

    ' false a, ' false a, ' false a, ' false a, 
    ' false a, ' false a, ' false a, ' false a,

: (edit-update) ( span addr pos -- span addr pos )
    2dup edit-linew @ safe/string type
    dup edit-linew ! ;
: (edit-everyline) ( -- )
    edit-linew off ;

align , , here
' (ins) A,  \ IS insert-char
' (ins-string) A,   \ IS insert-string
' (edit-control) A, \ is edit-control
' noop  A,  \ IS everychar
' (edit-everyline) A,  \ IS everyline
' (edit-update) A, \ IS edit-update
' std-ctrlkeys A,
' false A,
A, here 0 , AConstant kernel-editor
kernel-editor edit-out !

: >control ( key -- ctrl-key )
    dup -1 =   IF  drop 4  THEN  \ -1 is EOF
    dup #del = IF  drop #bs  THEN ; \ del is rubout

: win-ekey?
    s" GFORTH_WIN_EKEY" win-env? win-interactive? or ;

: win-ekey-dispatch
    dup 27 <> IF
	false EXIT
    THEN
    win-ekey? 0= IF
	false EXIT
    THEN
    drop key [char] [ <> IF
	bell false true EXIT
    THEN
    key
    dup [char] A = IF
	drop win-history-prev-line true EXIT
    THEN
    dup [char] B = IF
	drop win-history-next-line true EXIT
    THEN
    dup [char] 5 = over [char] 6 = or IF
	key drop
	drop bell false true EXIT
    THEN
    drop bell false true ;

: decode ( max span addr pos1 key -- max span addr pos2 flag )
    \ perform action corresponding to key; addr max is the buffer,
    \ addr span is the current string in the buffer, and pos1 is the
    \ cursor position in the buffer.
    win-ekey-dispatch IF
	EXIT
    THEN
    dup k-winch = IF
	drop win-handle-winch EXIT
    THEN
    everychar  >control
    dup bl u< \ ctrl key
    over $7FFFFFFF u> \ ekey
    or IF  edit-control  EXIT  THEN
    \ check for end reached
    insert-char key? 0= IF  edit-update  THEN 0 ;

Defer edit-key

: win-winch?
    s" GFORTH_WIN_WINCH" win-env? win-interactive? or ;

: win-edit-key
    win-winch? IF
	0 winch? atomic!@ IF
	    k-winch EXIT
	THEN
    THEN
    edit-key ;

: win-handle-winch
    form 2drop false ;

: edit-line ( c-addr n1 n2 -- n3 ) \ gforth
    \G edit the string with length @var{n2} in the buffer @var{c-addr
    \G n1}, like @code{accept}.
    win-history-index off
    everyline  rot over  edit-update
    BEGIN  win-edit-key decode  UNTIL
    2drop nip ;

: win-history-path
    s" GFORTH_WIN_HISTORY_FILE" getenv dup 0= IF
	2drop s" .gforth-history"
    THEN ;

: win-history-open
    win-history-path 2dup r/w open-file IF
	drop w/o create-file
    ELSE
	nip nip 0
    THEN ;

: win-history-add
    s" GFORTH_WIN_HISTORY" win-env? win-interactive? or 0= IF
	2drop EXIT
    THEN
    win-history-open dup IF
	drop drop 2drop EXIT
    THEN
    drop >r
    r@ file-size dup IF
	drop 2drop r> close-file drop 2drop EXIT
    THEN
    drop r@ reposition-file dup IF
	drop r> close-file drop 2drop EXIT
    THEN
    drop r@ write-line drop
    r> close-file drop ;

: win-history-nav?
    s" GFORTH_WIN_HISTORY_NAV" win-env? win-ekey? or ;

: win-history-read-last
    win-history-nav? 0= IF
	0 0 false EXIT
    THEN
    win-history-path r/o open-file IF
	drop 0 0 false EXIT
    THEN
    >r win-history-line-len off
    BEGIN
	win-history-line win-history-line-max r@ read-line
	dup IF
	    drop 2drop r> close-file drop 0 0 false EXIT
	THEN
	drop
    WHILE
	win-history-line-len !
    REPEAT
    drop r> close-file drop
    win-history-line-len @ dup IF
	win-history-line swap true
    ELSE
	drop 0 0 false
    THEN ;

: win-history-clear-display
    0 ?DO
	#bs emit space #bs emit
    LOOP ;

: win-history-count-lines
    win-history-path r/o open-file IF
	drop 0 false EXIT
    THEN
    >r win-history-count off
    BEGIN
	win-history-line win-history-line-max r@ read-line
	dup IF
	    drop 2drop r> close-file drop 0 false EXIT
	THEN
	drop
    WHILE
	drop 1 win-history-count +!
    REPEAT
    drop r> close-file drop
    win-history-count @ true ;

: win-history-read-index
    win-history-nav? 0= IF
	drop 0 0 false EXIT
    THEN
    win-history-count-lines 0= IF
	2drop 0 0 false EXIT
    THEN
    swap - 1+ dup 0<= IF
	drop 0 0 false EXIT
    THEN
    win-history-target !
    win-history-path r/o open-file IF
	drop 0 0 false EXIT
    THEN
    >r win-history-seen off
    BEGIN
	win-history-line win-history-line-max r@ read-line
	dup IF
	    drop 2drop r> close-file drop 0 0 false EXIT
	THEN
	drop
    WHILE
	1 win-history-seen +!
	win-history-seen @ win-history-target @ = IF
	    win-history-line-len !
	    r> close-file drop
	    win-history-line win-history-line-len @ true EXIT
	THEN
	drop
    REPEAT
    drop r> close-file drop 0 0 false ;

: win-history-replace-line
    >r >r
    dup 3 pick <> IF
	rdrop rdrop bell false EXIT
    THEN
    2 pick win-history-clear-display
    over win-history-edit-addr !
    3 pick win-history-edit-max !
    r> r> win-history-edit-max @ min dup win-history-edit-len !
    win-history-edit-addr @ swap move
    win-history-edit-addr @ win-history-edit-len @ type
    2drop 2drop
    win-history-edit-max @ win-history-edit-len @
    win-history-edit-addr @ win-history-edit-len @ false ;

: win-history-prev-line
    dup 3 pick <> IF
	bell false EXIT
    THEN
    win-history-index @ 0= 3 pick 0<> and IF
	bell false EXIT
    THEN
    1 win-history-index +!
    win-history-index @ win-history-read-index 0= IF
	-1 win-history-index +!
	bell false EXIT
    THEN
    win-history-replace-line ;

: win-history-next-line
    dup 3 pick <> IF
	bell false EXIT
    THEN
    win-history-index @ 0= IF
	bell false EXIT
    THEN
    -1 win-history-index +!
    win-history-index @ 0= IF
	win-history-line 0 win-history-replace-line EXIT
    THEN
    win-history-index @ win-history-read-index 0= IF
	1 win-history-index +!
	bell false EXIT
    THEN
    win-history-replace-line ;

' win-history-prev-line 16 cells std-ctrlkeys + !
' win-history-next-line 14 cells std-ctrlkeys + !
    
: accept   ( c-addr +n1 -- +n2 ) \ core
    \G Get a string of up to @var{n1} characters from the user input
    \G device and store it at @var{c-addr}.  @var{n2} is the length of
    \G the received string. The user indicates the end by pressing
    \G @key{RET}.  Gforth supports all the editing functions available
    \G on the Forth command line (including history and word
    \G completion) in @code{accept}.
    over >r
    dup 0< -&24 and throw \ use edit-line to edit given strings
    0 edit-line dup r> swap win-history-add space ;
