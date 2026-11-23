require "./spec_helper"

# The 80-column contract of `Commands.word_wrap`
# (`src/celerite/cli/commands.cr:1205-1214`), which reproduces the reference
# `bundler-4.0.24/lib/bundler/ui/shell.rb` `word_wrap` pattern verbatim:
# `(.{1,#{width}})(\s+|$)`. The wrap only breaks where the message already has
# whitespace, so a word that would overflow moves to the next line and a long
# word is never split in the middle.
#
# `PathError`'s message is "The path `<path>` does not exist.", so the first
# line measures `10 + path.size + 6` columns ("The path `" plus "` does"):
# 64 path characters give exactly 80 and keep `does` on the line, 65 push it
# over and the path then owns its line. These three lengths straddle that edge,
# which is the geometry that made task-225's two wrap specs red or green
# depending on the temp root's length.
private def boundary_path(body_chars : Int32) : String
  # `C:/t/cel225b/` is 13 columns, so 50/51/52 produce 63/64/65 characters.
  "C:/t/cel225b/" + ("a" * body_chars)
end

private def boundary_message(path : String) : String
  "The path `#{path}` does not exist."
end

describe "M7 word_wrap 80-column boundary" do
  it "breaks after `does` at 63 and 64 path characters and puts the path alone at 65" do
    path63 = boundary_path(50)
    path64 = boundary_path(51)
    path65 = boundary_path(52)
    # Guards the fixture itself: a miscounted literal would silently move the
    # boundary instead of failing here.
    path63.size.should eq(63)
    path64.size.should eq(64)
    path65.size.should eq(65)

    # Expected renderings are literals (`word_wrap` is the subject, so it cannot
    # also be the oracle).
    Celerite::Commands.word_wrap(boundary_message(path63), 80).should eq(
      "The path `#{path63}` does\nnot exist."
    )
    Celerite::Commands.word_wrap(boundary_message(path64), 80).should eq(
      "The path `#{path64}` does\nnot exist."
    )
    Celerite::Commands.word_wrap(boundary_message(path65), 80).should eq(
      "The path `#{path65}`\ndoes not exist."
    )
  end
end
