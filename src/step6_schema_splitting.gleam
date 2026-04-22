// Step 6: Schema Splitting
//
// Large schemas grow unwieldy in a single file. Split into domain modules,
// each returning a SchemaBuilder, then merge with query.merge.
//
// Run with: gleam run -m step6_schema_splitting

import gleam/io
import gleam/list
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
  User(id: String, name: String)
}

pub type Post {
  Post(id: String, title: String, author_id: String)
}

pub type Comment {
  Comment(id: String, body: String, post_id: String)
}

// ── Data ──────────────────────────────────────────────────────────────────────

fn all_users() {
  [User("1", "Alice"), User("2", "Bob")]
}

fn all_posts() {
  [Post("1", "Hello", "1"), Post("2", "Gleam", "2")]
}

fn all_comments() {
  [Comment("1", "Great post!", "1"), Comment("2", "Thanks!", "1")]
}

// ── User domain ───────────────────────────────────────────────────────────────

fn user_schema() -> query.SchemaBuilder {
  let builder =
    types.object("User")
    |> types.id("id", fn(u: User) { u.id })
    |> types.string("name", fn(u: User) { u.name })
  let #(user_type, encode_user) =
    types.build_with_encoder(builder, fn(dyn) {
      decode.run(dyn, {
        use id <- decode.field("id", decode.string)
        use name <- decode.field("name", decode.string)
        decode.success(User(id, name))
      })
      |> result.map_error(fn(_) { "failed to decode User" })
    })

  let users_query =
    query.query(
      name: "users",
      returns: schema.list_type(schema.named_type("User")),
      resolve: fn(_ctx) { Ok(all_users()) },
    )
    |> query.with_encoder(fn(us) { types.to_dynamic(list.map(us, encode_user)) })

  let create_user =
    query.mutation_with_args(
      name: "createUser",
      args: [query.arg("name", schema.non_null(schema.string_type()))],
      returns: schema.non_null(schema.named_type("User")),
      resolve: fn(args, _ctx) {
        use name <- result.try(query.get_string(args, "name"))
        Ok(User("3", name))
      },
    )
    |> query.with_encoder(encode_user)

  query.new()
  |> query.add_query(users_query)
  |> query.add_mutation(create_user)
  |> query.add_type(user_type)
}

// ── Post domain ───────────────────────────────────────────────────────────────

fn post_schema() -> query.SchemaBuilder {
  let builder =
    types.object("Post")
    |> types.id("id", fn(p: Post) { p.id })
    |> types.string("title", fn(p: Post) { p.title })
  let #(post_type, encode_post) =
    types.build_with_encoder(builder, fn(dyn) {
      decode.run(dyn, {
        use id <- decode.field("id", decode.string)
        use title <- decode.field("title", decode.string)
        use author_id <- decode.field("author_id", decode.string)
        decode.success(Post(id, title, author_id))
      })
      |> result.map_error(fn(_) { "failed to decode Post" })
    })

  let posts_query =
    query.query(
      name: "posts",
      returns: schema.list_type(schema.named_type("Post")),
      resolve: fn(_ctx) { Ok(all_posts()) },
    )
    |> query.with_encoder(fn(ps) {
      types.to_dynamic(
        list.map(ps, fn(p) {
          types.record([
            types.field("id", p.id),
            types.field("title", p.title),
            types.field("author_id", p.author_id),
          ])
        }),
      )
    })

  let post_query =
    query.query_with_args(
      name: "post",
      args: [query.arg("id", schema.non_null(schema.id_type()))],
      returns: schema.named_type("Post"),
      resolve: fn(args, _ctx) {
        use id <- result.try(query.get_id(args, "id"))
        list.find(all_posts(), fn(p) { p.id == id })
        |> result.map_error(fn(_) { error.new("Post not found") })
      },
    )
    |> query.with_encoder(fn(p) {
      types.record([
        types.field("id", p.id),
        types.field("title", p.title),
        types.field("author_id", p.author_id),
      ])
    })

  let _ = encode_post

  query.new()
  |> query.add_query(posts_query)
  |> query.add_query(post_query)
  |> query.add_type(post_type)
}

// ── Comment domain ────────────────────────────────────────────────────────────

fn comment_schema() -> query.SchemaBuilder {
  let builder =
    types.object("Comment")
    |> types.id("id", fn(c: Comment) { c.id })
    |> types.string("body", fn(c: Comment) { c.body })
  let #(comment_type, encode_comment) =
    types.build_with_encoder(builder, fn(dyn) {
      decode.run(dyn, {
        use id <- decode.field("id", decode.string)
        use body <- decode.field("body", decode.string)
        use post_id <- decode.field("post_id", decode.string)
        decode.success(Comment(id, body, post_id))
      })
      |> result.map_error(fn(_) { "failed to decode Comment" })
    })

  let comments_query =
    query.query_with_args(
      name: "comments",
      args: [query.arg("postId", schema.non_null(schema.id_type()))],
      returns: schema.list_type(schema.named_type("Comment")),
      resolve: fn(args, _ctx) {
        use post_id <- result.try(query.get_id(args, "postId"))
        Ok(list.filter(all_comments(), fn(c) { c.post_id == post_id }))
      },
    )
    |> query.with_encoder(fn(cs) {
      types.to_dynamic(
        list.map(cs, fn(c) {
          types.record([
            types.field("id", c.id),
            types.field("body", c.body),
            types.field("post_id", c.post_id),
          ])
        }),
      )
    })

  let _ = encode_comment

  query.new()
  |> query.add_query(comments_query)
  |> query.add_type(comment_type)
}

// ── Merged schema ─────────────────────────────────────────────────────────────

fn build_schema() {
  // Each domain returns a SchemaBuilder; merge combines them all
  user_schema()
  |> query.merge(post_schema())
  |> query.merge(comment_schema())
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

  // Queries from different domains all work together
  run(my_schema, "{ users { id name } }")
  run(my_schema, "{ posts { id title } }")
  run(my_schema, "{ post(id: \"1\") { id title } }")
  run(my_schema, "{ comments(postId: \"1\") { id body } }")
  run(my_schema, "mutation { createUser(name: \"Carol\") { id name } }")
}
