require "./spec_helper"

# M7(4) GEM source index fetch failures (task-137). The reference serves a
# `file:` GEM source from the legacy index only (`fetcher.rb:271-280`), so
# `bundle install` must read `<remote>specs.4.8.gz` even when
# `names`/`versions`/`info/*` are readable. A missing file is retried three
# times (`fetcher.rb:171-176`, `retry.rb#fail_attempt`) and then re-raised as
# `Bundler::HTTPError` with the wrapper text from `fetcher/index.rb:8-22`,
# which the friendly-errors pipeline word-wraps at the terminal width and exits
# with status 17.
#
# `fixtures/gem-index-ruby-constraints` is a compact-index-only directory (it
# ships `names`, `versions` and `info/*` but no `specs.4.8.gz`), so everything
# here stays offline.

private def index_missing_fixture_dir : String
  File.expand_path("../fixtures/gem-index-ruby-constraints", __DIR__).gsub('\\', "/")
end

private def index_missing_remote : String
  "file:///#{index_missing_fixture_dir}/"
end

private def index_missing_local_path : String
  "#{index_missing_fixture_dir}/specs.4.8.gz"
end

private def index_missing_gemfile : String
  %(source "#{index_missing_remote}"\n\ngem "rubygems_gem"\n)
end

# The reference resolves the source to `display_uri` (trailing slash kept) and
# renders the underlying `Errno::ENOENT` the legacy fetcher raised, with the
# `(uri)` suffix `Gem::RemoteFetcher::FetchError` appends.
private def index_missing_message : String
  "Could not fetch specs from #{index_missing_remote} due to underlying error " \
  "<Errno::ENOENT: No such file or directory @ rb_sysopen - " \
  "#{index_missing_local_path} (#{index_missing_remote}specs.4.8.gz)>"
end

# `Retry#fail_attempt` prints one empty progress line per attempt and one
# *unwrapped* warning per failed attempt except the last (`retry.rb`).
private def index_missing_stdout : String
  "Fetching source index from #{index_missing_remote}\n" + "\n" * 4
end

private def index_missing_retry_lines : Array(String)
  (2..4).map { |run| "Retrying fetcher due to error (#{run}/4): Bundler::HTTPError #{index_missing_message}" }
end

# The bridge env var must be set while the example *runs*, not while the
# describe block is merely registered.
private def with_index_missing_bridge(&)
  previous = ENV["CELERITE_BRIDGE_SERVER"]?
  ENV["CELERITE_BRIDGE_SERVER"] = File.expand_path("../assets/bridge/server.rb", __DIR__)
  begin
    yield
  ensure
    if previous
      ENV["CELERITE_BRIDGE_SERVER"] = previous
    else
      ENV.delete("CELERITE_BRIDGE_SERVER")
    end
  end
end

private def with_index_missing_columns(columns : String?, &)
  previous = ENV["THOR_COLUMNS"]?
  if columns
    ENV["THOR_COLUMNS"] = columns
  else
    ENV.delete("THOR_COLUMNS")
  end
  begin
    yield
  ensure
    if previous
      ENV["THOR_COLUMNS"] = previous
    else
      ENV.delete("THOR_COLUMNS")
    end
  end
end

describe "M7(4) GEM source index fetch failure" do
  it "reports Could not fetch specs from, retries three times and exits 17" do
    with_index_missing_bridge do
      with_project({"Gemfile" => index_missing_gemfile}) do
        # Wide terminal: this example pins wording and ordering, not wrap
        # points (the fixture's absolute path decides where the wrap lands, and
        # `differential index-missing-specs` pins the 80-column rendering).
        with_index_missing_columns("400") do
          code, out, err = run_cli(["install"])

          code.should eq(17)
          out.should eq(index_missing_stdout)
          err.should_not contain("celerite internal error")
          err.should eq(index_missing_retry_lines.join("\n") + "\n" + index_missing_message + "\n")
        end
      end
    end
  end

  it "keeps the retry warnings unwrapped and word-wraps the final error at 80 columns" do
    with_index_missing_bridge do
      with_project({"Gemfile" => index_missing_gemfile}) do
        with_index_missing_columns(nil) do
          code, _out, err = run_cli(["install"])
          lines = err.lines

          code.should eq(17)
          # Three unwrapped warnings plus the wrapped final message: the
          # reference passes `newline = true` to `ui.warn`, so only the final
          # error goes through Thor's word wrap.
          lines.size.should be > 4
          # `String#lines` drops the newline, so these compare line bodies.
          lines[0..2].each_with_index do |line, index|
            line.should eq(index_missing_retry_lines[index])
          end
          lines[0..2].each { |line| line.size.should be > 80 }
          # The final message goes through `Commands.word_wrap` at the default
          # width: the reference's break after "from" is reproduced here (the
          # wide-column example above proves the break comes from the width,
          # not from a hard-coded newline in the message).
          err.should contain("Could not fetch specs from\n")
          lines[3..].join("\n").gsub(/\s+/, " ").strip.should eq(index_missing_message.gsub(/\s+/, " ").strip)
        end
      end
    end
  end
end
