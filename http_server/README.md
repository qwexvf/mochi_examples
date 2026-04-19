# mochi HTTP server example

A real Wisp + Mist HTTP server serving GraphQL over POST `/graphql`, with a
`createPost` mutation that publishes to a WebSocket subscription topic.

## Setup

```sh
gleam deps download
```

## Start

```sh
gleam run -m http_server/server
```

Server listens on `http://localhost:4000`.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/graphql` | Execute GraphQL queries and mutations |

## Example requests

List posts:
```sh
curl -X POST http://localhost:4000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ posts { id title body } }"}'
```

Fetch a single post:
```sh
curl -X POST http://localhost:4000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ post(id: \"1\") { title body } }"}'
```

Create a post (publishes to the `post:created` subscription topic):
```sh
curl -X POST http://localhost:4000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { createPost(title: \"Hello\", body: \"World\") { id title } }"}'
```

## WebSocket subscriptions

The schema defines a `postCreated` subscription. To wire it up, add a `/ws`
route and pass each WebSocket frame through `websocket.handle_message`. See
`step7_subscriptions.gleam` for the full graphql-ws protocol simulation and
`mochi_websocket/websocket.gleam` for the handler API.
