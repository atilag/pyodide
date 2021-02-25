#!/bin/bash

ROOT=`dirname ${BASH_SOURCE[0]}`
export PATH=$ROOT/wasi-sdk/bin:$PATH
export WASI_SDK_PATH=$ROOT/wasi-sdk