# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- `validate`, `validate_with` and `validate_any` check a value against the rules in its `validate:"..."` struct tags and return every failure as a `Field_Error` with a dotted path, rule name, parameter and English message.
- Built-in rules: `required`, `omitempty`, `min`, `max`, `len`, `gt`, `gte`, `lt`, `lte`, `oneof`, `email`, `url`, `uuid`, `alpha`, `alnum`, `numeric`, `hex`, `prefix`, `suffix`, `contains` and `dive`.
- Recursion into nested structs, slices, dynamic and fixed arrays, pointers and unions such as `Maybe(T)`.
- `Validator` with `register_rule` for custom rules, `path_tag` for paths built from another tag such as `json`, and `max_depth`.
- Malformed tags, unknown rules and rules on unsupported types come back as typed errors instead of panics.
- `field_errors_destroy` and `error_for` helpers.
- Standalone format checks: `is_email`, `is_url`, `is_uuid`, `is_alpha`, `is_alnum`, `is_numeric` and `is_hex`.

[Unreleased]: https://github.com/alexisbcz/odin-validate/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-validate/releases/tag/v0.1.0
