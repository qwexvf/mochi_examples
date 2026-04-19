// Step 10: File Uploads with mochi_upload
//
// mochi_upload provides:
//   - The Upload scalar type for GraphQL schemas
//   - UploadedFile utilities: validate, read, move, cleanup
//   - UploadConfig for size and MIME type constraints
//
// In a real HTTP server, multipart requests are parsed via
// mochi_upload/multipart.parse_multipart_request(form_parts, config)
// which maps uploaded files into GraphQL variables before execution.
// This example simulates that: we write a temp file and wrap it as
// an UploadedFile, then show the full validate → read → cleanup flow.
//
// Run with: gleam run -m step10_upload

import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mochi/executor
import mochi/query
import mochi/response
import mochi/schema
import mochi/types
import mochi_upload/upload
import simplifile

// ── Domain types ──────────────────────────────────────────────────────────────

pub type FileInfo {
  FileInfo(filename: String, mime_type: String, size: Int, preview: String)
}

// ── Decoder + type ────────────────────────────────────────────────────────────

fn decode_file_info(dyn) {
  decode.run(dyn, {
    use filename <- decode.field("filename", decode.string)
    use mime_type <- decode.field("mimeType", decode.string)
    use size <- decode.field("size", decode.int)
    use preview <- decode.field("preview", decode.string)
    decode.success(FileInfo(filename, mime_type, size, preview))
  })
  |> result.map_error(fn(_) { "failed to decode FileInfo" })
}

fn file_info_schema() {
  let builder =
    types.object("FileInfo")
    |> types.string("filename", fn(f: FileInfo) { f.filename })
    |> types.string("mimeType", fn(f: FileInfo) { f.mime_type })
    |> types.int("size", fn(f: FileInfo) { f.size })
    |> types.string("preview", fn(f: FileInfo) { f.preview })
  types.build_with_encoder(builder, decode_file_info)
}

// ── Schema ────────────────────────────────────────────────────────────────────

fn build_schema() {
  let #(file_info_type, encode_file_info) = file_info_schema()

  let config =
    upload.default_config()
    |> upload.allow_images()
    |> upload.with_max_file_size(5 * 1024 * 1024)

  // uploadFile(file: Upload!): FileInfo
  // In production the Upload arg is populated by the multipart parser.
  // Here we decode it with upload.from_dynamic which expects an UploadedFile
  // that was placed into args by the HTTP layer.
  let upload_mutation =
    query.mutation(
      name: "uploadFile",
      args: [query.arg("file", schema.non_null(schema.named_type("Upload")))],
      returns: schema.non_null(schema.named_type("FileInfo")),
      decode: fn(args) {
        use file_dyn <- result.try(
          dict.get(args, "file")
          |> result.map_error(fn(_) { "Missing required argument: file" }),
        )
        upload.from_dynamic(file_dyn)
        |> result.map_error(fn(e) { "Invalid Upload value: " <> e })
      },
      resolve: fn(file: upload.UploadedFile, _ctx) {
        use validated <- result.try(
          upload.validate(file, config)
          |> result.map_error(upload.format_error),
        )
        use content <- result.try(
          upload.read_string(validated)
          |> result.map_error(upload.format_error),
        )
        let preview = string.slice(content, 0, 80)
        let info =
          FileInfo(
            filename: validated.filename,
            mime_type: validated.mime_type,
            size: validated.size,
            preview: preview,
          )
        let _ = upload.cleanup(validated)
        Ok(info)
      },
      encode: encode_file_info,
    )

  // listUploads — return the names of accepted MIME types from config
  let config_query =
    query.query(
      "acceptedMimeTypes",
      schema.list_type(schema.string_type()),
      fn(_ctx) { Ok(upload.allow_images(upload.default_config()).allowed_mime_types) },
      fn(types_list) { types.to_dynamic(list.map(types_list, types.to_dynamic)) },
    )

  query.new()
  |> query.add_scalar(upload.upload_scalar())
  |> query.add_mutation(upload_mutation)
  |> query.add_query(config_query)
  |> query.add_type(file_info_type)
  |> query.build
}

// ── Simulation ────────────────────────────────────────────────────────────────

pub fn main() {
  let my_schema = build_schema()

  // Show accepted MIME types
  io.println("> { acceptedMimeTypes }")
  executor.execute_query(my_schema, "{ acceptedMimeTypes }")
  |> response.from_execution_result
  |> response.to_json
  |> io.println

  // Simulate an upload: write a temp file, wrap as UploadedFile, validate, read, cleanup
  io.println("\n-- Simulating file upload --")
  let path = "/tmp/mochi_upload_example.txt"
  let content = "Hello from mochi_upload!\nThis file was uploaded via GraphQL."

  let assert Ok(_) = simplifile.write(path, content)
  io.println("Wrote temp file: " <> path)

  let size = bit_array.byte_size(bit_array.from_string(content))
  let file = upload.new_uploaded_file("hello.txt", "text/plain", path, size)

  let config =
    upload.default_config()
    |> upload.with_max_file_size(1024 * 1024)

  case upload.validate(file, config) {
    Error(e) -> io.println("Validate failed: " <> upload.format_error(e))
    Ok(validated) -> {
      io.println("Validate: OK")
      case upload.read_string(validated) {
        Error(e) -> io.println("Read failed: " <> upload.format_error(e))
        Ok(text) -> io.println("Content: " <> text)
      }
      case upload.cleanup(validated) {
        Ok(_) -> io.println("Cleanup: OK")
        Error(e) -> io.println("Cleanup failed: " <> upload.format_error(e))
      }
    }
  }

  io.println(
    "\nIn production, wire mochi_upload/multipart.parse_multipart_request"
    <> " into your HTTP handler to populate the Upload argument automatically.",
  )
}
