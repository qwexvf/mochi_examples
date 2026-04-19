// Step 9: Automatic Persisted Queries (APQ)
//
// APQ reduces bandwidth: after the first exchange, clients send a SHA-256 hash
// instead of the full query string. The server looks it up in a store.
//
// Flow:
//   Request 1 (cold)    — hash only       → PersistedQueryNotFound (error)
//   Request 2 (register)— hash + query    → stored, then executed
//   Request 3 (warm)    — hash only       → cache hit, executed directly
//
// In production, hold PersistedQueryStore in a shared ETS table or OTP agent
// so it survives across HTTP requests.
//
// Run with: gleam run -m step9_apq

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types
import mochi_apq/persisted_queries

// ── Domain type ───────────────────────────────────────────────────────────────

pub type User {
  User(id: String, name: String)
}

// ── Decoder + type ────────────────────────────────────────────────────────────

fn decode_user(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    decode.success(User(id, name))
  })
  |> result.map_error(fn(_) { "failed to decode User" })
}

fn user_schema() {
  let builder =
    types.object("User")
    |> types.id("id", fn(u: User) { u.id })
    |> types.string("name", fn(u: User) { u.name })
  types.build_with_encoder(builder, decode_user)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(user_type, encode_user) = user_schema()

  let users_query =
    query.query(
      "users",
      schema.list_type(schema.named_type("User")),
      fn(_ctx) { Ok([User("1", "Alice"), User("2", "Bob"), User("3", "Carol")]) },
      fn(us) { types.to_dynamic(list.map(us, encode_user)) },
    )

  query.new()
  |> query.add_query(users_query)
  |> query.add_type(user_type)
  |> query.build
}

// ── APQ request handler ───────────────────────────────────────────────────────

fn handle_apq(
  store: persisted_queries.PersistedQueryStore,
  my_schema,
  query_opt,
  hash: String,
) -> #(persisted_queries.PersistedQueryStore, String) {
  case persisted_queries.process_apq(store, query_opt, hash) {
    Error(persisted_queries.PersistedQueryNotFound) -> #(
      store,
      "{\"errors\":[{\"message\":\"PersistedQueryNotFound\"}]}",
    )
    Error(persisted_queries.HashMismatch(_, _)) -> #(
      store,
      "{\"errors\":[{\"message\":\"Hash mismatch\"}]}",
    )
    Error(persisted_queries.InvalidHash) -> #(
      store,
      "{\"errors\":[{\"message\":\"Invalid hash\"}]}",
    )
    Ok(#(new_store, resolved)) -> {
      let json =
        executor.execute_query(my_schema, resolved)
        |> response.from_execution_result
        |> response.to_json
      #(new_store, json)
    }
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() {
  let my_schema = build_schema()
  let query_str = "{ users { id name } }"
  let hash = persisted_queries.hash_query(query_str)

  io.println("Query:  " <> query_str)
  io.println("Hash:   " <> hash)

  let store = persisted_queries.new()

  io.println("\n-- Request 1: hash only (cache miss) --")
  let #(store, resp1) = handle_apq(store, my_schema, None, hash)
  io.println(resp1)

  io.println("\n-- Request 2: hash + query (register and execute) --")
  let #(store, resp2) = handle_apq(store, my_schema, Some(query_str), hash)
  io.println(resp2)

  io.println("\n-- Request 3: hash only (cache hit) --")
  let #(store, resp3) = handle_apq(store, my_schema, None, hash)
  io.println(resp3)

  io.println("\nStore size: " <> int.to_string(persisted_queries.size(store)))
}
