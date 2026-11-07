# Third-party licenses

Celerite itself is licensed under the MIT license (see `LICENSE`).

The macOS platform gem bundles shared libraries that the native binary links
against, so the gem runs on a machine without Homebrew packages installed. The
corresponding license texts are shipped in `assets/licenses/`:

| Library | License | Text |
|---|---|---|
| Boehm-Demers-Weiser GC (`libgc`) | MIT-style | `assets/licenses/bdw-gc.txt` |
| OpenSSL (`libssl`, `libcrypto`) | Apache-2.0 | `assets/licenses/openssl.txt` |
| PCRE2 (`libpcre2-8`) | BSD-3-Clause WITH PCRE2-exception | `assets/licenses/pcre2.txt` |
| libyaml (`libyaml`) | MIT | `assets/licenses/libyaml.txt` |

System libraries (`libSystem`, `libz`, `libiconv`) are provided by macOS and
are not redistributed.

Linux and Windows platform gems are built from the corresponding Crystal
toolchain; their bundled libraries are recorded in the same directory when
applicable.
