package validate_tests

import validate ".."
import "core:testing"

// Tag mistakes must surface on every run, not only when the field holds a value.

@(test)
test_tag_errors_reported_when_pointer_is_nil :: proc(t: ^testing.T) {
	R :: struct {
		a: ^int `validate:"min=abc"`,
		b: ^int `validate:"mni=3"`,
		c: Maybe(int) `validate:"min=abc"`,
		d: ^string `validate:"email=strict"`,
		e: Maybe(^int) `validate:"gt=1.5"`,
	}
	r: R
	expect_errors(
		t,
		&r,
		{
			{"a", "min", .Malformed_Tag},
			{"b", "mni", .Unknown_Rule},
			{"c", "min", .Malformed_Tag},
			{"d", "email", .Malformed_Tag},
			{"e", "gt", .Malformed_Tag},
		},
	)
}

@(test)
test_unsupported_rule_reported_when_pointer_is_nil :: proc(t: ^testing.T) {
	R :: struct {
		a: ^int `validate:"email"`,
		b: Maybe(bool) `validate:"min=1"`,
		c: ^int `validate:"dive"`,
	}
	r: R
	expect_errors(t, &r, {{"a", "email", .Unsupported_Type}, {"b", "min", .Unsupported_Type}, {"c", "dive", .Unsupported_Type}})
}

@(test)
test_tag_errors_reported_when_omitempty_skips :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"omitempty,mni=3"`,
		b: string `validate:"omitempty,min=x"`,
		c: int `validate:"omitempty,email"`,
		d: string `validate:"omitempty,"`,
	}
	r: R
	expect_errors(
		t,
		&r,
		{{"a", "mni", .Unknown_Rule}, {"b", "min", .Malformed_Tag}, {"c", "email", .Unsupported_Type}, {"d", "", .Malformed_Tag}},
	)
}

@(test)
test_tag_errors_after_dive_reported_on_empty_slice :: proc(t: ^testing.T) {
	R :: struct {
		a: []string `validate:"dive,reqired"`,
		b: []string `validate:"dive,min=x"`,
		c: [dynamic]int `validate:"dive,email"`,
		d: [][]int `validate:"dive,dive,gt=x"`,
	}
	r: R
	expect_errors(
		t,
		&r,
		{{"a", "reqired", .Unknown_Rule}, {"b", "min", .Malformed_Tag}, {"c", "email", .Unsupported_Type}, {"d", "gt", .Malformed_Tag}},
	)
}

@(test)
test_oneof_trailing_empty_option_is_malformed :: proc(t: ^testing.T) {
	R :: struct {
		a: string `validate:"oneof=a|"`,
		b: int `validate:"oneof=1|"`,
	}
	r := R{"a", 1}
	expect_errors(t, &r, {{"a", "oneof", .Malformed_Tag}, {"b", "oneof", .Malformed_Tag}})
}

@(test)
test_tag_error_wins_over_rule_failure :: proc(t: ^testing.T) {
	R :: struct {
		s: string `validate:"required,min=abc"`,
	}
	r: R
	expect_errors(t, &r, {{"s", "min", .Malformed_Tag}})
}

@(test)
test_custom_rule_on_nil_pointer_is_not_unknown :: proc(t: ^testing.T) {
	always_false :: proc(value: any, param: string) -> bool {return false}
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	testing.expect(t, validate.register_rule(&v, "never", always_false) == nil)

	R :: struct {
		p: ^int `validate:"never"`,
	}
	r: R
	expect_valid(t, &r, &v)
	n := 1
	r.p = &n
	expect_fail(t, &r, "p", "never", &v)
}

@(test)
test_union_with_several_variants_checks_types_at_run_time :: proc(t: ^testing.T) {
	R :: struct {
		u: union {
			int,
			string,
		} `validate:"min=3"`,
	}
	empty: R
	expect_valid(t, &empty)
	short := R{"ab"}
	expect_fail(t, &short, "u", "min")
	small := R{2}
	expect_fail(t, &small, "u", "min")
}
