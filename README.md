# validate

[![CI](https://github.com/alexisbcz/odin-validate/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-validate/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Struct validation driven by `validate:"..."` tags for Odin, in the spirit of Go's go-playground/validator and TypeScript's zod. Describe the rules next to the fields, call `validate.validate(&value)`, and get back every failure with a path such as `user.addresses[2].zip` and a readable message.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-validate libs/validate
```

```odin
import "libs/validate"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-validate ~/odin-shared/validate
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:validate"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:validate"

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
	addresses: []Address `validate:"min=1"`,
}

main :: proc() {
	form := Signup {
		name      = "Al",
		email     = "al@example",
		age       = 17,
		role      = "owner",
		addresses = []Address{{street = "1 Main St", zip = "1234x"}},
	}

	errs, ok := validate.validate(&form)
	defer validate.field_errors_destroy(errs)
	if !ok {
		for e in errs {
			fmt.println(e.message)
		}
	}
}
```

The program prints one line per failed field, in field order:

```text
name must be at least 3 characters long
email must be a valid email address
age must be at least 18
role must be one of admin, member, guest
addresses[0].zip must be a number
```

Each `Field_Error` also carries a `kind`, the `rule` name and its `param`, so you can write your own messages or translate them.

## Rules

A tag is a comma separated list of rules. A rule is a name, optionally followed by `=` and a parameter.

| Rule | Applies to | Passes when |
| --- | --- | --- |
| `required` | any type | the value isn't zero: not `0`, `false`, `""`, empty, or nil |
| `omitempty` | any type | always; when the value is zero, validation skips the remaining rules and nested fields |
| `min=n`, `max=n` | strings, collections, numbers | length or value is at least or at most `n` |
| `len=n` | strings, collections, numbers | length or value is exactly `n` |
| `gt=n`, `gte=n`, `lt=n`, `lte=n` | strings, collections, numbers | length or value is greater, greater or equal, less, less or equal |
| `oneof=a\|b\|c` | strings, numbers, enums | the value, or the enum member name, is one of the options |
| `email`, `url`, `uuid` | strings | the string has that format |
| `alpha`, `alnum`, `numeric`, `hex` | strings | the string holds only letters, letters and digits, a decimal number, or a hexadecimal number |
| `prefix=s`, `suffix=s`, `contains=s` | strings | the string starts with, ends with, or contains `s` |
| `dive` | slices and arrays | the rules after `dive` apply to each element |

Some details worth knowing:

- String lengths count runes, so `"été"` has length 3.
- Collections are slices, dynamic arrays, fixed arrays and maps.
- Rules on a field run in order and stop at the first failure, so an empty name reports `required` and not also `min`.
- Format rules fail on the empty string. Put `omitempty` first for optional fields.
- For pointers and unions such as `Maybe(T)`, `required` checks for nil, and the other rules apply to the value inside. When there is no value inside, only `required` can fail.
- A tag of `-` skips the field and everything inside it.
- Validation walks nested structs, slices, arrays, pointers and unions even without a tag. Map contents aren't, because map order isn't stable.

## Custom rules

Register rules on a `Validator` and run them with `validate_with`. The package keeps no global registry, so two parts of a program never fight over rule names.

```odin
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

v: validate.Validator
validate.validator_init(&v)
defer validate.validator_destroy(&v)
if err := validate.register_rule(&v, "lowercase", lowercase); err != nil {
	fmt.eprintln("register_rule failed:", err)
	return
}

errs, ok := validate.validate_with(&v, &form)
defer validate.field_errors_destroy(errs)
```

A rule receives the field value, or the value a pointer or union holds, and the text after `=` in the tag. Set `v.path_tag = "json"` to build paths from `json` tag names instead of Odin field names.

## Malformed tags

A broken tag never panics. It becomes a `Field_Error` whose `kind` says what went wrong:

| Kind | Example tag | Message |
| --- | --- | --- |
| `.Malformed_Tag` | `validate:"min"` | `invalid tag on name: rule "min" needs a parameter, for example min=3` |
| `.Unknown_Rule` | `validate:"even"` | `invalid tag on n: unknown rule "even"` |
| `.Unsupported_Type` | `validate:"email"` on an `int` | `invalid tag on a: rule "email" doesn't apply to int` |
| `.Too_Deep` | a pointer cycle | `next.next.name nests more than 64 levels deep` |

Write a test that validates a zero value of each tagged type to catch tag mistakes early.

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `validate(&value, allocator)` | Check a value against the built-in rules | Yes, when there are errors | `field_errors_destroy` |
| `validate_with(&v, &value, allocator)` | Same, with custom rules and options | Yes, when there are errors | `field_errors_destroy` |
| `validate_any(value, v, allocator)` | Same, for an `any` | Yes, when there are errors | `field_errors_destroy` |
| `field_errors_destroy(errs, allocator)` | Free an error slice and its strings | No | Not needed |
| `error_for(errs, path)` | Find the error for one path | No | Not needed |
| `Validator` | Custom rules, `path_tag` and `max_depth` | Not by itself | `validator_destroy` |
| `validator_init(&v, allocator)` | Prepare a `Validator` | Yes | `validator_destroy` |
| `register_rule(&v, name, rule)` | Add a custom rule; copies the name | Yes | `validator_destroy` |
| `is_email`, `is_url`, `is_uuid`, `is_alpha`, `is_alnum`, `is_numeric`, `is_hex` | The format checks on their own | No | Not needed |

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Validation reads the value and never changes it.
- Every allocating procedure takes `allocator := context.allocator`. The returned slice and each error's `path` and `message` belong to the caller; `rule` and `param` point into the program's static type table.
- `ok` is false whenever validation finds errors, and also when an allocation fails, so a failing allocator can't make bad input pass.
- Custom rules live in a `Validator` value rather than global state. Register them all before validating; after that, several threads may share one `Validator`.
- Validation uses `core:reflect`, so it costs more than hand-written checks. It's meant for input at the edges of a program, such as request bodies and configuration files.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
