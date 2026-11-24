require "./spec_helper"

# Shared S8e comparison helpers. A negative case is run twice from the exact
# same on-disk state: once with `CELERITE_FAST_PATH=0` (the compatibility path),
# once with the fast path enabled. The celerite cache is intentionally excluded
# from the file-tree comparison: a rejected hit may invalidate/rewrite its own
# bookkeeping, while every user-visible project and installed-gem file must be
# item-for-item identical.
record M8MatrixRun,
  status : Int32,
  stdout : String,
  stderr : String,
  procs : Int32,
  rpc : Int32,
  req_bytes : Int32,
  resp_bytes : Int32

def m8_matrix_bin : String
  path = File.expand_path("../bin/celerite.exe", __DIR__)
  fail "bin/celerite.exe is not built" unless File.file?(path)
  path
end

def m8_matrix_run(project : String, args : Array(String)) : M8MatrixRun
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run(m8_matrix_bin, args, chdir: project, output: output, error: errors)
  stderr = errors.to_s
  line = stderr.lines.find(&.starts_with?("bridge: procs="))
  fail "missing bridge stats in #{stderr.inspect}" unless line
  match = line.match(/^bridge: procs=(\d+) rpc=(\d+) req_bytes=(\d+) resp_bytes=(\d+)$/).not_nil!
  M8MatrixRun.new(status.exit_code, output.to_s, stderr,
    match[1].to_i, match[2].to_i, match[3].to_i, match[4].to_i)
end

def m8_matrix_copy_tree(source : String, destination : String) : Nil
  Dir.mkdir_p(destination)
  Dir.children(source).sort.each do |name|
    FileUtils.cp_r(File.join(source, name), File.join(destination, name))
  end
end

def m8_matrix_restore(project : String, archive : String) : Nil
  FileUtils.rm_rf(project)
  m8_matrix_copy_tree(archive, project)
end

def m8_matrix_snapshot(project : String, archive : String) : Nil
  FileUtils.rm_rf(archive)
  m8_matrix_copy_tree(project, archive)
end

def m8_matrix_tree(project : String) : Hash(String, String)
  tree = {} of String => String
  pending = [project]
  while current = pending.pop?
    Dir.children(current).sort.each do |name|
      path = File.join(current, name)
      relative = Path[path].relative_to(Path[project]).to_s.gsub('\\', "/")
      next if relative == ".celerite/cache" || relative.starts_with?(".celerite/cache/")
      if File.directory?(path)
        tree[relative] = "dir"
        pending << path
      else
        tree[relative] = "#{File.size(path)}:#{Digest::SHA256.hexdigest(File.read(path))}"
      end
    end
  end
  tree
end

def m8_matrix_normalize(text : String, project : String) : String
  text.gsub('\\', "/").gsub(project.gsub('\\', "/"), "<PROJECT>").gsub("\r\n", "\n")
end

def m8_matrix_observable_stderr(run : M8MatrixRun) : String
  run.stderr.lines.reject(&.starts_with?("bridge: procs=")).join
end

def m8_matrix_assert_compat_parity(reference : M8MatrixRun,
                                   candidate : M8MatrixRun,
                                   project : String,
                                   reference_tree : Hash(String, String),
                                   candidate_tree : Hash(String, String)) : Nil
  reference.procs.should be >= 1
  candidate.procs.should be >= 1
  candidate.status.should eq(reference.status)
  m8_matrix_normalize(candidate.stdout, project).should eq(m8_matrix_normalize(reference.stdout, project))
  m8_matrix_normalize(m8_matrix_observable_stderr(candidate), project)
    .should eq(m8_matrix_normalize(m8_matrix_observable_stderr(reference), project))

  missing = reference_tree.keys.reject { |path| candidate_tree.has_key?(path) }.sort
  added = candidate_tree.keys.reject { |path| reference_tree.has_key?(path) }.sort
  missing.should be_empty
  added.should be_empty
  changed = reference_tree.keys.select do |path|
    candidate_tree.has_key?(path) && candidate_tree[path] != reference_tree[path]
  end.sort
  changed.should be_empty
end
