#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
wrapper="$root/build/accelerator/accelerator.gen/sources_1/bd/accelerator/ip/accelerator_stream_fifo_0/sim/accelerator_stream_fifo_0.v"
[[ -f "$wrapper" ]] || { echo 'Generate the Vivado design first.' >&2; exit 1; }
mkdir -p "$root/build/sim_fifo" "$root/reports"
cd "$root/build/sim_fifo"
vivado_root=$(cd "$(dirname "$(command -v vivado)")/.." && pwd)
xvlog --sv "$vivado_root/data/verilog/src/glbl.v" "$wrapper" "$root/tests/tb_stream_fifo.sv" > "$root/reports/fifo_compile.log" 2>&1
xelab tb_stream_fifo glbl -s fifo_test -L axis_data_fifo_v2_0_18 -L axis_infrastructure_v1_1_1 \
  -L fifo_generator_v13_2_15 -L xpm -L unisims_ver -L unimacro_ver -L secureip \
  > "$root/reports/fifo_elaborate.log" 2>&1
xsim fifo_test -runall -log "$root/reports/fifo_simulation.log" > "$root/reports/fifo_simulation.console.log" 2>&1
grep '^FIFO_SIM_PASS' "$root/reports/fifo_simulation.log"
