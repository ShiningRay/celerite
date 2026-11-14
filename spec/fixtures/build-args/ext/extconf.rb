# M7(4) probe: record the arguments Gem::Ext::Builder passed to extconf and
# emit a no-op Makefile so `make`/`make install` succeed without a compiler.
marker = ENV["CELERITE_BUILD_ARGS_MARKER"] || File.join(Dir.pwd, "build_args_marker.txt")
File.write(marker, ARGV.inspect)

makefile = +"all:\n\t@echo build-args-demo built\n"
makefile << "install:\n\t@echo build-args-demo installed\n"
makefile << "clean:\n\t@echo build-args-demo clean\n"
File.write("Makefile", makefile)
