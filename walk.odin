package validate

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

// Walker carries the state of one validate_any call.
@(private)
Walker :: struct {
	validator:     ^Validator,
	allocator:     runtime.Allocator,
	errs:          [dynamic]Field_Error,
	path:          strings.Builder,
	depth:         int,
	max_depth:     int,
	out_of_memory: bool,
}

// Tag_Iter splits a tag on commas and remembers whether a trailing empty rule is left.
@(private)
Tag_Iter :: struct {
	rest: string,
	done: bool,
}

// tag_next returns the next comma separated rule, trimmed of spaces.
@(private)
tag_next :: proc(it: ^Tag_Iter) -> (rule: string, more: bool) {
	if it.done {
		return "", false
	}
	i := strings.index_byte(it.rest, ',')
	if i < 0 {
		rule = it.rest
		it.rest = ""
		it.done = true
	} else {
		rule = it.rest[:i]
		it.rest = it.rest[i + 1:]
	}
	return strings.trim_space(rule), true
}

// split_rule splits `min=3` into `min`, `3` and true.
@(private)
split_rule :: proc(rule: string) -> (name, param: string, has_param: bool) {
	i := strings.index_byte(rule, '=')
	if i < 0 {
		return rule, "", false
	}
	return strings.trim_space(rule[:i]), rule[i + 1:], true
}

// push_segment appends a path segment and returns the previous path length.
@(private)
push_segment :: proc(w: ^Walker, name: string, index: int = -1) -> (mark: int, ok: bool) {
	mark = strings.builder_len(w.path)
	if index >= 0 {
		fmt.sbprintf(&w.path, "[%d]", index)
		if strings.builder_len(w.path) < mark + 3 {
			w.out_of_memory = true
		}
	} else {
		want := mark + len(name)
		if mark > 0 {
			strings.write_byte(&w.path, '.')
			want += 1
		}
		strings.write_string(&w.path, name)
		if strings.builder_len(w.path) != want {
			w.out_of_memory = true
		}
	}
	w.depth += 1
	if w.depth > w.max_depth {
		report_too_deep(w)
		pop_segment(w, mark)
		return mark, false
	}
	return mark, true
}

@(private)
pop_segment :: proc(w: ^Walker, mark: int) {
	resize(&w.path.buf, mark)
	w.depth -= 1
}

// report appends one error. The message is the path followed by the given pieces.
@(private)
report :: proc(w: ^Walker, kind: Field_Error_Kind, rule, param: string, out: Outcome, value_type: ^runtime.Type_Info = nil) {
	path := strings.to_string(w.path)
	b := strings.builder_make(w.allocator)
	switch kind {
	case .Rule_Failed:
		strings.write_string(&b, path)
		strings.write_byte(&b, ' ')
		strings.write_string(&b, out.before)
		if out.show_rule {
			strings.write_string(&b, rule)
		}
		if out.list_param {
			write_options(&b, param)
		} else if out.show_param {
			strings.write_string(&b, param)
		}
		strings.write_string(&b, out.after)
	case .Malformed_Tag:
		fmt.sbprintf(&b, "invalid tag on %s: ", path)
		if rule == "" {
			strings.write_string(&b, "empty rule name")
		} else {
			fmt.sbprintf(&b, "rule %q %s", rule, out.before)
		}
	case .Unknown_Rule:
		fmt.sbprintf(&b, "invalid tag on %s: unknown rule %q", path, rule)
	case .Unsupported_Type:
		fmt.sbprintf(&b, "invalid tag on %s: rule %q doesn't apply to %v", path, rule, value_type.id if value_type != nil else nil)
	case .Too_Deep:
		fmt.sbprintf(&b, "%s nests more than %d levels deep", path, w.max_depth)
	}
	message := strings.to_string(b)
	owned_path, perr := strings.clone(path, w.allocator)
	if perr != nil || len(message) == 0 {
		delete(owned_path, w.allocator)
		strings.builder_destroy(&b)
		w.out_of_memory = true
		return
	}
	_, aerr := append(&w.errs, Field_Error{kind = kind, path = owned_path, rule = rule, param = param, message = message})
	if aerr != nil {
		delete(owned_path, w.allocator)
		strings.builder_destroy(&b)
		w.out_of_memory = true
	}
}

@(private)
report_too_deep :: proc(w: ^Walker) {
	report(w, .Too_Deep, "", "", {})
}

// write_options writes `a|b|c` as `a, b, c`.
@(private)
write_options :: proc(b: ^strings.Builder, param: string) {
	rest := param
	first := true
	for opt in strings.split_iterator(&rest, "|") {
		if !first {
			strings.write_string(b, ", ")
		}
		strings.write_string(b, opt)
		first = false
	}
}

// walk_value visits everything inside `v` that can carry tags, without applying rules to `v` itself.
@(private)
walk_value :: proc(w: ^Walker, v: any) {
	if v.data == nil || v.id == nil {
		return
	}
	ti := runtime.type_info_base(type_info_of(v.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		walk_struct(w, v, info)
	case runtime.Type_Info_Pointer:
		if info.elem == nil {
			return
		}
		p := (^rawptr)(v.data)^
		if p != nil {
			walk_value(w, any{p, info.elem.id})
		}
	case runtime.Type_Info_Union:
		inner := union_value(v, info)
		if inner.data != nil {
			walk_value(w, inner)
		}
	case runtime.Type_Info_Array:
		walk_elems(w, v.data, info.count, info.elem, info.elem_size, "")
	case runtime.Type_Info_Enumerated_Array:
		walk_elems(w, v.data, info.count, info.elem, info.elem_size, "")
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(v.data)^
		walk_elems(w, raw.data, raw.len, info.elem, info.elem_size, "")
	case runtime.Type_Info_Dynamic_Array:
		raw := (^runtime.Raw_Dynamic_Array)(v.data)^
		walk_elems(w, raw.data, raw.len, info.elem, info.elem_size, "")
	}
}

// walk_elems checks each element with `rules`, or only walks them when `rules` is empty.
@(private)
walk_elems :: proc(w: ^Walker, data: rawptr, count: int, elem: ^runtime.Type_Info, elem_size: int, rules: string, dive := false) {
	if data == nil || count <= 0 || elem == nil {
		return
	}
	if !dive && !may_contain_rules(elem) {
		return
	}
	for i in 0 ..< count {
		e := any{rawptr(uintptr(data) + uintptr(i * elem_size)), elem.id}
		mark, ok := push_segment(w, "", i)
		if !ok {
			return
		}
		check_field(w, e, rules)
		pop_segment(w, mark)
	}
}

// may_contain_rules reports whether a value of type `ti` can hold tagged fields, so plain data is skipped quickly.
@(private)
may_contain_rules :: proc(ti: ^runtime.Type_Info, depth := 0) -> bool {
	if ti == nil {
		return false
	}
	if depth > 16 {
		return true
	}
	base := runtime.type_info_base(ti)
	#partial switch info in base.variant {
	case runtime.Type_Info_Struct:
		return true
	case runtime.Type_Info_Pointer:
		return may_contain_rules(info.elem, depth + 1)
	case runtime.Type_Info_Union:
		for variant in info.variants {
			if may_contain_rules(variant, depth + 1) {
				return true
			}
		}
	case runtime.Type_Info_Array:
		return may_contain_rules(info.elem, depth + 1)
	case runtime.Type_Info_Enumerated_Array:
		return may_contain_rules(info.elem, depth + 1)
	case runtime.Type_Info_Slice:
		return may_contain_rules(info.elem, depth + 1)
	case runtime.Type_Info_Dynamic_Array:
		return may_contain_rules(info.elem, depth + 1)
	}
	return false
}

@(private)
walk_struct :: proc(w: ^Walker, v: any, info: runtime.Type_Info_Struct) {
	if .raw_union in info.flags || info.soa_kind != .None {
		return
	}
	for i in 0 ..< int(info.field_count) {
		name := info.names[i]
		if name == "_" {
			continue
		}
		tags := reflect.Struct_Tag(info.tags[i])
		rules := reflect.struct_tag_get(tags, TAG_KEY)
		if strings.trim_space(rules) == "-" {
			continue
		}
		segment := name
		if w.validator != nil && w.validator.path_tag != "" {
			if alias, found := reflect.struct_tag_lookup(tags, w.validator.path_tag); found {
				if comma := strings.index_byte(alias, ','); comma >= 0 {
					alias = alias[:comma]
				}
				if alias != "" && alias != "-" {
					segment = alias
				}
			}
		}
		field := any{rawptr(uintptr(v.data) + info.offsets[i]), info.types[i].id}
		mark, ok := push_segment(w, segment)
		if !ok {
			return
		}
		check_field(w, field, rules)
		pop_segment(w, mark)
	}
}

// check_field applies `rules` to `v`, then walks what `v` contains.
@(private)
check_field :: proc(w: ^Walker, v: any, rules: string) {
	if strings.trim_space(rules) == "" {
		walk_value(w, v)
		return
	}
	it := Tag_Iter {
		rest = rules,
	}
	for {
		rule, more := tag_next(&it)
		if !more {
			break
		}
		name, param, has_param := split_rule(rule)
		if name == "" {
			report(w, .Malformed_Tag, "", param, {})
			break
		}
		b := builtin_from_name(name)
		#partial switch b {
		case .Omitempty, .Required, .Dive:
			if has_param {
				report(w, .Malformed_Tag, name, param, {before = "doesn't take a parameter"})
				walk_value(w, v)
				return
			}
		}
		#partial switch b {
		case .Omitempty:
			if is_zero(v) {
				return
			}
			continue
		case .Required:
			if is_zero(v) {
				report(w, .Rule_Failed, name, param, {before = "is required"})
				return
			}
			continue
		case .Dive:
			dive(w, v, name, it.rest if !it.done else "")
			return
		}

		target, present := unwrap(v)
		if !present {
			// A nil pointer or union has nothing to check; only required can fail.
			continue
		}

		if b == .None {
			custom: Rule_Proc
			if w.validator != nil {
				custom = w.validator.rules[name]
			}
			if custom == nil {
				report(w, .Unknown_Rule, name, param, {})
				break
			}
			if !custom(target, param) {
				report(w, .Rule_Failed, name, param, {before = "failed the \"", show_rule = true, after = "\" rule"})
				break
			}
			continue
		}

		out := check_builtin(b, target, param, has_param)
		switch out.result {
		case .Pass:
			continue
		case .Fail:
			report(w, .Rule_Failed, name, param, out)
		case .Malformed:
			report(w, .Malformed_Tag, name, param, out)
		case .Unsupported:
			report(w, .Unsupported_Type, name, param, out, type_info_of(target.id))
		}
		break
	}
	walk_value(w, v)
}

// dive applies `rules` to every element of the slice or array in `v`.
@(private)
dive :: proc(w: ^Walker, v: any, name, rules: string) {
	target, present := unwrap(v)
	if !present {
		return
	}
	ti := runtime.type_info_base(type_info_of(target.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Array:
		walk_elems(w, target.data, info.count, info.elem, info.elem_size, rules, true)
	case runtime.Type_Info_Enumerated_Array:
		walk_elems(w, target.data, info.count, info.elem, info.elem_size, rules, true)
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(target.data)^
		walk_elems(w, raw.data, raw.len, info.elem, info.elem_size, rules, true)
	case runtime.Type_Info_Dynamic_Array:
		raw := (^runtime.Raw_Dynamic_Array)(target.data)^
		walk_elems(w, raw.data, raw.len, info.elem, info.elem_size, rules, true)
	case:
		report(w, .Unsupported_Type, name, "", {}, type_info_of(target.id))
	}
}

// union_value returns the variant a union holds, or a nil any when it holds none.
@(private)
union_value :: proc(v: any, info: runtime.Type_Info_Union) -> any {
	if len(info.variants) == 0 || v.data == nil {
		return nil
	}
	if reflect.type_info_union_is_pure_maybe(info) {
		// Maybe(^T) stores no tag; the pointer itself is nil or not.
		if (^rawptr)(v.data)^ == nil {
			return nil
		}
		return any{v.data, info.variants[0].id}
	}
	if info.tag_type == nil {
		return nil
	}
	tag, ok := reflect.as_i64(any{rawptr(uintptr(v.data) + info.tag_offset), info.tag_type.id})
	if !ok {
		return nil
	}
	if !info.no_nil {
		if tag == 0 {
			return nil
		}
		tag -= 1
	}
	if tag < 0 || tag >= i64(len(info.variants)) {
		return nil
	}
	return any{v.data, info.variants[tag].id}
}

// unwrap follows pointers and unions to the value they hold. present is false when one of them is nil.
@(private)
unwrap :: proc(v: any) -> (target: any, present: bool) {
	target = v
	for _ in 0 ..< 16 {
		if target.data == nil || target.id == nil {
			return target, false
		}
		ti := runtime.type_info_base(type_info_of(target.id))
		#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
			if info.elem == nil {
				return target, true
			}
			p := (^rawptr)(target.data)^
			if p == nil {
				return target, false
			}
			target = any{p, info.elem.id}
		case runtime.Type_Info_Union:
			inner := union_value(target, info)
			if inner.data == nil {
				return target, false
			}
			target = inner
		case:
			return target, true
		}
	}
	return target, true
}

// is_zero reports whether `v` holds its type's zero value, treating empty strings, slices and maps as zero.
@(private)
is_zero :: proc(v: any) -> bool {
	if v.data == nil || v.id == nil {
		return true
	}
	ti := runtime.type_info_base(type_info_of(v.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		if s, ok := reflect.as_string(v); ok {
			return len(s) == 0
		}
	case runtime.Type_Info_Slice:
		return (^runtime.Raw_Slice)(v.data).len == 0
	case runtime.Type_Info_Dynamic_Array:
		return (^runtime.Raw_Dynamic_Array)(v.data).len == 0
	case runtime.Type_Info_Map:
		return reflect.length(v) == 0
	case runtime.Type_Info_Pointer:
		return (^rawptr)(v.data)^ == nil
	case runtime.Type_Info_Union:
		return union_value(v, info).data == nil
	}
	bytes := ([^]u8)(v.data)[:ti.size]
	for c in bytes {
		if c != 0 {
			return false
		}
	}
	return true
}
