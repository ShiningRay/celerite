# frozen_string_literal: true

# Failure bucketing rules for `script/upstream-specs` (and the offline
# re-bucket tool under `.tmp-scratch/task91/`). Kept in one place so both the
# harness and the re-computation agree.
#
# The rule table is evaluated top-down, first match wins:
#
# | # | condition                                                       | bucket                     |
# |--:|-----------------------------------------------------------------|----------------------------|
# | 1 | text contains "Could not reach host"                            | env:artifice-unreachable   |
# | 2 | text contains "HTTP 403" or "403 Forbidden"                     | env:network-policy         |
# | 3 | text contains "0xC0000022" or "NtCreateDirectoryObject"         | env:low-il-shm             |
# | 4 | text contains "sinatra/base"                                    | env:test-deps-skipped      |
# | 5 | exception class is RSpec::Expectations::ExpectationNotMetError   | product:candidates         |
# | 5b| message has "expected:" and "got:" sections                     | product:candidates         |
# | 6 | text contains ENOENT / "does not exist!" / "rb_sysopen"         | fixture:missing-gem-files  |
# | 7 | text contains "Fetching "                                       | fixture:fetch-failed       |
# | 8 | otherwise                                                       | product:candidates         |
#
# Rules 1-4 are environment signatures and run first so a lock assertion that
# happens to quote an environment string still lands in its environment bucket.
# Rule 5 exists because an assertion failure is never a fixture problem: the
# recorded `got:` text can legitimately contain `Fetching source index ...`
# (the command under test prints it), which used to sweep lock-body assertions
# into `fixture:fetch-failed` (task-86 discovery, corrected in task-91).
module UpstreamSpecsBuckets
  ASSERTION_CLASS = "RSpec::Expectations::ExpectationNotMetError"

  ORDER = [
    "env:artifice-unreachable",
    "env:network-policy",
    "env:low-il-shm",
    "env:test-deps-skipped",
    "fixture:missing-gem-files",
    "fixture:fetch-failed",
    "product:candidates",
  ].freeze

  module_function

  def classify(klass, message, backtrace)
    text = klass + "\n" + message + "\n" + backtrace
    return "env:artifice-unreachable" if text.include?("Could not reach host")
    return "env:network-policy" if text.include?("HTTP 403") || text.include?("403 Forbidden")
    return "env:low-il-shm" if text.include?("0xC0000022") || text.include?("NtCreateDirectoryObject")
    return "env:test-deps-skipped" if text.include?("sinatra/base")
    return "product:candidates" if klass == ASSERTION_CLASS
    return "product:candidates" if message.include?("expected:") && message.include?("got:")
    if text.include?("Errno::ENOENT") || text.include?("does not exist!") || text.include?("No such file or directory @ rb_sysopen")
      return "fixture:missing-gem-files"
    end
    return "fixture:fetch-failed" if text.include?("Fetching ")
    "product:candidates"
  end
end