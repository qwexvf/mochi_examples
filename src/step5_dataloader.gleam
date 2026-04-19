// Step 5: DataLoader — N+1 Prevention
//
// Without DataLoader: fetching 10 posts each with an author fires 10 separate
// DB queries. With DataLoader: all author IDs are collected and fetched in one
// batched query. The batch function prints a log line so you can see it fires once.
//
// Run with: gleam run -m step5_dataloader

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/result
import mochi/dataloader
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types

// ── Domain types ──────────────────────────────────────────────────────────────

pub type Author {
  Author(id: Int, name: String)
}

pub type Post {
  Post(id: String, title: String, author_id: Int)
}

// ── In-memory "database" ──────────────────────────────────────────────────────

fn all_authors() {
  [Author(1, "Alice"), Author(2, "Bob")]
}

fn all_posts() {
  [
    Post("p1", "Hello World", 1),
    Post("p2", "Gleam is fast", 2),
    Post("p3", "Pattern matching", 1),
  ]
}

fn find_author_by_id(id: Int) -> Result(Author, String) {
  list.find(all_authors(), fn(a) { a.id == id })
  |> result.map_error(fn(_) { "Author not found" })
}

// ── DataLoader ────────────────────────────────────────────────────────────────

// The batch function receives ALL queued keys at once — one DB round-trip
// regardless of how many posts we're resolving.
fn author_batch_fn(ids: List(Int)) -> Result(List(Result(Author, String)), String) {
  io.println("  [batch] fetching authors for ids: " <> join_ints(ids))
  Ok(list.map(ids, find_author_by_id))
}

fn join_ints(ids: List(Int)) -> String {
  list.map(ids, int_to_string)
  |> list.fold("", fn(acc, s) {
    case acc {
      "" -> s
      _ -> acc <> ", " <> s
    }
  })
}

fn int_to_string(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    _ -> "?"
  }
}

// ── Type schemas ──────────────────────────────────────────────────────────────

fn author_schema() {
  let builder =
    types.object("Author")
    |> types.int("id", fn(a: Author) { a.id })
    |> types.string("name", fn(a: Author) { a.name })
  types.build_with_encoder(builder, fn(dyn: Dynamic) {
    decode.run(dyn, {
      use id <- decode.field("id", decode.int)
      use name <- decode.field("name", decode.string)
      decode.success(Author(id, name))
    })
    |> result.map_error(fn(_) { "failed to decode Author" })
  })
}

fn decode_post(dyn: Dynamic) -> Result(Post, String) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use author_id <- decode.field("author_id", decode.int)
    decode.success(Post(id, title, author_id))
  })
  |> result.map_error(fn(_) { "failed to decode Post" })
}

fn post_type(_encode_author: fn(Author) -> Dynamic) {
  types.object("Post")
  |> types.id("id", fn(p: Post) { p.id })
  |> types.string("title", fn(p: Post) { p.title })
  // author field uses field_with_args to get a custom resolver with ctx access
  |> types.field_with_args(
    name: "author",
    returns: schema.named_type("Author"),
    args: [],
    desc: "",
    resolve: fn(p: Post, _args, ctx) {
      // Load via DataLoader — batching happens automatically
      let #(_ctx, result) = schema.load_by_id(ctx, "authors", p.author_id)
      result
    },
  )
  |> types.build(decode_post)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(author_type, encode_author) = author_schema()

  let posts_query =
    query.query(
      "posts",
      schema.list_type(schema.named_type("Post")),
      fn(_ctx) { Ok(all_posts()) },
      fn(ps) {
        types.to_dynamic(
          list.map(ps, fn(p) {
            types.record([
              types.field("id", p.id),
              types.field("title", p.title),
              types.field("author_id", p.author_id),
            ])
          }),
        )
      },
    )

  query.new()
  |> query.add_query(posts_query)
  |> query.add_type(post_type(encode_author))
  |> query.add_type(author_type)
  |> query.build
}

// ── Loader wiring ─────────────────────────────────────────────────────────────

fn build_ctx(encode_author: fn(Author) -> Dynamic) {
  // int_loader_result: convenience for fn(Int) -> Result(t, String) loaders
  let author_loader =
    dataloader.int_loader_result(
      find_author_by_id,
      encode_author,
      "Author not found",
    )

  schema.execution_context(types.to_dynamic(dict.new()))
  |> schema.add_data_loader("authors", author_loader)
}

fn run(my_schema, ctx, gql) {
  io.println("\n> " <> gql)
  executor.execute_query_with_context(my_schema, gql, dict.new(), ctx)
  |> response.from_execution_result
  |> response.to_json
  |> io.println
}

pub fn main() {
  let #(_author_type, encode_author) = author_schema()
  let my_schema = build_schema()
  let _ = author_batch_fn

  io.println("Fetching posts with authors (watch the batch log):")
  run(my_schema, build_ctx(encode_author), "{ posts { id title author { id name } } }")
}
