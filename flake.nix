{
  description = "Build a RediSearch C program that links to a Rust library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    redis-flake = {
      url = "github:chesedo/redis-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    rltest-src = {
      url = "github:RedisLabsModules/RLTest/v0.7.16";
      flake = false;  # Use the source directly, not as a flake
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, redis-flake, rltest-src, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
          config.allowUnfree = true;
        };
        redis-source = redis-flake.packages.${system}.redis;

        # Custom RLTest package
        rltest = pkgs.python3Packages.buildPythonPackage rec {
          pname = "RLTest";
          version = "0.7.16";

          src = rltest-src;

          # Use pyproject.toml for building
          pyproject = true;
          build-system = with pkgs.python3Packages; [
            poetry-core
          ];

          # Runtime dependencies
          dependencies = with pkgs.python3Packages; [
            distro
            progressbar2
            psutil
            pytest
            pytest-cov
            redis-source
            setuptools  # Needed for pkg_resources
          ];

          # Skip tests during build
          doCheck = false;

          # Skip the runtime dependency version checking
          dontCheckRuntimeDeps = true;

          meta = with pkgs.lib; {
            description = "Redis Labs Test Framework";
            homepage = "https://github.com/RedisLabsModules/RLTest";
            license = licenses.bsd3;
          };
        };

        # Python environment with packages from requirements.txt
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pip # Needed for readies to detect this python env
          gevent
          packaging
          deepdiff
          redis
          numpy
          scipy
          faker
          distro
          orderly-set
          rltest
          ml-dtypes
        ]);
      in
      {
        devShells = {
          default =  pkgs.mkShell {
            hardeningDisable = [ "fortify" "stackprotector" "pic" "relro" ];
            # Shell hooks to create executable scripts in a local bin directory
            shellHook = ''
              cargo_version=$(cargo --version 2>/dev/null)

              echo -e "\033[1;36m=== 🦀 Welcome to the RediSearch development environment ===\033[0m"
              echo -e "\033[1;33m• $cargo_version\033[0m"
              echo -e "\n\033[1;33m• Checking for any outdated packages...\033[0m\n"
              cd src/redisearch_rs && cargo outdated --root-deps-only

              # For libclang dependency to work
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              # For `sys/types.h` and `stddef.h` required by redismodules-rs
              export BINDGEN_EXTRA_CLANG_ARGS="-I${pkgs.glibc.dev}/include -I${pkgs.gcc-unwrapped}/lib/gcc/x86_64-unknown-linux-gnu/14.3.0/include"

              # Force SVS to build from source instead of using precompiled library
              export CMAKE_ARGS="-DSVS_SHARED_LIB=OFF"

              # Tell getpy3 to use our Nix Python directly, skipping version detection and PEP_668 logic
              export MYPY="${pkgs.python3}/bin/python3"

              # Tell valgrind about the suppression file
              export VALGRINDFLAGS="--suppressions=$PWD/valgrind.supp"
            '';

            buildInputs = with pkgs; [
              # For LSP
              ccls

              # Dev dependencies based on developer.md
              cmake
              openssl.dev
              libxcrypt

              # To run the unit tests
              gtest.dev

              # Python environment for integration tests
              pythonEnv

              # Needed by python tests
              wget
              redis-source

              rust-bin.stable.latest.default

              # To profile the code or benchmarks
              samply
              linuxPackages.perf

              # For valgrind
              valgrind
              kdePackages.kcachegrind

              cargo-valgrind
            ];

            packages = with pkgs; [
              rust-analyzer
              cargo-watch
              cargo-outdated
              lldb
              vscode-extensions.vadimcn.vscode-lldb
            ];
          };

          nightly = pkgs.mkShell {
            hardeningDisable = [ "fortify" "stackprotector" "pic" "relro" ];

            buildInputs = with pkgs; [
              # Dev dependencies based on developer.md
              cmake
              openssl.dev
              libxcrypt

              (rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
                extensions = [ "rust-src" "miri" "llvm-tools-preview" ];
              }))
            ];

            packages = with pkgs; [
              cargo-llvm-cov
              lcov
            ];
          };
        };
      });
}
