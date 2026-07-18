// SCIInternalGates.x
// Ponto de instalação único (Logos %ctor) do motor de gates internos.
// Toda a lógica vive em SCIInternalGatesEngine.m; aqui é só o gate barato.
#import "SCIInternalGatesEngine.h"

%ctor {
	@autoreleasepool {
		SCIInternalGatesInstall();
	}
}
