package validate_tests

import "core:testing"

@(test)
test_required :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"required"`,
		n: int `validate:"required"`,
		f: f64 `validate:"required"`,
		b: bool `validate:"required"`,
		l: []int `validate:"required"`,
		m: map[string]int `validate:"required"`,
	}
	m := make(map[string]int)
	defer delete(m)
	m["a"] = 1
	good := R{"x", -1, 0.5, true, []int{0}, m}
	expect_valid(t, &good)

	zero := R{}
	expect_errors(
		t,
		&zero,
		{
			{"s", "required", .Rule_Failed},
			{"n", "required", .Rule_Failed},
			{"f", "required", .Rule_Failed},
			{"b", "required", .Rule_Failed},
			{"l", "required", .Rule_Failed},
			{"m", "required", .Rule_Failed},
		},
	)
}

@(test)
test_required_message :: proc(t: ^testing.T) {
	R :: struct {
		title: string `validate:"required"`,
	}
	r := R{}
	expect_message(t, &r, "title is required")
}

@(test)
test_min_string_counts_runes :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"min=3"`,
	}
	good := R{"été"} // Three runes, five bytes.
	expect_valid(t, &good)
	bad := R{"ab"}
	expect_fail(t, &bad, "s", "min")
}

@(test)
test_min_slice_and_number :: proc(t: ^testing.T) {
	R :: struct {
		items: []int `validate:"min=2"`,
		age:   int `validate:"min=18"`,
		ratio: f32 `validate:"min=0.5"`,
	}
	good := R{[]int{1, 2}, 18, 0.5}
	expect_valid(t, &good)
	bad := R{[]int{1}, 17, 0.25}
	expect_errors(t, &bad, {{"items", "min", .Rule_Failed}, {"age", "min", .Rule_Failed}, {"ratio", "min", .Rule_Failed}})
}

@(test)
test_max :: proc(t: ^testing.T) {
	R :: struct {
		s:     string `validate:"max=3"`,
		items: [dynamic]int `validate:"max=1"`,
		n:     i8 `validate:"max=-1"`,
	}
	good := R {
		s = "abc",
		n = -5,
	}
	expect_valid(t, &good)
	bad := R {
		s = "abcd",
		n = 0,
	}
	defer delete(bad.items)
	append(&bad.items, 1, 2)
	expect_errors(t, &bad, {{"s", "max", .Rule_Failed}, {"items", "max", .Rule_Failed}, {"n", "max", .Rule_Failed}})
}

@(test)
test_len :: proc(t: ^testing.T) {
	R :: struct {
		code:  string `validate:"len=4"`,
		pair:  []string `validate:"len=2"`,
		fixed: [3]int `validate:"len=3"`,
		n:     u8 `validate:"len=7"`,
	}
	good := R{"abcd", []string{"a", "b"}, {}, 7}
	expect_valid(t, &good)
	bad := R{"abc", []string{"a"}, {}, 8}
	expect_errors(t, &bad, {{"code", "len", .Rule_Failed}, {"pair", "len", .Rule_Failed}, {"n", "len", .Rule_Failed}})
}

@(test)
test_gt_gte_lt_lte_numbers :: proc(t: ^testing.T) {
	R :: struct {
		a: int `validate:"gt=0"`,
		b: int `validate:"gte=0"`,
		c: f64 `validate:"lt=1.5"`,
		d: f64 `validate:"lte=1.5"`,
	}
	good := R{1, 0, 1.4, 1.5}
	expect_valid(t, &good)
	bad := R{0, -1, 1.5, 1.6}
	expect_errors(
		t,
		&bad,
		{{"a", "gt", .Rule_Failed}, {"b", "gte", .Rule_Failed}, {"c", "lt", .Rule_Failed}, {"d", "lte", .Rule_Failed}},
	)
}

@(test)
test_gt_lt_on_lengths :: proc(t: ^testing.T) {
	R :: struct {
		s:     string `validate:"gt=2,lt=5"`,
		items: []int `validate:"gte=1,lte=2"`,
	}
	good := R{"abc", []int{1}}
	expect_valid(t, &good)
	short := R{"ab", []int{}}
	expect_errors(t, &short, {{"s", "gt", .Rule_Failed}, {"items", "gte", .Rule_Failed}})
	long := R{"abcde", []int{1, 2, 3}}
	expect_errors(t, &long, {{"s", "lt", .Rule_Failed}, {"items", "lte", .Rule_Failed}})
}

@(test)
test_large_unsigned_values_compare_exactly :: proc(t: ^testing.T) {
	R :: struct {
		n: u64 `validate:"gt=9223372036854775807"`,
	}
	good := R{max(u64)}
	expect_valid(t, &good)
	bad := R{9223372036854775807}
	expect_fail(t, &bad, "n", "gt")
}

@(test)
test_comparison_messages :: proc(t: ^testing.T) {
	A :: struct {
		s: string `validate:"max=1"`,
	}
	a := A{"ab"}
	expect_message(t, &a, "s must be at most 1 character long")

	B :: struct {
		items: []int `validate:"min=2"`,
	}
	b := B{}
	expect_message(t, &b, "items must contain at least 2 items")

	C :: struct {
		n: int `validate:"gt=10"`,
	}
	c := C{10}
	expect_message(t, &c, "n must be greater than 10")
}

@(test)
test_oneof :: proc(t: ^testing.T) {
	Color :: enum {
		Red,
		Green,
		Blue,
	}
	R :: struct {
		role:  string `validate:"oneof=admin|member|guest"`,
		level: int `validate:"oneof=1|2|3"`,
		color: Color `validate:"oneof=Red|Blue"`,
	}
	good := R{"member", 3, .Blue}
	expect_valid(t, &good)
	bad := R{"owner", 4, .Green}
	expect_errors(t, &bad, {{"role", "oneof", .Rule_Failed}, {"level", "oneof", .Rule_Failed}, {"color", "oneof", .Rule_Failed}})
}

@(test)
test_oneof_message_lists_options :: proc(t: ^testing.T) {
	R :: struct {
		role: string `validate:"oneof=admin|member|guest"`,
	}
	r := R{"owner"}
	expect_message(t, &r, "role must be one of admin, member, guest")
}

@(test)
test_email_rule :: proc(t: ^testing.T) {
	R :: struct {
		email: string `validate:"email"`,
	}
	good := R{"ada.lovelace+odin@mail.example.org"}
	expect_valid(t, &good)
	bad := R{"ada@localhost"}
	expect_fail(t, &bad, "email", "email")
}

@(test)
test_url_rule :: proc(t: ^testing.T) {
	R :: struct {
		site: string `validate:"url"`,
	}
	good := R{"https://odin-lang.org/docs?x=1#top"}
	expect_valid(t, &good)
	bad := R{"odin-lang.org"}
	expect_fail(t, &bad, "site", "url")
}

@(test)
test_uuid_rule :: proc(t: ^testing.T) {
	R :: struct {
		id: string `validate:"uuid"`,
	}
	good := R{"123E4567-e89b-12d3-a456-426614174000"}
	expect_valid(t, &good)
	bad := R{"123e4567e89b12d3a456426614174000"}
	expect_fail(t, &bad, "id", "uuid")
}

@(test)
test_alpha_rule :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"alpha"`,
	}
	good := R{"Odin"}
	expect_valid(t, &good)
	bad := R{"Odin2"}
	expect_fail(t, &bad, "s", "alpha")
}

@(test)
test_alnum_rule :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"alnum"`,
	}
	good := R{"Odin2026"}
	expect_valid(t, &good)
	bad := R{"odin-2026"}
	expect_fail(t, &bad, "s", "alnum")
}

@(test)
test_numeric_rule :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"numeric"`,
	}
	good := R{"-12.50"}
	expect_valid(t, &good)
	bad := R{"12a"}
	expect_fail(t, &bad, "s", "numeric")
}

@(test)
test_hex_rule :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"hex"`,
	}
	good := R{"0xDeadBeef"}
	expect_valid(t, &good)
	bad := R{"0xg1"}
	expect_fail(t, &bad, "s", "hex")
}

@(test)
test_prefix_rule :: proc(t: ^testing.T) {
	R :: struct {
		key: string `validate:"prefix=sk_"`,
	}
	good := R{"sk_live_123"}
	expect_valid(t, &good)
	bad := R{"pk_live_123"}
	expect_fail(t, &bad, "key", "prefix")
	expect_message(t, &bad, `key must start with "sk_"`)
}

@(test)
test_suffix_rule :: proc(t: ^testing.T) {
	R :: struct {
		file: string `validate:"suffix=.odin"`,
	}
	good := R{"main.odin"}
	expect_valid(t, &good)
	bad := R{"main.go"}
	expect_fail(t, &bad, "file", "suffix")
}

@(test)
test_contains_rule :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"contains=@"`,
	}
	good := R{"a@b"}
	expect_valid(t, &good)
	bad := R{"ab"}
	expect_fail(t, &bad, "s", "contains")
}

@(test)
test_format_rules_fail_on_empty_without_omitempty :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"email"`,
		b: string `validate:"omitempty,email"`,
	}
	r := R{}
	expect_fail(t, &r, "a", "email")
}

@(test)
test_cstring_and_named_types :: proc(t: ^testing.T) {
	Name :: distinct string
	Age :: distinct int
	R :: struct {
		c:    cstring `validate:"required,min=2"`,
		name: Name `validate:"alpha"`,
		age:  Age `validate:"gte=0"`,
	}
	good := R{"ok", "Ada", 3}
	expect_valid(t, &good)
	bad := R{"x", "Ada1", -1}
	expect_errors(t, &bad, {{"c", "min", .Rule_Failed}, {"name", "alpha", .Rule_Failed}, {"age", "gte", .Rule_Failed}})
}

@(test)
test_spaces_around_rules_are_trimmed :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:" required , min=2 "`,
	}
	bad := R{"a"}
	expect_fail(t, &bad, "s", "min")
}

@(test)
test_malformed_empty_rule :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"required,,min=3"`,
		b: string `validate:"required,"`,
	}
	r := R{"abc", "x"}
	expect_errors(t, &r, {{"a", "", .Malformed_Tag}, {"b", "", .Malformed_Tag}})
}

@(test)
test_malformed_missing_param :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"min"`,
		b: string `validate:"max="`,
		c: string `validate:"oneof"`,
		d: string `validate:"prefix="`,
	}
	r := R{"x", "x", "x", "x"}
	expect_errors(
		t,
		&r,
		{{"a", "min", .Malformed_Tag}, {"b", "max", .Malformed_Tag}, {"c", "oneof", .Malformed_Tag}, {"d", "prefix", .Malformed_Tag}},
	)
}

@(test)
test_malformed_bad_param :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"min=abc"`,
		b: string `validate:"len=-1"`,
		c: int `validate:"gt=1.5"`,
		d: f64 `validate:"lt=big"`,
		e: int `validate:"oneof=1|two"`,
		f: string `validate:"oneof=a||b"`,
	}
	r := R{"x", "x", 1, 1, 1, "a"}
	expect_errors(
		t,
		&r,
		{
			{"a", "min", .Malformed_Tag},
			{"b", "len", .Malformed_Tag},
			{"c", "gt", .Malformed_Tag},
			{"d", "lt", .Malformed_Tag},
			{"e", "oneof", .Malformed_Tag},
			{"f", "oneof", .Malformed_Tag},
		},
	)
}

@(test)
test_malformed_unexpected_param :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"required=yes"`,
		b: string `validate:"email=strict"`,
		c: string `validate:"omitempty=1"`,
	}
	r := R{"x", "a@b.co", ""}
	expect_errors(t, &r, {{"a", "required", .Malformed_Tag}, {"b", "email", .Malformed_Tag}, {"c", "omitempty", .Malformed_Tag}})
}

@(test)
test_malformed_message_is_clear :: proc(t: ^testing.T) {
	R :: struct {
		name: string `validate:"min"`,
	}
	r := R{"x"}
	expect_message(t, &r, `invalid tag on name: rule "min" needs a parameter, for example min=3`)
}

@(test)
test_unsupported_type :: proc(t: ^testing.T) {
	R :: struct {
		a: int `validate:"email"`,
		b: bool `validate:"min=1"`,
		c: []string `validate:"prefix=x"`,
	}
	r := R{1, true, nil}
	expect_errors(t, &r, {{"a", "email", .Unsupported_Type}, {"b", "min", .Unsupported_Type}, {"c", "prefix", .Unsupported_Type}})

	S :: struct {
		a: int `validate:"email"`,
	}
	one := S{1}
	expect_message(t, &one, `invalid tag on a: rule "email" doesn't apply to int`)
}

// 128-bit integers must compare on their full value, not a truncated 64-bit one.

@(test)
test_128_bit_integers_compare_exactly :: proc(t: ^testing.T) {
	S :: struct {
		x: i128 `validate:"gt=0"`,
	}
	big := S{1 << 70}
	expect_valid(t, &big)
	neg := S{-(1 << 70)}
	expect_fail(t, &neg, "x", "gt")

	U :: struct {
		x: u128 `validate:"lte=5"`,
	}
	huge := U{1 << 80}
	expect_fail(t, &huge, "x", "lte")
	top := U{max(u128)}
	expect_fail(t, &top, "x", "lte")
	small := U{5}
	expect_valid(t, &small)

	O :: struct {
		x: u128 `validate:"oneof=1|2"`,
	}
	wrapped := O{(1 << 64) + 1}
	expect_fail(t, &wrapped, "x", "oneof")
}

// required must agree with Odin's own idea of a zero value.

@(test)
test_required_treats_negative_zero_as_zero :: proc(t: ^testing.T) {
	R :: struct {
		f: f64 `validate:"required"`,
		g: f32 `validate:"required"`,
	}
	r := R{-0.0, -0.0}
	expect_errors(t, &r, {{"f", "required", .Rule_Failed}, {"g", "required", .Rule_Failed}})
}

@(test)
test_required_struct_compares_fields_not_bytes :: proc(t: ^testing.T) {
	Inner :: struct {
		s:    string,
		list: []int,
		f:    f64,
	}
	R :: struct {
		inner: Inner `validate:"required"`,
		arr:   [2]string `validate:"required"`,
	}
	text := "abc"
	nums := []int{1, 2}
	r := R {
		inner = Inner{s = text[:0], list = nums[:0], f = -0.0},
		arr = {text[:0], text[3:]},
	}
	expect_errors(t, &r, {{"inner", "required", .Rule_Failed}, {"arr", "required", .Rule_Failed}})

	set := R {
		inner = Inner{s = text},
		arr = {"", text},
	}
	expect_valid(t, &set)
}

@(test)
test_omitempty_skips_struct_holding_empty_views :: proc(t: ^testing.T) {
	Inner :: struct {
		s: string `validate:"required"`,
	}
	R :: struct {
		inner: Inner `validate:"omitempty"`,
	}
	text := "abc"
	r := R{Inner{text[:0]}}
	expect_valid(t, &r)
}
