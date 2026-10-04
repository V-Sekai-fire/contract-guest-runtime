// godot-lite: a minimal String over std::string (UTF-8 bytes, not Godot's
// char32_t). It carries what Cassie and the vendored core use: construction
// from C strings, concatenation, comparison, hashing for HashMap/HashSet,
// to_float/to_int, sprintf for vformat, and the number formatters.
// StringName is the same type: nothing here interns names.
#pragma once

#include "core/templates/hashfuncs.h"
#include "core/typedefs.h"

#include <cstdint>
#include <string>
#include <utility>

namespace gdl {

class Array;

// A std::string behind a pointer. Godot's containers move elements with
// realloc, and libstdc++'s short-string buffer points into the object itself.
class StdStringBox {
	std::string *_p = nullptr;

public:
	StdStringBox() = default;
	StdStringBox(std::string &&p_s) :
			_p(p_s.empty() ? nullptr : new std::string(std::move(p_s))) {}
	StdStringBox(const StdStringBox &p_o) :
			_p(p_o._p ? new std::string(*p_o._p) : nullptr) {}
	StdStringBox(StdStringBox &&p_o) :
			_p(p_o._p) { p_o._p = nullptr; }
	StdStringBox &operator=(const StdStringBox &p_o) {
		if (this != &p_o) {
			StdStringBox copy(p_o);
			std::swap(_p, copy._p);
		}
		return *this;
	}
	StdStringBox &operator=(StdStringBox &&p_o) {
		std::swap(_p, p_o._p);
		return *this;
	}
	~StdStringBox() { delete _p; }

	const std::string &get() const {
		static const std::string empty;
		return _p ? *_p : empty;
	}
	std::string &mut() {
		if (!_p) {
			_p = new std::string();
		}
		return *_p;
	}
};

class CharString {
	StdStringBox data;

public:
	CharString() = default;
	explicit CharString(std::string p_data) :
			data(std::move(p_data)) {}
	const char *get_data() const { return data.get().c_str(); }
	const char *ptr() const { return data.get().c_str(); }
	int length() const { return int(data.get().size()); }
	int size() const { return data.get().empty() ? 0 : int(data.get().size()) + 1; }
};

class String {
	StdStringBox _b;
	const std::string &_s() const { return _b.get(); }
	std::string &_m() { return _b.mut(); }

public:
	String() = default;
	String(const char *p_str) :
			_b(std::string(p_str ? p_str : "")) {}
	String(const std::string &p_str) :
			_b(std::string(p_str)) {}
	String(std::string &&p_str) :
			_b(std::move(p_str)) {}

	// gdl extension: the backing UTF-8 buffer.
	const std::string &std_string() const { return _s(); }
	const char *get_data() const { return _s().c_str(); }

	bool is_empty() const { return _s().empty(); }
	int length() const { return int(_s().size()); }
	int size() const { return _s().empty() ? 0 : int(_s().size()) + 1; }
	void clear() { _b = StdStringBox(); }

	CharString utf8() const { return CharString(_s()); }

	uint32_t hash() const;

	bool operator==(const String &p_o) const { return _s() == p_o._s(); }
	bool operator!=(const String &p_o) const { return _s() != p_o._s(); }
	bool operator<(const String &p_o) const { return _s() < p_o._s(); }
	bool operator<=(const String &p_o) const { return _s() <= p_o._s(); }
	bool operator>(const String &p_o) const { return _s() > p_o._s(); }
	bool operator>=(const String &p_o) const { return _s() >= p_o._s(); }
	bool operator==(const char *p_o) const { return _s() == (p_o ? p_o : ""); }
	bool operator!=(const char *p_o) const { return !(*this == p_o); }

	String operator+(const String &p_o) const { return String(_s() + p_o._s()); }
	String operator+(const char *p_o) const { return String(_s() + (p_o ? p_o : "")); }
	String operator+(char32_t p_c) const;
	String &operator+=(const String &p_o) {
		_m() += p_o._s();
		return *this;
	}
	String &operator+=(const char *p_o) {
		_m() += (p_o ? p_o : "");
		return *this;
	}
	String &operator+=(char32_t p_c);

	double to_float() const;
	int64_t to_int() const;

	// Godot's printf-alike (%d %i %s %f %e %g %x %X %c %%, flags, width, precision);
	// the arguments come from an Array of Variants.
	String sprintf(const Array &p_values, bool *r_error) const;

	static String num(double p_num, int p_decimals = -1);
	static String num_int64(int64_t p_num, int p_base = 10, bool p_capitalize_hex = false);
	static String num_real(double p_num, bool p_trailing = true);
};

using StringName = String;

String operator+(const char *p_a, const String &p_b);
String operator+(char32_t p_a, const String &p_b);
bool operator==(const char *p_a, const String &p_b);
bool operator!=(const char *p_a, const String &p_b);

String itos(int64_t p_val);
String rtos(double p_val);

} // namespace gdl
