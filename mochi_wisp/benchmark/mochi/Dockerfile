FROM ghcr.io/gleam-lang/gleam:v1.15.4-erlang-alpine AS builder
WORKDIR /build

COPY mochi/ ./mochi/
COPY examples/mochi_wisp/src/ ./app/src/
COPY examples/mochi_wisp/gleam.toml ./app/gleam.toml

WORKDIR /build/app

RUN sed -i \
  -e 's|wisp = { path = "[^"]*" }|wisp = ">= 2.2.1 and < 3.0.0"|' \
  -e 's|mochi = { path = "[^"]*" }|mochi = { path = "../mochi" }|' \
  gleam.toml

RUN gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:v1.15.4-erlang-alpine
WORKDIR /app
COPY --from=builder /build/app/build/erlang-shipment/ .
EXPOSE 4000
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run", "mochi_wisp"]
