// Step 2: Input Objects and Enums
//
// Builds on step 1: adds enums, input object types, and optional arguments.
// Run with: gleam run -m step2_inputs

import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/dynamic/decode
import mochi/error
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types

// ── Domain types ──────────────────────────────────────────────────────────────

pub type User {
  User(id: String, name: String, role: String, age: option.Option(Int))
}

// ── Enum ──────────────────────────────────────────────────────────────────────

fn role_enum() {
  types.enum_type("Role")
  |> types.value("ADMIN")
  |> types.value("MEMBER")
  |> types.build_enum
}

// ── Input object ──────────────────────────────────────────────────────────────

fn create_user_input() {
  types.input("CreateUserInput")
  |> types.input_string("name", "Full name of the user")
  |> types.input_string("role", "Role: ADMIN or MEMBER")
  |> types.input_optional_int("age", "Optional age in years")
  |> types.build_input
}

// ── User type ─────────────────────────────────────────────────────────────────

fn decode_user(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use role <- decode.field("role", decode.string)
    use age <- decode.optional_field("age", None, decode.optional(decode.int))
    decode.success(User(id, name, role, age))
  })
  |> result.map_error(fn(_) { "failed to decode User" })
}

fn user_schema() {
  let builder =
    types.object("User")
    |> types.id("id", fn(u: User) { u.id })
    |> types.string("name", fn(u: User) { u.name })
    |> types.string("role", fn(u: User) { u.role })
    |> types.optional_int("age", fn(u: User) { u.age })
  types.build_with_encoder(builder, decode_user)
}

// ── In-memory store ───────────────────────────────────────────────────────────

fn users() {
  [
    User("1", "Alice", "ADMIN", Some(30)),
    User("2", "Bob", "MEMBER", None),
  ]
}

// ── Queries ───────────────────────────────────────────────────────────────────

fn users_query(encode_user) {
  // Optional `limit` argument — returns at most N users
  query.query_with_args(
    name: "users",
    args: [query.arg("limit", schema.int_type())],
    returns: schema.list_type(schema.named_type("User")),
    resolve: fn(args, _ctx) {
      let limit = query.get_optional_int(args, "limit")
      let all = users()
      Ok(case limit {
        Some(n) -> list.take(all, n)
        None -> all
      })
    },
  )
  |> query.with_encoder(fn(us) { types.to_dynamic(list.map(us, encode_user)) })
}

// ── Mutations ─────────────────────────────────────────────────────────────────

fn create_user_mutation(encode_user) {
  // Decode the nested input object from the args dict
  query.mutation_with_args(
    name: "createUser",
    args: [
      query.arg("input", schema.non_null(schema.named_type("CreateUserInput"))),
    ],
    returns: schema.non_null(schema.named_type("User")),
    resolve: fn(args, _ctx) {
      use input_dyn <- result.try(
        dict.get(args, "input")
        |> result.map_error(fn(_) { error.new("Missing required argument: input") }),
      )
      use #(name, role, age) <- result.try(
        decode.run(input_dyn, {
          use name <- decode.field("name", decode.string)
          use role <- decode.field("role", decode.string)
          use age <- decode.optional_field("age", None, decode.optional(decode.int))
          decode.success(#(name, role, age))
        })
        |> result.map_error(fn(_) { error.new("Failed to decode CreateUserInput") }),
      )
      Ok(User(id: "3", name: name, role: role, age: age))
    },
  )
  |> query.with_encoder(encode_user)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(user_type, encode_user) = user_schema()

  query.new()
  |> query.add_query(users_query(encode_user))
  |> query.add_mutation(create_user_mutation(encode_user))
  |> query.add_type(user_type)
  |> query.add_enum(role_enum())
  |> query.add_input(create_user_input())
  |> query.build
}

fn run(my_schema, gql) {
  io.println("\n> " <> gql)
  executor.execute_query(my_schema, gql)
  |> response.from_execution_result
  |> response.to_json
  |> io.println
}

pub fn main() {
  let my_schema = build_schema()

  run(my_schema, "{ users { id name role age } }")
  run(my_schema, "{ users(limit: 1) { id name } }")
  run(
    my_schema,
    "mutation { createUser(input: { name: \"Eve\", role: \"ADMIN\" }) { id name role age } }",
  )
}
