# crates_filter

EmergenceSystem filter that searches crates.io for Rust packages. No API key required.

## Input

```json
{"query": "serde"}
```

| Field     | Type    | Default | Description              |
|-----------|---------|---------|--------------------------|
| `query`   | string  | —       | Package name or keyword  |
| `timeout` | integer | `10`    | HTTP timeout in seconds  |

## Output

Up to 10 embryos, one per crate:

```json
{
  "properties": {
    "url":       "https://crates.io/crates/serde",
    "resume":    "A generic serialization/deserialization framework v1.0.193 — 250000000 downloads",
    "title":     "serde",
    "version":   "1.0.193",
    "downloads": 250000000,
    "source":    "crates.io"
  }
}
```

## Capabilities

`crates`, `rust`, `packages`, `cargo`

## Usage

```bash
rebar3 shell
```

## License

Apache-2.0
