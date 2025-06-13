begin
  require "rubygems"
  rice_gem = Gem::Specification.find_by_name("rice")
  rice_lib = File.join(rice_gem.full_gem_path, "lib")
  $LOAD_PATH.unshift(rice_lib) unless $LOAD_PATH.include?(rice_lib)
  rice_include = File.join(rice_gem.full_gem_path, "include")
  $INCFLAGS << " -I#{rice_include}"
rescue => e
  abort "Could not add rice gem paths: #{e}"
end

require "mkmf-rice"
require "numo/narray"

# libomp changed to keg-only
# https://github.com/Homebrew/homebrew-core/issues/112107
if RbConfig::CONFIG["host_os"] =~ /darwin/i
  brew_prefix = RbConfig::CONFIG["host_cpu"] =~ /arm|aarch64/i ? "/opt/homebrew" : "/usr/local"
  find_library("omp", nil, "#{brew_prefix}/opt/libomp/lib")
  find_header("omp.h", "#{brew_prefix}/opt/libomp/include")
end

abort "BLAS not found" unless have_library("blas")
abort "LAPACK not found" unless have_library("lapack")
abort "OpenMP not found" unless have_library("omp") || have_library("gomp")

numo = File.join(Gem.loaded_specs["numo-narray"].require_path, "numo")
abort "Numo not found" unless find_header("numo/narray.h", numo)

# for https://bugs.ruby-lang.org/issues/19005
$LDFLAGS += " -Wl,-undefined,dynamic_lookup" if RbConfig::CONFIG["host_os"] =~ /darwin/i

$CXXFLAGS += " -std=c++17 -DFINTEGER=int"
$CXXFLAGS += " -Wall -Wno-unused-parameter -Wno-unused-function -Wno-unused-variable -Wno-unused-private-field -Wno-deprecated-declarations -Wno-sign-compare"

# CPU-specific optimization flags
cpu_arch = RbConfig::CONFIG["host_cpu"]
is_macos = RbConfig::CONFIG["host_os"].downcase.include?("darwin")

# Remove any -march flag to avoid accidental AVX-512 or other issues
$CXXFLAGS.gsub!(/-march=[^\s]+/, "")
$CFLAGS.gsub!(/-march=[^\s]+/, "")

if cpu_arch =~ /x86_64/
  # Force AVX2 for x86_64 platforms, regardless of CPU capabilities
  $CXXFLAGS += " -mavx2"
  $CFLAGS += " -mavx2"

  # On macOS, must also enable FMA for AVX2 code using FMA intrinsics!
  if is_macos
    $CXXFLAGS += " -mfma"
    $CFLAGS += " -mfma"
  end
elsif cpu_arch =~ /arm|aarch64/
  # No specific CPU flags for ARM platforms
  # Let the compiler choose appropriate optimizations
end

apple_clang = RbConfig::CONFIG["CC_VERSION_MESSAGE"] =~ /apple clang/i
$CXXFLAGS += " -Xclang" if apple_clang
$CXXFLAGS += " -fopenmp"

ext = File.expand_path(".", __dir__)
vendor = File.expand_path("../../vendor/faiss", __dir__)

$srcs = Dir["{#{ext},#{vendor}/faiss,#{vendor}/faiss/{impl,invlists,utils}/**}/*.{cpp}"]
$objs = $srcs.map { |v| v.sub(/cpp\z/, "o") }
abort "Faiss not found" unless find_header("faiss/Index.h", vendor)
$VPATH << vendor

create_makefile("faiss/ext")
