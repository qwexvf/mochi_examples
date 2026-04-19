// Step 1: Basic Schema
//
// The minimum viable mochi schema: one type, one query, one mutation.
// Run with: gleam run -m step1_basic

import gleam/io
import gleam/list
import gleam/result
import gleam/dynamic/decode
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types

// ── Domain type ───────────────────────────────────────────────────────────────

pub type User {
  User(id: String, name: String, age: Int)
}

// ── Data ──────────────────────────────────────────────────────────────────────

fn all_users() {
  [User("1", "Alice", 30), User("2", "Bob", 25), User("3", "Carol", 35)]
}

// ── Decoder + type ────────────────────────────────────────────────────────────

fn decode_user(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use age <- decode.field("age", decode.int)
    decode.success(User(id, name, age))
  })
  |> result.map_error(fn(_) { "failed to decode User" })
}

fn user_schema() {
  let builder =
    types.object("User")
    |> types.id("id", fn(u: User) { u.id })
    |> types.string("name", fn(u: User) { u.name })
    |> types.int("age", fn(u: User) { u.age })
  types.build_with_encoder(builder, decode_user)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(user_type, encode_user) = user_schema()

  // List query — no args
  let users_query =
    query.query(
      "users",
      schema.list_type(schema.named_type("User")),
      fn(_ctx) { Ok(all_users()) },
      fn(us) { types.to_dynamic(list.map(us, encode_user)) },
    )

  // Single query — requires id arg
  let get_user_query =
    query.query_with_args(
      name: "user",
      args: [query.arg("id", schema.non_null(schema.id_type()))],
      returns: schema.named_type("User"),
      decode: fn(args) { query.get_id(args, "id") },
      resolve: fn(id, _ctx) {
        list.find(all_users(), fn(u) { u.id == id })
        |> result.map_error(fn(_) { "User not found: " <> id })
      },
      encode: encode_user,
    )

  // Mutation — creates a new user
  let create_user_mutation =
    query.mutation(
      name: "createUser",
      args: [
        query.arg("name", schema.non_null(schema.string_type())),
        query.arg("age", schema.non_null(schema.int_type())),
      ],
      returns: schema.non_null(schema.named_type("User")),
      decode: fn(args) {
        use name <- result.try(query.get_string(args, "name"))
        use age <- result.try(query.get_int(args, "age"))
        Ok(#(name, age))
      },
      resolve: fn(input, _ctx) {
        let #(name, age) = input
        Ok(User("4", name, age))
      },
      encode: encode_user,
    )

  query.new()
  |> query.add_query(users_query)
  |> query.add_query(get_user_query)
  |> query.add_mutation(create_user_mutation)
  |> query.add_type(user_type)
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
  run(my_schema, "{ users { id name age } }")
  run(my_schema, "{ user(id: \"2\") { id name } }")
  run(my_schema, "mutation { createUser(name: \"Dan\", age: 22) { id name age } }")
  run(my_schema, "{ user(id: \"999\") { id name } }")
}
