// Example basic validates a sign-up form and prints every error. Run it with `odin run examples/basic`.
package main

import validate "../.."
import "core:fmt"

Address :: struct {
	street: string `validate:"required"`,
	zip:    string `validate:"required,len=5,numeric"`,
}

Signup :: struct {
	name:      string `validate:"required,min=3,max=64"`,
	email:     string `validate:"required,email"`,
	age:       int `validate:"gte=18,lte=130"`,
	role:      string `validate:"oneof=admin|member|guest"`,
	website:   string `validate:"omitempty,url"`,
	tags:      []string `validate:"max=3,dive,required,lowercase"`,
	addresses: []Address `validate:"min=1"`,
}

// lowercase is a custom rule: the string has no ASCII capital letters.
lowercase :: proc(value: any, param: string) -> bool {
	s, ok := value.(string)
	if !ok {
		return false
	}
	for c in transmute([]u8)s {
		if c >= 'A' && c <= 'Z' {
			return false
		}
	}
	return true
}

main :: proc() {
	v: validate.Validator
	validate.validator_init(&v)
	defer validate.validator_destroy(&v)
	if err := validate.register_rule(&v, "lowercase", lowercase); err != nil {
		fmt.eprintln("register_rule failed:", err)
		return
	}

	form := Signup {
		name      = "Al",
		email     = "al@example",
		age       = 17,
		role      = "owner",
		tags      = []string{"odin", "Systems"},
		addresses = []Address{{street = "1 Main St", zip = "1234x"}},
	}

	errs, ok := validate.validate_with(&v, &form)
	defer validate.field_errors_destroy(errs)

	if ok {
		fmt.println("form is valid")
		return
	}
	for e in errs {
		fmt.printf("%-16s %-10s %s\n", e.path, e.rule, e.message)
	}
}
