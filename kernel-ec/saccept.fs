\ a very simple accept approach

\ Authors: Anton Ertl, Bernd Paysan
\ Copyright (C) 1995,1996,1997,1998,1999,2000,2003,2006,2007,2010,2012,2019,2021 Free Software Foundation, Inc.

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

require ./io.fs

\ : xon $11 emit ;
\ : xoff $13 emit ;

Variable eof
Variable echo  -1 echo !

: win-env?
    getenv dup 0= IF
	2drop false EXIT
    THEN
    2drop true ;

: win-interactive?
    s" GFORTH_WIN_INTERACTIVE" win-env? ;

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

: accept ( adr len -- len )
  ( xon ) over + over ( start end pnt )  eof off
  BEGIN
   key dup #del = IF drop #bs THEN
   dup bl u<
   IF
       dup #cr = over #lf = or IF
	   echo @ IF  space  THEN
	   drop 2 pick >r nip swap - dup r> swap win-history-add
	   ( xoff ) EXIT THEN
       dup #eof = IF  eof on  THEN
       #bs = IF 2 pick over <>
	   IF 1 chars -
	       echo @ IF  #bs emit bl emit #bs emit  THEN
	   ELSE  echo @ IF  bell  THEN  THEN  THEN
   ELSE	>r 2dup <> IF r>
	   echo @ IF  dup emit  THEN
	   over c! char+ ELSE r> drop bell THEN
   THEN 
  AGAIN ;

\ simple include for terminal.fs

: refill-loop ( -- )
    BEGIN  3 emit refill  WHILE  interpret  REPEAT ;   
: included ( addr u -- )
    2 emit dup $20 + emit type
    echo @ IF
	echo off ['] refill-loop catch
	dup IF  4 emit  THEN  echo on  throw
    THEN ;
: include ( "file" -- )  parse-name included ;
