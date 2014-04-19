all: dwscript_test.exe

dwscript_test.exe: dwscript.c test.c
	cl /Fedwscript_test.exe /nologo /O2 $**

clean: dummy
	-@del dwscript_test.exe
	-@del test.obj
	-@del dwscript.obj

dummy:
	
