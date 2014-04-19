/**
 * \file
 * \author       Dirk de la Hunt (gmail:noshbar)
 * \copyright    Mozilla Public License 1.1 
 * \brief        Simple DWScript DLL wrapper
 * \version      1.0.1.0
 *
 * Normal execution process would be something like:
 * HMODULE handle = DWScript_initialise("dwscript.dll");
 *    //you can make as many contexts as you like, but cannot mix and match contexts as you wish
 *    DWScriptContext context = DWScript_createContext(DWScript_Flags_Ole | DWScript_Flags_Asm);
 *    //add any local C functions into the context with DWScript_addFunction() and DWScript_addParameter() before compiling
 *    DWScript_compile(context, "begin end.", DWScript_Flags_Jitter); //only necessary once per context
 *       DWScript_execute(context); //call as many times as you like
 *    DWScript_destroyContext(context);
 * DWScript_finalise(handle);
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <Windows.h>

/* TYPES */
typedef void* DWScriptContext;
typedef void* DWScriptState;
typedef void* DWScriptFunction;

typedef enum DWScript_DataType
{
	DWScript_DataType_NotSet = 0,
	DWScript_DataType_Float,
	DWScript_DataType_Integer,
	DWScript_DataType_String,
	DWScript_DataType_Boolean,

	DWScript_DataType_Invalid = 65536 /**< promotes this type to an integer, do not use */
}
DWScript_DataType;

typedef enum DWScript_Flags
{
	DWScript_Flags_None    = 0,
	DWScript_Flags_Jitter  = 1 << 0, /**< enable JIT engine (DWScript_createContext()) */
	DWScript_Flags_Ole     = 1 << 1, /**< add OLE support to script environment (DWScript_createContext()) */
	DWScript_Flags_Asm     = 1 << 2, /**< add ASM support to script environment, requires NASM executable (DWScript_execute()) */

	DWScript_Flags_Invalid = 65536 /**< promotes this type to an integer, do not use */
}
DWScript_Flags;

/** Poor implementation of a variant-type variable for passing between C and DWScript */
typedef struct DWScript_Variable
{
    const char        *name;
    DWScript_DataType  datatype;
    union
    {
        float f;
        int   i;
        char *s;
        int   b;
    };
}
DWScript_Variable;

/** A structure used to pass data to and from the DWScript context.\n
    This is passed in to a registered C callback function and contains the parameters in the .parameters.value array. The result of the function should be stored in the .result variable.\n
    To call a Pascal function in the script, you would set up one of these structs containing the parameters for it in a similar way, obtaining the return value in the .result variable. */
typedef struct DWScript_Data
{
    DWScriptContext    context;      /**< when in a C callback method, this is the context responsible for calling it */
    DWScriptState      state;        /**< when in a C callback method, this is the current execution state, useful for using the DWScript_Call() function */
    const char        *functionName; /**< when in a C callback method, this is the registered name of the function in the script context */
    DWScript_Variable  result;       /**< this stores the return value of a function */
    struct
    {
        int               count;     /**< this indicates how many parameters there are */
        DWScript_Variable value[32]; /**< each of the value[count] elements should have their type and value specified */
    } parameters;
}
DWScript_Data;

typedef DWScriptContext  (__stdcall *LP_DWS_CREATECONTEXT)(DWScript_Flags flags);
typedef void             (__stdcall *LP_DWS_DESTROYCONTEXT)(DWScriptContext context);
typedef DWScriptFunction (__stdcall *LP_DWS_ADDFUNCTION)(DWScriptContext context, const char *name, void *function, void *userdata);
typedef int              (__stdcall *LP_DWS_ADDPARAMETER)(DWScriptContext context, DWScriptFunction function, const char *name, DWScript_DataType datatype);
typedef int              (__stdcall *LP_DWS_SETRETURNTYPE)(DWScriptContext context, DWScriptFunction function, DWScript_DataType datatype);
typedef int              (__stdcall *LP_DWS_COMPILE)(DWScriptContext context, const char *script, DWScript_Flags flags);
typedef int              (__stdcall *LP_DWS_EXECUTE)(DWScriptContext context, DWScript_Flags flags);
typedef int              (__stdcall *LP_DWS_CALL)(DWScriptContext context, DWScriptState state, const char *name, DWScript_Data *data);
typedef int              (__stdcall *LP_DWS_CALLSTATELESS)(DWScriptContext context, const char *name, DWScript_Data *data);
typedef int              (__stdcall *LP_DWS_GETMESSAGE)(DWScriptContext context, char *message, int size);

/* FUNCTIONS */

/**
    This loads the DLL from the specified path and sets up the function pointers
    \param   dllPath  The path to the DLL to load
    \return  a handle to the DLL
*/
HMODULE DWScript_initialise(const char *dllPath);

/**
    This unloads the DLL, be sure to destroy and contexts before calling this (not necessary if you are exiting your program)
    \param  handle  The handle to the DLL obtained using DWScript_initialise
*/
void DWScript_finalise(HMODULE handle);

/**
    This creates a new script execution context. You can create as many of these as you like and pass them around threads freely.
	\param   flags   features to support in the script environment.\n
	                 bitmask of: DWScript_Flags_None, DWScript_Flags_Ole, DWScript_Flags_Asm
    \return  a pointer to a new context on success, or NULL on failure.
*/
LP_DWS_CREATECONTEXT /* DWScriptContext */DWScript_createContext/*(DWScript_Flags flags)*/;

/**
    This frees an existing context. Note that the context must not be used after this call.
    \param   context  the context created with DWScript_createContext you wish to destroy.
*/
LP_DWS_DESTROYCONTEXT /* void */DWScript_destroyContext/*(DWScriptContext context)*/;

/**
    This inserts a local C function into the script context, making it callable from within the script.\n
    Note: if you have a C function called "test", you can add it to the script context as any name you like, e.g., "test1",
          meaning that the script will have to call "test1" to get to test.\n
          Not only that, but you could additionally register "test" as "test2" as well, resuling in the script being able
          to call "test1" and "test2" that both result in calling the native C function called "test".
    \param   context  an existing context created with DWScript_createContext
    \param   name     what name to register the function in the script context as
    \param   function the address of the local C function to associate with the script function
    \param   userdata this can be a pointer to whatever you like, it will simply be passed in to the C function, can be NULL
    \return  a pointer to the new script function, can be used to add parameters and set return type,
             or NULL on failure, use DWScript_getMessage() for more information
*/
LP_DWS_ADDFUNCTION /* DWScriptFunction */DWScript_addFunction/*(DWScriptContext context, const char *name, void *function, void *userdata)*/;

/**
    This registers a parameter to a function already registered using DWScript_addFunction() above.
    Note: the order you add these parameters in is the order they will be considered when called.
    \param   context  an existing context created with DWScript_createContext
    \param   function an existing script function created with DWScript_addFunction
    \param   name     the name of the parameter to add
    \param   datatype the type of the parameter
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_ADDPARAMETER /* int */DWScript_addParameter/*(DWScriptContext context, DWScriptFunction function, const char *name, DWScript_DataType datatype)*/;

/**
    This sets the return type of a function already registered using DWScript_addFunction() above.
    \param   context  an existing context created with DWScript_createContext
    \param   function an existing script function created with DWScript_addFunction
    \param   datatype the type of the return value
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_SETRETURNTYPE /* int */DWScript_setReturnType/*(DWScriptContext context, DWScriptFunction function, DWScript_DataType datatype)*/;

/**
    This attempts to compile the provided script into the given context.\n
    It is only necessary to call this function once per script-change in a single context.\n
    NOTE: it is necessary to register any functions before calling this using DWScript_addFunction() and DWScript_addParameter()
    \param   context   an existing context created with DWScript_createContext
    \param   script    the script to compile
	\param   flags     features to support during compiling the script.\n
	                   bitmask of: DWScript_Flags_None, DWScript_Flags_Jitter
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_COMPILE /* int */DWScript_compile/*(DWScriptContext context, const char *script, DWScript_Flags flags)*/;

/**
    This attempts to run a script already compiled using DWScript_compile() above.\n
    This can be called as many times as you like within a context.\n
    \warning this function blocks while executing
    \param   context  an existing context created with DWScript_createContext that has had a script compiled within it
	\param   flags    can only be DWScript_Flags_None for now.\n
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_EXECUTE /* int */DWScript_execute/*(DWScriptContext context, DWScript_Flags flags)*/;

/**
    This attempts to call a script function within an already running/executing context.\n
    This can only be used within a C function that has been called from the script context.\n
    This is due to it requiring an existing running execution context to work. This can be obtained via the DWScript_Data.state
    variable of the DWScript_Data structure passed in to a locally registered C callback.
    \warning this function blocks while executing
    \param   context  an existing context created with DWScript_createContext
    \param   state    an existing context execution state obtained from the DWScript_Data structure passed in to a C callback.
    \param   name     the name of the script function to call
    \param   data     any parameters you wish to pass the function must be set in this, the return value of the function will
                      also be stored in this structure.  If this is NULL, the function will be called with no parameters,
                      and the return result discarded.
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_CALL /* int */DWScript_call/*(DWScriptContext context, DWScriptState state, const char *name, DWScript_Data *data)*/;

/**
    This attempts to call a script function without requiring a running execution context.\n
    As this does not require a running context, once a script has been compiled using DWScript_compile(), you can make
    multiple calls to any static functions within that script that don't use global data.\n
    \warning this function blocks while executing
    \param   context  an existing context created with DWScript_createContext
    \param   name     the name of the script function to call
    \param   data     any parameters you wish to pass the function must be set in this, the return value of the function will
                      also be stored in this structure.  If this is NULL, the function will be called with no parameters,
                      and the return result discarded.
    /return  non-zero on success, 0 on failure, use DWScript_getMessage() for more information
*/
LP_DWS_CALLSTATELESS /* int */DWScript_callStateless/*(DWScriptContext context, const char *name, DWScript_Data *data)*/;

/**
    This fills a buffer with information about the latest failure encountered during operation.
    \param   context  an existing context created with DWScript_createContext
    \param   message  the buffer to hold the message or NULL if you wish to obtain the length of the message being held
    \param   size     the capacity of the message buffer, the status will be truncated to fit this.
    /return  if message is NULL, this will be the length of the message available, otherwise it will be the amount
             of characters filled into the message buffer.
*/
LP_DWS_GETMESSAGE /* int */DWScript_getMessage/*(DWScriptContext context, char *message, int size)*/;

#ifdef __cplusplus
}
#endif
