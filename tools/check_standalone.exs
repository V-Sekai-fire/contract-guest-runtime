# Builds tests/standalone, a guest outside the pen, and checks its ELF; every check has a control that must fail.
#   elixir tools/check_standalone.exs --sysroot=<repository-riscv64-sysroot> [--build=<dir>] [--same-as=<elf>]
defmodule CheckStandalone do
  @root Path.expand("..", __DIR__)
  @project Path.join(@root, "tests/standalone")
  @double "SBXV" <> <<40::little-32>>
  @single "SBXV" <> <<24::little-32>>
  @sht_riscv_attributes 0x7000_0003

  def main(argv) do
    {kv, _, _} = OptionParser.parse(argv, strict: [sysroot: :string, build: :string, same_as: :string])
    for t <- ~w(cmake ninja clang++ ld.lld), do: System.find_executable(t) || fail("#{t} is not on PATH")
    sysroot = kv[:sysroot] || System.get_env("RISCV64_SYSROOT") || fail("no --sysroot and no RISCV64_SYSROOT")
    toolchain = Path.join(Path.expand(sysroot), "toolchain.cmake")
    File.exists?(toolchain) || fail("no toolchain.cmake under #{sysroot}")
    build = Path.expand(kv[:build] || Path.join(@root, "build/standalone"))
    File.rm_rf!(build)
    rv64 = Path.join(build, "rv64")

    run!(["-S", @project, "-B", rv64, "-G", "Ninja", "-DCMAKE_TOOLCHAIN_FILE=#{toolchain}"])
    run!(["--build", rv64])
    elf = File.read!(Path.join(rv64, "dress_on.elf"))
    say("dress_on.elf: #{byte_size(elf)} bytes, sha256 #{sha256(elf)}")

    vext = Path.join(build, "vext")
    run!(["-S", @project, "-B", vext, "-G", "Ninja", "-DCMAKE_TOOLCHAIN_FILE=#{toolchain}", "-DSANDBOX_RISCV_EXT_V=ON"])
    run!(["--build", vext])
    vext_elf = File.read!(Path.join(vext, "dress_on.elf"))

    {host_out, host_rc} = cmake(["-S", @project, "-B", Path.join(build, "host"), "-G", "Ninja"])
    {ggml_out, ggml_rc} =
      cmake(["-S", @project, "-B", Path.join(build, "no-ggml"), "-G", "Ninja", "-DCMAKE_TOOLCHAIN_FILE=#{toolchain}",
             "-DGUEST_RUNTIME_GGML=ON", "-DGGML_ROOT=#{Path.join(build, "absent-ggml")}"])

    results =
      [
        check("dress_on.elf is a riscv64 ELF64 with a double-precision Variant", elf_ok(elf)),
        check("control: an x86-64 e_machine is refused", refused(elf_ok(put_machine(elf, 62)))),
        check("control: a single-precision Variant is refused", refused(elf_ok(:binary.replace(elf, @double, @single)))),
        check("dress_on.elf's RISC-V arch attribute carries no vector extension", scalar_arch(elf)),
        check("control: dress_on.elf built with SANDBOX_RISCV_EXT_V=ON is refused", refused(scalar_arch(vext_elf))),
        check("control: an ELF without .riscv.attributes is refused", refused(scalar_arch(retype_attributes(elf)))),
        check("control: a host-compiler configure is refused",
              refused_with(host_rc, host_out, "not a riscv64 sysroot build")),
        check("control: GUEST_RUNTIME_GGML without a ggml checkout is refused",
              refused_with(ggml_rc, ggml_out, "GUEST_RUNTIME_GGML needs"))
      ] ++ same_as(kv[:same_as], elf)

    failed = Enum.count(results, &(&1 != :ok))
    say("#{length(results) - failed} of #{length(results)} checks pass")
    if failed > 0, do: System.halt(1)
  end

  defp elf_ok(<<0x7F, "ELF", 2, 1, _::binary-size(10), _type::little-16, machine::little-16, _::binary>> = elf) do
    cond do
      machine != 243 -> {:error, "e_machine #{machine}, not RISC-V (243)"}
      :binary.match(elf, @double) == :nomatch -> {:error, "no .sandbox_variant of 40 bytes (double precision)"}
      true -> :ok
    end
  end

  defp elf_ok(_), do: {:error, "not a little-endian ELF64"}

  defp put_machine(<<head::binary-size(18), _::little-16, rest::binary>>, m), do: head <> <<m::little-16>> <> rest

  defp scalar_arch(elf) do
    with [attrs] <- for({_, @sht_riscv_attributes, off, size} <- sections(elf), do: binary_part(elf, off, size)),
         [arch] <- Regex.run(~r/rv(?:32|64)[a-z0-9_]+/, attrs) do
      case Enum.filter(extensions(arch), &(&1 == "v" or String.starts_with?(&1, "zv"))) do
        [] -> say("  arch #{arch}")
        vector -> {:error, "arch #{arch} carries #{Enum.join(vector, ", ")}"}
      end
    else
      [] -> {:error, "no .riscv.attributes section"}
      nil -> {:error, "no Tag_RISCV_arch in .riscv.attributes"}
      many -> {:error, "#{length(many)} .riscv.attributes sections, not one"}
    end
  end

  defp extensions("rv" <> <<_::binary-size(2)>> <> rest) do
    Enum.flat_map(String.split(rest, "_", trim: true), fn part ->
      if String.starts_with?(part, ["z", "s", "x"]),
        do: [Regex.replace(~r/\d+(p\d+)?$/, part, "")],
        else: String.graphemes(Regex.replace(~r/\d+(p\d+)?/, part, ""))
    end)
  end

  defp sections(<<_::binary-size(0x28), shoff::little-64, _::binary-size(10), entsize::little-16, n::little-16, _::binary>> = elf) do
    Enum.map(0..(n - 1)//1, fn i ->
      at = shoff + i * entsize
      <<_::32, type::little-32, _::binary-size(16), off::little-64, size::little-64>> = binary_part(elf, at, 40)
      {at, type, off, size}
    end)
  end

  defp retype_attributes(elf) do
    Enum.reduce(sections(elf), elf, fn
      {at, @sht_riscv_attributes, _, _}, acc ->
        binary_part(acc, 0, at + 4) <> <<1::little-32>> <> binary_part(acc, at + 8, byte_size(acc) - at - 8)

      _, acc -> acc
    end)
  end

  defp refused(:ok), do: {:error, "accepted"}
  defp refused({:error, why}), do: say("  refused: #{why}")

  defp refused_with(0, _, _), do: {:error, "configure succeeded"}

  defp refused_with(_, out, msg) do
    if out =~ msg, do: :ok, else: {:error, "configure failed without naming #{inspect(msg)}:\n#{out}"}
  end

  defp same_as(nil, _), do: []

  defp same_as(path, elf) do
    other = File.read!(path)
    [check("sha256 equals #{path} (#{sha256(other)})", if(other == elf, do: :ok, else: {:error, "differs"}))]
  end

  defp check(name, :ok), do: (say("PASS #{name}"); :ok)
  defp check(name, {:error, why}), do: (say("FAIL #{name}: #{why}"); :fail)

  defp run!(args) do
    {out, rc} = cmake(args)
    if rc != 0, do: fail("cmake exited #{rc}\n#{out}")
  end

  defp cmake(args) do
    say("$ cmake #{Enum.join(args, " ")}")
    System.cmd("cmake", args, stderr_to_stdout: true)
  end

  defp sha256(bin), do: Base.encode16(:crypto.hash(:sha256, bin), case: :lower)
  defp say(msg), do: (IO.puts("== #{msg}"); :ok)

  defp fail(msg) do
    IO.puts(:stderr, "check_standalone: #{msg}")
    System.halt(1)
  end
end

CheckStandalone.main(System.argv())
