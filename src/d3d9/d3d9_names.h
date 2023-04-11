#include "d3d9_include.h"

namespace dxvk {

	std::ostream& operator << (std::ostream& os, D3DRENDERSTATETYPE e);

	const char* D3DTEXTUREOP_ToString(const D3DTEXTUREOP op);

	const char* D3DTEXTUREARGUMENT_ToString(const int op);

}