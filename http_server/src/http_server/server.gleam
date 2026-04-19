// Step 10: Real HTTP Server with Wisp + Mist
//
// A complete mochi GraphQL server using Wisp (HTTP framework) and Mist (TCP server).
//
// Endpoints:
//   POST /graphql   — execute GraphQL queries and mutations
//   GET  /graphql   — health check / method guard
//
// Start with: gleam run -m http_server/server
//
// Then try:
//   curl -X POST http://localhost:4000/graphql \
//     -H 'Content-Type: application/json' \
//     -d '{"query":"{ posts { id title } }"}'
//
// For WebSocket subscriptions, see step7_subscriptions.gleam for the protocol
// and wire websocket.handle_message into a mist.websocket handler.

import gleam/erlang/process
import gleam/http
import gleam/io
import http_server/schema as app_schema
import mist
import mochi/executor
import mochi/response
import mochi_websocket/subscription
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret = wisp.random_string(64)

  let pubsub = subscription.new_pubsub()
  let my_schema = app_schema.build(pubsub)

  io.println("mochi GraphQL server → http://localhost:4000/graphql")

  let handler = fn(req) { handle_request(req, my_schema) }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret)
    |> mist.new
    |> mist.port(4000)
    |> mist.start
  process.sleep_forever()
}

fn handle_request(req: wisp.Request, my_schema) -> wisp.Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes

  case wisp.path_segments(req) {
    ["graphql"] -> handle_graphql(req, my_schema)
    _ -> wisp.not_found()
  }
}

fn handle_graphql(req: wisp.Request, my_schema) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_string_body(req)
  let json =
    executor.execute_query(my_schema, body)
    |> response.from_execution_result
    |> response.to_json
  wisp.json_response(json, 200)
}
