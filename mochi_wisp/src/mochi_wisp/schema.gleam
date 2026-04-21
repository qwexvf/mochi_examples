import gleam/int
import gleam/list
import gleam/result
import mochi/error
import mochi/query

@external(erlang, "env_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
import mochi/schema
import mochi/types

pub type Post {
  Post(id: String, title: String, body: String)
}

pub type User {
  User(id: String, name: String, email: String, posts: List(Post))
}

fn irange(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..irange(from + 1, to)]
  }
}

fn seed_posts(user_id: String) -> List(Post) {
  irange(1, 5)
  |> list.map(fn(i) {
    let n = user_id <> "-" <> int.to_string(i)
    Post(n, "Post " <> n, "Body of post " <> n)
  })
}

fn seed_users() -> List(User) {
  irange(1, 10)
  |> list.map(fn(i) {
    let id = int.to_string(i)
    User(id, "User " <> id, "user" <> id <> "@example.com", seed_posts(id))
  })
}

pub fn build() -> schema.Schema {
  let #(post_type, encode_post) =
    types.object("Post")
    |> types.id("id", fn(p: Post) { p.id })
    |> types.string("title", fn(p: Post) { p.title })
    |> types.string("body", fn(p: Post) { p.body })
    |> types.build_direct

  let #(user_type, encode_user) =
    types.object("User")
    |> types.id("id", fn(u: User) { u.id })
    |> types.string("name", fn(u: User) { u.name })
    |> types.string("email", fn(u: User) { u.email })
    |> types.list_object("posts", "Post", fn(u: User) {
      types.to_dynamic(list.map(u.posts, encode_post))
    })
    |> types.build_direct

  let all_users = seed_users()

  let users_query =
    query.query(
      name: "users",
      returns: schema.list_type(schema.named_type("User")),
      resolve: fn(_ctx) { Ok(all_users) },
    )
    |> query.with_encoder(fn(us) { types.to_dynamic(list.map(us, encode_user)) })

  let user_query =
    query.query_with_args(
      name: "user",
      args: [query.arg("id", schema.non_null(schema.id_type()))],
      returns: schema.named_type("User"),
      resolve: fn(args, _ctx) {
        use id <- result.try(query.get_id(args, "id"))
        case list.find(all_users, fn(u) { u.id == id }) {
          Ok(u) -> Ok(u)
          Error(_) -> Error(error.new("User not found: " <> id))
        }
      },
    )
    |> query.with_encoder(encode_user)

  let builder =
    query.new()
    |> query.add_query(users_query)
    |> query.add_query(user_query)
    |> query.add_type(user_type)
    |> query.add_type(post_type)

  case get_env("MOCHI_CACHE") {
    Ok("true") -> builder |> query.with_cache |> query.build
    _ -> query.build(builder)
  }
}
