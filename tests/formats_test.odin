package validate_tests

import validate ".."
import "core:testing"

// expect_format checks a format procedure against strings that must pass and strings that must fail.
expect_format :: proc(t: ^testing.T, name: string, check: proc(s: string) -> bool, pass, fail: []string, loc := #caller_location) {
	for s in pass {
		testing.expectf(t, check(s), "%s(%q) = false, want true", name, s, loc = loc)
	}
	for s in fail {
		testing.expectf(t, !check(s), "%s(%q) = true, want false", name, s, loc = loc)
	}
}

@(test)
test_is_email :: proc(t: ^testing.T) {
	expect_format(
		t,
		"is_email",
		validate.is_email,
		{"a@b.co", "first.last@example.com", "x+tag@sub.example.org", "o'brien@ex-ample.io", "UPPER@EXAMPLE.COM"},
		{
			"",
			"plain",
			"@example.com",
			"a@",
			"a@b",
			"a@.com",
			"a@b..com",
			"a@-b.com",
			"a@b-.com",
			"a@b.com.",
			".a@b.com",
			"a.@b.com",
			"a..b@c.com",
			"a b@c.com",
			"a@b_c.com",
		},
	)
}

@(test)
test_is_url :: proc(t: ^testing.T) {
	expect_format(
		t,
		"is_url",
		validate.is_url,
		{"http://x", "https://odin-lang.org", "https://user:pw@host:8080/p?q#f", "ftp://files.example.com/a", "file:///etc/hosts", "git+ssh://host/repo"},
		{"", "odin-lang.org", "://host", "1http://host", "http://", "http:///path", "https://exa mple.com", "ht_tp://host", "mailto:a@b.co"},
	)
}

@(test)
test_is_uuid :: proc(t: ^testing.T) {
	expect_format(
		t,
		"is_uuid",
		validate.is_uuid,
		{"00000000-0000-0000-0000-000000000000", "123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000"},
		{"", "123e4567-e89b-12d3-a456-42661417400", "123e4567-e89b-12d3-a456-4266141740000", "123e4567_e89b_12d3_a456_426614174000", "g23e4567-e89b-12d3-a456-426614174000"},
	)
}

@(test)
test_is_alpha_and_alnum :: proc(t: ^testing.T) {
	expect_format(t, "is_alpha", validate.is_alpha, {"a", "Odin", "ABCxyz"}, {"", "a1", "a b", "é", "a-b"})
	expect_format(t, "is_alnum", validate.is_alnum, {"a", "1", "Odin2026"}, {"", "a_1", "a b", "ü1"})
}

@(test)
test_is_numeric :: proc(t: ^testing.T) {
	expect_format(t, "is_numeric", validate.is_numeric, {"0", "42", "-7", "+3", "3.14", "-0.5"}, {"", "-", "+", "1.", ".5", "1e3", "1.2.3", "12a", " 1"})
}

@(test)
test_is_hex :: proc(t: ^testing.T) {
	expect_format(t, "is_hex", validate.is_hex, {"0", "ff", "DEADbeef", "0x1F", "0Xab"}, {"", "0x", "g", "0xg", "-1", "1 2"})
}
