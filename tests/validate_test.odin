// Package validate_tests holds the unit tests for validate. Run them with `odin test tests`.
package validate_tests

import validate ".."
import "core:mem"
import "core:reflect"
import "core:testing"

// Want is one expected error: its path, rule and kind.
Want :: struct {
	path: string,
	rule: string,
	kind: validate.Field_Error_Kind,
}

// expect_no_leaks fails the test when the tracking allocator still holds allocations.
expect_no_leaks :: proc(t: ^testing.T, track: ^mem.Tracking_Allocator, loc := #caller_location) {
	testing.expectf(t, len(track.allocation_map) == 0, "leaked %d allocation(s)", len(track.allocation_map), loc = loc)
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad free(s)", len(track.bad_free_array), loc = loc)
}

// expect_errors validates `value` under a tracking allocator and checks the exact errors, in order.
expect_errors :: proc(t: ^testing.T, value: ^$T, want: []Want, v: ^validate.Validator = nil, loc := #caller_location) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	errs: []validate.Field_Error
	ok: bool
	if v != nil {
		errs, ok = validate.validate_with(v, value, alloc)
	} else {
		errs, ok = validate.validate(value, alloc)
	}
	testing.expectf(t, ok == (len(want) == 0), "ok = %v, want %v; errors: %v", ok, len(want) == 0, errs, loc = loc)
	testing.expectf(t, len(errs) == len(want), "got %d error(s), want %d: %v", len(errs), len(want), errs, loc = loc)
	for w, i in want {
		if i >= len(errs) {
			break
		}
		e := errs[i]
		testing.expectf(
			t,
			e.path == w.path && e.rule == w.rule && e.kind == w.kind,
			"error %d: got {{%q, %q, %v}}, want {{%q, %q, %v}} (%s)",
			i,
			e.path,
			e.rule,
			e.kind,
			w.path,
			w.rule,
			w.kind,
			e.message,
			loc = loc,
		)
	}
	validate.field_errors_destroy(errs, alloc)
	expect_no_leaks(t, &track, loc)
}

// expect_valid checks that `value` passes with no errors and no leaks.
expect_valid :: proc(t: ^testing.T, value: ^$T, v: ^validate.Validator = nil, loc := #caller_location) {
	expect_errors(t, value, {}, v, loc)
}

// expect_fail checks that `value` fails exactly one rule on `path`.
expect_fail :: proc(t: ^testing.T, value: ^$T, path, rule: string, v: ^validate.Validator = nil, loc := #caller_location) {
	expect_errors(t, value, {{path, rule, .Rule_Failed}}, v, loc)
}

// expect_message checks the message of the single error that `value` produces.
expect_message :: proc(t: ^testing.T, value: ^$T, message: string, loc := #caller_location) {
	errs, ok := validate.validate(value)
	defer validate.field_errors_destroy(errs)
	testing.expect(t, !ok, "expected a failure", loc = loc)
	testing.expectf(t, len(errs) == 1, "got %d error(s), want 1: %v", len(errs), errs, loc = loc)
	if len(errs) == 1 {
		testing.expectf(t, errs[0].message == message, "message: got %q, want %q", errs[0].message, message, loc = loc)
	}
}

Address :: struct {
	street: string `validate:"required"`,
	zip:    string `validate:"required,len=5,numeric"`,
}

User :: struct {
	name:      string `validate:"required,min=3,max=64"`,
	email:     string `validate:"required,email"`,
	addresses: []Address,
}

Signup :: struct {
	user:  User,
	terms: bool `validate:"required"`,
}

@(test)
test_valid_struct_has_no_errors :: proc(t: ^testing.T) {
	addrs := []Address{{"1 Main St", "12345"}}
	s := Signup {
		user = {name = "Ada", email = "ada@example.com", addresses = addrs},
		terms = true,
	}
	expect_valid(t, &s)
}

@(test)
test_valid_returns_nil_slice :: proc(t: ^testing.T) {
	a := Address{"1 Main St", "12345"}
	errs, ok := validate.validate(&a)
	testing.expect(t, ok)
	testing.expect(t, errs == nil)
}

@(test)
test_nested_slice_path :: proc(t: ^testing.T) {
	addrs := []Address{{"a", "12345"}, {"b", "12345"}, {"c", "1234x"}}
	s := Signup {
		user = {name = "Ada", email = "ada@example.com", addresses = addrs},
		terms = true,
	}
	expect_fail(t, &s, "user.addresses[2].zip", "numeric")
}

@(test)
test_nested_struct_path :: proc(t: ^testing.T) {
	s := Signup {
		user = {name = "Ad", email = "ada@example.com"},
		terms = true,
	}
	expect_fail(t, &s, "user.name", "min")
}

@(test)
test_errors_collected_in_field_order :: proc(t: ^testing.T) {
	addrs := []Address{{"", "12345"}, {"b", "12"}}
	s := Signup {
		user = {name = "", email = "nope", addresses = addrs},
		terms = false,
	}
	expect_errors(
		t,
		&s,
		{
			{"user.name", "required", .Rule_Failed},
			{"user.email", "email", .Rule_Failed},
			{"user.addresses[0].street", "required", .Rule_Failed},
			{"user.addresses[1].zip", "len", .Rule_Failed},
			{"terms", "required", .Rule_Failed},
		},
	)
}

@(test)
test_first_failing_rule_per_field_wins :: proc(t: ^testing.T) {
	F :: struct {
		code: string `validate:"min=3,alpha,prefix=x"`,
	}
	f := F{"1"}
	expect_fail(t, &f, "code", "min")
}

@(test)
test_messages_include_path :: proc(t: ^testing.T) {
	s := Signup {
		user = {name = "Al", email = "al@example.com"},
		terms = true,
	}
	expect_message(t, &s, "user.name must be at least 3 characters long")
}

@(test)
test_fixed_array_path :: proc(t: ^testing.T) {
	Team :: struct {
		members: [3]Address,
	}
	team := Team {
		members = {{"a", "12345"}, {"b", "12345"}, {"c", ""}},
	}
	expect_fail(t, &team, "members[2].zip", "required")
}

@(test)
test_dynamic_array_path :: proc(t: ^testing.T) {
	Book :: struct {
		addresses: [dynamic]Address,
	}
	b: Book
	defer delete(b.addresses)
	append(&b.addresses, Address{"a", "12345"}, Address{"", "12345"})
	expect_fail(t, &b, "addresses[1].street", "required")
}

@(test)
test_dive_applies_rules_to_elements :: proc(t: ^testing.T) {
	Post :: struct {
		tags: []string `validate:"min=1,dive,required,max=5"`,
	}
	p := Post{[]string{"odin", "", "toolong"}}
	expect_errors(t, &p, {{"tags[1]", "required", .Rule_Failed}, {"tags[2]", "max", .Rule_Failed}})

	empty := Post{}
	expect_fail(t, &empty, "tags", "min")
}

@(test)
test_nested_dive :: proc(t: ^testing.T) {
	Grid :: struct {
		rows: [][]int `validate:"dive,min=1,dive,gte=0"`,
	}
	g := Grid{[][]int{{1, 2}, {}, {3, -4}}}
	expect_errors(t, &g, {{"rows[1]", "min", .Rule_Failed}, {"rows[2][1]", "gte", .Rule_Failed}})
}

@(test)
test_dive_on_non_container_is_unsupported :: proc(t: ^testing.T) {
	F :: struct {
		n: int `validate:"dive,min=1"`,
	}
	f := F{1}
	expect_errors(t, &f, {{"n", "dive", .Unsupported_Type}})
}

@(test)
test_omitempty_skips_zero_values :: proc(t: ^testing.T) {
	Profile :: struct {
		website: string `validate:"omitempty,url"`,
		age:     int `validate:"omitempty,gte=13"`,
		home:    ^Address `validate:"omitempty"`,
	}
	empty := Profile{}
	expect_valid(t, &empty)

	bad := Profile {
		website = "not a url",
		age     = 5,
	}
	expect_errors(t, &bad, {{"website", "url", .Rule_Failed}, {"age", "gte", .Rule_Failed}})
}

@(test)
test_omitempty_skips_nested_struct :: proc(t: ^testing.T) {
	Order :: struct {
		billing: Address `validate:"omitempty"`,
	}
	o := Order{}
	expect_valid(t, &o)

	half := Order {
		billing = {street = "1 Main St"},
	}
	expect_fail(t, &half, "billing.zip", "required")
}

@(test)
test_nil_pointer_fails_only_required :: proc(t: ^testing.T) {
	Form :: struct {
		nickname: ^string `validate:"required,min=3"`,
		bio:      ^string `validate:"min=3"`,
	}
	f := Form{}
	expect_fail(t, &f, "nickname", "required")
}

@(test)
test_pointer_rules_apply_to_pointee :: proc(t: ^testing.T) {
	Form :: struct {
		nickname: ^string `validate:"required,min=3"`,
	}
	short := "al"
	f := Form{&short}
	expect_fail(t, &f, "nickname", "min")

	long := "alice"
	f.nickname = &long
	expect_valid(t, &f)
}

@(test)
test_pointer_to_struct_recurses :: proc(t: ^testing.T) {
	Customer :: struct {
		home: ^Address,
	}
	c := Customer{}
	expect_valid(t, &c)

	a := Address{"1 Main St", "abcde"}
	c.home = &a
	expect_fail(t, &c, "home.zip", "numeric")
}

@(test)
test_maybe_values :: proc(t: ^testing.T) {
	Settings :: struct {
		theme:   Maybe(string) `validate:"oneof=light|dark"`,
		timeout: Maybe(int) `validate:"required,gt=0"`,
	}
	s := Settings{}
	expect_fail(t, &s, "timeout", "required")

	s.theme = "blue"
	s.timeout = 0 // Present but zero: required passes, gt fails.
	expect_errors(t, &s, {{"theme", "oneof", .Rule_Failed}, {"timeout", "gt", .Rule_Failed}})

	s.theme = "dark"
	s.timeout = 30
	expect_valid(t, &s)
}

@(test)
test_maybe_pointer_is_nil_aware :: proc(t: ^testing.T) {
	Link :: struct {
		home: Maybe(^Address) `validate:"required"`,
	}
	l := Link{}
	expect_fail(t, &l, "home", "required")

	a := Address{"", "12345"}
	l.home = &a
	expect_fail(t, &l, "home.street", "required")
}

@(test)
test_union_recurses_into_variant :: proc(t: ^testing.T) {
	Shipping :: union {
		Address,
		string,
	}
	Parcel :: struct {
		to: Shipping `validate:"required"`,
	}
	p := Parcel{}
	expect_fail(t, &p, "to", "required")

	p.to = Address{"1 Main St", ""}
	expect_fail(t, &p, "to.zip", "required")
}

@(test)
test_validate_nil_pointer_passes :: proc(t: ^testing.T) {
	a: ^Address
	errs, ok := validate.validate(a)
	testing.expect(t, ok)
	testing.expect(t, errs == nil)
}

@(test)
test_dash_tag_skips_field :: proc(t: ^testing.T) {
	Wrapper :: struct {
		skipped: Address `validate:"-"`,
		kept:    Address,
	}
	w := Wrapper {
		kept = {"x", "12345"},
	}
	expect_valid(t, &w)
}

@(test)
test_untagged_scalars_are_ignored :: proc(t: ^testing.T) {
	Plain :: struct {
		a: int,
		b: string,
		c: []u8,
	}
	p := Plain{}
	expect_valid(t, &p)
}

@(test)
test_validate_any :: proc(t: ^testing.T) {
	a := Address{"", "12345"}
	errs, ok := validate.validate_any(a)
	defer validate.field_errors_destroy(errs)
	testing.expect(t, !ok)
	testing.expect_value(t, len(errs), 1)
}

@(test)
test_error_for_finds_path :: proc(t: ^testing.T) {
	a := Address{"", "1"}
	errs, _ := validate.validate(&a)
	defer validate.field_errors_destroy(errs)
	e, found := validate.error_for(errs, "zip")
	testing.expect(t, found)
	testing.expect_value(t, e.rule, "len")
	testing.expect_value(t, e.param, "5")
	_, missing := validate.error_for(errs, "nope")
	testing.expect(t, !missing)
}

is_even :: proc(value: any, param: string) -> bool {
	n, ok := reflect.as_i64(value)
	return ok && n % 2 == 0
}

divisible_by :: proc(value: any, param: string) -> bool {
	n, ok := reflect.as_i64(value)
	switch param {
	case "3":
		return ok && n % 3 == 0
	case "5":
		return ok && n % 5 == 0
	}
	return false
}

@(test)
test_custom_rule :: proc(t: ^testing.T) {
	Pair :: struct {
		count: int `validate:"required,even"`,
		group: int `validate:"divisible=3"`,
	}
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	v: validate.Validator
	validate.validator_init(&v, alloc)
	testing.expect_value(t, validate.register_rule(&v, "even", is_even), nil)
	testing.expect_value(t, validate.register_rule(&v, "divisible", divisible_by), nil)

	good := Pair{4, 9}
	expect_valid(t, &good, &v)

	bad := Pair{3, 10}
	expect_errors(t, &bad, {{"count", "even", .Rule_Failed}, {"group", "divisible", .Rule_Failed}}, &v)

	errs, _ := validate.validate_with(&v, &bad)
	defer validate.field_errors_destroy(errs)
	testing.expect_value(t, errs[0].message, `count failed the "even" rule`)
	testing.expect_value(t, errs[1].param, "3")

	validate.validator_destroy(&v)
	expect_no_leaks(t, &track)
}

@(test)
test_custom_rule_receives_pointee :: proc(t: ^testing.T) {
	Box :: struct {
		n: ^int `validate:"even"`,
	}
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	_ = validate.register_rule(&v, "even", is_even)

	three := 3
	b := Box{&three}
	expect_fail(t, &b, "n", "even", &v)
}

@(test)
test_unknown_rule_without_validator :: proc(t: ^testing.T) {
	F :: struct {
		n: int `validate:"even"`,
	}
	f := F{2}
	expect_errors(t, &f, {{"n", "even", .Unknown_Rule}})
}

@(test)
test_register_rule_errors :: proc(t: ^testing.T) {
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	testing.expect_value(t, validate.register_rule(&v, "", is_even), validate.Error(validate.Register_Error.Empty_Name))
	testing.expect_value(t, validate.register_rule(&v, "has space", is_even), validate.Error(validate.Register_Error.Invalid_Name))
	testing.expect_value(t, validate.register_rule(&v, "a=b", is_even), validate.Error(validate.Register_Error.Invalid_Name))
	testing.expect_value(t, validate.register_rule(&v, "email", is_even), validate.Error(validate.Register_Error.Reserved_Name))
	testing.expect_value(t, validate.register_rule(&v, "dive", is_even), validate.Error(validate.Register_Error.Reserved_Name))
	testing.expect_value(t, validate.register_rule(&v, "even", nil), validate.Error(validate.Register_Error.Nil_Rule))
	testing.expect_value(t, validate.register_rule(&v, "even", is_even), nil)
	testing.expect_value(t, validate.register_rule(&v, "even", is_even), validate.Error(validate.Register_Error.Duplicate_Name))
}

@(test)
test_register_rule_copies_name :: proc(t: ^testing.T) {
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	buf := make([]u8, 4)
	copy(buf, "even")
	testing.expect_value(t, validate.register_rule(&v, string(buf), is_even), nil)
	copy(buf, "xxxx")
	delete(buf)

	F :: struct {
		n: int `validate:"even"`,
	}
	f := F{1}
	expect_fail(t, &f, "n", "even", &v)
}

@(test)
test_path_tag_renames_segments :: proc(t: ^testing.T) {
	Account :: struct {
		user_name: string `json:"userName,omitempty" validate:"required"`,
		hidden:    string `json:"-" validate:"required"`,
		home:      Address `json:"homeAddress"`,
	}
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	v.path_tag = "json"
	a := Account{}
	a.home.zip = "12345"
	expect_errors(
		t,
		&a,
		{
			{"userName", "required", .Rule_Failed},
			{"hidden", "required", .Rule_Failed},
			{"homeAddress.street", "required", .Rule_Failed},
		},
		&v,
	)
}

Node :: struct {
	name: string `validate:"required"`,
	next: ^Node,
}

@(test)
test_pointer_cycle_stops_at_max_depth :: proc(t: ^testing.T) {
	n := Node{name = "loop"}
	n.next = &n
	v: validate.Validator
	v.max_depth = 4
	expect_errors(t, &n, {{"next.next.next.next.name", "", .Too_Deep}}, &v)
}

@(test)
test_linked_list_within_depth :: proc(t: ^testing.T) {
	c := Node{name = ""}
	b := Node{name = "b", next = &c}
	a := Node{name = "a", next = &b}
	expect_fail(t, &a, "next.next.name", "required")
}

@(test)
test_many_errors_do_not_leak :: proc(t: ^testing.T) {
	addrs := make([]Address, 50)
	defer delete(addrs)
	s := Signup {
		user = {addresses = addrs},
	}
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	errs, ok := validate.validate(&s, alloc)
	testing.expect(t, !ok)
	testing.expect_value(t, len(errs), 2 + 50 * 2 + 1)
	validate.field_errors_destroy(errs, alloc)
	expect_no_leaks(t, &track)
}

// Limited_Allocator serves `remaining` allocations from `backing`, then fails every later one.
Limited_Allocator :: struct {
	backing:   mem.Allocator,
	remaining: int,
}

limited_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	l := (^Limited_Allocator)(data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if l.remaining <= 0 {
			return nil, .Out_Of_Memory
		}
		l.remaining -= 1
	}
	return l.backing.procedure(l.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

@(test)
test_allocation_failure_reports_not_ok_without_leaks :: proc(t: ^testing.T) {
	addrs := make([]Address, 10)
	defer delete(addrs)
	s := Signup {
		user = {addresses = addrs},
	}
	for budget in 0 ..< 40 {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		limited := Limited_Allocator{mem.tracking_allocator(&track), budget}
		alloc := mem.Allocator{limited_allocator_proc, &limited}

		errs, ok := validate.validate(&s, alloc)
		testing.expectf(t, !ok, "budget %d: expected ok == false", budget)
		validate.field_errors_destroy(errs, alloc)
		expect_no_leaks(t, &track)
		mem.tracking_allocator_destroy(&track)
	}
}
