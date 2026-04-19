# mochi_codegen example

Demonstrates the full mochi_codegen workflow: SDL schema → generated Gleam types,
resolver stubs, TypeScript definitions, and operation-based resolver boilerplate.

## Setup

```sh
gleam deps download
```

## Generate

```sh
gleam run -m mochi_codegen/cli -- generate
```

Output lands in `src/generated/`. The files there are pre-committed so you can
see what the generator produces before running it yourself.

## What's generated

| File | Source | Write policy |
|------|--------|-------------|
| `src/generated/types.ts` | all schema files | always overwrite |
| `src/generated/*_types.gleam` | per schema file | overwrite if changed |
| `src/generated/*_resolvers.gleam` | per schema file | append new stubs only |
| `src/generated/get_user_resolvers.gleam` | `src/graphql/get_user.gql` | append new stubs only |
| `src/generated/post_mutations_resolvers.gleam` | `src/graphql/post_mutations.gql` | append new stubs only |
| `src/generated/schema.graphql` | all schema files merged | always overwrite |

## Config reference (`mochi.config.yaml`)

```yaml
# Schema source — glob, single path, or list of globs
schema:
  - "graphql/*.graphql"

# Generate resolver stubs from .gql client operation files
operations_input: "src/graphql/**/*.gql"

output:
  typescript: "src/generated/types.ts"   # always overwritten
  gleam_types: "src/generated/"          # trailing "/" = one file per schema
  resolvers: "src/generated/"            # new functions appended, existing preserved
  operations: "src/generated/"           # from .gql files, same append policy
  sdl: "src/generated/schema.graphql"   # normalised SDL

gleam:
  types_module_prefix: "myapp/generated"
  resolvers_module_prefix: "myapp/generated"
  type_suffix: "_types"
  resolver_suffix: "_resolvers"
  resolver_imports:
    - "gleam/dict"
    - "mochi/schema.{type ExecutionContext}"
  generate_docs: true
```

## Re-generating safely

Resolver files (`*_resolvers.gleam`) use the `MergeNewFunctions` write policy:
- New resolver stubs are appended
- Existing function bodies are **never overwritten**

This means you can fill in the `TODO` bodies and re-run `generate` safely —
your implementations are preserved.
