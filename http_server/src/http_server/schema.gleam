import gleam/dynamic/decode
import gleam/bit_array
import gleam/crypto
import gleam/string
import gleam/list
import gleam/result
import mochi/query
import mochi/schema
import mochi/types
import mochi_transport/subscription

pub type Post {
  Post(id: String, title: String, body: String)
}

fn decode_post(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use body <- decode.field("body", decode.string)
    decode.success(Post(id, title, body))
  })
  |> result.map_error(fn(_) { "failed to decode Post" })
}

fn post_schema() {
  let builder =
    types.object("Post")
    |> types.id("id", fn(p: Post) { p.id })
    |> types.string("title", fn(p: Post) { p.title })
    |> types.string("body", fn(p: Post) { p.body })
  types.build_with_encoder(builder, decode_post)
}

pub fn build(pubsub: subscription.PubSub) {
  let #(post_type, encode_post) = post_schema()

  let posts_query =
    query.query(
      "posts",
      schema.list_type(schema.named_type("Post")),
      fn(_ctx) {
        Ok([
          Post("1", "Hello Gleam", "Gleam is a type-safe functional language."),
          Post("2", "mochi GraphQL", "Code-first GraphQL for Gleam."),
        ])
      },
      fn(ps) { types.to_dynamic(list.map(ps, encode_post)) },
    )

  let get_post_query =
    query.query_with_args(
      name: "post",
      args: [query.arg("id", schema.non_null(schema.id_type()))],
      returns: schema.named_type("Post"),
      decode: fn(args) { query.get_id(args, "id") },
      resolve: fn(id, _ctx) {
        case id {
          "1" -> Ok(Post("1", "Hello Gleam", "Gleam is a type-safe functional language."))
          "2" -> Ok(Post("2", "mochi GraphQL", "Code-first GraphQL for Gleam."))
          _ -> Error("Post not found: " <> id)
        }
      },
      encode: encode_post,
    )

  let create_post_mutation =
    query.mutation(
      name: "createPost",
      args: [
        query.arg("title", schema.non_null(schema.string_type())),
        query.arg("body", schema.non_null(schema.string_type())),
      ],
      returns: schema.non_null(schema.named_type("Post")),
      decode: fn(args) {
        use title <- result.try(query.get_string(args, "title"))
        use body <- result.try(query.get_string(args, "body"))
        Ok(#(title, body))
      },
      resolve: fn(input, _ctx) {
        let #(title, body) = input
        let id =
          crypto.strong_random_bytes(8)
          |> bit_array.base16_encode
          |> string.lowercase
        let post = Post(id, title, body)
        subscription.publish(pubsub, "post:created", encode_post(post))
        Ok(post)
      },
      encode: encode_post,
    )

  let post_created_sub =
    query.subscription(
      "postCreated",
      schema.named_type("Post"),
      "post:created",
      fn(p: Post) { encode_post(p) },
    )

  query.new()
  |> query.add_query(posts_query)
  |> query.add_query(get_post_query)
  |> query.add_mutation(create_post_mutation)
  |> query.add_subscription(post_created_sub)
  |> query.add_type(post_type)
  |> query.build
}
