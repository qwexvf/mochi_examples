# mochi examples

Progressive examples for [mochi](https://github.com/qwexvf/mochi), a code-first GraphQL library for Gleam.

Each step is a self-contained file you can run independently.

## Steps

| Step | File | Topic |
|------|------|-------|
| 1 | `step1_basic.gleam` | One type, list query, single query, mutation |
| 2 | `step2_inputs.gleam` | Enums, input objects, optional arguments |
| 3 | `step3_auth.gleam` | Execution context, guards, bearer token |
| 4 | `step4_advanced_types.gleam` | Interfaces, unions, inline fragments |
| 5 | `step5_dataloader.gleam` | N+1 prevention with DataLoader |
| 6 | `step6_schema_splitting.gleam` | Modular schema with `query.merge` |
| 7 | `step7_subscriptions.gleam` | WebSocket subscriptions (graphql-ws) |

## Running

```sh
gleam deps download
gleam run -m step1_basic
gleam run -m step2_inputs
# ...and so on
```

## Codegen example

The `codegen/` directory is a standalone sub-project demonstrating the full
`mochi_codegen` workflow — schema splitting, TypeScript generation, Gleam resolver
stubs, and operation-based boilerplate from `.gql` files. Pre-generated output is
committed so you can read the results immediately.

```sh
cd codegen
gleam deps download
gleam run -m mochi_codegen/cli -- generate
```

See [`codegen/README.md`](codegen/README.md) for the full config reference.

## Requirements

- [Gleam](https://gleam.run) >= 1.0
- Erlang/OTP
