// Step 7: WebSocket Subscriptions
//
// Real-time GraphQL subscriptions using the graphql-ws protocol.
// mochi_transport handles the protocol; mochi core defines the subscription field.
//
// Protocol flow:
//   Client → ConnectionInit  →  Server: ConnectionAck
//   Client → Subscribe(id, query)  →  events arrive as Next(id, data)
//   Server publishes to a topic  →  all subscribers on that topic receive Next
//   Client → Complete(id)  →  Server: Complete(id)
//
// In a real server (Wisp, Mist, etc.) you wire handle_message into your
// WebSocket frame handler and send encode_server_message output back.
//
// Run with: gleam run -m step7_subscriptions

import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types
import mochi_transport/subscription
import mochi_transport/websocket

// ── Domain type ───────────────────────────────────────────────────────────────

pub type Post {
  Post(id: String, title: String, author: String)
}

// ── Type + encoder ────────────────────────────────────────────────────────────

fn decode_post(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use author <- decode.field("author", decode.string)
    decode.success(Post(id, title, author))
  })
  |> result.map_error(fn(_) { "failed to decode Post" })
}

fn post_schema() {
  let builder =
    types.object("Post")
    |> types.id("id", fn(p: Post) { p.id })
    |> types.string("title", fn(p: Post) { p.title })
    |> types.string("author", fn(p: Post) { p.author })
  types.build_with_encoder(builder, decode_post)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(post_type, encode_post) = post_schema()

  let posts_query =
    query.query(
      "posts",
      schema.list_type(schema.named_type("Post")),
      fn(_ctx) {
        Ok([Post("1", "Hello World", "Alice"), Post("2", "Gleam", "Bob")])
      },
      fn(ps) { types.to_dynamic(list.map(ps, encode_post)) },
    )

  // query.subscription(name, return_type, topic, encoder)
  // topic is a fixed string — all subscribers on this topic receive events
  let post_added_subscription =
    query.subscription(
      "postAdded",
      schema.named_type("Post"),
      "post:added",
      fn(p: Post) { encode_post(p) },
    )

  query.new()
  |> query.add_query(posts_query)
  |> query.add_subscription(post_added_subscription)
  |> query.add_type(post_type)
  |> query.build
}

// ── Simulation ────────────────────────────────────────────────────────────────

pub fn main() {
  let my_schema = build_schema()

  // Regular query still works alongside subscriptions
  io.println("> { posts { id title author } }")
  executor.execute_query(my_schema, "{ posts { id title author } }")
  |> response.from_execution_result
  |> response.to_json
  |> io.println

  // Set up the pub/sub system and execution context
  let pubsub = subscription.new_pubsub()
  let ctx = schema.execution_context(types.to_dynamic(dict.new()))

  io.println("\n-- Simulating WebSocket session --")

  // Step 1: client connects and sends ConnectionInit
  let init_json = "{\"type\":\"connection_init\"}"
  io.println("\n[client→] " <> init_json)

  let state = websocket.new_connection(my_schema, pubsub, ctx)

  let #(state, ack) = case websocket.decode_client_message(init_json) {
    Ok(msg) ->
      case websocket.handle_message(state, msg) {
        websocket.HandleOk(state: s, response: Some(r)) -> #(
          s,
          websocket.encode_server_message(r),
        )
        _ -> #(state, "(no response)")
      }
    Error(e) -> #(state, websocket.format_decode_error(e))
  }
  io.println("[server→] " <> ack)

  // Step 2: client subscribes
  let sub_json =
    "{\"type\":\"subscribe\",\"id\":\"1\",\"payload\":{\"query\":\"subscription { postAdded { id title author } }\"}}"
  io.println("\n[client→] " <> sub_json)

  let state = case websocket.decode_client_message(sub_json) {
    Ok(msg) ->
      case websocket.handle_message(state, msg) {
        websocket.HandleOk(state: s, response: None) -> {
          io.println("[server→] (subscribed, waiting for events)")
          s
        }
        websocket.HandleOk(state: s, response: Some(r)) -> {
          io.println("[server→] " <> websocket.encode_server_message(r))
          s
        }
        websocket.HandleClose(reason) -> {
          io.println("[server→] CLOSE: " <> reason)
          state
        }
        websocket.HandleMultiple(state: s, responses: rs) -> {
          list.each(rs, fn(r) {
            io.println("[server→] " <> websocket.encode_server_message(r))
          })
          s
        }
      }
    Error(e) -> {
      io.println("[error] " <> websocket.format_decode_error(e))
      state
    }
  }

  // Step 3: server publishes a new post — subscribers receive it immediately
  io.println("\n[server] Publishing new post to topic \"post:added\"...")
  let new_post =
    types.record([
      types.field("id", "3"),
      types.field("title", "Real-time with mochi"),
      types.field("author", "Carol"),
    ])
  subscription.publish(state.pubsub, "post:added", new_post)

  // Step 4: client unsubscribes
  let complete_json = "{\"type\":\"complete\",\"id\":\"1\"}"
  io.println("\n[client→] " <> complete_json)
  case websocket.decode_client_message(complete_json) {
    Ok(msg) ->
      case websocket.handle_message(state, msg) {
        websocket.HandleOk(state: _, response: Some(r)) ->
          io.println("[server→] " <> websocket.encode_server_message(r))
        _ -> io.println("[server→] (done)")
      }
    Error(e) -> io.println("[error] " <> websocket.format_decode_error(e))
  }

  io.println(
    "\nIn production, wire websocket.handle_message into your Wisp/Mist WebSocket handler.",
  )
}
