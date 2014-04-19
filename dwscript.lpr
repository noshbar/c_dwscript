{!
 \author       Dirk de la Hunt (gmail:noshbar)
 \copyright    Mozilla Public License 1.1
 \version      1.0.1
 \brief        Simple C-compatible DLL wrapper for the DWScript engine
}

LIBRARY dwscript;

{$ifdef FPC}
  {$mode objfpc}{$H+}
{$endif}

USES
  Classes, deell, SysUtils
{$ifdef FPC}
  ,strings
{$endif}
  ;

//FIXME: unicode->ansistring badness
FUNCTION GetMessage(context : pointer; buffer : pansichar; size : integer) : integer; STDCALL;
VAR
  dws : DWScript_Context;
  len : integer;
BEGIN
  IF (context = NIL) THEN
  BEGIN
    result := 0;
    exit;
  END;
  dws := DWScript_Context(Context);
  len := length(dws.message);
  result := len;
  IF (buffer = NIL) THEN exit;

  IF (len > size) THEN len := size;
  strlcopy(buffer, pansichar(dws.message), len);
  result := len;
END;

FUNCTION CreateContext(flags : Integer) : pointer; STDCALL;
VAR
  dws : DWScript_Context;
BEGIN
  TRY
    dws := DWScript_Context.Create(flags);
  EXCEPT
    ON E: Exception DO
    BEGIN
      dws := NIL; //FIXME: make a way to propogate the error message
    END;
  END;
  result := dws;
END;

PROCEDURE DestroyContext(context : pointer); STDCALL;
VAR
  dws : DWScript_Context;
BEGIN
  IF (context = NIL) THEN Exit;

  TRY
    dws := DWScript_Context(context);
    dws.Destroy;
  EXCEPT
    ON E: Exception DO
    BEGIN
      dws := NIL; //FIXME: make a way to propogate the error message
    END;
  END;
END;

EXPORTS
  CreateContext          NAME 'CreateContext',
  DestroyContext         NAME 'DestroyContext',
  GetMessage             NAME 'GetMessage',
  DWScript_addFunction   NAME 'AddFunction',
  DWScript_addParameter  NAME 'AddParameter',
  DWScript_setReturnType NAME 'SetReturnType',
  DWScript_call          NAME 'Call',
  DWScript_callStateless NAME 'CallStateless',
  DWScript_compile       NAME 'Compile',
  DWScript_execute       NAME 'Execute';

END.
