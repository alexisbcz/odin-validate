package validate

import "core:strings"

/*
is_email reports whether `s` looks like an email address: `local@domain`.

The check is deliberately practical rather than full RFC 5322. The local part
is 1 to 64 characters of letters, digits and ``!#$%&'*+/=?^_`{|}~.-``, with no
leading, trailing or doubled dot. The domain has at least two labels of 1 to
63 letters, digits or hyphens, and no label starts or ends with a hyphen. The
whole address is at most 254 bytes.
*/
is_email :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 254 {
		return false
	}
	at := strings.last_index_byte(s, '@')
	if at <= 0 || at > 64 {
		return false
	}
	local, domain := s[:at], s[at + 1:]
	if local[0] == '.' || local[len(local) - 1] == '.' || strings.contains(local, "..") {
		return false
	}
	for c in transmute([]u8)local {
		if !is_ascii_alnum(c) && strings.index_byte("!#$%&'*+/=?^_`{|}~.-", c) < 0 {
			return false
		}
	}
	return is_hostname(domain, 2)
}

/*
is_url reports whether `s` is an absolute URL with a scheme and a host, for
example `https://odin-lang.org/docs`.

The scheme starts with a letter and continues with letters, digits, `+`, `-`
or `.`, then `://`. The authority before the first `/`, `?` or `#` must hold
a host, except for `file:` URLs. Whitespace and control characters anywhere
fail the check.
*/
is_url :: proc(s: string) -> bool {
	sep := strings.index(s, "://")
	if sep <= 0 {
		return false
	}
	scheme := s[:sep]
	if !is_ascii_alpha(scheme[0]) {
		return false
	}
	for c in transmute([]u8)scheme {
		if !is_ascii_alnum(c) && c != '+' && c != '-' && c != '.' {
			return false
		}
	}
	for c in transmute([]u8)s {
		if c <= ' ' || c == 0x7f {
			return false
		}
	}
	rest := s[sep + 3:]
	end := strings.index_any(rest, "/?#")
	authority := rest if end < 0 else rest[:end]
	if at := strings.last_index_byte(authority, '@'); at >= 0 {
		authority = authority[at + 1:]
	}
	if authority == "" {
		return strings.equal_fold(scheme, "file")
	}
	return true
}

/*
is_uuid reports whether `s` is a UUID in the canonical 8-4-4-4-12 hexadecimal
form, for example `123e4567-e89b-12d3-a456-426614174000`. Upper and lower case
both pass; the version and variant bits aren't checked.
*/
is_uuid :: proc(s: string) -> bool {
	if len(s) != 36 {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return false
			}
		case:
			if !is_ascii_hex(c) {
				return false
			}
		}
	}
	return true
}

// is_alpha reports whether `s` is non-empty and holds only ASCII letters.
is_alpha :: proc(s: string) -> bool {
	if s == "" {
		return false
	}
	for c in transmute([]u8)s {
		if !is_ascii_alpha(c) {
			return false
		}
	}
	return true
}

// is_alnum reports whether `s` is non-empty and holds only ASCII letters and digits.
is_alnum :: proc(s: string) -> bool {
	if s == "" {
		return false
	}
	for c in transmute([]u8)s {
		if !is_ascii_alnum(c) {
			return false
		}
	}
	return true
}

/*
is_numeric reports whether `s` is a decimal number: an optional `+` or `-`,
one or more digits, and optionally a `.` followed by one or more digits. For
example `42`, `-7` and `3.14` pass, while `1e3`, `.5` and `1.` fail.
*/
is_numeric :: proc(s: string) -> bool {
	t := s
	if len(t) > 0 && (t[0] == '+' || t[0] == '-') {
		t = t[1:]
	}
	dot := strings.index_byte(t, '.')
	whole, frac := t, ""
	if dot >= 0 {
		whole, frac = t[:dot], t[dot + 1:]
		if frac == "" {
			return false
		}
	}
	return all_digits(whole) && (dot < 0 || all_digits(frac))
}

// is_hex reports whether `s` is a hexadecimal number with an optional `0x` or `0X` prefix, for example `ff` or `0x1F`.
is_hex :: proc(s: string) -> bool {
	t := s
	if len(t) >= 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X') {
		t = t[2:]
	}
	if t == "" {
		return false
	}
	for c in transmute([]u8)t {
		if !is_ascii_hex(c) {
			return false
		}
	}
	return true
}

// is_hostname checks dot separated labels of letters, digits and inner hyphens.
@(private)
is_hostname :: proc(s: string, min_labels: int) -> bool {
	if len(s) == 0 || len(s) > 253 {
		return false
	}
	labels := 0
	rest := s
	for label in strings.split_iterator(&rest, ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label) - 1] == '-' {
			return false
		}
		for c in transmute([]u8)label {
			if !is_ascii_alnum(c) && c != '-' {
				return false
			}
		}
		labels += 1
	}
	// split_iterator drops a trailing empty label, so reject a trailing dot here.
	return labels >= min_labels && s[len(s) - 1] != '.'
}

@(private)
all_digits :: proc(s: string) -> bool {
	if s == "" {
		return false
	}
	for c in transmute([]u8)s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

@(private)
is_ascii_alpha :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

@(private)
is_ascii_alnum :: proc(c: u8) -> bool {
	return is_ascii_alpha(c) || (c >= '0' && c <= '9')
}

@(private)
is_ascii_hex :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}
