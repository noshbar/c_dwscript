{!
 \author       Dirk de la Hunt (gmail:noshbar)
 \copyright    Mozilla Public License 1.1
 \version      1.0.1
 \brief        The main wrapping work gets done here.
}

UNIT deell;

{$ifdef FPC}
  {$mode objfpc}{$H+}
{$else}
  {$ifndef WIN64}
    {$define JITTER}
  {$endif}
{$endif}

INTERFACE

USES
  Classes, dwsComp, dwsCompiler, dwsExprs, dwsCoreExprs, sysutils, variants, dwsAsmLibModule,
{$ifdef JITTER}
  dwsJIT, dwsJITx86,
{$endif}
{$ifdef FPC}
  contnrs
{$else}
  dwsComConnector,
  Generics.Collections,
  ComObj,
  ActiveX
{$endif};

{ ----- Between these lines the values and orders of parameters/struct member variables is important as they are mirrored in the C wrapper ----- }
CONST
  DATATYPE_NOTSET  = 0;
  DATATYPE_FLOAT   = 1;
  DATATYPE_INTEGER = 2;
  DATATYPE_STRING  = 3;
  DATATYPE_BOOLEAN = 4;

CONST
  FLAG_NONE   = 0;
  FLAG_JITTER = 1 SHL 0;
  FLAG_OLE    = 1 SHL 1;
  FLAG_ASM    = 1 SHL 2;

TYPE
  DWScript_Variable = RECORD
    name     : PAnsiChar;
    dataType : Integer;
    CASE Integer OF
      DATATYPE_FLOAT   : (f : Single);
      DATATYPE_INTEGER : (i : Integer);
      DATATYPE_STRING  : (s : PAnsiChar);
      DATATYPE_BOOLEAN : (b : Boolean);
  END;

  DWScript_DataPtr = ^DWScript_Data;
  DWScript_Data = RECORD
    context      : Pointer;
    state        : Pointer;
    functionName : PAnsiChar;
    returnValue  : DWScript_Variable;
    valueCount   : Integer;
    value        : ARRAY[0..31] OF DWScript_Variable;
  END;

TYPE
  DWScript_CallbackFunction = PROCEDURE(parameters : DWScript_DataPtr; userdata : Pointer); STDCALL;
{ ----- ---------------------------------------------------------------------------------------------------------------------------------- ----- }

TYPE
  DWScript_Function = CLASS(TObject)
  PUBLIC
    name           : AnsiString;
    userFunction   : Pointer;
    userData       : Pointer;
    dwsFunction    : TdwsFunction;
    dwsData        : DWScript_Data;
    parameterNames : ARRAY[0..31] OF AnsiString;
  END;

TYPE
  DWScript_Context = CLASS(TObject)
  PROTECTED
    dwsUnit    : TdwsUnit;
    dwsScript  : TDelphiWebScript;
    dwsProgram : IdwsProgram;
    dwsAsm     : TdwsAsmLibModule;
    status     : AnsiString;
{$ifdef FPC}
    functions  : TFPHashList;
{$else}
    functions  : TDictionary<AnsiString, Pointer>;
    com        : TdwsComConnector;
{$endif}

  PROTECTED
    PROCEDURE wrapper(Info : TProgramInfo);

  PUBLIC
    PROPERTY Message : AnsiString READ status;
  PUBLIC
    CONSTRUCTOR Create(flags : Integer);
    DESTRUCTOR Destroy; OVERRIDE;
  END;

FUNCTION DWScript_addFunction(context : pointer; functionName : PAnsiChar; userFunction, userdata : Pointer) : Pointer; stdcall;
FUNCTION DWScript_addParameter(context : pointer; dwsFunctionPtr : Pointer; parameterName : PAnsiChar; dataType : Integer) : Boolean; stdcall;
FUNCTION DWScript_setReturnType(context : pointer; dwsFunctionPtr : Pointer; dataType : Integer) : Boolean; stdcall;
FUNCTION DWScript_call(context : pointer; state : Pointer; functionName : PAnsiChar; data : DWScript_DataPtr) : Boolean; stdcall;
FUNCTION DWScript_callStateless(context : pointer; functionName : PAnsiChar; data : DWScript_DataPtr) : Boolean; stdcall;
FUNCTION DWScript_compile(context : pointer; scriptText : PAnsiChar; flags : Integer) : Boolean; stdcall;
FUNCTION DWScript_execute(context : pointer; flags : Integer) : Boolean; stdcall;

IMPLEMENTATION

CONSTRUCTOR DWScript_Context.Create(flags : Integer);
BEGIN
  dwsScript        := TDelphiWebScript.Create(NIL);
  dwsUnit          := TdwsUnit.Create(NIL);
  dwsUnit.UnitName := 'CustomFunctions';
  dwsUnit.Script   := dwsScript;
  status           := '';
{$ifdef FPC}
  functions        := TFPHashList.Create;
  //TODO: implement OLE stuff for FPC
{$else}
  functions        := TDictionary<AnsiString, Pointer>.Create;
  IF (flags AND FLAG_OLE <> 0) THEN
  BEGIN
    CoInitialize(NIL);
    com := TdwsComConnector.Create(NIL);
    com.Script := dwsScript;
  END;
{$endif}
  IF (flags AND FLAG_ASM <> 0) THEN
  BEGIN
    dwsAsm := TdwsAsmLibModule.Create(NIL);
    dwsAsm.Script := dwsScript;
  END;
END;

DESTRUCTOR DWScript_Context.Destroy;
VAR
  index       : Integer;
  dwsFunction : DWScript_Function;
  p           : Pointer;
BEGIN
{$ifdef FPC}
  FOR index := 0 TO functions.Count - 1 DO
  BEGIN
    dwsFunction := DWScript_Function(functions.Items[index]);
    dwsFunction.Free;
  END;
{$else}
  FOR p IN functions.Values DO
  BEGIN
    dwsFunction := DWScript_Function(p);
    dwsFunction.Free;
  END;
{$endif}
  dwsScript.Free;
  dwsUnit.Free;
  dwsAsm.Free;
  functions.Free;
{$ifndef FPC}
  IF (com <> NIL) THEN
  BEGIN
    com.Free;
    CoUninitialize;
  END;
{$endif}
  INHERITED;
END;

PROCEDURE DWScript_Context.wrapper(Info : TProgramInfo);
VAR
  parameter       : Integer;
  temporaryString : Ansistring;
  dwsFunction     : DWScript_Function;
  userFunction    : DWScript_CallbackFunction;
BEGIN
  TRY
{$ifdef FPC}
    dwsFunction := DWScript_Function(functions.Find(info.FuncSym.ExternalName));
{$else}
    functions.TryGetValue(info.FuncSym.ExternalName, Pointer(dwsFunction));
{$endif}
    IF (dwsFunction = NIL) OR (dwsFunction.userFunction = NIL) THEN Exit;

    FOR parameter := 0 TO dwsFunction.dwsData.valueCount - 1 DO
      CASE dwsFunction.dwsData.value[parameter].dataType OF
        DATATYPE_INTEGER: dwsFunction.dwsData.value[parameter].i := Info.ValueAsInteger[dwsFunction.parameterNames[parameter]];
        DATATYPE_FLOAT:   dwsFunction.dwsData.value[parameter].f := Info.ValueAsFloat[dwsFunction.parameterNames[parameter]];
        DATATYPE_BOOLEAN: dwsFunction.dwsData.value[parameter].b := Info.ValueAsBoolean[dwsFunction.parameterNames[parameter]];
        DATATYPE_STRING:
        BEGIN
          temporaryString := Info.ValueAsString[dwsFunction.parameterNames[parameter]];
          dwsFunction.dwsData.value[parameter].s := PAnsiChar(temporaryString);
        END;
      END;

    dwsFunction.dwsData.context := self;
    dwsFunction.dwsData.state   := info;
    userFunction                := DWScript_CallbackFunction(dwsFunction.userFunction);
    userFunction(@dwsFunction.dwsData, dwsFunction.userData);
    dwsFunction.dwsData.state   := NIL;

    CASE dwsFunction.dwsData.returnValue.dataType OF
      DATATYPE_INTEGER: Info.ResultAsInteger := dwsFunction.dwsData.returnValue.i;
      DATATYPE_FLOAT:   Info.ResultAsFloat := dwsFunction.dwsData.returnValue.f;
      DATATYPE_BOOLEAN: Info.ResultAsBoolean := dwsFunction.dwsData.returnValue.b;
      DATATYPE_STRING:  Info.ResultAsString := dwsFunction.dwsData.returnValue.s;
    END;
  EXCEPT
    ON E: Exception DO
    BEGIN
      status := 'EXCEPTION (Finding function): ' + E.ClassName + ': ' + E.Message;
      //need to figure out how to propogate this error
      Exit;
    END;
  END;
END;




FUNCTION DWScript_addParameter(context : pointer; dwsFunctionPtr : Pointer; parameterName : PAnsiChar; dataType : Integer) : Boolean; STDCALL;
VAR
  parameter : TdwsParameter;
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);

  scriptContext.status := '';
  IF (dwsFunctionPtr = NIL) THEN BEGIN scriptContext.status := 'AddParameter() cannot accept a NULL Function parameter'; Exit; END;
  IF (parameterName = NIL) OR (Length(parameterName) = 0) THEN BEGIN   scriptContext.status := 'AddParameter() cannot accept a NULL or empty parameter name'; Exit; END;

  WITH DWScript_Function(dwsFunctionPtr) DO
  BEGIN
    parameter := dwsFunction.Parameters.Add;
    parameter.Name := parameterName;

    parameterNames[dwsData.valueCount] := parameterName;
    dwsData.value[dwsData.valueCount].dataType := dataType;
    dwsData.value[dwsData.valueCount].name := PAnsiChar(parameterNames[dwsData.valueCount]);
    CASE dataType OF
      DATATYPE_INTEGER: parameter.DataType := 'Integer';
      DATATYPE_FLOAT:   parameter.DataType := 'Float';
      DATATYPE_BOOLEAN: parameter.DataType := 'Boolean';
      DATATYPE_STRING:  parameter.DataType := 'String';
    ELSE
      BEGIN scriptContext.status := 'AddParameter() Invalid data type specified'; Exit; END;
    END;

    dwsData.valueCount := dwsData.valueCount + 1;
  END;

  Result := TRUE;
END;

FUNCTION DWScript_setReturnType(context : pointer; dwsFunctionPtr : Pointer; dataType : Integer) : Boolean; STDCALL;
VAR
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);

  scriptContext.status := '';
  IF (dwsFunctionPtr = NIL) THEN BEGIN scriptContext.status := 'SetReturnType() cannot accept a NULL Function parameter'; Exit; END;

  WITH DWScript_Function(dwsFunctionPtr) DO
  BEGIN
    dwsData.returnValue.dataType := dataType;
    CASE dataType OF
      DATATYPE_INTEGER: dwsFunction.ResultType := 'Integer';
      DATATYPE_FLOAT:   dwsFunction.ResultType := 'Float';
      DATATYPE_BOOLEAN: dwsFunction.ResultType := 'Boolean';
      DATATYPE_STRING:  dwsFunction.ResultType := 'String';
    ELSE
      BEGIN scriptContext.status := 'SetReturnType() Invalid data type specified'; Exit; END;
    END;
  END;
  Result := TRUE;
END;

FUNCTION DWScript_addFunction(context : pointer; functionName : PAnsiChar; userFunction, userData : Pointer) : Pointer; STDCALL;
VAR
  newFunction : DWScript_Function;
  scriptContext : DWScript_Context;
BEGIN
  Result := NIL;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);

  scriptContext.status := '';
  IF (functionName = NIL) OR (Length(functionName) = 0) THEN BEGIN scriptContext.status := 'AddFunction() cannot accept a NULL or empty function name'; Exit; END;
  IF (userFunction = NIL) THEN BEGIN scriptContext.status := 'AddFunction() cannot accept a NULL Callback parameter'; Exit; END;
{$ifdef FPC} //using the FPHashList for now, which uses ShortStrings as keys, hence this restriction
  IF (Length(functionName) > 255) THEN BEGIN scriptContext.status := 'AddFunction() Function name must be less than 256 characters in length'; Exit; END;
{$endif};

  newFunction := DWScript_Function.Create;
  WITH newFunction DO
  BEGIN
    dwsFunction            := scriptContext.dwsUnit.Functions.Add;
    dwsFunction.Name       := functionName;
    name                   := functionName;
    dwsData.valueCount     := 0;
    dwsData.functionName   := PAnsiChar(name);
    dwsData.state          := NIL;
{$ifdef FPC}
    dwsFunction.OnEval     := @scriptContext.wrapper;
{$else}
    dwsFunction.OnEval     := scriptContext.wrapper;
{$endif}
  END;
  newFunction.userFunction := userFunction; //do this here because of naming clashes, TODO: make more sane variable names
  newFunction.userData     := userData;
  scriptContext.functions.Add(functionName, newFunction);
  Result := newFunction;
END;

FUNCTION doCall(scriptContext : DWScript_Context; Info : IInfo; data : DWScript_DataPtr) : Boolean;
VAR
  parameters  : ARRAY OF Variant;
  index       : Integer;
  returnValue : IInfo;
  stringValue : AnsiString;
BEGIN
  Result := TRUE;
  TRY
    //set up any required parameters
    IF (data <> NIL) THEN
    BEGIN
      SetLength(parameters, data^.valueCount);
      FOR index := 0 TO data^.valueCount-1 DO
      BEGIN
        CASE data^.value[index].dataType OF
          DATATYPE_INTEGER: parameters[index] := data^.value[index].i;
          DATATYPE_FLOAT:   parameters[index] := data^.value[index].f;
          DATATYPE_BOOLEAN: parameters[index] := data^.value[index].b;
          DATATYPE_STRING:  BEGIN stringValue := data^.value[index].s; parameters[index] := stringValue; END;
        END;
      END;
    END;
    //call the function
    returnValue := Info.Call(parameters);
    //store its return value if required
    IF (data <> NIL) THEN
    BEGIN
      data^.returnValue.dataType := DATATYPE_NOTSET;
      CASE VarType(returnValue.Value) OF
        varInteger, varInt64, varSmallInt, varWord, varByte, varLongWord:
          BEGIN data^.returnValue.dataType := DATATYPE_INTEGER; data^.returnValue.i := returnValue.GetValueAsInteger; END;
        varSingle, varDouble:
          BEGIN data^.returnValue.dataType := DATATYPE_FLOAT;   data^.returnValue.f := returnValue.GetValueAsFloat; END;
        varBoolean:
          BEGIN data^.returnValue.dataType := DATATYPE_BOOLEAN; data^.returnValue.b := returnValue.GetValueAsBoolean; END;
        varString:
          BEGIN data^.returnValue.dataType := DATATYPE_STRING;  data^.returnValue.s := PAnsiChar(returnValue.GetValueAsString); END; //FLAMES! Need memory management
        ELSE
          BEGIN scriptContext.status := 'Unhandled script return type'; Result := FALSE; END;
      END;
    END;
  EXCEPT
    ON E: Exception DO
    BEGIN
      scriptContext.status := 'EXCEPTION (Calling function) : ' + E.ClassName + ': ' + E.Message;
      Result := FALSE;
    END;
  END;
END;

FUNCTION DWScript_call(context : pointer; state : Pointer; functionName : PAnsiChar; data : DWScript_DataPtr) : Boolean; STDCALL;
VAR
  info : TProgramInfo;
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);
  scriptContext.status := '';
  IF (state = NIL) THEN BEGIN scriptContext.status := 'Call() cannot accept a NULL State parameter'; Exit; END;
  IF (functionName = NIL) OR (Length(functionName) = 0) THEN BEGIN scriptContext.status := 'Call() cannot accept a NULL or empty function name'; Exit; END;
  //data can be NULL, simply calls the function without parameters and without storing result

  TRY
    info := TProgramInfo(state);
    Result := doCall(scriptContext, info.Execution.ProgramInfo.Func[functionName], data);
  EXCEPT
    ON E: Exception DO
    BEGIN
      scriptContext.status := 'EXCEPTION (Call("' + functionName + '"): ' + E.ClassName + ': ' + E.Message;
    END;
  END;
END;

FUNCTION DWScript_callStateless(context : pointer; functionName : PAnsiChar; data : DWScript_DataPtr) : Boolean; STDCALL;
VAR
  execution : IdwsProgramExecution;
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);
  scriptContext.status := '';
  IF (functionName = NIL) OR (Length(functionName) = 0) THEN BEGIN scriptContext.status := 'CallStateless() cannot accept a NULL or empty function name'; Exit; END;
  //data can be NULL, simply calls the function without parameters and without storing result

  TRY
    execution := scriptContext.dwsProgram.CreateNewExecution;
    Result := doCall(scriptContext, execution.Info.Func[functionName], data);
  EXCEPT
    ON E: Exception DO
    BEGIN
      scriptContext.status := 'EXCEPTION (CallStateless("' + functionName + '"): ' + E.ClassName + ': ' + E.Message;
    END;
  END;
END;

FUNCTION DWScript_compile(context : pointer; scriptText : PAnsiChar; flags : Integer) : Boolean; STDCALL;
VAR
{$ifdef JITTER}
  jitter : TdwsJITx86;
{$endif}
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);
  scriptContext.status := '';
  IF (scriptText = NIL) OR (Length(scriptText) = 0) THEN BEGIN scriptContext.status := 'Compile() cannot accept a NULL or empty Script parameter'; Exit; END;

  TRY
    scriptContext.dwsProgram := scriptContext.dwsScript.Compile(scriptText);
    IF scriptContext.dwsProgram.Msgs.Count > 0 THEN
    BEGIN
      scriptContext.status := scriptContext.dwsProgram.Msgs.AsInfo
    END ELSE
    BEGIN
      {$ifdef JITTER}
      IF (flags AND FLAG_JITTER <> 0) THEN
      BEGIN
        jitter := TdwsJITx86.Create;
        jitter.Options := jitter.Options-[jitoNoBranchAlignment];
        jitter.GreedyJIT(scriptContext.dwsProgram.ProgramObject);
        jitter.Free;
      END;
      {$else}
      IF (flags AND FLAG_JITTER <> 0) THEN scriptContext.status := 'WARNING: Jitter not supported in this build';
      {$endif}
      Result := True;
    END;
  EXCEPT
    ON E: Exception DO
    BEGIN
      scriptContext.status := scriptContext.status + 'EXCEPTION (Compile()): ' + E.ClassName + ': ' + E.Message;
    END;
  END;

END;

FUNCTION DWScript_execute(context : pointer; flags : Integer) : Boolean; STDCALL;
VAR
  scriptContext : DWScript_Context;
BEGIN
  Result := FALSE;
  IF (context = NIL) THEN Exit;

  scriptContext := DWScript_Context(context);
  TRY
    scriptContext.status := '';
    scriptContext.dwsProgram.Execute;
    scriptContext.status := 'Finished executing';
    Result := TRUE;
  EXCEPT
    ON E: Exception DO
    BEGIN
      scriptContext.status := 'EXCEPTION (Run): ' + E.ClassName + ': ' + E.Message;
    END;
  END;
END;

END.
