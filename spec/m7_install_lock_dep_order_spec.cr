require "./spec_helper"

# task-175: `install` rewrote the lockfile with each spec's dependency lines in
# gemspec *declaration* order, while `lock` (and Bundler's
# `LazySpecification#to_lock`, `lazy_specification.rb:117`) sorts them by
# `dep.to_s` and de-duplicates. The serializer is therefore the single place
# that guarantees the two commands cannot disagree.
module Celerite
  describe "lockfile dependency line ordering" do
    it "sorts and de-duplicates a spec's dependency lines when rendering" do
      text = <<-LOCK
      GEM
        remote: http://127.0.0.1:9/
        specs:
          zdep-root (1.0.0)
            zchild-gem (~> 1.0)
            achild-gem (~> 1.0)
            achild-gem (~> 1.0)

      PLATFORMS
        x64-mingw-ucrt

      DEPENDENCIES
        zdep-root

      BUNDLED WITH
         4.0.24
      LOCK
      data = Lockfile::Parser.parse(text + "\n")
      rendered = String.build { |io| data.sources[0].to_lock(io) }
      rendered.should contain("      achild-gem (~> 1.0)\n      zchild-gem (~> 1.0)\n")
      rendered.scan("achild-gem").size.should eq(1)
      rendered.scan("zchild-gem").size.should eq(1)
    end
  end
end
