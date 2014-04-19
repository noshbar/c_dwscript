/**
 * \author       Dirk de la Hunt (gmail:noshbar)
 * \copyright    Mozilla Public License 1.1 
 * \version      1.0.1.0
 * \brief        Example code on how to call and use the DWScript DLL wrapper
 */

#include <stdio.h>
#include <stdlib.h>
#include <Windows.h>
#include "dwscript.h"

/** the order of the names is important, the should match the enums of datatypes in dwscript.h */
static char *typeNames[] = { "Not set", "Float", "Integer", "String", "Boolean", "Invalid" };
/** this is a general purpose buffer for getting error messages and lazily reusing it for sending/receiving strings to/from functions.
    the basic rule is that the thread that allocates the memory is responsible for freeing it, and obviously the memory should exist
    long enough for the script function using it. */
static char buffer[1024];

void __stdcall test(DWScript_Data *dwsData, void *userData)
{
    if (!dwsData)
        return;

    /* this shows how to enumerate all the incoming parameters */
    {
        int index;
        printf("Function [%s] called, parameter count: %d\n", dwsData->functionName, dwsData->parameters.count);
        if (userData) //teeny hack as we know we sent the script as a string, simply print it. don't be so naive in your code, it's whatever you know you passed in!
            printf("User data as string:\n[%s]\n", (char*)userData);

        for (index = 0; index < dwsData->parameters.count; index++)
        {
            printf("%d [%s]: (%s) ", index, dwsData->parameters.value[index].name, typeNames[dwsData->parameters.value[index].datatype]);
            switch(dwsData->parameters.value[index].datatype)
            {
                case DWScript_DataType_Float:   printf("%.2f\n", dwsData->parameters.value[index].f); break;
                case DWScript_DataType_Integer: printf("%d\n",   dwsData->parameters.value[index].i); break;
                case DWScript_DataType_String:  printf("%s\n",   dwsData->parameters.value[index].s); break;
                case DWScript_DataType_Boolean: printf("%d\n",   dwsData->parameters.value[index].b); break;
            }
        }
    }

    /* this shows how to call a function that exists in the script only */
    {
        DWScript_Data parameter;
        memset(&parameter, 0, sizeof(parameter)); //not strictly necessary
        parameter.parameters.count = 1;
        parameter.parameters.value[0].datatype = DWScript_DataType_Integer;
        parameter.parameters.value[0].i = 2659004;
        if (DWScript_call(dwsData->context, dwsData->state, "TimesTwo", &parameter))
        {
            if (parameter.result.datatype != DWScript_DataType_Integer)
                printf("Incorrect return type from TimesTwo() (Expected %s, got %s)\n", typeNames[DWScript_DataType_Integer], typeNames[parameter.result.datatype]);
            else
                printf("TimesTwo(%d) returned value: %d\n", parameter.parameters.value[0].i, parameter.result.i);
        }
        else
        {
            DWScript_getMessage(dwsData->context, buffer, 1024);
            printf("Could not call function: %s\n", buffer);
        }
    }
}

void __stdcall getInput(DWScript_Data *dwsData, void *userData)
{
    printf("%s", dwsData->parameters.value[0].s);
    fgets(buffer, 1024, stdin);
    buffer[strlen(buffer)-1] = 0; /* nuke the newline */
    dwsData->result.s = buffer;
}

void __stdcall printString(DWScript_Data *dwsData, void *userData)
{
    printf("%s\n", dwsData->parameters.value[0].s);
}

int main(int argc, char *argv[])
{
    HMODULE          handle;
    DWScriptContext  context = NULL;
    char            *script =
        "function TimesTwo(value : integer) : integer;\n"
        "begin\n"
        "  result := value * 2;\n"
        "end;\n"
        "\n"
        "var\n"
        "  name : string;\n"
        "begin\n"
        "  debug(0.5, TimesTwo(21), 'test', true);\n"
        "  name := GetInput(#13#10 + 'Please enter your name: ');\n"
        "  PrintString('Your name backwards is \"' + ReverseString(name) + '\".');\n"
        "end.";

    //initialise the library (open the DLL, find the function addresses)
    handle = DWScript_initialise("..\\dwscript.dll");
    if (!handle)
    {
        printf("Could not load DWScript DLL (%d)\n", GetLastError());
        getchar();
        return -1;
    }

    //create a new script processor
    context = DWScript_createContext(DWScript_Flags_None);
    if (!context)
    {
        printf("Could not create context\n");
        getchar();
        DWScript_finalise(handle);
        return -1;
    }

    //add our "debug" function, this simply enumerates the function parameters
    {
        DWScriptFunction function = DWScript_addFunction(context, "debug", test, script);
        DWScript_addParameter(context, function, "a", DWScript_DataType_Float);
        DWScript_addParameter(context, function, "bb", DWScript_DataType_Integer);
        DWScript_addParameter(context, function, "ccc", DWScript_DataType_String);
        DWScript_addParameter(context, function, "dddd", DWScript_DataType_Boolean);
    }
    //add a "PrintString" function which displays a message on the screen
    {
        DWScriptFunction function = DWScript_addFunction(context, "PrintString", printString, NULL);
        DWScript_addParameter(context, function, "message", DWScript_DataType_String);
    }
    //add a "GetInput" function which reads a string from the keyboard
    {
        DWScriptFunction function = DWScript_addFunction(context, "GetInput", getInput, NULL);
        DWScript_setReturnType(context, function, DWScript_DataType_String);
        DWScript_addParameter(context, function, "message", DWScript_DataType_String);
    }

    //try compile and run the script
    if (!DWScript_compile(context, script, DWScript_Flags_Jitter))
    {
        DWScript_getMessage(context, buffer, 1024);
        printf("Could not compile script:\n(%s)\n", buffer);
    }
    else if (!DWScript_execute(context, DWScript_Flags_None))
    {
        DWScript_getMessage(context, buffer, 1024);
        printf("Could not run script:\n(%s)\n", buffer);
    }

    /* if you have a script that contains a utility function you'd like to call, you can simply compile the script once,
       then use DWScript_callStateless as many times as you like to use that or any other utility function.
       NOTE: the utility function cannot use global data as it has no state, it must essentially be a static function */

    DWScript_destroyContext(context);
    //FIXME: trying to free the DLL handle hangs, so the DLL is doing something wrong... for now just let the OS clean up after us...
    //DWScript_finalise(handle);

    printf("\nDone. (Press enter to quit)\n");
    getchar();
    return 0;
}
