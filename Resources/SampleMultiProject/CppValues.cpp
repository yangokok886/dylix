#include "Shared.h"
#include <string>
int FixtureCppValue(void) { std::string value("local"); return (int)value.size(); }
