package validate

import "base:runtime"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// Builtin names every rule and keyword the package understands without a Validator.
@(private)
Builtin :: enum {
	None,
	Required,
	Omitempty,
	Dive,
	Min,
	Max,
	Len,
	Gt,
	Gte,
	Lt,
	Lte,
	Oneof,
	Email,
	Url,
	Uuid,
	Alpha,
	Alnum,
	Numeric,
	Hex,
	Prefix,
	Suffix,
	Contains,
}

@(private)
builtin_from_name :: proc(name: string) -> Builtin {
	switch name {
	case "required":
		return .Required
	case "omitempty":
		return .Omitempty
	case "dive":
		return .Dive
	case "min":
		return .Min
	case "max":
		return .Max
	case "len":
		return .Len
	case "gt":
		return .Gt
	case "gte":
		return .Gte
	case "lt":
		return .Lt
	case "lte":
		return .Lte
	case "oneof":
		return .Oneof
	case "email":
		return .Email
	case "url":
		return .Url
	case "uuid":
		return .Uuid
	case "alpha":
		return .Alpha
	case "alnum":
		return .Alnum
	case "numeric":
		return .Numeric
	case "hex":
		return .Hex
	case "prefix":
		return .Prefix
	case "suffix":
		return .Suffix
	case "contains":
		return .Contains
	}
	return .None
}

@(private)
is_name_char :: proc(c: u8) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '_':
		return true
	}
	return false
}

@(private)
Check :: enum {
	Pass,
	Fail,
	Malformed,
	Unsupported,
}

/*
Outcome is the verdict of one built-in rule plus the pieces of its message.
For Fail the message is `path before [rule] [param] after`; for Malformed,
`before` holds the reason.
*/
@(private)
Outcome :: struct {
	result:     Check,
	before:     string,
	after:      string,
	show_param: bool,
	show_rule:  bool,
	list_param: bool,
}

@(private)
Value_Kind :: enum {
	Other,
	String,
	Collection,
	Integer,
	Float,
	Enum,
}

@(private)
classify :: proc(v: any) -> Value_Kind {
	ti := runtime.type_info_base(type_info_of(v.id))
	#partial switch _ in ti.variant {
	case runtime.Type_Info_String:
		if _, ok := reflect.as_string(v); ok {
			return .String
		}
	case runtime.Type_Info_Integer, runtime.Type_Info_Rune:
		return .Integer
	case runtime.Type_Info_Float:
		return .Float
	case runtime.Type_Info_Array, runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Map:
		return .Collection
	case runtime.Type_Info_Enum:
		return .Enum
	}
	return .Other
}

/*
Number holds an integer or float field value, or a parsed parameter, for
comparison. `huge` marks an unsigned 128-bit value above max(i128); it is
greater than every parameter, because parameters parse as i128.
*/
@(private)
Number :: struct {
	is_float: bool,
	huge:     bool,
	i:        i128,
	f:        f64,
}

@(private)
number_of :: proc(v: any, kind: Value_Kind) -> (n: Number, ok: bool) {
	if kind == .Float {
		n.is_float = true
		n.f, ok = reflect.as_f64(v)
		return
	}
	ti := runtime.type_info_core(type_info_of(v.id))
	if ti.size == 16 {
		// reflect.as_i64 and as_u64 truncate 128-bit values, so read them directly.
		ok = true
		core := any{v.data, ti.id}
		switch x in core {
		case i128:
			n.i = x
		case i128le:
			n.i = i128(x)
		case i128be:
			n.i = i128(x)
		case u128:
			n.i, n.huge = u128_number(x)
		case u128le:
			n.i, n.huge = u128_number(u128(x))
		case u128be:
			n.i, n.huge = u128_number(u128(x))
		case:
			ok = false
		}
		return
	}
	signed := true
	if info, is_int := ti.variant.(runtime.Type_Info_Integer); is_int {
		signed = info.signed
	}
	if signed {
		x: i64
		x, ok = reflect.as_i64(v)
		n.i = i128(x)
	} else {
		x: u64
		x, ok = reflect.as_u64(v)
		n.i = i128(x)
	}
	return
}

@(private)
u128_number :: proc(x: u128) -> (i: i128, huge: bool) {
	if x > u128(max(i128)) {
		return max(i128), true
	}
	return i128(x), false
}

// parse_number parses `s` as a whole integer, or as a float when `as_float` is set.
@(private)
parse_number :: proc(s: string, as_float: bool) -> (n: Number, ok: bool) {
	if s == "" {
		return
	}
	used: int
	if as_float {
		n.is_float = true
		n.f, ok = strconv.parse_f64(s, &used)
	} else {
		n.i, ok = strconv.parse_i128_of_base(s, 10, &used)
	}
	return n, ok && used == len(s)
}

@(private)
compare_numbers :: proc(a, b: Number) -> int {
	if a.is_float {
		switch {
		case a.f < b.f:
			return -1
		case a.f > b.f:
			return 1
		case a.f == b.f:
			return 0
		}
		return 2 // NaN compares as nothing; every comparison then fails.
	}
	if a.huge != b.huge {
		return 1 if a.huge else -1
	}
	switch {
	case a.i < b.i:
		return -1
	case a.i > b.i:
		return 1
	}
	return 0
}

@(private)
malformed :: proc(reason: string) -> Outcome {
	return {result = .Malformed, before = reason}
}

@(private)
unsupported :: proc() -> Outcome {
	return {result = .Unsupported}
}

@(private)
verdict :: proc(pass: bool, fail: Outcome) -> Outcome {
	if pass {
		return {}
	}
	out := fail
	out.result = .Fail
	return out
}

// check_builtin runs one built-in rule other than required, omitempty and dive against `v`.
@(private)
check_builtin :: proc(b: Builtin, v: any, param: string, has_param: bool) -> Outcome {
	#partial switch b {
	case .Email, .Url, .Uuid, .Alpha, .Alnum, .Numeric, .Hex:
		if has_param {
			return malformed("doesn't take a parameter")
		}
		s, is_string := reflect.as_string(v)
		if !is_string {
			return unsupported()
		}
		#partial switch b {
		case .Email:
			return verdict(is_email(s), {before = "must be a valid email address"})
		case .Url:
			return verdict(is_url(s), {before = "must be a valid URL"})
		case .Uuid:
			return verdict(is_uuid(s), {before = "must be a valid UUID"})
		case .Alpha:
			return verdict(is_alpha(s), {before = "must contain only ASCII letters"})
		case .Alnum:
			return verdict(is_alnum(s), {before = "must contain only ASCII letters and digits"})
		case .Numeric:
			return verdict(is_numeric(s), {before = "must be a number"})
		case .Hex:
			return verdict(is_hex(s), {before = "must be a hexadecimal number"})
		}
	}

	if !has_param || param == "" {
		return malformed("needs a parameter, for example min=3")
	}

	#partial switch b {
	case .Prefix, .Suffix, .Contains:
		s, is_string := reflect.as_string(v)
		if !is_string {
			return unsupported()
		}
		#partial switch b {
		case .Prefix:
			return verdict(strings.has_prefix(s, param), {before = "must start with \"", show_param = true, after = "\""})
		case .Suffix:
			return verdict(strings.has_suffix(s, param), {before = "must end with \"", show_param = true, after = "\""})
		case .Contains:
			return verdict(strings.contains(s, param), {before = "must contain \"", show_param = true, after = "\""})
		}
	case .Oneof:
		return check_oneof(v, param)
	case .Min, .Max, .Len, .Gt, .Gte, .Lt, .Lte:
		return check_compare(b, v, param)
	}
	return unsupported()
}

@(private)
check_oneof :: proc(v: any, param: string) -> Outcome {
	kind := classify(v)
	if kind != .String && kind != .Integer && kind != .Float && kind != .Enum {
		return unsupported()
	}
	value: Number
	text: string
	switch kind {
	case .String:
		text, _ = reflect.as_string(v)
	case .Enum:
		text, _ = reflect.enum_name_from_value_any(v)
	case .Integer, .Float:
		value, _ = number_of(v, kind)
	case .Collection, .Other:
	}

	found := false
	rest := param
	for opt in strings.split_iterator(&rest, "|") {
		if opt == "" {
			return malformed("has an empty option")
		}
		switch kind {
		case .String, .Enum:
			if opt == text {
				found = true
			}
		case .Integer, .Float:
			want, ok := parse_number(opt, kind == .Float)
			if !ok {
				return malformed("has an option that isn't a number")
			}
			if compare_numbers(value, want) == 0 {
				found = true
			}
		case .Collection, .Other:
		}
	}
	return verdict(found, {before = "must be one of ", list_param = true})
}

@(private)
check_compare :: proc(b: Builtin, v: any, param: string) -> Outcome {
	kind := classify(v)
	got, want: Number
	switch kind {
	case .String, .Collection:
		count, ok := parse_number(param, false)
		if !ok || count.i < 0 {
			return malformed("needs a non-negative integer parameter")
		}
		want = count
		if kind == .String {
			s, _ := reflect.as_string(v)
			got.i = i128(utf8.rune_count_in_string(s))
		} else {
			got.i = i128(reflect.length(v))
		}
	case .Integer, .Float:
		ok: bool
		want, ok = parse_number(param, kind == .Float)
		if !ok {
			if kind == .Float {
				return malformed("needs a number parameter")
			}
			return malformed("needs an integer parameter")
		}
		got, _ = number_of(v, kind)
	case .Enum, .Other:
		return unsupported()
	}

	c := compare_numbers(got, want)
	pass: bool
	#partial switch b {
	case .Min, .Gte:
		pass = c == 0 || c == 1
	case .Max, .Lte:
		pass = c <= 0
	case .Gt:
		pass = c == 1
	case .Lt:
		pass = c == -1
	case .Len:
		pass = c == 0
	}
	if pass {
		return {}
	}

	one := param == "1"
	out := Outcome {
		result     = .Fail,
		show_param = true,
	}
	switch kind {
	case .String:
		unit := " characters" if !one else " character"
		#partial switch b {
		case .Min, .Gte:
			out.before, out.after = "must be at least ", unit
		case .Max, .Lte:
			out.before, out.after = "must be at most ", unit
		case .Gt:
			out.before, out.after = "must be longer than ", unit
		case .Lt:
			out.before, out.after = "must be shorter than ", unit
		case .Len:
			out.before, out.after = "must be exactly ", unit
		}
		if b != .Gt && b != .Lt {
			out.after = " characters long" if !one else " character long"
		}
	case .Collection:
		unit := " items" if !one else " item"
		out.after = unit
		#partial switch b {
		case .Min, .Gte:
			out.before = "must contain at least "
		case .Max, .Lte:
			out.before = "must contain at most "
		case .Gt:
			out.before = "must contain more than "
		case .Lt:
			out.before = "must contain fewer than "
		case .Len:
			out.before = "must contain exactly "
		}
	case .Integer, .Float, .Enum, .Other:
		#partial switch b {
		case .Min, .Gte:
			out.before = "must be at least "
		case .Max, .Lte:
			out.before = "must be at most "
		case .Gt:
			out.before = "must be greater than "
		case .Lt:
			out.before = "must be less than "
		case .Len:
			out.before = "must equal "
		}
	}
	return out
}
