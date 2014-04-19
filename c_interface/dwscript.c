/**
 * \author       Dirk de la Hunt (gmail:noshbar)
 * \copyright    Mozilla Public License 1.1 
 * \brief        Simple DWScript DLL wrapper
 * \version      1.0.1.0
 *
 * Normal execution process would be something like:
 * HMODULE handle = DWScript_initialise("dwscript.dll");
 *    //you can make as many contexts as you like, but cannot mix and match contexts as you wish
 *    DWScriptContext context = DWScript_createContext();
 *    //add any local C functions into the context with DWScript_addFunction() and DWScript_addParameter() before compiling
 *    DWScript_compile(context, "begin end."); //only necessary once per context
 *       DWScript_run(context); //call as many times as you like
 *    DWScript_destroyContext(context);
 * DWScript_finalise(handle);
 */

#include "dwscript.h"

HMODULE DWScript_initialise(const char *dllPath)
{
    HMODULE handle;

    if ((handle = LoadLibraryA(dllPath)) == NULL)
        return NULL;

    DWScript_addFunction    = (LP_DWS_ADDFUNCTION)GetProcAddress(handle, "AddFunction");
    DWScript_addParameter   = (LP_DWS_ADDPARAMETER)GetProcAddress(handle, "AddParameter");
    DWScript_setReturnType  = (LP_DWS_SETRETURNTYPE)GetProcAddress(handle, "SetReturnType");
    DWScript_compile        = (LP_DWS_COMPILE)GetProcAddress(handle, "Compile");
    DWScript_execute        = (LP_DWS_EXECUTE)GetProcAddress(handle, "Execute");
    DWScript_call           = (LP_DWS_CALL)GetProcAddress(handle, "Call");
    DWScript_callStateless  = (LP_DWS_CALLSTATELESS)GetProcAddress(handle, "CallStateless");
    DWScript_getMessage     = (LP_DWS_GETMESSAGE)GetProcAddress(handle, "GetMessage");
    DWScript_createContext  = (LP_DWS_CREATECONTEXT)GetProcAddress(handle, "CreateContext");
    DWScript_destroyContext = (LP_DWS_DESTROYCONTEXT)GetProcAddress(handle, "DestroyContext");

    if (!DWScript_addFunction || 
        !DWScript_addParameter || 
        !DWScript_compile || 
        !DWScript_execute || 
        !DWScript_call || 
        !DWScript_callStateless || 
        !DWScript_getMessage || 
        !DWScript_createContext || 
        !DWScript_destroyContext)
    {
        FreeLibrary(handle);
        return NULL;
    }
    return handle;
}

void DWScript_finalise(HMODULE handle)
{
    if (handle)
        FreeLibrary(handle);
}
