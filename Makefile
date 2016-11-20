all:
	@GAIA_HOME=$(shell pwd) \
		swift build \
		-Xcc -I`llvm-config --includedir` \
		-Xlinker -L`llvm-config --libdir` \
		-Xlinker -rpath -Xlinker `llvm-config --libdir`

test:
	@GAIA_HOME=$(shell pwd) \
		swift test \
		-Xcc -I`llvm-config --includedir` \
		-Xlinker -L`llvm-config --libdir` \
		-Xlinker -rpath -Xlinker `llvm-config --libdir`
