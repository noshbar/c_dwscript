DWScript in a DLL
=================
(Delphi Web Scripting in a Dynamic Link Library for running Object Pascal scripts in C [and other languages])

What it is.
-----------

This compiles to a simple Windows DLL *(32-bit DLL provided)* that enables you to compile and run Object Pascal scripts from within your favourite language (provided it supports loading DLL's with the stdcall calling convention) using the [DWScript engine](http://www.delphitools.info/dwscript/) by Eric Grange.

Support for calling functions in the Pascal script is supported, as well as registering functions from e.g., C that the script can call. (A sample C wrapper and example are included in the **"c_interface"** folder).

Available under the [Mozilla Public License 1.1](http://www.mozilla.org/MPL/1.1/)

Features.
---------

- Run full Object Pascal scripts from within your application
- Jitter can be enabled for JIT compilation, speeding up code "quite a lot" (I obtained double the execution performance in some cases) [*only when compiled with Delphi for now*]
- OLE support can be enabled [*only when compiled with Delphi for now*]
- ASM support can be enabled [*requires NASM executable in the same path as the DLL*]
- The provided DLL was built using Delphi XE 5 from an SVN checkout of the DWScript sources on the 18th of April 2014.

Using.
------

A simple C example would be something like this:

        HMODULE handle = DWScript_initialise("dwscript.dll");  
        //you can make as many contexts as you like, but cannot mix and match contexts as you wish
        DWScriptContext context = DWScript_createContext(DWScript_Flags_Ole | DWScript_Flags_Asm);
        //add any local C functions into the context with DWScript_addFunction()
        //and DWScript_addParameter() before compiling
        DWScript_compile(context, "begin end.", DWScript_Flags_Jitter); //only necessary once per context
        DWScript_execute(context, DWScript_Flags_None); //call as many times as you like
        DWScript_destroyContext(context);
        DWScript_finalise(handle);
 

Ideas / TODO
-----

- Instead of the horrendous fixed-array of unions parameter nonsense going on, you could optionally make the functions take varargs and make calling them a much-more straight-forward affair.  
My only worry then is that you'd have to change from stdcall to cdecl, thereby losing the ability to use this DLL from within certain languages (I'd hate to prejudice Visual Basic 6 users who want to run Pascal script containing highly optimised assembler from within their application).
- Fix Unicode/AnsiString conversions  /  Implement Unicode support
- Add the ability to run a script in a non-blocking manner.
- Add debugger support so that you can set breakpoints in the code, etc.
- Make error handling and reporting not suck.

Free Pascal Notes.
------------------

**TL;DR;** Only [this](https://dl.dropboxusercontent.com/u/4716604/fpc2.7.1.7z) binary collection of FPC 2.7.1 works for me.

I initially started this project using [Free Pascal](http://www.freepascal.org/).

As DWScript uses Generics, I needed a newer version of the Free Pascal compiler than what they provide on their home page (2.6).

Fortunately I had [Laz4Android](http://sourceforge.net/projects/laz4android/) installed, which came with a build of FPC 2.7.1  
This also provided me with the Masks unit that some DWScript units needed.  
*(I found mine in laz4android/components/lazutils)*

I initially made some horrible hacks to the DWScript code to just get it compiling *(deleting entire classes, casting wide to ansi strings, etc.)*, a simple proof-of-concept to see if it was worthwhile continuing.

Once I had a working DLL, I decided to update my version of Laz4Android to see if it fared any better at the Generics stuff...

    dwscript.lpr(157,1) Error: Undefined symbol: VMT_$DWSUTILS_$$_$GENDEF386

Hmm, Google had nothing on it, nothing on GENDEF386, couldn't find mention of this in the sources.  
Oh well, no worry, I'll just try:
- compiling FPC from SVN
- [CrossFPC](http://www.crossfpc.com/)
- [CodeTyphon](http://www.pilotlogic.com/sitejoom/index.php/codetyphon)
- A random version of Laz4Android I found
- Building it all on the command line using FPC, then linking it all manually with verbosity set to "I can show you the world"

...

    dwscript.lpr(157,1) Error: Undefined symbol: VMT_$DWSUTILS_$$_$GENDEF386

I've done some investigation into it, I built a little Python Pascal Parser to detect differentiating Interface/Implementation function descriptions and found some things... but nothing the compiler seems upset about.  
So instead, if you want to use Free Pascal to compile this, you can try using the binary dump of FPC2.7.1 I took from my working version of Laz4Anroid from [here](https://dl.dropboxusercontent.com/u/4716604/fpc2.7.1.7z).
