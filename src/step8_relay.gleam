// Step 8: Relay Cursor Pagination
//
// Relay-style cursor-based pagination with mochi_relay/connections.
// Exposes UserConnection with edges, pageInfo, and totalCount.
//
// Run with: gleam run -m step8_relay

import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types
import mochi_relay/connections

// ── Domain type ───────────────────────────────────────────────────────────────

pub type User {
  User(id: String, name: String, age: Int)
}

// ── Data ──────────────────────────────────────────────────────────────────────

fn all_users() {
  [
    User("1", "Alice", 30),
    User("2", "Bob", 25),
    User("3", "Carol", 35),
    User("4", "Dan", 22),
    User("5", "Eve", 28),
  ]
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

// ── Pagination helper ─────────────────────────────────────────────────────────

fn paginate(
  items: List(User),
  first: Int,
  after: Option(String),
) -> connections.Connection(User) {
  let tail = case after {
    None -> items
    Some(cursor) ->
      case list.split_while(items, fn(u) { u.id != cursor }) {
        #(_, [_, ..rest]) -> rest
        _ -> []
      }
  }
  let page = list.take(tail, first)
  connections.from_list(
    page,
    fn(u) { u.id },
    has_next: list.length(tail) > first,
    has_prev: after != None,
    total: Some(list.length(items)),
  )
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(user_type, encode_user) = user_schema()

  // connection_types/1 returns (UserConnection, UserEdge, PageInfo) ObjectTypes
  let #(connection_type, edge_type, page_info_type) =
    connections.connection_types("User")

  let users_query =
    query.query_with_args(
      name: "users",
      args: [
        query.arg("first", schema.int_type()),
        query.arg("after", schema.string_type()),
        query.arg("last", schema.int_type()),
        query.arg("before", schema.string_type()),
      ],
      returns: schema.named_type("UserConnection"),
      decode: fn(args) {
        let first = query.get_optional_int(args, "first")
        let after = query.get_optional_string(args, "after")
        Ok(#(first, after))
      },
      resolve: fn(input, _ctx) {
        let #(first, after) = input
        Ok(paginate(all_users(), option.unwrap(first, 3), after))
      },
      encode: fn(conn) { connections.connection_to_dynamic(conn, encode_user) },
    )

  query.new()
  |> query.add_query(users_query)
  |> query.add_type(user_type)
  |> query.add_type(connection_type)
  |> query.add_type(edge_type)
  |> query.add_type(page_info_type)
  |> query.build
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn run(my_schema, gql) {
  io.println("\n> " <> gql)
  executor.execute_query(my_schema, gql)
  |> response.from_execution_result
  |> response.to_json
  |> io.println
}

pub fn main() {
  let my_schema = build_schema()

  // First page: 2 items
  run(
    my_schema,
    "{ users(first: 2) { edges { node { id name age } cursor } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }",
  )

  // Next page: after cursor "2"
  run(
    my_schema,
    "{ users(first: 2, after: \"2\") { edges { node { id name } cursor } pageInfo { hasNextPage hasPreviousPage } totalCount } }",
  )

  // Default page size (3)
  run(my_schema, "{ users { edges { node { name } } totalCount } }")
}
