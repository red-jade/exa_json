## EXA Json

𝔼𝕏tr𝔸 𝔼li𝕏ir 𝔸dditions (𝔼𝕏𝔸)

EXA project index: [exa](https://github.com/red-jade/exa)

Utilities for reading and writing JSON data.

Module path: `Exa.Json`

### Features

- Read JSON files and decode JSON data
- Write JSON files and encode JSON data
- Configure data value parsers

### Benchmarks

Exa uses _Benchee_ for performancee testing.

Test results are stored under `text/bench/*.benchee`.
The current _latest_ baseline and previous results are checked-in.

Run the benchmarks and compare with latest result:

`$ mix test --only benchmark:true`

To run specific benchmark test, for example:

`$ mix test --only benchmark:true test/exa/json/json_resder_test.exs`

### License

EXA source code is released under the MIT license.

EXA code and documentation are:<br>
Copyright (c) 2024 Mike French
