// Step 4: Unions and Interfaces
//
// Defines an interface (Animal), two implementing types (Cat, Dog),
// and a union (Pet) — then queries both with inline fragments.
// Run with: gleam run -m step4_advanced_types

import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/result
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types

// ── Domain types ──────────────────────────────────────────────────────────────

pub type Cat {
  Cat(id: String, name: String, indoor: Bool)
}

pub type Dog {
  Dog(id: String, name: String, breed: String)
}

// ── Interface ─────────────────────────────────────────────────────────────────

// The interface defines shared fields. Each implementing type must include them.
fn animal_interface() {
  schema.interface("Animal")
  |> schema.interface_description("Any animal")
  |> schema.interface_field(schema.field_def("id", schema.non_null(schema.id_type())))
  |> schema.interface_field(schema.field_def("name", schema.non_null(schema.string_type())))
  |> schema.interface_resolve_type(fn(value) {
    // Inspect the dynamic value to determine the concrete type name
    case
      decode.run(value, decode.dict(decode.string, decode.dynamic))
      |> result.try(fn(d) {
        dict.get(d, "indoor")
        |> result.map_error(fn(_) { [] })
      })
    {
      Ok(_) -> Ok("Cat")
      _ -> Ok("Dog")
    }
  })
}

// ── Object types ──────────────────────────────────────────────────────────────

fn decode_cat(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use indoor <- decode.field("indoor", decode.bool)
    decode.success(Cat(id, name, indoor))
  })
  |> result.map_error(fn(_) { "failed to decode Cat" })
}

fn decode_dog(dyn) {
  decode.run(dyn, {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use breed <- decode.field("breed", decode.string)
    decode.success(Dog(id, name, breed))
  })
  |> result.map_error(fn(_) { "failed to decode Dog" })
}

fn cat_type(animal: schema.InterfaceType) {
  types.object("Cat")
  |> types.id("id", fn(c: Cat) { c.id })
  |> types.string("name", fn(c: Cat) { c.name })
  |> types.bool("indoor", fn(c: Cat) { c.indoor })
  |> types.build(decode_cat)
  |> fn(obj) { schema.ObjectType(..obj, interfaces: [animal]) }
}

fn dog_type(animal: schema.InterfaceType) {
  types.object("Dog")
  |> types.id("id", fn(d: Dog) { d.id })
  |> types.string("name", fn(d: Dog) { d.name })
  |> types.string("breed", fn(d: Dog) { d.breed })
  |> types.build(decode_dog)
  |> fn(obj) { schema.ObjectType(..obj, interfaces: [animal]) }
}

// ── Union ─────────────────────────────────────────────────────────────────────

fn pet_union(cat: schema.ObjectType, dog: schema.ObjectType) {
  schema.union("Pet")
  |> schema.union_description("A domesticated animal")
  |> schema.union_member(cat)
  |> schema.union_member(dog)
  |> schema.union_resolve_type(fn(value) {
    case
      decode.run(value, decode.dict(decode.string, decode.dynamic))
      |> result.try(fn(d) {
        dict.get(d, "indoor")
        |> result.map_error(fn(_) { [] })
      })
    {
      Ok(_) -> Ok("Cat")
      _ -> Ok("Dog")
    }
  })
}

// ── In-memory data ────────────────────────────────────────────────────────────

// Data is returned as Dynamic records so it passes through the encoder directly
fn all_pets() {
  [
    types.record([
      types.field("id", "1"),
      types.field("name", "Whiskers"),
      types.field("indoor", True),
    ]),
    types.record([
      types.field("id", "2"),
      types.field("name", "Rex"),
      types.field("breed", "Labrador"),
    ]),
  ]
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let animal = animal_interface()
  let cat = cat_type(animal)
  let dog = dog_type(animal)
  let pet = pet_union(cat, dog)

  let pets_query =
    query.query(
      "pets",
      schema.list_type(schema.named_type("Pet")),
      fn(_ctx) { Ok(all_pets()) },
      fn(ps) { types.to_dynamic(ps) },
    )

  let animals_query =
    query.query(
      "animals",
      schema.list_type(schema.named_type("Animal")),
      fn(_ctx) { Ok(all_pets()) },
      fn(ps) { types.to_dynamic(ps) },
    )

  query.new()
  |> query.add_query(pets_query)
  |> query.add_query(animals_query)
  |> query.add_type(cat)
  |> query.add_type(dog)
  |> query.add_union(pet)
  |> query.add_interface(animal)
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

  // Inline fragments let you request type-specific fields
  run(
    my_schema,
    "{ pets { ... on Cat { id name indoor } ... on Dog { id name breed } } }",
  )

  // Interface query — only shared fields available without inline fragment
  run(my_schema, "{ animals { id name } }")

  // __typename is always available
  run(my_schema, "{ pets { __typename ... on Cat { name } ... on Dog { name } } }")
}
