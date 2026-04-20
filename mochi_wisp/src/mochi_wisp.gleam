import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import mist
import mochi/executor
import mochi/response
import mochi/schema
import mochi_wisp/schema as bench_schema
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret = wisp.random_string(64)
  let my_schema = bench_schema.build()
  let port = 4000

  io.println("mochi listening on :" <> int.to_string(port))

  let handler = fn(req) { handle_request(req, my_schema) }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret)
    |> mist.new
    |> mist.port(port)
    |> mist.start
  process.sleep_forever()
}

fn handle_request(req: wisp.Request, my_schema: schema.Schema) -> wisp.Response {
  case wisp.path_segments(req) {
    ["graphql"] -> handle_graphql(req, my_schema)
    _ -> wisp.not_found()
  }
}

fn handle_graphql(req: wisp.Request, my_schema: schema.Schema) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_string_body(req)
  case parse_graphql_request(body) {
    Ok(#(query, variables)) -> {
      let json_body =
        executor.execute_query_with_variables(my_schema, query, variables)
        |> response.from_execution_result
        |> response.to_json
      wisp.json_response(json_body, 200)
    }
    Error(_) ->
      wisp.json_response(
        "{\"errors\":[{\"message\":\"Invalid request body\"}]}",
        400,
      )
  }
}

fn parse_graphql_request(
  body: String,
) -> Result(#(String, dict.Dict(String, Dynamic)), String) {
  let decoder = {
    use query <- decode.field("query", decode.string)
    use variables <- decode.optional_field(
      "variables",
      dict.new(),
      decode.dict(decode.string, decode.dynamic),
    )
    decode.success(#(query, variables))
  }
  json.parse(body, decoder)
  |> result.map_error(fn(_) { "Invalid GraphQL request body" })
}
