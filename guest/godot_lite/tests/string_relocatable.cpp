// Godot's containers move elements with realloc, so a String must not point
// into itself. The control is std::string, whose short-string buffer does.
#include "core/string/ustring.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

template <typename T>
static bool points_into_itself(const T &p_s, const char *p_data) {
	const char *lo = reinterpret_cast<const char *>(&p_s);
	return p_data >= lo && p_data < lo + sizeof(T);
}

template <typename T>
static bool survives_realloc(const char *p_text) {
	void *block = malloc(sizeof(T));
	T *s = new (block) T(p_text);
	void *moved = malloc(sizeof(T));
	memcpy(moved, block, sizeof(T));
	memset(block, 0xAB, sizeof(T));
	free(block);
	T *m = static_cast<T *>(moved);
	const char *data = nullptr;
	if constexpr (std::is_same_v<T, std::string>) {
		data = m->c_str();
	} else {
		data = m->get_data();
	}
	const bool ok = !points_into_itself(*m, data) && strcmp(data, p_text) == 0;
	if (ok) {
		m->~T();
	}
	free(moved);
	(void)s;
	return ok;
}

int main() {
	int failures = 0;
	const char *cases[] = { "", "1,2,", "101,102,103,", "a string well past any inline buffer" };
	for (const char *c : cases) {
		if (!survives_realloc<gdl::String>(c)) {
			printf("FAIL String \"%s\" does not survive a bytewise move\n", c);
			failures++;
		}
	}
	if (survives_realloc<std::string>("1,2,")) {
		printf("FAIL control: a short std::string survived a bytewise move, so the check sees nothing\n");
		failures++;
	}
	printf("%s: %d String cases, 1 control\n", failures ? "FAIL" : "PASS", int(sizeof(cases) / sizeof(cases[0])));
	return failures ? 1 : 0;
}
