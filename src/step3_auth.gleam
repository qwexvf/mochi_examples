// Step 3: Authentication and Guards
//
// Adds execution context, bearer token extraction, and guards that
// short-circuit resolvers with an error before they run.
// Run with: gleam run -m step3_auth

import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/result
import mochi/context
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types

// ── Domain type ───────────────────────────────────────────────────────────────

pub type Post {
  Post(id: String, title: String, author_id: String)
}

fn decode_post(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    decode.success(Post(id, title, ""))
  })
  |> result.map_error(fn(_) { "failed to decode Post" })
}

fn post_schema() {
  let builder =
    types.object("Post")
    |> types.id("id", fn(p: Post) { p.id })
    |> types.string("title", fn(p: Post) { p.title })
  types.build_with_encoder(builder, decode_post)
}

fn posts() {
  [Post("1", "Hello World", "user-1"), Post("2", "Gleam is great", "user-1")]
}

// ── Guards ────────────────────────────────────────────────────────────────────

// Guards are fn(ExecutionContext) -> Result(Nil, String).
// Ok(Nil) → resolver runs. Error(msg) → resolver is skipped, error returned.

fn require_auth(ctx: schema.ExecutionContext) -> Result(Nil, String) {
  case dynamic.classify(ctx.user_context) {
    "Dict" ->
      case
        decode.run(ctx.user_context, decode.dict(decode.string, decode.dynamic))
        |> result.try(fn(d) {
          dict.get(d, "user_id")
          |> result.map_error(fn(_) { [] })
        })
      {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error("Authentication required")
      }
    _ -> Error("Authentication required")
  }
}

fn require_admin(ctx: schema.ExecutionContext) -> Result(Nil, String) {
  case
    decode.run(ctx.user_context, decode.dict(decode.string, decode.dynamic))
    |> result.try(fn(d) {
      dict.get(d, "role")
      |> result.map_error(fn(_) { [] })
    })
    |> result.try(fn(role) {
      decode.run(role, decode.string)
      |> result.map_error(fn(_) { [] })
    })
  {
    Ok("admin") -> Ok(Nil)
    _ -> Error("Admin access required")
  }
}

// ── Queries ───────────────────────────────────────────────────────────────────

fn my_posts_query(encode_post) {
  // require_auth runs before the resolver — if it returns Error, resolver is skipped
  query.query(
    "myPosts",
    schema.list_type(schema.named_type("Post")),
    fn(_ctx) { Ok(posts()) },
    fn(ps) { types.to_dynamic(list.map(ps, encode_post)) },
  )
  |> query.with_guard(require_auth)
}

fn public_posts_query(encode_post) {
  query.query(
    "posts",
    schema.list_type(schema.named_type("Post")),
    fn(_ctx) { Ok(posts()) },
    fn(ps) { types.to_dynamic(list.map(ps, encode_post)) },
  )
}

// ── Mutations ─────────────────────────────────────────────────────────────────

fn delete_post_mutation() {
  // all_of chains guards — both must pass
  query.mutation(
    name: "deletePost",
    args: [query.arg("id", schema.non_null(schema.id_type()))],
    returns: schema.non_null(schema.string_type()),
    decode: fn(args) { query.get_id(args, "id") },
    resolve: fn(id, _ctx) { Ok("Deleted post " <> id) },
    encode: fn(msg) { types.to_dynamic(msg) },
  )
  |> query.mutation_with_guard(query.all_of([require_auth, require_admin]))
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(post_type, encode_post) = post_schema()

  query.new()
  |> query.add_query(public_posts_query(encode_post))
  |> query.add_query(my_posts_query(encode_post))
  |> query.add_mutation(delete_post_mutation())
  |> query.add_type(post_type)
  |> query.build
}

// ── Context helpers ───────────────────────────────────────────────────────────

fn unauthenticated_ctx() {
  schema.execution_context(types.to_dynamic(dict.new()))
}

fn user_ctx(user_id: String, role: String) {
  let d =
    dict.new()
    |> dict.insert("user_id", types.to_dynamic(user_id))
    |> dict.insert("role", types.to_dynamic(role))
  schema.execution_context(types.to_dynamic(d))
}

fn run(label, my_schema, gql, ctx) {
  io.println("\n[" <> label <> "] " <> gql)
  executor.execute_query_with_context(my_schema, gql, dict.new(), ctx)
  |> response.from_execution_result
  |> response.to_json
  |> io.println
}

pub fn main() {
  let my_schema = build_schema()

  // No auth needed
  run("public", my_schema, "{ posts { id title } }", unauthenticated_ctx())

  // Guard fails — error returned, resolver never runs
  run(
    "unauthenticated",
    my_schema,
    "{ myPosts { id title } }",
    unauthenticated_ctx(),
  )

  // Guard passes
  run(
    "authenticated",
    my_schema,
    "{ myPosts { id title } }",
    user_ctx("user-1", "member"),
  )

  // require_auth passes, require_admin passes
  run(
    "admin delete",
    my_schema,
    "mutation { deletePost(id: \"1\") }",
    user_ctx("user-1", "admin"),
  )

  // require_auth passes, require_admin fails
  run(
    "member delete",
    my_schema,
    "mutation { deletePost(id: \"1\") }",
    user_ctx("user-1", "member"),
  )

  // context.gleam helpers — how to extract a bearer token from request headers
  let headers =
    dict.from_list([#("authorization", "Bearer my-jwt-token-here")])
  let req = context.request_info(headers, "POST", "/graphql")
  io.println("\nBearer token: " <> {
    case context.get_bearer_token(req) {
      Ok(token) -> token
      Error(_) -> "(none)"
    }
  })
}
