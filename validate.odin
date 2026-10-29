/*
Package validate checks struct values against rules written in struct tags,
in the style of Go's go-playground/validator and TypeScript's zod.

Tag a field with `validate:"..."`, a comma separated list of rules. A rule is
a name, optionally followed by `=` and a parameter:

	Signup :: struct {
		name:  string `validate:"required,min=3,max=64"`,
		email: string `validate:"required,email"`,
		age:   int    `validate:"gte=18,lte=130"`,
		role:  string `validate:"oneof=admin|member|guest"`,
	}

validate walks the value with `core:reflect`. It recurses into nested
structs, slices, dynamic arrays, fixed arrays, pointers and unions such as
`Maybe(T)`, and reports every failure as a Field_Error with a dotted path
like `user.addresses[2].zip`.

Built-in rules:
- required: the value isn't the zero value. A nil pointer, nil Maybe, empty
  string, empty slice or map, `0`, `-0.0` and `false` all fail, and so does
  a struct or array whose fields or elements are all zero.
- omitempty: when the value is zero, skip the remaining rules and nested fields.
- min, max, len, gt, gte, lt, lte: compare the length of strings (in runes),
  slices, arrays and maps, or the value of integers and floats.
- oneof=a|b|c: the string, number or enum member name is one of the options.
- email, url, uuid, alpha, alnum, numeric, hex: string formats. See is_email
  and the other `is_*` procedures for the exact grammar. An empty string
  fails them, so pair them with omitempty for optional fields.
- prefix=, suffix=, contains=: substring checks on strings.
- dive: apply the rules after `dive` to every element of a slice or array,
  for example `validate:"min=1,dive,required,max=20"`.
- `-` as the whole tag skips the field and everything inside it.

Rules run in tag order and stop at the first failure for that field, so an
empty name reports `required` and not also `min`. Nested fields still run.
For pointers and unions, rules other than required apply to the value they
hold; when they hold nothing, only required can fail. Tag mistakes are
different: every tag is checked against the field's type before any rule
runs, so an unknown rule or a bad parameter is reported even on a nil
pointer, a zero value under omitempty or an empty slice under dive.

Register extra rules on a Validator with register_rule and run them with
validate_with.

Example:
	import "core:fmt"
	import "shared:validate"

	User :: struct {
		name:  string `validate:"required,min=3"`,
		email: string `validate:"required,email"`,
	}

	main :: proc() {
		u := User{name = "al", email = "al@example.com"}
		errs, ok := validate.validate(&u)
		defer validate.field_errors_destroy(errs)
		if !ok {
			for e in errs {
				fmt.println(e.message) // name must be at least 3 characters long
			}
		}
	}
*/
package validate

import "base:runtime"

// DEFAULT_MAX_DEPTH is how many path segments deep validation goes before it reports Too_Deep.
DEFAULT_MAX_DEPTH :: 64

// TAG_KEY is the struct tag key that holds the rules.
TAG_KEY :: "validate"

// Field_Error_Kind says why a Field_Error was reported.
Field_Error_Kind :: enum {
	// The value broke a rule, for example it was shorter than `min`.
	Rule_Failed,
	// The tag couldn't be parsed: an empty rule, a missing or unexpected parameter, or a parameter of the wrong form.
	Malformed_Tag,
	// The tag names a rule that is neither built in nor registered on the Validator.
	Unknown_Rule,
	// The rule exists but doesn't apply to the field's type, for example `email` on an `int`.
	Unsupported_Type,
	// The value nests deeper than the maximum depth, which usually means a pointer cycle.
	Too_Deep,
}

/*
Field_Error describes one failed rule or one problem with a tag.

Fields:
- kind: why this error was reported.
- path: where the value lives, for example `user.addresses[2].zip`. Owned by
  the error slice; field_errors_destroy frees it.
- rule: the rule name as written in the tag, for example `min`. Empty for
  Too_Deep. It points into the program's static type table, so never free it.
- param: the rule parameter, for example `3` for `min=3`, or empty. Static
  like rule.
- message: a default English message that includes the path, for example
  `name must be at least 3 characters long`. Owned like path.
*/
Field_Error :: struct {
	kind:    Field_Error_Kind,
	path:    string,
	rule:    string,
	param:   string,
	message: string,
}

/*
Rule_Proc is the signature of a custom rule. It returns true when `value`
passes.

Inputs:
- value: the field value. For pointers and unions it's the value they hold,
  so a rule on a `^string` field receives a `string`. Use `core:reflect` or a
  type switch to read it.
- param: the text after `=` in the tag, or empty when the tag has none.
*/
Rule_Proc :: #type proc(value: any, param: string) -> bool

// Register_Error lists the ways register_rule can fail.
Register_Error :: enum {
	None,
	// The rule name was empty.
	Empty_Name,
	// The rule name contains a character other than a letter, digit or underscore.
	Invalid_Name,
	// The rule name matches a built-in rule or keyword such as `required` or `dive`.
	Reserved_Name,
	// A rule with this name is already registered on the Validator.
	Duplicate_Name,
	// The rule procedure was nil.
	Nil_Rule,
}

/*
Error is the compound error type returned by register_rule. `nil` means
success.
*/
Error :: union #shared_nil {
	Register_Error,
	runtime.Allocator_Error,
}

/*
Validator holds custom rules and options. A zero Validator works with no
custom rules; call validator_init before register_rule and validator_destroy
when done.

Fields:
- rules: custom rules by name. Use register_rule rather than writing it.
- path_tag: when set, for example to `"json"`, a field's path segment comes
  from that tag (the text before the first comma) instead of the Odin field
  name. Fields without that tag, or with `-`, keep their Odin name.
- max_depth: how many path segments deep validation goes; 0 means
  DEFAULT_MAX_DEPTH.
- allocator: owns the rule names.

Register all rules before validating. After that, several threads may call
validate_with on the same Validator at once, because validation only reads it.
*/
Validator :: struct {
	rules:     map[string]Rule_Proc,
	path_tag:  string,
	max_depth: int,
	allocator: runtime.Allocator,
}

/*
validator_init prepares `v` for register_rule. Every rule name copy uses
`allocator`. Call validator_destroy when done.
*/
validator_init :: proc(v: ^Validator, allocator := context.allocator) {
	v^ = {}
	v.allocator = allocator
	v.rules = make(map[string]Rule_Proc, allocator)
}

// validator_destroy frees the rule names and the rule map. The Validator is zeroed.
validator_destroy :: proc(v: ^Validator) {
	for name in v.rules {
		delete(name, v.allocator)
	}
	delete(v.rules)
	v^ = {}
}

/*
register_rule adds a custom rule that tags can use by `name`.

Inputs:
- v: a Validator prepared with validator_init.
- name: letters, digits and underscores; it may not match a built-in rule.
  The Validator stores its own copy.
- rule: called with the field value and the tag parameter.

Returns:
- err: a Register_Error when the name or rule is invalid, or an allocator error.

Example:
	is_even :: proc(value: any, param: string) -> bool {
		n, ok := reflect.as_i64(value)
		return ok && n % 2 == 0
	}

	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	_ = validate.register_rule(&v, "even", is_even)
*/
register_rule :: proc(v: ^Validator, name: string, rule: Rule_Proc) -> Error {
	if name == "" {
		return .Empty_Name
	}
	for c in transmute([]u8)name {
		if !is_name_char(c) {
			return .Invalid_Name
		}
	}
	if builtin_from_name(name) != .None {
		return .Reserved_Name
	}
	if rule == nil {
		return .Nil_Rule
	}
	if name in v.rules {
		return .Duplicate_Name
	}
	if v.allocator.procedure == nil {
		v.allocator = context.allocator
	}
	owned := make([]u8, len(name), v.allocator) or_return
	copy(owned, name)
	if map_insert(&v.rules, string(owned), rule) == nil {
		delete(owned, v.allocator)
		return runtime.Allocator_Error.Out_Of_Memory
	}
	return nil
}

/*
validate checks `value` against the built-in rules in its `validate` tags.

Inputs:
- value: a pointer to the value to check, usually a struct. A nil pointer
  passes.
- allocator: allocates the error slice and each error's path and message.

Returns:
- errs: every failure in field order, owned by the caller; free with
  `field_errors_destroy(errs, allocator)`. nil when there are none.
- ok: true when there were no errors. It's also false when an allocation
  failed, in which case errs may be incomplete.

Example:
	errs, ok := validate.validate(&signup)
	defer validate.field_errors_destroy(errs)
*/
validate :: proc(value: ^$T, allocator := context.allocator) -> (errs: []Field_Error, ok: bool) {
	if value == nil {
		return nil, true
	}
	return validate_any(value^, nil, allocator)
}

/*
validate_with is validate with the custom rules and options of `v`.

Returns:
- errs: owned by the caller; free with `field_errors_destroy(errs, allocator)`.
- ok: true when there were no errors and no allocation failed.
*/
validate_with :: proc(v: ^Validator, value: ^$T, allocator := context.allocator) -> (errs: []Field_Error, ok: bool) {
	if value == nil {
		return nil, true
	}
	return validate_any(value^, v, allocator)
}

/*
validate_any checks any value whose type is only known at run time. `value`
must refer to addressable memory, which it does whenever it comes from a
variable or a pointer dereference.

Inputs:
- value: the value to check.
- v: a Validator with custom rules and options, or nil for built-ins only.
- allocator: allocates the error slice and each error's strings.

Returns:
- errs: owned by the caller; free with `field_errors_destroy(errs, allocator)`.
- ok: true when there were no errors and no allocation failed.
*/
validate_any :: proc(value: any, v: ^Validator = nil, allocator := context.allocator) -> (errs: []Field_Error, ok: bool) {
	if value.data == nil || value.id == nil {
		return nil, true
	}
	w := Walker {
		validator = v,
		allocator = allocator,
		max_depth = DEFAULT_MAX_DEPTH,
	}
	if v != nil && v.max_depth > 0 {
		w.max_depth = v.max_depth
	}
	w.errs.allocator = allocator
	w.path.buf.allocator = allocator
	defer delete(w.path.buf)

	walk_value(&w, value)

	if len(w.errs) == 0 {
		delete(w.errs)
		return nil, !w.out_of_memory
	}
	return w.errs[:], false
}

/*
field_errors_destroy frees an error slice returned by validate, validate_with
or validate_any, including each error's path and message. Pass the same
allocator that the validate call used. A nil slice is fine.
*/
field_errors_destroy :: proc(errs: []Field_Error, allocator := context.allocator) {
	for e in errs {
		delete(e.path, allocator)
		delete(e.message, allocator)
	}
	delete(errs, allocator)
}

/*
error_for returns the first error whose path is exactly `path`.

Returns:
- err: the matching error; it shares its strings with `errs`.
- found: false when no error has that path.
*/
error_for :: proc(errs: []Field_Error, path: string) -> (err: Field_Error, found: bool) {
	for e in errs {
		if e.path == path {
			return e, true
		}
	}
	return {}, false
}
