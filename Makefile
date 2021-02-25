PYODIDE_ROOT=$(abspath .)

include Makefile.envs

.PHONY=check

FILEPACKAGER=$$EM_DIR/tools/file_packager.py
UGLIFYJS=$(PYODIDE_ROOT)/node_modules/.bin/uglifyjs

CPYTHONROOT=cpython
CPYTHONLIB=$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/python$(PYMINOR)

#CC=emcc
#CXX=em++
CC=$(WASI_SDK_PATH)/bin/clang
CXX=$(WASI_SDK_PATH)/bin/clang++
OPTFLAGS=-O2
CFLAGS=\
	$(OPTFLAGS) \
	-g \
	-I$(PYTHONINCLUDE) \
	-fPIC \
	-Wno-warn-absolute-paths \
	-Werror=int-conversion \
	-Werror=incompatible-pointer-types \
	$(EXTRA_CFLAGS)
LDFLAGS=\
	-s BINARYEN_EXTRA_PASSES="--pass-arg=max-func-params@61" \
	$(OPTFLAGS) \
	-s MODULARIZE=1 \
	$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/libpython$(PYMINOR).a \
	-s TOTAL_MEMORY=20971520 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-s MAIN_MODULE=1 \
	-s EMULATE_FUNCTION_POINTER_CASTS=1 \
	-s LINKABLE=1 \
	-s EXPORT_ALL=1 \
	-s EXPORTED_FUNCTIONS='["___cxa_guard_acquire", "__ZNSt3__28ios_base4initEPv", "_main"]' \
	-s WASM=1 \
	-s USE_FREETYPE=1 \
	-s USE_LIBPNG=1 \
	-std=c++14 \
	-L$(wildcard $(CPYTHONROOT)/build/sqlite*/.libs) -lsqlite3 \
	$(wildcard $(CPYTHONROOT)/build/bzip2*/libbz2.a) \
	-lstdc++ \
	--memory-init-file 0 \
	-s LZ4=1 \
	$(EXTRA_LDFLAGS)

all: check \
	build/pyodide.asm.bc \
	build/packages.bc
	echo -e "\nSUCCESS!"


build/pyodide.asm.bc: \
	src/pystone.py \
	src/_testcapi.py \
	src/webbrowser.py \
	$(wildcard src/pyodide-py/pyodide/*.py) \
	$(CPYTHONLIB)
	date +"[%F %T] Building pyodide.asm.bc..."
	[ -d build ] || mkdir build
	$(CXX) -s EXPORT_NAME="'pyodide'" -o build/pyodide.asm.bc $(filter %.o,$^) \
		$(LDFLAGS) -s FORCE_FILESYSTEM=1 \
		--preload-file $(CPYTHONLIB)@/lib/python$(PYMINOR) \
		--preload-file src/webbrowser.py@/lib/python$(PYMINOR)/webbrowser.py \
		--preload-file src/_testcapi.py@/lib/python$(PYMINOR)/_testcapi.py \
		--preload-file src/pystone.py@/lib/python$(PYMINOR)/pystone.py \
		--preload-file src/pyodide-py/pyodide@/lib/python$(PYMINOR)/site-packages/pyodide \
		--exclude-file "*__pycache__*" \
		--exclude-file "*/test/*"
	date +"[%F %T] done building pyodide.asm.bc."


env:
	env

lint:
	# check for unused imports, the rest is done by black
	flake8 --select=F401 src tools pyodide_build benchmark conftest.py
	clang-format-6.0 -output-replacements-xml `find src -type f -regex ".*\.\(c\|h\|js\)"` | (! grep '<replacement ')
	black --check .
	mypy --ignore-missing-imports pyodide_build/ src/ packages/micropip/micropip/ packages/*/test* conftest.py


apply-lint:
	./tools/apply-lint.sh

clean:
	rm -fr build/*
	rm -fr src/*.o


clean-all: clean
	make -C clean
	make -C cpython clean
	rm -fr cpython/build

%.o: %.c $(CPYTHONLIB) $(wildcard src/**/*.h)
	$(CC) -o $@ -c $< $(CFLAGS) -Isrc/core/


build/test.data: $(CPYTHONLIB) $(UGLIFYJS)
	( \
		cd $(CPYTHONLIB)/test; \
		find . -type d -name __pycache__ -prune -exec rm -rf {} \; \
	)
	( \
		cd build; \
		python $(FILEPACKAGER) test.data --lz4 --preload ../$(CPYTHONLIB)/test@/lib/python$(PYMINOR)/test --js-output=test.js --export-name=pyodide._module --exclude __pycache__ \
	)
	$(UGLIFYJS) build/test.js -o build/test.js


$(CPYTHONLIB): $(PYODIDE_CXX)
	date +"[%F %T] Building cpython..."
	make -C $(CPYTHONROOT)
	date +"[%F %T] done building cpython..."

build/packages.bc: FORCE
 	date +"[%F %T] Building packages..."
 	make -C packages
 	date +"[%F %T] done building packages..."

FORCE:

check:
	./tools/dependency-check.sh

minimal :
	PYODIDE_PACKAGES="micropip" make

debug :
	EXTRA_CFLAGS="-D DEBUG_F" \
	EXTRA_LDFLAGS="-s ASSERTIONS=2" \
	PYODIDE_PACKAGES+="micropip,pyparsing,pytz,packaging,kiwisolver" \
	make
