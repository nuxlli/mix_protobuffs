defmodule Mix.Tasks.Compile.Protobuffs do
  alias :protobuffs_compile, as: Compiler
  alias Mix.Tasks.Compile.Erlang

  use Mix.Task

  @hidden true
  @shortdoc "Compile protocol buffer files"
  @recursive true

  @moduledoc """
  A task to compile protocol buffer files.

  When this task runs, it will check the mod time of every file, and
  if it has changed, then file will be compiled. Files will be
  compiled in the same source directory with .erl extension.
  You can force compilation regardless of mod times by passing
  the `--force` option.

  ## Command line options

  * `--force` - forces compilation regardless of module times;

  ## Configuration

  * `:protobuff_paths` - directories to find source files.
    Defaults to `["proto"]`, can be configured as:

        [protobuff_paths: ["proto", "other"]]

  * `:protobuff_options` - compilation options that applies
     to protobuff's compiler. There are many other available
     options here: https://github.com/basho/erlang_protobuffs

  """
  def run(args) do
    { opts, _ } = OptionParser.parse(args, switches: [force: :boolean])

    proto_paths  = opts[:protobuff_paths] || ["proto"]
    incl_path = "src"
    ebin_path = "ebin"

    File.mkdir_p!(incl_path)
    File.mkdir_p!(ebin_path)

    manifest = Path.join(ebin_path, ".compile.proto")
    protos   = lc path inlist proto_paths, do: { path, "lib" }
    options  = Keyword.merge([
      output_include_dir: '#{incl_path}',
      output_ebin_dir: '#{ebin_path}'
    ], opts[:protobuff_options] || [])

    Erlang.compile_mappings manifest, protos,
      :proto, :ex, opts[:force],
      fn input, output -> file_compile(input, output, options) end
  end

  defp file_compile(input, output, opts) do
    case Compiler.scan_file('#{input}', opts) do
      :error -> :error
      _ ->
        generate_wrapper(input, output)
        {:ok, true}
    end
  end

  defp generate_wrapper(input, output) do
    basename = Path.basename(input, ".proto")
    header   = "src/" <> basename <> "_pb.hrl"
    records  = record_names(header)

    {:ok, file} = File.open(output, [:write])
    IO.write(file, "defmodule #{String.capitalize(basename)} do\n\n")
    lc record inlist records do
      IO.write(file, "  defrecord :#{record}, Record.extract(:#{record}, from: \"#{header}\")\n")
      IO.write(file, "  def encode_#{record}(record), do: :#{basename}_pb.encode_#{record}(record)\n")
      IO.write(file, "  def decode_#{record}(binary), do: :#{basename}_pb.decode_#{record}(binary)\n\n")
    end
    IO.write(file, "end")
    File.close(file)
  end

  defp record_names(header) do
    contents = File.read!(header)
    Regex.scan(%r/record\((.*),/, contents) |> Enum.map fn
      [_, record] -> record
    end
  end
end
